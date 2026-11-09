"""Generates pictures_openpyxl.xlsx (used by tests/pictures.rs) with openpyxl
and Pillow: a PNG and a JPEG picture next to a chart and a comment on one
sheet, the same PNG again on a second sheet.

    python3 make_pictures_fixture.py   # needs openpyxl and pillow
"""
import io
import os

from openpyxl import Workbook
from openpyxl.chart import BarChart, Reference
from openpyxl.comments import Comment
from openpyxl.drawing.image import Image
from PIL import Image as PILImage, ImageDraw


def png_bytes():
    im = PILImage.new("RGBA", (120, 80), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((10, 10, 110, 70), fill=(220, 60, 40, 255))
    b = io.BytesIO()
    im.save(b, "PNG")
    return b.getvalue()


def jpeg_bytes():
    im = PILImage.new("RGB", (200, 100))
    for x in range(200):
        for y in range(100):
            im.putpixel((x, y), (x, y * 2, 128))
    b = io.BytesIO()
    im.save(b, "JPEG", quality=85)
    return b.getvalue()


wb = Workbook()
ws = wb.active
ws.title = "Pics"
for i, (m, v) in enumerate([("Jan", 3), ("Feb", 5), ("Mar", 4)], start=1):
    ws.cell(i, 1, m)
    ws.cell(i, 2, v)
ws["A1"].comment = Comment("A note", "Tester")
chart = BarChart()
chart.add_data(Reference(ws, min_col=2, min_row=1, max_row=3))
ws.add_chart(chart, "H2")
img = Image(io.BytesIO(png_bytes()))
ws.add_image(img, "D2")
img2 = Image(io.BytesIO(jpeg_bytes()))
ws.add_image(img2, "D20")
ws2 = wb.create_sheet("More")
ws2.add_image(Image(io.BytesIO(png_bytes())), "B3")
wb.save(os.path.join(os.path.dirname(os.path.abspath(__file__)), "pictures_openpyxl.xlsx"))
