-- =====================================================================
-- KEIM Arcade · KEIMLINGE credits v2  (Supabase)
-- Run once in SQL Editor, AFTER arcade_board.sql.  Safe to re-run.
--
-- Sign-in: Supabase Auth, email + 6-digit code (no password).
-- Earn:  $5 when you register · $5 per friend who registers with your link ·
--        $2 for beating this week's challenge. Cap $10 per member per week.
-- Spend: Redeem → a Wix shop discount code (created by the Wix function in
--        wix/http-functions.js, triggered by a Supabase Database Webhook).
-- Credits expire 6 months after they are earned. Amounts are in cents.
-- =====================================================================
create extension if not exists pgcrypto;

-- ---------- tables ----------
create table if not exists arcade_members (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  email        text not null,
  initials     text check (initials is null or initials ~ '^[A-Z]{3}$'),
  ref_code     text not null unique,
  referred_by  uuid references arcade_members(user_id),
  created_at   timestamptz not null default now()
);
create table if not exists arcade_ledger (
  id          bigserial primary key,
  user_id     uuid not null references arcade_members(user_id) on delete cascade,
  key         text not null,          -- welcome · ref:<uuid> · week:<date> · redeem:<uuid> · refund:<uuid>
  cents       integer not null,
  created_at  timestamptz not null default now(),
  unique (user_id, key)
);
create index if not exists arcade_ledger_user_idx on arcade_ledger(user_id, created_at);
create table if not exists arcade_weekly (
  week_start  date primary key,       -- the Monday (Sydney) the challenge starts
  game        text not null check (game in ('quest','knockout','goal-kick','kart','bucket-toss','facade-defender','rush',
                                            'kommando','klash','paint-wall','render-stacker','colour-lab')),
  target      integer not null check (target > 0),
  note        text
);
create table if not exists arcade_redemptions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references arcade_members(user_id) on delete cascade,
  cents        integer not null,
  dollars      integer not null,
  status       text not null default 'pending',   -- pending → issued | refunded
  coupon_code  text,
  coupon_id    text,
  created_at   timestamptz not null default now(),
  issued_at    timestamptz
);

-- ---------- locks ----------
alter table arcade_members     enable row level security;
alter table arcade_ledger      enable row level security;
alter table arcade_weekly      enable row level security;
alter table arcade_redemptions enable row level security;
drop policy if exists m_own on arcade_members;     create policy m_own on arcade_members     for select to authenticated using (user_id = auth.uid());
drop policy if exists l_own on arcade_ledger;      create policy l_own on arcade_ledger      for select to authenticated using (user_id = auth.uid());
drop policy if exists r_own on arcade_redemptions; create policy r_own on arcade_redemptions for select to authenticated using (user_id = auth.uid());
drop policy if exists w_all on arcade_weekly;      create policy w_all on arcade_weekly      for select to anon, authenticated using (true);
grant select on arcade_members, arcade_ledger, arcade_redemptions to authenticated;
grant select on arcade_weekly to anon, authenticated;
-- all writes go through the functions below (security definer)

-- ---------- helpers ----------
create or replace function arcade_now_syd() returns timestamp language sql stable as $$
  select now() at time zone 'Australia/Sydney' $$;
create or replace function arcade_week_start() returns date language sql stable as $$
  select date_trunc('week', arcade_now_syd())::date $$;           -- Monday
create or replace function arcade_cap_cents() returns integer language sql immutable as $$ select 1000 $$;

-- earned this week (positive entries, refunds excluded)
create or replace function arcade_week_cents(p_user uuid) returns integer language sql stable security definer set search_path = public as $$
  select coalesce(sum(cents),0)::int from arcade_ledger
   where user_id = p_user and cents > 0 and key not like 'refund:%'
     and created_at >= (arcade_week_start()::timestamp at time zone 'Australia/Sydney') $$;
-- spendable balance: credits earned in the last 6 months minus everything spent
create or replace function arcade_balance_cents(p_user uuid) returns integer language sql stable security definer set search_path = public as $$
  select greatest(0, coalesce(sum(cents),0))::int from arcade_ledger
   where user_id = p_user and (cents < 0 or created_at > now() - interval '6 months') $$;

-- give credit, respecting the weekly cap; returns cents actually given (0 if capped or already given)
create or replace function arcade_give(p_user uuid, p_key text, p_cents integer) returns integer language plpgsql security definer set search_path = public as $$
declare v_give integer;
begin
  if exists (select 1 from arcade_ledger where user_id = p_user and key = p_key) then return 0; end if;
  v_give := least(p_cents, greatest(arcade_cap_cents() - arcade_week_cents(p_user), 0));
  if v_give <= 0 then return 0; end if;
  insert into arcade_ledger(user_id, key, cents) values (p_user, p_key, v_give);
  return v_give;
end $$;

