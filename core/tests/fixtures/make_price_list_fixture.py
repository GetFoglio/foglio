"""Generates price_list_layout.xlsx (used by tests/pictures.rs and scripts/ui_tests.sh): the layout of a typical
Excel price list, with made-up products. What it reproduces:

* header row frozen with `state="frozenSplit"` (as Excel writes panes frozen after a split), no grid lines;
* every product row merges C:E, and each cell of the merge carries the full thin border (Excel stores the border on
  every cell of a merged range; only the outline is shown);
* prices with a euro number format, a hidden row and a hidden column;
* a tall row with product photos grouped in one group shape (`xdr:grpSp` with scaled child coordinates and a
  nested group), and a logo inside a single header cell, not centred.

    python3 make_price_list_fixture.py   # needs openpyxl and pillow
"""
import io
import os
import re
import zipfile

from openpyxl import Workbook
from openpyxl.drawing.image import Image
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from PIL import Image as PILImage, ImageDraw

EMU_PX = 9525


def picture(w, h, color):
    im = PILImage.new("RGB", (w, h), (255, 255, 255))
    ImageDraw.Draw(im).rectangle((4, 4, w - 5, h - 5), fill=color)
    b = io.BytesIO()
    im.save(b, "PNG")
    return b


wb = Workbook()
ws = wb.active
ws.title = "Listino"
thin = Side(style="thin", color="FF000000")
thick = Side(style="thick", color="FF000000")
box = Border(left=thin, right=thin, top=thin, bottom=thin)
head = Border(left=thick, right=thick, top=thick, bottom=thick)
grey = PatternFill("solid", fgColor="FFD2D2D2")
orange = PatternFill("solid", fgColor="FFFAC896")
center = Alignment(horizontal="center", vertical="center", wrap_text=True)
bold = Font(name="Calibri", size=9, bold=True)

for col, width in {"A": 17.5, "B": 21, "C": 21, "D": 58.33, "E": 21, "F": 17.5, "G": 14, "H": 11.66}.items():
    ws.column_dimensions[col].width = width
ws.column_dimensions["G"].hidden = True

titles = ["Serie", "Modello", "Descrizione", None, None, "Prezzo", "Nascosta", "Pezzi"]
for c, t in enumerate(titles, start=1):
    cell = ws.cell(1, c, t)
    cell.fill, cell.border, cell.alignment, cell.font = grey, head, center, bold
ws.merge_cells("C1:E1")
ws.row_dimensions[1].height = 63

ws.cell(2, 1, "Borse e zaini").alignment = center
ws.merge_cells("A2:E2")

for r in range(3, 61):
    values = [f"Serie {r % 7}", f"{4000 + r} nero", f"Articolo {r}: borsa per notebook", None, None, 10 + r * 1.25, r, 6 + r % 3]
    for c, v in enumerate(values, start=1):
        cell = ws.cell(r, c, v)
        cell.fill, cell.border, cell.font = orange, box, bold
        cell.alignment = Alignment(horizontal="left" if c == 3 else "center", vertical="center")
    ws.cell(r, 6).number_format = '_-* #,##0.00\\ [$€-407]_-;\\-* #,##0.00\\ [$€-407]_-;_-* \\-??\\ [$€-407]_-;_-@_-'
    ws.merge_cells(start_row=r, start_column=3, end_row=r, end_column=5)
    ws.row_dimensions[r].height = 15
ws.row_dimensions[10].hidden = True
ws.row_dimensions[5].height = 180

ws.freeze_panes = "A2"
ws.sheet_view.showGridLines = False

# Two photos and a logo; the photos are regrouped below.
ws.add_image(Image(picture(160, 120, (200, 40, 60))), "C5")
ws.add_image(Image(picture(90, 150, (40, 80, 200))), "D5")
ws.add_image(Image(picture(100, 50, (20, 60, 90))), "B1")

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "price_list_layout.xlsx")
buf = io.BytesIO()
wb.save(buf)

