"""Generates features_openpyxl.xlsx (used by tests/features.rs) with openpyxl:
comments, data validation, hyperlinks, tab colours and font names.

    python3 make_features_fixture.py   # needs openpyxl
"""
import os

from openpyxl import Workbook
from openpyxl.comments import Comment
from openpyxl.styles import Font
from openpyxl.worksheet.datavalidation import DataValidation

wb = Workbook()
ws = wb.active
ws.title = "Data"
ws.sheet_properties.tabColor = "FF0000"
ws["A1"] = "Fruit"
ws["B1"] = "Qty"
for i, (fruit, qty) in enumerate([("apple", 3), ("pear", 5), ("plum", 7)], start=2):
    ws.cell(i, 1, fruit)
    ws.cell(i, 2, qty)
ws["A1"].comment = Comment("Pick a fruit\nfrom the list", "Ada")
ws["C3"].comment = Comment("second note", "Bob")
ws["D1"] = "Arial text"
ws["D1"].font = Font(name="Arial", size=14)
ws["E1"] = "Courier"
ws["E1"].font = Font(name="Courier New")

dv = DataValidation(type="list", formula1='"apple,pear,plum"', allow_blank=True)
dv.error = "Choose from the list"
dv.errorTitle = "Wrong fruit"
dv.prompt = "Which fruit?"
dv.promptTitle = "Fruit"
dv.showErrorMessage = True
dv.showInputMessage = True
dv.add("A2:A10")
ws.add_data_validation(dv)

dv2 = DataValidation(type="whole", operator="between", formula1="1", formula2="10")
dv2.errorStyle = "warning"
dv2.showErrorMessage = True
dv2.add("B2:B10")
ws.add_data_validation(dv2)

dv3 = DataValidation(type="list", formula1="Lists!$A$1:$A$3", showDropDown=True)
dv3.showErrorMessage = True
dv3.add("F2:F5")
dv3.add("H2")
ws.add_data_validation(dv3)

dv4 = DataValidation(type="custom", formula1="ISEVEN(G2)")
dv4.showErrorMessage = True
dv4.add("G2:G10")
ws.add_data_validation(dv4)

ws["A12"] = "IronCalc"
ws["A12"].hyperlink = "https://www.ironcalc.com/"
ws["A13"] = "Go to lists"
ws["A13"].hyperlink = "#Lists!A1"

lists = wb.create_sheet("Lists")
lists.sheet_properties.tabColor = "00B050"
for i, v in enumerate(["red", "green", "blue"], start=1):
    lists.cell(i, 1, v)

wb.save(os.path.join(os.path.dirname(os.path.abspath(__file__)), "features_openpyxl.xlsx"))
