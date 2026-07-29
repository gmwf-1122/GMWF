import openpyxl
wb = openpyxl.load_workbook("e:/GMWF/gmwf/GRT DAILY Donation Record.xlsx", read_only=True)
print("Sheet names:", wb.sheetnames)
