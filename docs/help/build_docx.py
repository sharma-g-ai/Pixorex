"""Builds SeaStock-Help.docx from the same content as help.html.
Uses the screenshots with the boxes drawn in (img-marked/, from annotate.py).
Run: python build_docx.py"""
import html
import json
import re
import sys

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

sys.path.insert(0, '.')
from content import INTRO, ROLES, SCREENS, WORDS  # noqa: E402

shots = json.load(open('img/shots.json', encoding='utf-8'))

# Same palette and type as help.html (light theme).
NAVY, BLUE, CYAN = RGBColor(0x00, 0x33, 0x66), RGBColor(0x00, 0x52, 0x9B), RGBColor(0x00, 0x91, 0xC8)
INK, MUTED, LINE = RGBColor(0x14, 0x22, 0x33), RGBColor(0x56, 0x65, 0x77), 'DBE3EC'
MARK, MARK_SOFT, SOFT = 'F07D00', 'FDEEDF', 'E7F0F9'
DISPLAY, BODY = 'Barlow Semi Condensed', 'Source Sans 3'

doc = Document()
sec = doc.sections[0]
sec.page_width, sec.page_height = Inches(8.27), Inches(11.69)  # A4
for side in ('left_margin', 'right_margin'):
    setattr(sec, side, Inches(0.75))
sec.top_margin, sec.bottom_margin = Inches(0.7), Inches(0.7)
WIDTH = Inches(8.27 - 1.5)


def set_font(target, name, size=None, bold=None, color=None):
    target.font.name = name
    rpr = target.element.get_or_add_rPr() if hasattr(target.element, 'get_or_add_rPr') else target.element.rPr
    fonts = rpr.find(qn('w:rFonts'))
    if fonts is None:
        fonts = OxmlElement('w:rFonts')
        rpr.insert(0, fonts)
    for attr in ('w:ascii', 'w:hAnsi', 'w:cs', 'w:eastAsia'):
        fonts.set(qn(attr), name)
    if size:
        target.font.size = Pt(size)
    if bold is not None:
        target.font.bold = bold
    if color is not None:
        target.font.color.rgb = color


def style(name, font, size, bold, color, before, after):
    s = doc.styles[name]
    set_font(s, font, size, bold, color)
    s.font.italic = False
    s.paragraph_format.space_before, s.paragraph_format.space_after = Pt(before), Pt(after)
    return s


style('Normal', BODY, 11, False, INK, 0, 6).paragraph_format.line_spacing = 1.2
style('Title', DISPLAY, 34, True, NAVY, 0, 8)
style('Heading 1', DISPLAY, 26, True, NAVY, 0, 6)
style('Heading 2', DISPLAY, 18, True, NAVY, 18, 4)
style('Heading 3', DISPLAY, 15, True, INK, 14, 6)

for name in ('Heading 1', 'Heading 2', 'Heading 3'):
    doc.styles[name].paragraph_format.keep_with_next = True


def shade(cell_or_par, fill):
    el = cell_or_par._tc.get_or_add_tcPr() if hasattr(cell_or_par, '_tc') else cell_or_par._p.get_or_add_pPr()
    sh = OxmlElement('w:shd')
    sh.set(qn('w:val'), 'clear')
    sh.set(qn('w:color'), 'auto')
    sh.set(qn('w:fill'), fill)
    el.append(sh)


def border(par, side, color, size=8, space=4):
    ppr = par._p.get_or_add_pPr()
    bdr = ppr.find(qn('w:pBdr'))
    if bdr is None:
        bdr = OxmlElement('w:pBdr')
        ppr.append(bdr)
    b = OxmlElement(f'w:{side}')
    for k, v in (('val', 'single'), ('sz', str(size)), ('space', str(space)), ('color', color)):
        b.set(qn(f'w:{k}'), v)
    bdr.append(b)


