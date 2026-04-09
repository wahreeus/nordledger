from typing import Any, Dict

from db_common import (
    CUSTOMERS_TABLE,
    ConflictError,
    ValidationError,
    generate_unique_numeric_id,
    get_db_connection,
    json_response,
    parse_event_payload,
    require_fields,
)


ALLOWED_CURRENCIES = {
    "AED", "AFN", "ALL", "AMD", "ANG", "AOA", "ARS", "AUD", "AWG", "AZN",
    "BAM", "BBD", "BDT", "BGN", "BHD", "BIF", "BMD", "BND", "BOB", "BRL",
    "BSD", "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHF", "CLP", "CNY",
    "COP", "CRC", "CUP", "CVE", "CZK", "DJF", "DKK", "DOP", "DZD", "EGP",
    "ERN", "ETB", "EUR", "FJD", "FKP", "GBP", "GEL", "GHS", "GIP", "GMD",
    "GNF", "GTQ", "GYD", "HKD", "HNL", "HTG", "HUF", "IDR", "ILS", "INR",
    "IQD", "IRR", "ISK", "JMD", "JOD", "JPY", "KES", "KGS", "KHR", "KMF",
    "KRW", "KWD", "KYD", "KZT", "LAK", "LBP", "LKR", "LRD", "LSL", "LYD",
    "MAD", "MDL", "MGA", "MKD", "MMK", "MNT", "MOP", "MRU", "MUR", "MVR",
    "MWK", "MXN", "MYR", "MZN", "NAD", "NGN", "NIO", "NOK", "NPR", "NZD",
    "OMR", "PAB", "PEN", "PGK", "PHP", "PKR", "PLN", "PYG", "QAR", "RON",
    "RSD", "RUB", "RWF", "SAR", "SBD", "SCR", "SDG", "SEK", "SGD", "SHP",
    "SLE", "SLL", "SOS", "SRD", "SSP", "STN", "SYP", "SZL", "THB", "TJS",
    "TMT", "TND", "TOP", "TRY", "TTD", "TWD", "TZS", "UAH", "UGX", "USD",
    "UYU", "UZS", "VES", "VND", "VUV", "WST", "XAF", "XCD", "XOF", "XPF",
    "YER", "ZAR", "ZMW", "ZWL",
}


def normalize_payload(payload: Dict[str, Any]) -> Dict[str, str]:
    require_fields(
        payload,
        ["company_name", "streetadress", "postalcode", "city", "country", "currency"],
    )

    normalized = {
        "customer_id": str(payload["customer_id"]).strip() if payload.get("customer_id") else "",
        "company_name": str(payload["company_name"]).strip(),
        "streetadress": str(payload["streetadress"]).strip(),
        "postalcode": str(payload["postalcode"]).strip(),
        "city": str(payload["city"]).strip(),
        "country": str(payload["country"]).strip(),
        "currency": str(payload["currency"]).strip().upper(),
    }

    if normalized["currency"] not in ALLOWED_CURRENCIES:
        raise ValidationError(f"Unsupported currency code: {normalized['currency']}")

    return normalized


def customer_exists(connection, customer_id: str) -> bool:
    cursor = connection.cursor()
    cursor.execute(
        f"SELECT 1 FROM {CUSTOMERS_TABLE} WHERE customer_id = %s LIMIT 1",
        (customer_id,),
    )
    return cursor.fetchone() is not None


def insert_customer(connection, customer: Dict[str, str]) -> Dict[str, str]:
    cursor = connection.cursor()
    cursor.execute(
        f"""
        INSERT INTO {CUSTOMERS_TABLE}
            (customer_id, company_name, streetadress, postalcode, city, country, currency)
        VALUES
            (%s, %s, %s, %s, %s, %s, %s)
        """,
        (
            customer["customer_id"],
            customer["company_name"],
            customer["streetadress"],
            customer["postalcode"],
            customer["city"],
            customer["country"],
            customer["currency"],
        ),
    )
    connection.commit()
    return customer


def lambda_handler(event, context):
    connection = None
    try:
        payload = normalize_payload(parse_event_payload(event))
        connection = get_db_connection()

        if not payload["customer_id"]:
            payload["customer_id"] = generate_unique_numeric_id(
                connection=connection,
                table_name=CUSTOMERS_TABLE,
                id_column="customer_id",
                length=6,
            )
        elif customer_exists(connection, payload["customer_id"]):
            raise ConflictError(f"Customer already exists: {payload['customer_id']}")

        created_customer = insert_customer(connection, payload)
        return json_response(
            201,
            {
                "message": "Customer created successfully.",
                "customer": created_customer,
            },
        )

    except ValidationError as exc:
        return json_response(400, {"message": str(exc)})
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
                "message": "Failed to create customer.",
                "error": str(exc),
            },
        )
    finally:
        if connection is not None:
            connection.close()
