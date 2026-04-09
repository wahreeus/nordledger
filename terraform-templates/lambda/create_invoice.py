from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, List

from db_common import (
    CUSTOMERS_TABLE,
    INVOICE_ITEMS_TABLE,
    INVOICES_TABLE,
    ConflictError,
    NotFoundError,
    ValidationError,
    generate_unique_numeric_id,
    get_db_connection,
    json_response,
    parse_event_payload,
    require_fields,
)


DEFAULT_PAYMENT_TERMS_DAYS = 14


def parse_decimal(value: Any, field_name: str) -> Decimal:
    try:
        return Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError):
        raise ValidationError(f"{field_name} must be a valid number.")


def parse_positive_decimal(value: Any, field_name: str) -> Decimal:
    parsed = parse_decimal(value, field_name)
    if parsed <= 0:
        raise ValidationError(f"{field_name} must be greater than 0.")
    return parsed


def parse_positive_int(value: Any, field_name: str) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        raise ValidationError(f"{field_name} must be an integer.")
    if parsed <= 0:
        raise ValidationError(f"{field_name} must be greater than 0.")
    return parsed


def normalize_invoice_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
    require_fields(payload, ["customer_id", "entries"])

    entries = payload.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ValidationError("entries must be a non-empty list.")

    issue_date_value = str(payload.get("issue_date") or date.today().isoformat())
    due_date_value = str(
        payload.get("due_date")
        or (date.fromisoformat(issue_date_value) + timedelta(days=DEFAULT_PAYMENT_TERMS_DAYS)).isoformat()
    )

    try:
        date.fromisoformat(issue_date_value)
        date.fromisoformat(due_date_value)
    except ValueError:
        raise ValidationError("issue_date and due_date must use YYYY-MM-DD format.")

    normalized_entries: List[Dict[str, Any]] = []
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict):
            raise ValidationError(f"entries[{index}] must be an object.")
        require_fields(entry, ["service", "quantity", "unit_price"])
        normalized_entries.append(
            {
                "service": str(entry["service"]).strip(),
                "quantity": parse_positive_int(entry["quantity"], f"entries[{index}].quantity"),
                "unit_price": parse_positive_decimal(entry["unit_price"], f"entries[{index}].unit_price"),
            }
        )

    return {
        "invoice_id": str(payload["invoice_id"]).strip() if payload.get("invoice_id") else "",
        "customer_id": str(payload["customer_id"]).strip(),
        "issue_date": issue_date_value,
        "due_date": due_date_value,
        "entries": normalized_entries,
    }


def customer_exists(connection, customer_id: str) -> bool:
    cursor = connection.cursor()
    cursor.execute(
        f"SELECT 1 FROM {CUSTOMERS_TABLE} WHERE customer_id = %s LIMIT 1",
        (customer_id,),
    )
    return cursor.fetchone() is not None


def invoice_exists(connection, invoice_id: str) -> bool:
    cursor = connection.cursor()
    cursor.execute(
        f"SELECT 1 FROM {INVOICES_TABLE} WHERE invoice_id = %s LIMIT 1",
        (invoice_id,),
    )
    return cursor.fetchone() is not None


def insert_invoice(connection, invoice: Dict[str, Any]) -> Dict[str, Any]:
    cursor = connection.cursor()

    cursor.execute(
        f"""
        INSERT INTO {INVOICES_TABLE}
            (invoice_id, customer_id, issue_date, due_date)
        VALUES
            (%s, %s, %s, %s)
        """,
        (
            invoice["invoice_id"],
            invoice["customer_id"],
            invoice["issue_date"],
            invoice["due_date"],
        ),
    )

    for entry in invoice["entries"]:
        cursor.execute(
            f"""
            INSERT INTO {INVOICE_ITEMS_TABLE}
                (invoice_id, service, quantity, unit_price)
            VALUES
                (%s, %s, %s, %s)
            """,
            (
                invoice["invoice_id"],
                entry["service"],
                entry["quantity"],
                entry["unit_price"],
            ),
        )

    connection.commit()
    total_amount = sum(entry["quantity"] * entry["unit_price"] for entry in invoice["entries"])

    return {
        "invoice_id": invoice["invoice_id"],
        "customer_id": invoice["customer_id"],
        "issue_date": invoice["issue_date"],
        "due_date": invoice["due_date"],
        "entry_count": len(invoice["entries"]),
        "total_amount": str(total_amount),
    }


def lambda_handler(event, context):
    connection = None
    try:
        payload = normalize_invoice_payload(parse_event_payload(event))
        connection = get_db_connection()

        if not customer_exists(connection, payload["customer_id"]):
            raise NotFoundError(f"Customer not found: {payload['customer_id']}")

        if not payload["invoice_id"]:
            payload["invoice_id"] = generate_unique_numeric_id(
                connection=connection,
                table_name=INVOICES_TABLE,
                id_column="invoice_id",
                length=12,
            )
        elif invoice_exists(connection, payload["invoice_id"]):
            raise ConflictError(f"Invoice already exists: {payload['invoice_id']}")

        created_invoice = insert_invoice(connection, payload)
        return json_response(
            201,
            {
                "message": "Invoice created successfully.",
                "invoice": created_invoice,
            },
        )

    except ValidationError as exc:
        return json_response(400, {"message": str(exc)})
    except NotFoundError as exc:
        if connection is not None:
            connection.rollback()
        return json_response(404, {"message": str(exc)})
    except ConflictError as exc:
        if connection is not None:
            connection.rollback()
        return json_response(409, {"message": str(exc)})
    except Exception as exc:
        if connection is not None:
            connection.rollback()
        return json_response(
            500,
            {
                "message": "Failed to create invoice.",
                "error": str(exc),
            },
        )
    finally:
        if connection is not None:
            connection.close()