def cell_borders(cell, color=LINE, sides=('top', 'left', 'bottom', 'right'), size=6):
    tcpr = cell._tc.get_or_add_tcPr()
    bdr = OxmlElement('w:tcBorders')
    for side in ('top', 'left', 'bottom', 'right'):
        b = OxmlElement(f'w:{side}')
        if side in sides:
            for k, v in (('val', 'single'), ('sz', str(size)), ('space', '0'), ('color', color)):
                b.set(qn(f'w:{k}'), v)
        else:
            b.set(qn('w:val'), 'nil')
        bdr.append(b)
    tcpr.append(bdr)


def cell_margins(cell, top=80, bottom=80, left=120, right=120):
    tcpr = cell._tc.get_or_add_tcPr()
    mar = OxmlElement('w:tcMar')
    for side, v in (('top', top), ('bottom', bottom), ('start', left), ('end', right)):
        m = OxmlElement(f'w:{side}')
        m.set(qn('w:w'), str(v))
        m.set(qn('w:type'), 'dxa')
        mar.append(m)
    tcpr.append(mar)


def no_table_borders(table):
    tblpr = table._tbl.tblPr
    bdr = OxmlElement('w:tblBorders')
    for side in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'):
        b = OxmlElement(f'w:{side}')
        b.set(qn('w:val'), 'nil')
        bdr.append(b)
    tblpr.append(bdr)


def widths(table, inches):
    table.autofit = False
    for row in table.rows:
        for cell, w in zip(row.cells, inches):
            cell.width = Inches(w)


def rich(par, text, size=None, color=None):
    """Adds text with <b>…</b> as bold runs; decodes &amp; and friends."""
    for i, part in enumerate(re.split(r'</?b>', text)):
        if not part:
            continue
        run = par.add_run(html.unescape(part))
        run.bold = i % 2 == 1
        if size:
            run.font.size = Pt(size)
        if color is not None:
            run.font.color.rgb = color
    return par


def toc(par):
    run = par.add_run()
    for kind, text in (('begin', None), (None, 'TOC \\o "1-2" \\h \\z \\u'), ('separate', None), (None, None), ('end', None)):
        if kind:
            fc = OxmlElement('w:fldChar')
            fc.set(qn('w:fldCharType'), kind)
            run._r.append(fc)
        elif text:
            it = OxmlElement('w:instrText')
            it.set(qn('xml:space'), 'preserve')
            it.text = text
            run._r.append(it)
        else:
            t = OxmlElement('w:t')
            t.text = 'Right-click here and choose Update Field to show the contents.'
            run._r.append(t)


def page_number(par):
    run = par.add_run()
    for kind, text in (('begin', None), (None, 'PAGE'), ('end', None)):
        if kind:
            fc = OxmlElement('w:fldChar')
            fc.set(qn('w:fldCharType'), kind)
            run._r.append(fc)
        else:
            it = OxmlElement('w:instrText')
            it.set(qn('xml:space'), 'preserve')
            it.text = text
            run._r.append(it)
    run.font.size, run.font.color.rgb = Pt(9), MUTED


def figure(fig, title=None):
    shot = shots[fig['shot']]
    if len(shot['boxes']) != len(fig['items']):
        raise SystemExit(f"{fig['shot']}: boxes and explanations differ")
    if title:
        doc.add_heading(title, level=3)
    pic = doc.add_paragraph()
    pic.paragraph_format.keep_with_next = True
    pic.paragraph_format.space_before = Pt(6)
    pic.add_run().add_picture(f"img-marked/{fig['shot']}.png", width=WIDTH)
    cap = doc.add_paragraph()
    cap.paragraph_format.keep_with_next = True
    rich(cap, fig['caption'], size=9.5, color=MUTED)
    table = doc.add_table(rows=0, cols=2)
    no_table_borders(table)
    for n, text in enumerate(fig['items'], 1):
        row = table.add_row()
        num, body = row.cells
        shade(num, MARK)
        num.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.TOP
        cell_margins(num, 40, 40, 0, 0)
        p = num.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(0)
        r = p.add_run(str(n))
        set_font(r, BODY, 10, True, RGBColor(0xFF, 0xFF, 0xFF))
        cell_margins(body, 40, 60, 160, 0)
        bp = body.paragraphs[0]
        bp.paragraph_format.space_after = Pt(2)
        rich(bp, text)
    widths(table, [0.28, WIDTH.inches - 0.28])
    doc.add_paragraph().paragraph_format.space_after = Pt(6)


