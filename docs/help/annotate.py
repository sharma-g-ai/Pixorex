"""Draws the help page's orange numbered boxes onto each screenshot (for the Word version).
Chrome renders the same frame and box styles as help.html, so the pictures look the same.
Run: python annotate.py  ->  img-marked/<shot>.png"""
import json
import os
import subprocess

CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
PAD = 16  # room for the number badges that sit on a box's top-left corner
here = os.path.abspath('.')
shots = json.load(open('img/shots.json', encoding='utf-8'))
os.makedirs('img-marked', exist_ok=True)
os.makedirs('tmp-html', exist_ok=True)

CSS = """
html,body{margin:0;background:#fff}
.frame{position:absolute;left:%dpx;top:%dpx;border:1px solid #dbe3ec;border-radius:10px;overflow:visible;
  box-shadow:0 1px 2px rgba(10,30,60,.06),0 8px 24px rgba(10,30,60,.06)}
.frame img{display:block;border-radius:10px}
.mark{position:absolute;border:2.5px solid #f07d00;border-radius:6px;box-sizing:border-box}
.mark span{position:absolute;top:-11px;left:-11px;min-width:24px;height:24px;padding:0 6px;box-sizing:border-box;
  border-radius:12px;background:#f07d00;color:#fff;font:700 13px/24px "Source Sans 3","Segoe UI",sans-serif;
  text-align:center;box-shadow:0 0 0 2px #fff}
""" % (PAD, PAD)

for name, shot in shots.items():
    W, H = shot['w'], shot['h']
    marks = []
    for n, b in enumerate(shot['boxes'], 1):
        x0, y0 = max(b['x'] - 3, 0), max(b['y'] - 3, 0)
        x1, y1 = min(b['x'] + b['w'] + 3, W), min(b['y'] + b['h'] + 3, H)
        marks.append(f'<div class="mark" style="left:{x0}px;top:{y0}px;width:{x1 - x0}px;height:{y1 - y0}px"><span>{n}</span></div>')
    img = 'file:///' + os.path.join(here, 'img', name + '.png').replace('\\', '/')
    page = (f'<!doctype html><meta charset="utf-8"><link rel="stylesheet" '
            f'href="https://fonts.googleapis.com/css2?family=Source+Sans+3:wght@700&display=swap"><style>{CSS}</style>'
            f'<div class="frame" style="width:{W}px;height:{H}px"><img src="{img}" width="{W}" height="{H}">{"".join(marks)}</div>')
    src = os.path.join(here, 'tmp-html', name + '.html')
    open(src, 'w', encoding='utf-8').write(page)
    out = os.path.join(here, 'img-marked', name + '.png')
    subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
                    '--virtual-time-budget=3000', f'--window-size={W + 2 * PAD},{H + 2 * PAD}',
                    f'--screenshot={out}', 'file:///' + src.replace('\\', '/')],
                   check=True, capture_output=True)
    print('marked', name)
