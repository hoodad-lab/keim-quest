# KEIM Arcade · shared board + KEIMLINGE credits

Everything runs on one free Supabase project. The arcade page talks to it with the public anon key;
the SQL decides what that key may do.

## 1. Switch on the shared high-score board (10 min)
1. Supabase → **SQL Editor** → run `arcade_board.sql` once (safe to re-run).
2. Settings → API: copy the **Project URL** and the **anon public** key.
3. In the repo `index.html`, fill the line `const LB={url:'',anon:''};` with those two values. Commit, push. Done.

Monthly prize text lives in `prizes.json` (key = month `"2026-11"` or `"default"`).
Winners on the 1st: Table Editor → view **arcade_last_month_winners** (best score per initials + the email they left).

## 2. Switch on KEIMLINGE credits (30 min)
Players join with email + a 6-digit code. 100 points = $1. 500 welcome, 500 per referred friend, 200 weekly challenge,
50 first play of each game, 25 per day played, Colour Lab star bonuses. Cap 1,000 points ($10) per week.

**Supabase**
1. SQL Editor → run `arcade_credits_v2.sql` (after step 1; safe to re-run).
2. Authentication → Providers → **Email**: enabled. Turn **Confirm email** OFF (the code is the confirmation).
3. Authentication → **Email Templates** → *Magic Link*: the body must contain the code, e.g.
   `<h2>Your KEIM Arcade code</h2><p style="font-size:32px;letter-spacing:6px">{{ .Token }}</p><p>Valid for a few minutes.</p>`
   Subject: `Your KEIM Arcade code: {{ .Token }}`
4. Project Settings → Authentication → **SMTP**: the built-in sender allows only a few emails an hour, so set custom SMTP
   (Microsoft 365: smtp.office365.com, port 587, a KEIM mailbox such as play@keim.com.au). Sender name "KEIM Arcade".
5. Database → **Webhooks** → Create: name `arcade redeem`, table `arcade_redemptions`, event **Insert**,
   type HTTP request, POST, URL `https://www.keim.com.au/_functions/arcadeRedeem`,
   HTTP header `x-arcade-secret` = a long random string (same as the Wix secret below).

**Wix (keim.com.au)**
6. Dev Mode → Backend → add `http-functions.js` from `wix/http-functions.js`.
7. Secrets Manager: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` (Settings → API → service_role; never in page code), `ARCADE_WEBHOOK_SECRET`.
8. Optional: in the file set `SAMPLES_COLLECTION_ID` to a Stores collection so codes only work on samples / fandeck / merch. Publish.

**HubSpot** — done. Form "KEIM Arcade - KEIMLINGE join" (id 44e1f000-eb6d-4f2e-ba13-b7fe2643b5ea, portal 47417993) is wired
into `index.html`; every new member is submitted to it and appears as a contact with conversion "KEIM Arcade - KEIMLINGE join".
Build a list / workflow from that form in HubSpot (welcome email, KEIMLINGE tag) whenever you like.

**Weekly challenge**
Table Editor → `arcade_weekly`: one row per Monday (Sydney): game slug + target score. Four weeks are pre-filled; tune the
targets once you see real scores. No row for a week = no challenge that week.

**Reports**
Table Editor → view `arcade_credits_report`: every member, referrals, balance, codes issued.

## Local test
`python3 fake_sb.py` fakes everything on http://localhost:8799 (any email, code 123456, codes issued after 4 s).
Point `LB.url` at it in a test copy of index.html.
