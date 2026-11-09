"""Writes tests/fixtures/sheet_view.xlsx: a sheet saved at 150 % zoom with "show zeros" off, a custom default
row height and an AutoFilter on the header row that hides the "B" rows (made-up data).
Run: python3 make_sheet_view_fixture.py  (needs openpyxl)."""
import os
from openpyxl import Workbook
from openpyxl.worksheet.filters import FilterColumn, Filters

wb = Workbook()
ws = wb.active
ws.title = "Stock"
ws.append(["Item", "Group", "Qty"])
for i in range(1, 13):
    ws.append([f"Item {i}", "A" if i % 3 else "B", 0 if i % 4 == 0 else i * 5])
ws.sheet_view.zoomScale = 150
ws.sheet_view.showZeros = False
ws.sheet_format.defaultRowHeight = 11.45
ws.sheet_format.customHeight = True
ws.auto_filter.ref = "A1:C1"
ws.auto_filter.filterColumn.append(FilterColumn(colId=1, filters=Filters(filter=["A"])))
for r in range(2, 14):
    if ws.cell(r, 2).value == "B":
        ws.row_dimensions[r].hidden = True
wb.save(os.path.join(os.path.dirname(os.path.abspath(__file__)), "sheet_view.xlsx"))
