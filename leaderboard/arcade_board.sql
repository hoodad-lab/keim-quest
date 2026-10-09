-- =====================================================================
-- KEIM Arcade · shared high-score board (Supabase)
-- Run once in Supabase → SQL Editor. Free tier is plenty.
-- The arcade page posts with the public anon key; these rules decide
-- what it is allowed to do: insert one sane-looking score, read the top 10.
-- =====================================================================
create table if not exists arcade_scores (
  id          bigserial primary key,
  initials    text not null check (initials ~ '^[A-Z]{3}$'),
  game        text not null check (game in ('quest','knockout','goal-kick','kart','bucket-toss','facade-defender','rush',
                                            'kommando','klash','paint-wall','render-stacker','colour-lab')),
  score       integer not null check (score > 0 and score < 10000000),
  month       text not null check (month ~ '^\d{4}-\d{2}$'),
  email       text check (email is null or (length(email) <= 120 and email ~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$')),
  created_at  timestamptz not null default now()
);
-- (upgrade from the first version of this script)
alter table arcade_scores add column if not exists email text
  check (email is null or (length(email) <= 120 and email ~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$'));
create index if not exists arcade_scores_month_idx on arcade_scores(month, game, score desc);

alter table arcade_scores enable row level security;
-- anyone may add a score; a trigger below keeps it honest
drop policy if exists arcade_insert on arcade_scores;
create policy arcade_insert on arcade_scores for insert to anon with check (true);
-- nobody reads the raw table directly (the view below is what the page reads)
drop policy if exists arcade_read on arcade_scores;
create policy arcade_read on arcade_scores for select to anon using (true);

-- the month must be the current Sydney month (no back-dating), and no more than 30 posts a day per initials
create or replace function arcade_scores_guard() returns trigger language plpgsql as $$
begin
  if new.month <> to_char(now() at time zone 'Australia/Sydney', 'YYYY-MM') then
    raise exception 'wrong month';
  end if;
  if (select count(*) from arcade_scores where initials = new.initials and created_at > now() - interval '1 day') >= 30 then
    raise exception 'too many posts';
  end if;
  return new;
end $$;
drop trigger if exists arcade_scores_guard_t on arcade_scores;
create trigger arcade_scores_guard_t before insert on arcade_scores for each row execute function arcade_scores_guard();

-- best score per player per game (what the board shows)
create or replace view arcade_board as
  select distinct on (month, game, initials) initials, game, score, month, created_at
    from arcade_scores
   order by month, game, initials, score desc, created_at asc;
grant select on arcade_board to anon;
-- the public key may insert a score (with or without an email) but can only ever READ the non-personal columns:
-- email is never selectable from the browser, so it cannot appear on the board or be scraped.
revoke all on arcade_scores from anon;
grant insert (initials, game, score, month, email) on arcade_scores to anon;
grant select (id, initials, game, score, month, created_at) on arcade_scores to anon;
grant usage, select on sequence arcade_scores_id_seq to anon;

-- for you only (Supabase dashboard, Table Editor → arcade_month_winners): this month's top players with the
-- email they left so you can send the prizes. Not granted to anon, so the page can never read it.
drop view if exists arcade_month_winners;
create view arcade_month_winners as
  select distinct on (initials) month, initials, game, score, created_at,
         (select email from arcade_scores e
           where e.initials = s.initials and e.email is not null
           order by e.created_at desc limit 1) as email
    from arcade_scores s
   where month = to_char(now() at time zone 'Australia/Sydney', 'YYYY-MM')
   order by initials, score desc, created_at asc;
revoke all on arcade_month_winners from anon, authenticated;

-- last month's winners (run on the 1st): same thing for the month that just ended
drop view if exists arcade_last_month_winners;
create view arcade_last_month_winners as
  select distinct on (initials) month, initials, game, score, created_at,
         (select email from arcade_scores e
           where e.initials = s.initials and e.email is not null
           order by e.created_at desc limit 1) as email
    from arcade_scores s
   where month = to_char((now() at time zone 'Australia/Sydney') - interval '1 month', 'YYYY-MM')
   order by initials, score desc, created_at asc;
revoke all on arcade_last_month_winners from anon, authenticated;
