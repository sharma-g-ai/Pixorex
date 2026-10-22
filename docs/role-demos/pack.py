"""Packs one role build (dist-<user>/) into a single page for an artifact: the app's CSS and JS
go inline, the favicon is dropped (the artifact has its own icon). Run: python pack.py"""
import glob
import re

ROLES = {
    'u01': ('SeaStock PPG Admin', 'ppg-admin.html'),
    'u06': ('SeaStock Customer Admin', 'customer-admin.html'),
    'u12': ('SeaStock Ship Admin', 'ship-admin.html'),
}
FONTS = ('<link rel="preconnect" href="https://fonts.googleapis.com">\n'
         '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n'
         '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700'
         '&family=IBM+Plex+Mono:wght@400;500&display=swap">')

for user, (title, out) in ROLES.items():
    css = open(glob.glob(f'dist-{user}/assets/*.css')[0], encoding='utf-8').read()
    js = open(glob.glob(f'dist-{user}/assets/*.js')[0], encoding='utf-8').read()
    # A literal "</script" inside the bundle would end the inline script early.
    js = re.sub(r'</(script)', r'<\\/\1', js, flags=re.I)
    css = css.replace('</style', '<\\/style')
    page = (f'<title>{title}</title>\n{FONTS}\n<style>\n{css}\n</style>\n'
            f'<div id="root"></div>\n<script type="module">\n{js}\n</script>\n')
    open(out, 'w', encoding='utf-8').write(page)
    print(out, round(len(page) / 1024), 'KB')
