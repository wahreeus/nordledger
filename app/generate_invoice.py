import json
import os
import re
import sys
from datetime import datetime

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle


SELLER = {
    "name": "NordLedger AB",
    "lines": [
        "Drottninggatan 1",
        "123 45 Stockholm",
        "Sweden",
        "billing@nordledger.com",
    ],
}


def money(amount, currency="EUR"):
    return f"{currency} {amount:,.2f}"


def load_json_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def calculate_total_amount(entries):
    return sum(float(entry["quantity"]) * float(entry["unit_price"]) for entry in entries)


def validate_customer_data(customer):
    required_fields = {
        "customer_id": str,
        "company_name": str,
        "streetadress": str,
        "postalcode": str,
        "city": str,
        "country": str,
        "currency": str,
    }

    for field, expected_type in required_fields.items():
        if field not in customer:
            raise ValueError(f"Customer is missing required field: {field}")
        if not isinstance(customer[field], expected_type):
            raise TypeError(
                f"Customer field '{field}' must be of type {expected_type.__name__}, got {type(customer[field]).__name__}"
            )

    if not re.fullmatch(r"\d{6}", customer["customer_id"]):
        raise ValueError("customer_id must be in format 123456")

    if not customer["company_name"].strip():
        raise ValueError("company_name must not be empty")

    if not re.fullmatch(r"[A-Z]{3}", customer["currency"]):
        raise ValueError("currency must be a 3-letter uppercase code like EUR or SEK")



def validate_invoice_data(invoice):
    required_fields = {
        "invoice_id": str,
        "customer_id": str,
        "issue_date": str,
        "due_date": str,
        "entries": list,
    }

    for field, expected_type in required_fields.items():
        if field not in invoice:
            raise ValueError(f"Invoice is missing required field: {field}")
        if not isinstance(invoice[field], expected_type):
            raise TypeError(
                f"Invoice field '{field}' must be of type {expected_type.__name__}, got {type(invoice[field]).__name__}"
            )

    if not re.fullmatch(r"\d{12}", invoice["invoice_id"]):
        raise ValueError("invoice_id must be in format INV-20260001")

    if not re.fullmatch(r"\d{6}", invoice["customer_id"]):
        raise ValueError("customer_id must be in format 123456")

    for date_field in ["issue_date", "due_date"]:
        try:
            datetime.strptime(invoice[date_field], "%Y-%m-%d")
        except ValueError:
            raise ValueError(f"{date_field} must be in format YYYY-MM-DD")

    issue_date = datetime.strptime(invoice["issue_date"], "%Y-%m-%d")
    due_date = datetime.strptime(invoice["due_date"], "%Y-%m-%d")

    if due_date < issue_date:
        raise ValueError("due_date cannot be earlier than issue_date")

    if len(invoice["entries"]) == 0:
        raise ValueError("entries must contain at least one item")

    for index, entry in enumerate(invoice["entries"]):
        if not isinstance(entry, dict):
            raise TypeError(f"entries[{index}] must be an object")

        for field in ["service", "quantity", "unit_price"]:
            if field not in entry:
                raise ValueError(f"entries[{index}] is missing required field: {field}")

        if not isinstance(entry["service"], str) or not entry["service"].strip():
            raise ValueError(f"entries[{index}]['service'] must be a non-empty string")

        if not isinstance(entry["quantity"], (int, float)):
            raise TypeError(f"entries[{index}]['quantity'] must be a number")
        if entry["quantity"] <= 0:
            raise ValueError(f"entries[{index}]['quantity'] must be greater than 0")

        if not isinstance(entry["unit_price"], (int, float)):
            raise TypeError(f"entries[{index}]['unit_price'] must be a number")
        if entry["unit_price"] < 0:
            raise ValueError(f"entries[{index}]['unit_price'] cannot be negative")



def build_invoice_document(invoice, customer):
    validate_invoice_data(invoice)
    validate_customer_data(customer)

    if invoice["customer_id"] != customer["customer_id"]:
        raise ValueError(
            f"Invoice {invoice['invoice_id']} customer_id does not match customer record"
        )

    total_amount = calculate_total_amount(invoice["entries"])

    return {
        "seller": SELLER,
        "buyer": {
            "name": customer["company_name"],
            "lines": [
                customer["streetadress"],
                f"{customer['postalcode']} {customer['city']}",
                customer["country"]
                
            ],
        },
        "meta": {
            "invoice_number": invoice["invoice_id"],
            "customer_id": invoice["customer_id"],
            "invoice_date": invoice["issue_date"],
            "due_date": invoice["due_date"],
        },
        "items": [
            {
                "description": entry["service"],
                "qty": float(entry["quantity"]),
                "unit_price": float(entry["unit_price"]),
            }
            for entry in invoice["entries"]
        ],
        "currency": customer["currency"],
        "total_amount": total_amount,
        "note": "Please pay by the due date to avoid extra fees. Thank you for your business.",
    }



