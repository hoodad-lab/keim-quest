# KEIM Arcade · play.keim.com.au

Free retro arcade by KEIM Australia, hosted on GitHub Pages from this repo.

## What lives where

| Path | What it is |
|---|---|
| `index.html` | The arcade page: cabinet, game cards, prizes, high-score board, footer and prize terms. One file. |
| `<game>/index.html` | Each game, one self-contained file: house-call, knockout, colour-lab, goal-kick, quest, klash, rush, bucket-toss, facade-defender, render-stacker, paint-wall, kommando. |
| `covers/<game>.jpg` | Card picture for each game (16:9). |
| `clips/<game>.mp4 / .webm / .jpg` | Short clip shown on the cabinet screen. |
| `audio/arcade.mp3` | Arcade music (made with ElevenLabs). Plays the intro once, then loops 8.94s–53.94s (`MLOOP` in `index.html`). Delete it and the page falls back to the built-in chiptune. |
| `audio/announcer.mp3` | Announcer lines: "Free play!", "Player one, ready!", "New high score!". Start/length of each are in `VOX` in `index.html`. |
| `house-call/koala.mp3` | Koala's four lines in House Call. Start/length in `KV` inside the game file. |
| `prizes.json` | This month's prizes. Edit this file each month; no code change needed. |
| `play/`, `arcade/`, `kart/` | Old addresses. They only redirect to the arcade. |

## Monthly routine (10 minutes)

1. On the 1st, in Supabase → SQL Editor run: `select * from arcade_last_month_winners limit 10;`
2. Check the top 3 look real (a sensible score for that game, an email). Impossible scores are already rejected.
3. Email the winners at the address shown. One prize per person.
4. Update `prizes.json` for the new month and push.

## Adding a game

1. Add `<slug>/index.html`, `covers/<slug>.jpg` and `clips/<slug>.*`.
2. In `index.html`: one line in `GAMES`, its high-score key in `SCORE_OF` and `BESTS`, and its bronze/silver/gold targets in `TIERS`.
3. In Supabase: `insert into arcade_games values ('<slug>', 'Title', <gold target>, <max score>);`

## Settings in `index.html` (search for the name)

- `LB`: Supabase address and public key for the shared board.
- `CREDITS_ON`: KEIM Points. `false` at launch, so every join/points button is hidden. Turn on only once the sign-in email works and the points SQL has been run.
- `HOUSE`: the starter "house scores" (marked `*`). They never win.

## Database files (Supabase), run in this order

`arcade_board.sql` → `arcade_board_name.sql` → `arcade_house_call.sql` → `arcade_launch.sql`

Later, for KEIM Points: `arcade_credits_v2.sql` → `arcade_points_percent.sql`, plus the Wix backend file.

© KEIM Australia · info@keim.com.au
