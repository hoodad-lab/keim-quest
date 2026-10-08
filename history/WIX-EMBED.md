# Putting the Education page on keim.com.au (Wix)

Everything is hosted at https://hoodad-lab.github.io/keim-quest/history/ — nothing to upload.

## The 5-minute version
1. Wix Editor → Pages → Add page → Blank page. Name it **Education**, URL `/education`.
2. Make the page full-width with no header padding, then: Add Elements → Embed Code → **Embed HTML**.
3. Paste the snippet below, stretch the element to full width, and set its height to about 4,400 px on desktop (the page scrolls inside the site) — or tick "Adjust height automatically" if your Wix shows it.
4. Publish. The Wix header and footer sit above and below it, so the page looks like every other page on the site.

```html
<iframe src="https://hoodad-lab.github.io/keim-quest/history/education/embed.html"
  title="KEIM Education — From Ochre to KEIM"
  style="width:100%;height:4400px;border:0;display:block"
  allow="autoplay; fullscreen" allowfullscreen loading="lazy"></iframe>
```

Mobile: in the Wix mobile editor set the same element to about 5,600 px high.

## Just the film (anywhere on the site, e.g. the home page)
```html
<iframe src="https://hoodad-lab.github.io/keim-quest/history/"
  title="From Ochre to KEIM — a brief history of paint"
  style="width:100%;aspect-ratio:16/10;border:0;display:block"
  allow="autoplay; fullscreen" allowfullscreen loading="lazy"></iframe>
```

## Direct links to share
- Film: https://hoodad-lab.github.io/keim-quest/history/
- A language: add `?lang=de` (de, es, it, fr, pt, fa, ar, hi, zh)
- A chapter: add `#keim`, `#pompeii`, `#cave`, `#plastic-skin`, `#verdict`, `#today`

## Updating later
Replace files under `history/` in the GitHub repo hoodad-lab/keim-quest; the site updates within a minute.
