# KEIM Arcade · shared high-score board

1. In Supabase (the same project as Project Studio is fine) open **SQL Editor** and run `arcade_board.sql` once.
2. Copy the project's **URL** and **anon public key** (Settings → API).
3. In the repo, open `index.html` and fill in the line near the top of the scores code:
   `const LB={url:'https://xxxx.supabase.co',anon:'eyJ...'};`
4. Commit and push. The board switches on.

Monthly prize: edit `prizes.json`. The key is the month (`"2026-11"`) or `"default"`.
Winners: in Supabase → Table Editor → view `arcade_month_winners`, or just read the board on the page on the 1st.
Scores are posted from the player's browser, so treat the top of the board as "verify before you post the prize" — a quick look at the game's own best on the winner's phone is enough.

## Finding the winners on the 1st

Players type an email when they post a score ("so we can send your prize"). It is stored next to the score
but the public key can never read that column, so it never appears on the board.

On the 1st of each month, in Supabase: **Table Editor → arcade_last_month_winners**. That view lists last
month's best score per set of initials, highest first, with the email they left. Email the top three, send the
prizes, and post the initials on the arcade (prizes.json → update the month).

A player who posted without an email has `email` empty: they were warned at post time that no email = no prize,
so skip to the next initials.
