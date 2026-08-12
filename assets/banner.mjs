import fs from 'node:fs'

const OUT = process.argv[2]

// Two parallel signal traces, coupled. Warm channel = Claude Code, cool = Antigravity.
// No gradients from the usual indigo/purple well, no drop shadows: depth comes from
// a 1px translucent rule and the ambient glow behind the coupling arc.
const V = {
  en: { tag: 'Antigravity as a non-blocking peer for Claude Code', foot: 'ask a second model without waiting for it' },
  es: { tag: 'Antigravity como par no bloqueante para Claude Code', foot: 'consulta a un segundo modelo sin esperarlo' },
  zh: { tag: '让 Antigravity 成为 Claude Code 的非阻塞协作伙伴', foot: '咨询第二个模型，无需等待' },
}

const page = (lang, w, h) => {
  const v = V[lang]
  const big = lang === 'zh' ? 96 : 104
  const cjk = lang === 'zh'
  return `<!doctype html><meta charset="utf-8"><style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:${w}px;height:${h}px;overflow:hidden}
  body{background:#08080a;font-family:${cjk ? '"PingFang SC","Hiragino Sans GB","Noto Sans CJK SC",' : ''}-apple-system,"Helvetica Neue",Arial,sans-serif;
       color:#f4f2ee;display:flex;align-items:center;position:relative}
  .wrap{position:relative;z-index:2;padding:0 ${Math.round(w * 0.066)}px;width:100%}
  /* The wordmark never inherits the CJK stack: font fallback would reshape the
     logo per language, and a logo that changes shape is not a logo. */
  h1{font-family:"Helvetica Neue",Helvetica,Arial,sans-serif;font-size:${big}px;font-weight:600;
     letter-spacing:-.045em;line-height:.95;display:flex;align-items:flex-end;gap:${Math.round(big * 0.1)}px}
  /* Drawn, not typed: a period glyph is square in one face and round in the next. */
  .dot{width:${Math.round(big * 0.19)}px;height:${Math.round(big * 0.19)}px;background:#d97757;
       margin-bottom:${Math.round(big * 0.045)}px}
  .tag{margin-top:${Math.round(h * 0.055)}px;font-size:${cjk ? 25 : 26}px;font-weight:400;color:#a8a29b;letter-spacing:${cjk ? '.005em' : '-.011em'}}
  .foot{margin-top:${Math.round(h * 0.075)}px;font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:15px;
        color:#6f6a63;letter-spacing:.04em}
  svg{position:absolute;inset:0;width:${w}px;height:${h}px;z-index:1}
</style>
<svg viewBox="0 0 ${w} ${h}" fill="none">
  <defs>
    <radialGradient id="glow" cx="50%" cy="50%">
      <stop offset="0" stop-color="#d97757" stop-opacity=".26"/>
      <stop offset="1" stop-color="#d97757" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <ellipse cx="${w * 0.845}" cy="${h * 0.5}" rx="${w * 0.2}" ry="${h * 0.44}" fill="url(#glow)"/>
  <!-- warm trace: claude code -->
  <path d="M${w * 0.7} ${h * 0.3} H${w}" stroke="#d97757" stroke-width="2"/>
  <!-- cool trace: antigravity -->
  <path d="M${w * 0.7} ${h * 0.72} H${w}" stroke="#5b8fb9" stroke-width="2"/>
  <!-- the coupling: signal bleeding across, which is what crosstalk means -->
  <path d="M${w * 0.845} ${h * 0.3} C${w * 0.885} ${h * 0.3} ${w * 0.885} ${h * 0.72} ${w * 0.925} ${h * 0.72}"
        stroke="#f4f2ee" stroke-width="1.5" stroke-opacity=".55" stroke-dasharray="4 5"/>
  <circle cx="${w * 0.845}" cy="${h * 0.3}" r="4.5" fill="#d97757"/>
  <circle cx="${w * 0.925}" cy="${h * 0.72}" r="4.5" fill="#5b8fb9"/>
  <text x="${w * 0.7}" y="${h * 0.3 - 15}" fill="#8a8078" font-family="ui-monospace,Menlo,monospace" font-size="13" letter-spacing="1.4">CLAUDE CODE</text>
  <text x="${w * 0.7}" y="${h * 0.72 + 27}" fill="#7c8894" font-family="ui-monospace,Menlo,monospace" font-size="13" letter-spacing="1.4">ANTIGRAVITY</text>
  <rect x="0" y="${h - 1}" width="${w}" height="1" fill="#ffffff" fill-opacity=".07"/>
</svg>
<div class="wrap">
  <h1><span>crosstalk</span><span class="dot"></span></h1>
  <div class="tag">${v.tag}</div>
  <div class="foot">${v.foot}</div>
</div>`
}

fs.mkdirSync(OUT, { recursive: true })
for (const lang of ['en', 'es', 'zh']) {
  fs.writeFileSync(`${OUT}/banner-${lang}.html`, page(lang, 1200, 400))
}
fs.writeFileSync(`${OUT}/social.html`, page('en', 1280, 640))
console.log('html listo')