def render_invoice_pdf(pdf_invoice, filename):
    doc = SimpleDocTemplate(
        filename,
        pagesize=A4,
        leftMargin=22 * mm,
        rightMargin=22 * mm,
        topMargin=18 * mm,
        bottomMargin=18 * mm,
    )

    page_width = doc.width
    styles = getSampleStyleSheet()

    normal = ParagraphStyle(
        "NormalCustom",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=10.5,
        leading=14,
        alignment=TA_LEFT,
    )

    small = ParagraphStyle(
        "SmallCustom",
        parent=normal,
        fontSize=9,
        leading=12,
        textColor=colors.HexColor("#666666"),
    )

    right = ParagraphStyle(
        "RightCustom",
        parent=normal,
        alignment=TA_RIGHT,
    )

    invoice_title = ParagraphStyle(
        "InvoiceTitle",
        parent=normal,
        fontName="Helvetica-Bold",
        fontSize=30,
        leading=34,
        alignment=TA_LEFT,
    )

    right_bold = ParagraphStyle(
        "RightBoldCustom",
        parent=right,
        fontName="Helvetica-Bold",
    )

    elements = []

    invoice_block = Table(
        [
            [Paragraph("INVOICE", invoice_title)],
            [Paragraph("&nbsp;", normal)],
            [Paragraph(f"<b>Invoice Number:</b> {pdf_invoice['meta']['invoice_number']}", normal)],
            [Paragraph(f"<b>Customer ID:</b> {pdf_invoice['meta']['customer_id']}", normal)],
            [Paragraph(f"<b>Invoice Date:</b> {pdf_invoice['meta']['invoice_date']}", normal)],
            [Paragraph(f"<b>Due Date:</b> {pdf_invoice['meta']['due_date']}", normal)],
            [Paragraph("&nbsp;", normal)],
        ],
        colWidths=[page_width * 0.52],
        hAlign="LEFT",
    )
    invoice_block.setStyle(
        TableStyle(
            [
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
            ]
        )
    )

    seller_text = (
        f"<b>{pdf_invoice['seller']['name']}</b><br/>"
        + "<br/>".join(pdf_invoice["seller"]["lines"])
    )

    bill_to_text = (
        "<b>Bill To</b><br/>"
        f"{pdf_invoice['buyer']['name']}<br/>"
        + "<br/>".join(pdf_invoice["buyer"]["lines"])
    )

    top_layout = Table(
        [
            [invoice_block, Paragraph("", normal)],
            [Paragraph(seller_text, normal), Paragraph(bill_to_text, normal)],
        ],
        colWidths=[page_width * 0.55, page_width * 0.45],
        hAlign="LEFT",
    )
    top_layout.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
                ("SPAN", (0, 0), (0, 0)),
            ]
        )
    )

    elements.append(top_layout)
    elements.append(Spacer(1, 12 * mm))

    item_rows = [[
        Paragraph("<b>Description</b>", normal),
        Paragraph("<b>Qty</b>", right),
        Paragraph("<b>Unit Price</b>", right),
        Paragraph("<b>Total</b>", right),
    ]]

    for item in pdf_invoice["items"]:
        line_total = item["qty"] * item["unit_price"]
        qty_display = int(item["qty"]) if item["qty"].is_integer() else item["qty"]

        item_rows.append(
            [
                Paragraph(item["description"], normal),
                Paragraph(str(qty_display), right),
                Paragraph(money(item["unit_price"], pdf_invoice["currency"]), right),
                Paragraph(money(line_total, pdf_invoice["currency"]), right),
            ]
        )

    items_table = Table(
        item_rows,
        colWidths=[
            page_width * 0.52,
            page_width * 0.08,
            page_width * 0.20,
            page_width * 0.20,
        ],
        repeatRows=1,
        hAlign="LEFT",
    )
    items_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F3F3F3")),
                ("LINEBELOW", (0, 0), (-1, 0), 1, colors.HexColor("#9E9E9E")),
                ("LINEBELOW", (0, 1), (-1, -1), 0.35, colors.HexColor("#D9D9D9")),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ALIGN", (1, 1), (-1, -1), "RIGHT"),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
                ("FONTSIZE", (0, 0), (-1, -1), 10.5),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )

    elements.append(items_table)
    elements.append(Spacer(1, 6 * mm))

    totals_table = Table(
        [[
            Paragraph("<b>Total</b>", right_bold),
            Paragraph(f"<b>{money(pdf_invoice['total_amount'], pdf_invoice['currency'])}</b>", right_bold),
        ]],
        colWidths=[page_width * 0.16, page_width * 0.18],
        hAlign="RIGHT",
    )
    totals_table.setStyle(
        TableStyle(
            [
                ("LINEABOVE", (0, -1), (-1, -1), 1, colors.black),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ("FONTSIZE", (0, 0), (-1, -1), 10.5),
            ]
        )
    )

    elements.append(totals_table)
    elements.append(Spacer(1, 14 * mm))
    elements.append(Paragraph(pdf_invoice["note"], small))

    doc.build(elements)
    print(f"Created {filename}")



