"""Builds help.html from content.py and img/shots.json. Run: python build.py"""
import html
import json
import sys

sys.path.insert(0, '.')
from content import INTRO, ROLES, SCREENS, WORDS  # noqa: E402

shots = json.load(open('img/shots.json', encoding='utf-8'))
errors = []


def figure(fig, fid, title=None):
    shot = shots.get(fig['shot'])
    if shot is None:
        errors.append(f"missing screenshot {fig['shot']}")
        return ''
    boxes, items = shot['boxes'], fig['items']
    if len(boxes) != len(items):
        errors.append(f"{fig['shot']}: {len(boxes)} boxes but {len(items)} explanations")
    W, H = shot['w'], shot['h']
    marks = []
    for n, b in enumerate(boxes, 1):
        # Keep each box inside the picture (a pop-up's table can run past its bottom edge).
        x0, y0 = max(b['x'] - 3, 0), max(b['y'] - 3, 0)
        x1, y1 = min(b['x'] + b['w'] + 3, W), min(b['y'] + b['h'] + 3, H)
        style = (f"left:{x0 / W * 100:.3f}%;top:{y0 / H * 100:.3f}%;"
                 f"width:{(x1 - x0) / W * 100:.3f}%;height:{(y1 - y0) / H * 100:.3f}%")
        marks.append(
            f'<a class="mark" href="#{fid}-{n}" style="{style}" data-n="{n}" '
            f'aria-label="{n}: {html.escape(b["label"])}"><span>{n}</span></a>')
    lis = ''.join(
        f'<li id="{fid}-{n}" data-n="{n}"><span class="num">{n}</span><div>{text}</div></li>'
        for n, text in enumerate(items, 1))
    head = f'<h4>{html.escape(title)}</h4>' if title else ''
    return f'''
      <figure class="shot" id="{fid}">
        {head}
        <div class="frame" style="aspect-ratio:{W}/{H}">
          <img src="img/{fig['shot']}.png" width="{W}" height="{H}" loading="lazy"
               alt="{html.escape(fig['caption'])}">
          {''.join(marks)}
        </div>
        <figcaption>{html.escape(fig['caption'])}</figcaption>
        <ol class="keys">{lis}</ol>
      </figure>'''


nav, body = [], []
for s in SCREENS:
    nav.append(f'<li><a href="#{s["id"]}">{html.escape(s["title"])}</a></li>')
    figs = ''.join(figure(f, f'{s["id"]}-f{i}') for i, f in enumerate(s['figures'], 1))
    pops = ''
    if s.get('popups'):
        pops = '<h3 class="popups">Pop-ups on this screen</h3>' + ''.join(
            figure(p, f'{s["id"]}-p{i}', p['title']) for i, p in enumerate(s['popups'], 1))
    body.append(f'''
    <section class="screen" id="{s["id"]}">
      <h2>{html.escape(s["title"])}</h2>
      <p class="intro">{s["intro"]}</p>
      {figs}{pops}
    </section>''')

if errors:
    raise SystemExit('\n'.join(errors))

roles = ''.join(f'<div class="role"><h4>{r}</h4><p>{t}</p></div>' for r, t in ROLES)
words = ''.join(f'<dt>{w}</dt><dd>{t}</dd>' for w, t in WORDS)
how = ''.join(f'<li>{t}</li>' for t in INTRO['how'])