-- ---------- what the page calls (as the signed-in user) ----------
create or replace function arcade_wallet() returns json language plpgsql security definer set search_path = public as $$
declare m arcade_members; w arcade_weekly; r arcade_redemptions; v_done boolean;
begin
  select * into m from arcade_members where user_id = auth.uid();
  if not found then return json_build_object('member', false); end if;
  select * into w from arcade_weekly where week_start = arcade_week_start();
  v_done := exists (select 1 from arcade_ledger where user_id = m.user_id and key = 'week:' || arcade_week_start());
  select * into r from arcade_redemptions where user_id = m.user_id order by created_at desc limit 1;
  return json_build_object(
    'member', true, 'email', m.email, 'initials', m.initials, 'ref_code', m.ref_code,
    'balance', arcade_balance_cents(m.user_id), 'week', arcade_week_cents(m.user_id), 'cap', arcade_cap_cents(),
    'referrals', (select count(*) from arcade_members x where x.referred_by = m.user_id),
    'weekly', case when w.week_start is null then null else json_build_object('game', w.game, 'target', w.target, 'done', v_done) end,
    'last_code', case when r.id is null then null else json_build_object('id', r.id, 'status', r.status, 'code', r.coupon_code, 'dollars', r.dollars, 'at', r.created_at) end
  );
end $$;

-- first call after sign-in: creates the member (= KEIMLINGE registration), welcome credit, referral credit
create or replace function arcade_register(p_initials text default null, p_ref text default null) returns json language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_email text; v_new boolean := false; v_ref uuid; v_code text;
begin
  if v_uid is null then raise exception 'not signed in'; end if;
  select email into v_email from auth.users where id = v_uid;
  if not exists (select 1 from arcade_members where user_id = v_uid) then
    v_new := true;
    loop
      v_code := upper(substr(encode(gen_random_bytes(6), 'base64'), 1, 6));
      v_code := regexp_replace(v_code, '[^A-Z0-9]', 'K', 'g');
      exit when not exists (select 1 from arcade_members where ref_code = v_code);
    end loop;
    if p_ref is not null then
      select user_id into v_ref from arcade_members where ref_code = upper(p_ref) and user_id <> v_uid;
    end if;
    insert into arcade_members(user_id, email, initials, ref_code, referred_by)
      values (v_uid, lower(v_email), case when p_initials ~ '^[A-Z]{3}$' then p_initials else null end, v_code, v_ref);
    perform arcade_give(v_uid, 'welcome', 500);
    if v_ref is not null then perform arcade_give(v_ref, 'ref:' || v_uid, 500); end if;
  elsif p_initials ~ '^[A-Z]{3}$' then
    update arcade_members set initials = p_initials where user_id = v_uid;
  end if;
  return json_build_object('new', v_new, 'wallet', arcade_wallet());
end $$;

-- weekly challenge: the page reports the player's best in this week's game
create or replace function arcade_weekly_claim(p_game text, p_score integer) returns json language plpgsql security definer set search_path = public as $$
declare w arcade_weekly; v_given integer := 0;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into w from arcade_weekly where week_start = arcade_week_start();
  if found and w.game = p_game and p_score >= w.target then
    v_given := arcade_give(auth.uid(), 'week:' || w.week_start, 200);
  end if;
  return json_build_object('given', v_given, 'wallet', arcade_wallet());
end $$;

-- redeem the whole balance (whole dollars, $5 to $50) → pending redemption; the Wix function issues the code
create or replace function arcade_redeem() returns json language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_bal integer; v_dollars integer; v_id uuid;
begin
  if v_uid is null then raise exception 'not signed in'; end if;
  perform 1 from arcade_members where user_id = v_uid for update;
  if exists (select 1 from arcade_redemptions where user_id = v_uid and status = 'pending' and created_at > now() - interval '10 minutes') then
    return json_build_object('ok', false, 'reason', 'pending');
  end if;
  v_bal := arcade_balance_cents(v_uid);
  v_dollars := least(50, v_bal / 100);
  if v_dollars < 5 then return json_build_object('ok', false, 'reason', 'balance', 'balance', v_bal, 'need', 500); end if;
  insert into arcade_redemptions(user_id, cents, dollars) values (v_uid, v_dollars * 100, v_dollars) returning id into v_id;
  insert into arcade_ledger(user_id, key, cents) values (v_uid, 'redeem:' || v_id, -v_dollars * 100);
  return json_build_object('ok', true, 'id', v_id, 'dollars', v_dollars, 'wallet', arcade_wallet());
end $$;

-- ---------- for the Wix function (service role only) ----------
create or replace function arcade_redeem_issued(p_id uuid, p_code text, p_coupon_id text) returns void language sql security definer set search_path = public as $$
  update arcade_redemptions set status = 'issued', coupon_code = p_code, coupon_id = p_coupon_id, issued_at = now() where id = p_id and status = 'pending' $$;
