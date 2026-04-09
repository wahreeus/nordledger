import json
import os
import random
from typing import Any, Dict, Optional

import pg8000


CUSTOMERS_TABLE = os.environ.get("CUSTOMERS_TABLE", "customers")
INVOICES_TABLE = os.environ.get("INVOICES_TABLE", "invoices")
INVOICE_ITEMS_TABLE = os.environ.get("INVOICE_ITEMS_TABLE", "invoice_items")


class ValidationError(Exception):
    pass


class NotFoundError(Exception):
    pass


class ConflictError(Exception):
    pass


class DatabaseError(Exception):
    pass


def get_db_connection():
    return pg8000.connect(
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        database=os.environ["DB_NAME"],
    )


def parse_event_payload(event: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    event = event or {}

    if "body" in event:
        body = event["body"]
        if body is None:
            return {}
        if isinstance(body, str):
            if not body.strip():
                return {}
            try:
                return json.loads(body)
            except json.JSONDecodeError as exc:
                raise ValidationError(f"Request body is not valid JSON: {exc}")
        if isinstance(body, dict):
            return body
        raise ValidationError("Request body must be a JSON object or JSON string.")

    if isinstance(event, dict):
        return event

    raise ValidationError("Event payload must be a JSON object.")


def json_response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def require_fields(payload: Dict[str, Any], field_names):
    missing = [field for field in field_names if payload.get(field) in (None, "")]
    if missing:
        raise ValidationError(f"Missing required field(s): {', '.join(missing)}")


def random_numeric_id(length: int) -> str:
    first_digit = str(random.randint(1, 9))
    remaining = "".join(str(random.randint(0, 9)) for _ in range(length - 1))
    return first_digit + remaining


def generate_unique_numeric_id(connection, table_name: str, id_column: str, length: int, max_attempts: int = 20) -> str:
    cursor = connection.cursor()
    for _ in range(max_attempts):
        candidate = random_numeric_id(length)
        cursor.execute(
            f"SELECT 1 FROM {table_name} WHERE {id_column} = %s LIMIT 1",
            (candidate,),
        )
        if cursor.fetchone() is None:
            return candidate
    raise ConflictError(f"Failed to generate a unique ID for {table_name} after {max_attempts} attempts.")