page = f'''<title>SeaStock Help</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Semi+Condensed:wght@600;700&family=Source+Sans+3:wght@400;600;700&family=IBM+Plex+Mono:wght@500&display=swap">
<style>
/* Layout: a fixed screen index on the left, one long manual on the right; screenshots carry
   numbered callouts tied to the list under each one. */
:root {{
  --bg: #f3f6f9; --paper: #ffffff; --ink: #142233; --muted: #566577; --line: #dbe3ec;
  --navy: #003366; --blue: #00529b; --cyan: #0091c8; --soft: #e7f0f9;
  --mark: #f07d00; --mark-soft: rgba(240,125,0,.14); --mark-ink: #ffffff;
  --display: "Barlow Semi Condensed", "Arial Narrow", system-ui, sans-serif;
  --body: "Source Sans 3", "Segoe UI", system-ui, sans-serif;
  --mono: "IBM Plex Mono", ui-monospace, monospace;
}}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{
  --bg: #0d1724; --paper: #142133; --ink: #e6edf5; --muted: #9fb0c3; --line: #2a3a50;
  --navy: #9cc7f0; --blue: #7db8f0; --cyan: #5cc6f2; --soft: #1b2d44;
  --mark: #ff9a2e; --mark-soft: rgba(255,154,46,.18); --mark-ink: #1a1000; color-scheme: dark }} }}
:root[data-theme="dark"] {{
  --bg: #0d1724; --paper: #142133; --ink: #e6edf5; --muted: #9fb0c3; --line: #2a3a50;
  --navy: #9cc7f0; --blue: #7db8f0; --cyan: #5cc6f2; --soft: #1b2d44;
  --mark: #ff9a2e; --mark-soft: rgba(255,154,46,.18); --mark-ink: #1a1000; color-scheme: dark }}
* {{ box-sizing: border-box }}
html {{ scroll-behavior: smooth; scroll-padding-top: 16px }}
@media (prefers-reduced-motion: reduce) {{ html {{ scroll-behavior: auto }} }}
body {{ background: var(--bg); color: var(--ink); font: 17px/1.55 var(--body) }}
.wrap {{ display: grid; grid-template-columns: 250px minmax(0, 1fr); gap: 40px; max-width: 1280px;
  margin: 0 auto; padding-block: 32px 80px;
  padding-left: max(24px, env(safe-area-inset-left, 0px)); padding-right: max(24px, env(safe-area-inset-right, 0px)) }}
nav.index {{ position: sticky; top: calc(env(safe-area-inset-top, 0px) + 24px); align-self: start }}
.brand {{ font: 700 26px/1 var(--display); color: var(--navy); letter-spacing: .01em }}
.brand b {{ color: var(--cyan); font-weight: 700 }}
.brand small {{ display: block; margin-top: 6px; font: 600 12px/1 var(--body); letter-spacing: .12em; text-transform: uppercase; color: var(--muted) }}
nav.index ol {{ list-style: none; margin: 24px 0 0; padding: 0; display: grid; gap: 2px; counter-reset: s }}
nav.index a {{ display: block; padding: 7px 12px; border-radius: 8px; color: var(--ink); text-decoration: none; font-weight: 600 }}
nav.index a:hover, nav.index a:focus-visible {{ background: var(--soft); color: var(--blue); outline: none }}
nav.index a.on {{ background: var(--soft); color: var(--blue) }}
nav.index .lead-links a {{ font-weight: 400; color: var(--muted) }}
main {{ min-width: 0 }}
h1 {{ font: 700 clamp(34px, 5vw, 46px)/1.05 var(--display); color: var(--navy); margin: 0 0 14px; text-wrap: balance }}
.lead {{ font-size: 19px; max-width: 68ch; margin: 0 }}
.panel {{ background: var(--paper); border: 1px solid var(--line); border-radius: 14px; padding: 22px 24px; margin-top: 24px }}
.panel h2 {{ margin: 0 0 10px; font: 700 22px/1.2 var(--display); color: var(--navy) }}
.panel ul {{ margin: 0; padding-left: 20px }}
.preview {{ margin-top: 16px; padding: 12px 16px; border-left: 3px solid var(--mark); background: var(--mark-soft); border-radius: 6px; font-size: 15px; max-width: 75ch }}
.roles {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px }}
.role {{ border: 1px solid var(--line); border-radius: 10px; padding: 14px 16px }}
.role h4 {{ margin: 0 0 4px; font: 700 18px/1.2 var(--display); color: var(--blue) }}
.role p {{ margin: 0; font-size: 15px; color: var(--muted) }}
dl.words {{ display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 8px 20px; margin: 0; font-size: 16px }}
dl.words dt {{ font-weight: 700 }}
dl.words dd {{ margin: 0; color: var(--muted) }}
.screen {{ margin-top: 64px; padding-top: 8px; border-top: 2px solid var(--line) }}
.screen h2 {{ font: 700 34px/1.1 var(--display); color: var(--navy); margin: 18px 0 8px }}
.intro {{ max-width: 72ch; margin: 0 0 8px }}
h3.popups {{ font: 700 24px/1.2 var(--display); color: var(--navy); margin: 48px 0 0 }}
.shot {{ margin: 28px 0 0 }}
.shot h4 {{ margin: 0 0 10px; font: 700 21px/1.2 var(--display); color: var(--ink) }}
.frame {{ position: relative; width: 100%; max-width: 100%; border: 1px solid var(--line); border-radius: 10px; overflow: hidden; background: #fff; box-shadow: 0 1px 2px rgba(10,30,60,.06), 0 8px 24px rgba(10,30,60,.06) }}
.frame img {{ display: block; width: 100%; height: 100%; max-width: 100% }}
.mark {{ position: absolute; border: 2.5px solid var(--mark); border-radius: 6px; background: transparent; transition: background-color .15s, box-shadow .15s }}
.mark span {{ position: absolute; top: -11px; left: -11px; min-width: 24px; height: 24px; padding: 0 6px; border-radius: 12px; background: var(--mark); color: var(--mark-ink);
  font: 700 13px/24px var(--body); text-align: center; box-shadow: 0 0 0 2px #fff }}
.mark.lit, .mark:hover, .mark:focus-visible {{ background: var(--mark-soft); box-shadow: 0 0 0 4px var(--mark-soft); outline: none }}
figcaption {{ margin-top: 8px; font-size: 14px; color: var(--muted) }}
ol.keys {{ list-style: none; margin: 14px 0 0; padding: 0; display: grid; gap: 4px }}
ol.keys li {{ display: grid; grid-template-columns: 30px minmax(0, 1fr); gap: 10px; padding: 8px 10px; border-radius: 8px; transition: background-color .15s }}
ol.keys li.lit, ol.keys li:target {{ background: var(--mark-soft) }}
.num {{ width: 24px; height: 24px; border-radius: 12px; background: var(--mark); color: var(--mark-ink); font: 700 13px/24px var(--body); text-align: center; margin-top: 1px; font-variant-numeric: tabular-nums }}
ol.keys b {{ font-weight: 700 }}
@media (max-width: 900px) {{
  .wrap {{ grid-template-columns: minmax(0, 1fr); gap: 20px;
    padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)) }}
  nav.index {{ position: static }}
  nav.index ol {{ display: flex; flex-wrap: wrap; gap: 6px }}
  nav.index a {{ border: 1px solid var(--line); padding: 5px 10px; font-size: 15px }}
  .mark span {{ min-width: 18px; height: 18px; font-size: 11px; line-height: 18px; top: -9px; left: -9px; padding: 0 4px }}
  dl.words {{ grid-template-columns: minmax(0, 1fr) }}
  dl.words dd {{ margin-bottom: 8px }}
}}
</style>

<div class="wrap">
  <nav class="index" aria-label="Screens">
    <div class="brand">PPG <b>SeaStock</b><small>Help</small></div>
    <ol>
      <li class="lead-links"><a href="#start">Getting started</a></li>
      {''.join(nav)}
    </ol>
  </nav>
  <main>
    <header id="start">
      <h1>{INTRO['title']}</h1>
      <p class="lead">{INTRO['lead']}</p>
      <p class="preview">{INTRO['preview']}</p>
    </header>
    <section class="panel">
      <h2>How to read this guide</h2>
      <ul>{how}</ul>
    </section>
    <section class="panel">
      <h2>Roles</h2>
      <div class="roles">{roles}</div>
    </section>
    <section class="panel">
      <h2>Words used in SeaStock</h2>
      <dl class="words">{words}</dl>
    </section>
    {''.join(body)}
  </main>
</div>

<script>
// Pointing at an explanation lights up its box, and the other way round.
document.querySelectorAll('figure.shot').forEach((fig) => {{
  const light = (n, on) => fig.querySelectorAll(`[data-n="${{n}}"]`).forEach((el) => el.classList.toggle('lit', on))
  fig.querySelectorAll('[data-n]').forEach((el) => {{
    const n = el.dataset.n
    el.addEventListener('mouseenter', () => light(n, true))
    el.addEventListener('mouseleave', () => light(n, false))
    el.addEventListener('focusin', () => light(n, true))
    el.addEventListener('focusout', () => light(n, false))
  }})
}})
// Mark the screen you are reading in the index.
const links = [...document.querySelectorAll('nav.index a')]
const seen = new IntersectionObserver((entries) => {{
  entries.forEach((e) => {{
    if (!e.isIntersecting) return
    links.forEach((a) => a.classList.toggle('on', a.getAttribute('href') === '#' + e.target.id))
  }})
}}, {{ rootMargin: '0px 0px -70% 0px' }})
document.querySelectorAll('main > header, section.screen').forEach((s) => seen.observe(s))
</script>
'''
open('help.html', 'w', encoding='utf-8').write(page)
print('built help.html with', sum(len(s['figures']) + len(s.get('popups', [])) for s in SCREENS), 'screenshots')
