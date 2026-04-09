import io
import os
from decimal import Decimal
from typing import Any, Dict, Iterable, List, Tuple

import boto3
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from db_common import (
    CUSTOMERS_TABLE,
    INVOICE_ITEMS_TABLE,
    INVOICES_TABLE,
    NotFoundError,
    ValidationError,
    get_db_connection,
    json_response,
    parse_event_payload,
)


s3 = boto3.client("s3")

SELLER = {
    "name": os.environ.get("SELLER_NAME", "NordLedger AB"),
    "lines": [
        os.environ.get("SELLER_LINE_1", "Drottninggatan 1"),
        os.environ.get("SELLER_LINE_2", "123 45 Stockholm"),
        os.environ.get("SELLER_LINE_3", "Sweden"),
        os.environ.get("SELLER_LINE_4", "billing@nordledger.com"),
    ],
}

INVOICE_BUCKET = os.environ["INVOICE_BUCKET"]
PDF_PREFIX = os.environ.get("PDF_PREFIX", "invoices")


def money(amount: float, currency: str = "EUR") -> str:
    return f"{currency} {amount:,.2f}"


def to_float(value: Any) -> float:
    if isinstance(value, Decimal):
        return float(value)
    return float(value)


def fetch_invoice_and_customer(connection, invoice_id: str) -> Tuple[Dict[str, Any], Dict[str, Any], List[Dict[str, Any]]]:
    cursor = connection.cursor()

    cursor.execute(
        f"""
        SELECT
            i.invoice_id,
            i.customer_id,
            i.issue_date,
            i.due_date,
            c.company_name,
            c.streetadress,
            c.postalcode,
            c.city,
            c.country,
            c.currency
        FROM {INVOICES_TABLE} AS i
        JOIN {CUSTOMERS_TABLE} AS c
          ON c.customer_id = i.customer_id
        WHERE i.invoice_id = %s
        """,
        (invoice_id,),
    )
    row = cursor.fetchone()

    if not row:
        raise NotFoundError(f"Invoice not found: {invoice_id}")

    invoice = {
        "invoice_id": str(row[0]),
        "customer_id": str(row[1]),
        "issue_date": str(row[2]),
        "due_date": str(row[3]),
    }

    customer = {
        "customer_id": str(row[1]),
        "company_name": row[4],
        "streetadress": row[5],
        "postalcode": str(row[6]),
        "city": row[7],
        "country": row[8],
        "currency": row[9],
    }

    cursor.execute(
        f"""
        SELECT
            service,
            quantity,
            unit_price
        FROM {INVOICE_ITEMS_TABLE}
        WHERE invoice_id = %s
        ORDER BY item_id ASC
        """,
        (invoice_id,),
    )
    item_rows = cursor.fetchall()

    if not item_rows:
        raise NotFoundError(f"No invoice items found for invoice: {invoice_id}")

    items = [
        {
            "service": item[0],
            "quantity": to_float(item[1]),
            "unit_price": to_float(item[2]),
        }
        for item in item_rows
    ]

    return invoice, customer, items


def fetch_invoice_ids_for_customer(connection, customer_id: str) -> List[str]:
    cursor = connection.cursor()
    cursor.execute(
        f"""
        SELECT invoice_id
        FROM {INVOICES_TABLE}
        WHERE customer_id = %s
        ORDER BY issue_date DESC, invoice_id DESC
        """,
        (customer_id,),
    )
    rows = cursor.fetchall()
    return [str(row[0]) for row in rows]


def calculate_total_amount(entries: Iterable[Dict[str, Any]]) -> float:
    return sum(to_float(entry["quantity"]) * to_float(entry["unit_price"]) for entry in entries)


def build_invoice_document(invoice: Dict[str, Any], customer: Dict[str, Any], entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    total_amount = calculate_total_amount(entries)

    return {
        "seller": SELLER,
        "buyer": {
            "name": customer["company_name"],
            "lines": [
                customer["streetadress"],
                f"{customer['postalcode']} {customer['city']}",
                customer["country"],
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
                "qty": to_float(entry["quantity"]),
                "unit_price": to_float(entry["unit_price"]),
            }
            for entry in entries
        ],
        "currency": customer["currency"],
        "total_amount": total_amount,
        "note": "Please pay by the due date to avoid extra fees. Thank you for your business.",
    }


def render_invoice_pdf(pdf_invoice: Dict[str, Any]) -> bytes:
    buffer = io.BytesIO()

    doc = SimpleDocTemplate(
        buffer,
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
        qty_display = int(item["qty"]) if float(item["qty"]).is_integer() else item["qty"]

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
    return buffer.getvalue()


def build_s3_key(invoice_id: str, customer_id: str) -> str:
    prefix = PDF_PREFIX.strip("/")
    return f"{prefix}/{customer_id}/CUST_{customer_id}-INV_{invoice_id}.pdf"


def upload_pdf_to_s3(pdf_bytes: bytes, bucket: str, key: str) -> None:
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=pdf_bytes,
        ContentType="application/pdf",
    )


def generate_and_upload_invoice(connection, invoice_id: str) -> Dict[str, Any]:
    invoice, customer, items = fetch_invoice_and_customer(connection, invoice_id)
    pdf_invoice = build_invoice_document(invoice, customer, items)
    pdf_bytes = render_invoice_pdf(pdf_invoice)
    s3_key = build_s3_key(invoice_id=invoice["invoice_id"], customer_id=invoice["customer_id"])
    upload_pdf_to_s3(pdf_bytes, INVOICE_BUCKET, s3_key)

    return {
        "invoice_id": invoice["invoice_id"],
        "customer_id": invoice["customer_id"],
        "bucket": INVOICE_BUCKET,
        "key": s3_key,
        "s3_uri": f"s3://{INVOICE_BUCKET}/{s3_key}",
    }


def lambda_handler(event, context):
    connection = None
    try:
        payload = parse_event_payload(event)
        invoice_id = str(payload.get("invoice_id", "")).strip()
        customer_id = str(payload.get("customer_id", "")).strip()

        if not invoice_id and not customer_id:
            raise ValidationError("Provide either invoice_id or customer_id.")

        connection = get_db_connection()

        if invoice_id:
            result = generate_and_upload_invoice(connection, invoice_id)
            return json_response(200, {"generated": 1, "files": [result]})

        invoice_ids = fetch_invoice_ids_for_customer(connection, customer_id)
        if not invoice_ids:
            raise NotFoundError(f"No invoices found for customer: {customer_id}")

        files = [generate_and_upload_invoice(connection, current_invoice_id) for current_invoice_id in invoice_ids]
        return json_response(200, {"generated": len(files), "files": files})

    except ValidationError as exc:
        return json_response(
            400,
            {
                "message": str(exc),
                "example_single": {"invoice_id": "807126593418"},
                "example_customer_batch": {"customer_id": "731406"},
            },
        )
    except NotFoundError as exc:
        return json_response(404, {"message": str(exc)})
    except Exception as exc:
        return json_response(
            500,
            {
                "message": "Failed to generate invoice PDF.",
                "error": str(exc),
            },
        )
    finally:
        if connection is not None:
            connection.close()
