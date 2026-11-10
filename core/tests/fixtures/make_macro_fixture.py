#!/usr/bin/env python3
"""Builds macro_workbook.xlsm: a small macro-enabled workbook for the UI tests (scripts/ui_tests.sh).

Synthetic: the "VBA project" is a placeholder blob, not real VBA. Foglio never runs or parses
macros; it only has to copy xl/vbaProject.bin verbatim and restore the code names
(ThisWorkbook / Sheet1 / Sheet2) when the workbook is saved as .xlsm.
Run: /usr/bin/python3 make_macro_fixture.py   (needs openpyxl)
"""
import io
import os
import zipfile

from openpyxl import Workbook

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "macro_workbook.xlsm")

wb = Workbook()
ws = wb.active
ws.title = "Orders"
ws.append(["Item", "Qty", "Price", "Total"])
ws.append(["Paper", 10, 2.5, "=B2*C2"])
ws.append(["Pens", 4, 1.2, "=B3*C3"])
ws["D4"] = "=SUM(D2:D3)"
wb.create_sheet("Notes")["A1"] = "Macros run in Excel only"
buf = io.BytesIO()
wb.save(buf)

VBA = bytes((i * 31 + 7) % 251 for i in range(8192))  # placeholder, not a real VBA project
src = zipfile.ZipFile(io.BytesIO(buf.getvalue()))
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as out:
    for item in src.infolist():
        data = src.read(item.filename)
        if item.filename == "[Content_Types].xml":
            data = data.replace(b"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
                                b"application/vnd.ms-excel.sheet.macroEnabled.main+xml")
            data = data.replace(b"</Types>", b'<Default Extension="bin" ContentType="application/vnd.ms-office.vbaProject"/></Types>')
        elif item.filename == "xl/_rels/workbook.xml.rels":
            data = data.replace(b"</Relationships>", b'<Relationship Id="rId99" Type="http://schemas.microsoft.com/office/2006/relationships/vbaProject" Target="vbaProject.bin"/></Relationships>')
        elif item.filename == "xl/workbook.xml":
            data = data.replace(b"<workbookPr", b'<workbookPr codeName="ThisWorkbook"', 1)
        elif item.filename.startswith("xl/worksheets/sheet"):
            n = item.filename[len("xl/worksheets/sheet"):-4]
            data = data.replace(b"<sheetPr", b'<sheetPr codeName="Sheet' + n.encode() + b'"', 1)
        out.writestr(item, data)
    out.writestr("xl/vbaProject.bin", VBA)
print("wrote", OUT)