create or replace function arcade_redeem_refund(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare r arcade_redemptions;
begin
  select * into r from arcade_redemptions where id = p_id and status = 'pending' for update;
  if not found then return; end if;
  update arcade_redemptions set status = 'refunded' where id = p_id;
  insert into arcade_ledger(user_id, key, cents) values (r.user_id, 'refund:' || p_id, r.cents);
end $$;

revoke all on function arcade_give(uuid,text,integer), arcade_week_cents(uuid), arcade_balance_cents(uuid),
                       arcade_redeem_issued(uuid,text,text), arcade_redeem_refund(uuid) from public, anon, authenticated;
grant execute on function arcade_wallet(), arcade_register(text,text), arcade_weekly_claim(text,integer), arcade_redeem() to authenticated;
revoke execute on function arcade_wallet(), arcade_register(text,text), arcade_weekly_claim(text,integer), arcade_redeem() from public, anon;

-- ---------- weekly challenges: add a row per Monday (Table Editor → arcade_weekly). Tune the targets as you go. ----------
insert into arcade_weekly(week_start, game, target, note) values
  (date_trunc('week', arcade_now_syd())::date,                      'knockout',        6000, 'win one fight'),
  (date_trunc('week', arcade_now_syd())::date + 7,                  'goal-kick',       2500, 'a solid career run'),
  (date_trunc('week', arcade_now_syd())::date + 14,                 'facade-defender', 3000, ''),
  (date_trunc('week', arcade_now_syd())::date + 21,                 'quest',           1500, '')
on conflict (week_start) do nothing;

-- ---------- reports for you ----------
create or replace view arcade_credits_report as
  select m.email, m.initials, m.ref_code, m.created_at as joined,
         (select count(*) from arcade_members x where x.referred_by = m.user_id) as referrals,
         arcade_balance_cents(m.user_id) as balance_cents, arcade_week_cents(m.user_id) as this_week_cents,
         (select count(*) from arcade_redemptions r where r.user_id = m.user_id and r.status = 'issued') as codes_issued
    from arcade_members m order by joined desc;
revoke all on arcade_credits_report from anon, authenticated;

-- ---------- v2.1: points for playing (100 points = $1; all subject to the same weekly cap) ----------
-- play:<game>  first play of each game  50 pts   · daily:<YYYY-MM-DD>  play any game today  25 pts
-- cl-stars:12/24/36  Colour Lab career stars  150 / 250 / 500 pts
create or replace function arcade_milestone(p_key text) returns json language plpgsql security definer set search_path = public as $$
declare v_pts integer := 0; v_given integer := 0; m text[];
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from arcade_members where user_id = auth.uid()) then return json_build_object('given', 0, 'wallet', arcade_wallet()); end if;
  m := regexp_match(p_key, '^play:(quest|knockout|goal-kick|kart|bucket-toss|facade-defender|rush|kommando|klash|paint-wall|render-stacker|colour-lab)$');
  if m is not null then v_pts := 50; end if;
  m := regexp_match(p_key, '^daily:(\d{4}-\d{2}-\d{2})$');
  if m is not null and m[1] = to_char(arcade_now_syd(), 'YYYY-MM-DD') then v_pts := 25; end if;
  m := regexp_match(p_key, '^cl-stars:(12|24|36)$');
  if m is not null then v_pts := case m[1] when '12' then 150 when '24' then 250 else 500 end; end if;
  if v_pts > 0 then v_given := arcade_give(auth.uid(), p_key, v_pts); end if;
  return json_build_object('given', v_given, 'wallet', arcade_wallet());
end $$;
grant execute on function arcade_milestone(text) to authenticated;
revoke execute on function arcade_milestone(text) from public, anon;

-- wallet: also report which milestones are done
create or replace function arcade_wallet() returns json language plpgsql security definer set search_path = public as $$
declare m arcade_members; w arcade_weekly; r arcade_redemptions; v_done boolean;
begin
  select * into m from arcade_members where user_id = auth.uid();
  if not found then return json_build_object('member', false); end if;
  select * into w from arcade_weekly where week_start = arcade_week_start();
  v_done := exists (select 1 from arcade_ledger where user_id = m.user_id and key = 'week:' || arcade_week_start());
  select * into r from arcade_redemptions where user_id = m.user_id order by created_at desc limit 1;
  return json_build_object(
    'member', true, 'email', m.email, 'initials', m.initials, 'ref_code', m.ref_code,
    'balance', arcade_balance_cents(m.user_id), 'week', arcade_week_cents(m.user_id), 'cap', arcade_cap_cents(),
    'referrals', (select count(*) from arcade_members x where x.referred_by = m.user_id),
    'played', (select coalesce(json_agg(substr(key, 6)), '[]'::json) from arcade_ledger where user_id = m.user_id and key like 'play:%'),
    'daily', exists (select 1 from arcade_ledger where user_id = m.user_id and key = 'daily:' || to_char(arcade_now_syd(), 'YYYY-MM-DD')),
    'stars', (select coalesce(max(substr(key, 10)::int), 0) from arcade_ledger where user_id = m.user_id and key like 'cl-stars:%'),
    'weekly', case when w.week_start is null then null else json_build_object('game', w.game, 'target', w.target, 'done', v_done) end,
    'last_code', case when r.id is null then null else json_build_object('id', r.id, 'status', r.status, 'code', r.coupon_code, 'dollars', r.dollars, 'at', r.created_at) end
  );
end $$;
