# Brand

The name is the concept. In electronics, *crosstalk* is signal coupling between adjacent traces — two channels that end up talking to each other. The mark draws exactly that: a warm trace and a cool one, with a dashed coupling jumping between them.

## Palette

| Token | Hex | Use |
|---|---|---|
| Ink | `#08080a` | Background. Near-black, never pure `#000`. |
| Paper | `#f4f2ee` | Wordmark and primary text. Warm off-white. |
| Signal | `#d97757` | The accent block, the Claude Code trace, the ambient glow. |
| Peer | `#5b8fb9` | The Antigravity trace. Cool counterweight, deliberately not a default blue. |
| Muted | `#a8a29b` | Tagline. |
| Faint | `#6f6a63` | Monospace footnote. |

No gradients beyond the single radial glow behind the coupling. No drop shadows — depth comes from the 1px translucent rule at the baseline.

## Wordmark

`crosstalk` set in Helvetica Neue Medium at `-0.045em` tracking, followed by a **drawn square block**, never a typed period.

That block is a rule, not a preference. A `.` glyph is square in one face and round in the next, so the logo reshaped itself between the English and Chinese banners until it was drawn as an element. The wordmark also pins its own font stack and never inherits the CJK stack used for body copy, for the same reason.

## Regenerating

```bash
node assets/banner.mjs build
```

Writes HTML into `build/`. Render at 2× with headless Chrome:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1200,400 --screenshot=build/banner-en.png "file://$PWD/build/banner-en.html"
```

Banners are 1200×400 (shipped at 2×). The social card is 1280×640.

Adding a language means one entry in the `V` map — tagline and footnote — and one render. Keep the tagline to a single line at 1200px; it is the only string that has to fit.