def generate_invoice_pdf(invoice, customer, output_dir="."):
    pdf_invoice = build_invoice_document(invoice, customer)
    filename = os.path.join(output_dir, f"CUST_{invoice['customer_id']}-INV_{invoice['invoice_id']}.pdf")
    render_invoice_pdf(pdf_invoice, filename)



def build_customer_lookup(customers):
    customer_lookup = {}
    for customer in customers:
        validate_customer_data(customer)
        customer_id = customer["customer_id"]
        if customer_id in customer_lookup:
            raise ValueError(f"Duplicate customer_id found: {customer_id}")
        customer_lookup[customer_id] = customer
    return customer_lookup



def generate_from_files(customers_path, invoices_path, output_dir=".", invoice_id=None):
    customers = load_json_file(customers_path)
    invoices = load_json_file(invoices_path)

    if not isinstance(customers, list):
        raise TypeError("Customers file must contain a JSON array")
    if not isinstance(invoices, list):
        raise TypeError("Invoices file must contain a JSON array")

    customer_lookup = build_customer_lookup(customers)

    os.makedirs(output_dir, exist_ok=True)

    generated_count = 0
    for invoice in invoices:
        validate_invoice_data(invoice)

        if invoice_id and invoice["invoice_id"] != invoice_id:
            continue

        customer = customer_lookup.get(invoice["customer_id"])
        if customer is None:
            raise ValueError(
                f"No customer found for invoice {invoice['invoice_id']} with customer_id {invoice['customer_id']}"
            )

        generate_invoice_pdf(invoice, customer, output_dir=output_dir)
        generated_count += 1

    if invoice_id and generated_count == 0:
        raise ValueError(f"Invoice ID not found: {invoice_id}")

    print(f"Generated {generated_count} invoice PDF(s) in {output_dir}")


if __name__ == "__main__":
    if len(sys.argv) < 3 or len(sys.argv) > 5:
        print(
            "Usage:\n"
            "  python3 generate_invoices_from_files.py <customers.json> <invoices.json>\n"
            "  python3 generate_invoices_from_files.py <customers.json> <invoices.json> <invoice_id>\n"
            "  python3 generate_invoices_from_files.py <customers.json> <invoices.json> <invoice_id> <output_dir>\n"
            "  python3 generate_invoices_from_files.py <customers.json> <invoices.json> - <output_dir>\n"
            "\n"
            "Use '-' as <invoice_id> to generate all invoices into a custom output directory."
        )
        sys.exit(1)

    customers_path = sys.argv[1]
    invoices_path = sys.argv[2]
    invoice_id = None
    output_dir = "."

    if len(sys.argv) >= 4 and sys.argv[3] != "-":
        invoice_id = sys.argv[3]
    if len(sys.argv) == 5:
        output_dir = sys.argv[4]
    elif len(sys.argv) == 4 and sys.argv[3] == "-":
        print("Failed: when using '-' you must also provide an output directory")
        sys.exit(1)

    try:
        generate_from_files(customers_path, invoices_path, output_dir=output_dir, invoice_id=invoice_id)
    except json.JSONDecodeError:
        print("Error: one of the input files does not contain valid JSON")
        sys.exit(1)
    except (ValueError, TypeError, OSError) as e:
        print(f"Failed: {e}")
        sys.exit(1)