# Post-processing: frozenSplit, the group shape and the logo's two-cell anchor inside B1.
src = zipfile.ZipFile(io.BytesIO(buf.getvalue()))
dst = zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED)
for item in src.infolist():
    data = src.read(item.filename)
    if item.filename == "xl/worksheets/sheet1.xml":
        data = data.replace(b'state="frozen"', b'state="frozenSplit"')
    if item.filename == "xl/drawings/drawing1.xml":
        xml = data.decode()
        rids = re.findall(r'r:embed="([^"]+)"', xml)
        # Written the way Excel does (xdr:/a: prefixes), replacing openpyxl's one-cell anchors.
        head_xml = (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
            'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        )

        def pic(i, rid, x, y, cx, cy):
            return (
                f'<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="{i}" name="Foto {i}"/><xdr:cNvPicPr/></xdr:nvPicPr>'
                f'<xdr:blipFill><a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="{rid}"/>'
                f'<a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="{x}" y="{y}"/>'
                f'<a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>'
            )

        def point(tag, col, col_off, row, row_off):
            return f"<xdr:{tag}><xdr:col>{col}</xdr:col><xdr:colOff>{col_off}</xdr:colOff><xdr:row>{row}</xdr:row><xdr:rowOff>{row_off}</xdr:rowOff></xdr:{tag}>"

        # Row 5 (index 4) is 180 pt: the group spans column D from 10 px to 300 px, 20 px below the top, 160 px high.
        w, h = 290 * EMU_PX, 160 * EMU_PX
        group = (
            "<xdr:twoCellAnchor>" + point("from", 3, 10 * EMU_PX, 4, 20 * EMU_PX) + point("to", 3, 300 * EMU_PX, 4, 180 * EMU_PX)
            + '<xdr:grpSp><xdr:nvGrpSpPr><xdr:cNvPr id="10" name="Gruppo 1"/><xdr:cNvGrpSpPr/></xdr:nvGrpSpPr>'
            + f'<xdr:grpSpPr><a:xfrm><a:off x="5000000" y="2000000"/><a:ext cx="{w}" cy="{h}"/>'
            + f'<a:chOff x="100000" y="300000"/><a:chExt cx="{w * 2}" cy="{h * 2}"/></a:xfrm></xdr:grpSpPr>'
            + pic(11, rids[0], 100000, 300000, 160 * EMU_PX * 2, 120 * EMU_PX * 2)
            + '<xdr:grpSp><xdr:nvGrpSpPr><xdr:cNvPr id="12" name="Gruppo 2"/><xdr:cNvGrpSpPr/></xdr:nvGrpSpPr>'
            + f'<xdr:grpSpPr><a:xfrm><a:off x="{100000 + 190 * EMU_PX * 2}" y="300000"/><a:ext cx="{90 * EMU_PX * 2}" cy="{150 * EMU_PX * 2}"/>'
            + f'<a:chOff x="0" y="0"/><a:chExt cx="{90 * EMU_PX}" cy="{150 * EMU_PX}"/></a:xfrm></xdr:grpSpPr>'
            + pic(13, rids[1], 0, 0, 90 * EMU_PX, 150 * EMU_PX)
            + "</xdr:grpSp></xdr:grpSp><xdr:clientData/></xdr:twoCellAnchor>"
        )
        logo = (
            "<xdr:twoCellAnchor>" + point("from", 1, 7 * EMU_PX, 0, 10 * EMU_PX) + point("to", 1, 107 * EMU_PX, 0, 60 * EMU_PX)
            + pic(14, rids[2], 0, 0, 100 * EMU_PX, 50 * EMU_PX) + "<xdr:clientData/></xdr:twoCellAnchor>"
        )
        data = (head_xml + group + logo + "</xdr:wsDr>").encode()
    dst.writestr(item, data)
dst.close()
print("wrote", out)