# ---- Footer: name and page number ----
foot = sec.footer.paragraphs[0]
foot.alignment = WD_ALIGN_PARAGRAPH.RIGHT
r = foot.add_run('PPG SeaStock help   ·   page ')
r.font.size, r.font.color.rgb = Pt(9), MUTED
page_number(foot)

# ---- Opening ----
brand = doc.add_paragraph()
brand.paragraph_format.space_after = Pt(2)
r = brand.add_run('PPG ')
set_font(r, DISPLAY, 20, True, NAVY)
r = brand.add_run('SeaStock')
set_font(r, DISPLAY, 20, True, CYAN)
tag = doc.add_paragraph()
r = tag.add_run('HELP')
set_font(r, BODY, 9, True, MUTED)
r.font.all_caps = True
tag.paragraph_format.space_after = Pt(18)

doc.add_paragraph(INTRO['title'], style='Title')
lead = rich(doc.add_paragraph(), INTRO['lead'], size=13)
lead.paragraph_format.space_after = Pt(10)
pre = rich(doc.add_paragraph(), INTRO['preview'], size=10.5)
shade(pre, MARK_SOFT)
border(pre, 'left', MARK, size=18, space=8)
pre.paragraph_format.left_indent = Inches(0.12)
pre.paragraph_format.space_after = Pt(16)

doc.add_heading('Contents', level=2)
toc(doc.add_paragraph())

doc.add_heading('How to read this guide', level=2)
for t in INTRO['how']:
    rich(doc.add_paragraph(style='List Bullet'), t)

doc.add_heading('Roles', level=2)
roles = doc.add_table(rows=1, cols=len(ROLES))
roles.alignment = WD_TABLE_ALIGNMENT.CENTER
no_table_borders(roles)
for cell, (name, text) in zip(roles.rows[0].cells, ROLES):
    cell_borders(cell)
    cell_margins(cell, 120, 120, 160, 160)
    p = cell.paragraphs[0]
    r = p.add_run(name)
    set_font(r, DISPLAY, 14, True, BLUE)
    rich(cell.add_paragraph(), text, size=10, color=MUTED)
widths(roles, [WIDTH.inches / 3] * 3)

doc.add_heading('Words used in SeaStock', level=2)
words = doc.add_table(rows=0, cols=2)
no_table_borders(words)
for w, t in WORDS:
    a, b = words.add_row().cells
    cell_margins(a, 40, 40, 0, 160)
    cell_margins(b, 40, 40, 0, 0)
    r = a.paragraphs[0].add_run(w)
    r.bold = True
    rich(b.paragraphs[0], t, color=MUTED)
widths(words, [1.6, WIDTH.inches - 1.6])

# ---- One part per screen, each starting on a new page ----
for s in SCREENS:
    doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
    h = doc.add_heading(s['title'], level=1)
    border(h, 'top', LINE, size=12, space=10)
    rich(doc.add_paragraph(), s['intro'])
    for fig in s['figures']:
        figure(fig)
    if s.get('popups'):
        doc.add_heading('Pop-ups on this screen', level=2)
        for p in s['popups']:
            figure(p, p['title'])

# Ask Word to fill in the contents when the file opens.
upd = OxmlElement('w:updateFields')
upd.set(qn('w:val'), 'true')
doc.settings.element.append(upd)

doc.core_properties.title = 'SeaStock Help'
doc.core_properties.subject = 'PPG SeaStock web portal: screens, parts and pop-ups'
doc.save('SeaStock-Help.docx')
print('saved SeaStock-Help.docx')
