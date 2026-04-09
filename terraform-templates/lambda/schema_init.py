from db_common import (
    CUSTOMERS_TABLE,
    INVOICE_ITEMS_TABLE,
    INVOICES_TABLE,
    get_db_connection,
    json_response,
)


SCHEMA_STATEMENTS = [
    f"""
    CREATE TABLE IF NOT EXISTS {CUSTOMERS_TABLE} (
        customer_id VARCHAR(32) PRIMARY KEY,
        company_name TEXT NOT NULL,
        streetadress TEXT NOT NULL,
        postalcode VARCHAR(32) NOT NULL,
        city TEXT NOT NULL,
        country TEXT NOT NULL,
        currency VARCHAR(3) NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    """,
    f"""
    CREATE TABLE IF NOT EXISTS {INVOICES_TABLE} (
        invoice_id VARCHAR(32) PRIMARY KEY,
        customer_id VARCHAR(32) NOT NULL REFERENCES {CUSTOMERS_TABLE}(customer_id) ON DELETE RESTRICT,
        issue_date DATE NOT NULL,
        due_date DATE NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    """,
    f"""
    CREATE TABLE IF NOT EXISTS {INVOICE_ITEMS_TABLE} (
        item_id BIGSERIAL PRIMARY KEY,
        invoice_id VARCHAR(32) NOT NULL REFERENCES {INVOICES_TABLE}(invoice_id) ON DELETE CASCADE,
        service TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity > 0),
        unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price > 0)
    )
    """,
    f"CREATE INDEX IF NOT EXISTS idx_{INVOICES_TABLE}_customer_id ON {INVOICES_TABLE} (customer_id)",
    f"CREATE INDEX IF NOT EXISTS idx_{INVOICE_ITEMS_TABLE}_invoice_id ON {INVOICE_ITEMS_TABLE} (invoice_id)",
]


def lambda_handler(event, context):
    connection = None
    try:
        connection = get_db_connection()
        cursor = connection.cursor()

        for statement in SCHEMA_STATEMENTS:
            cursor.execute(statement)

        connection.commit()

        return json_response(
            200,
            {
                "message": "NordLedger schema initialized successfully.",
                "tables": [CUSTOMERS_TABLE, INVOICES_TABLE, INVOICE_ITEMS_TABLE],
            },
        )
    except Exception as exc:
        if connection is not None:
            connection.rollback()
        return json_response(
            500,
            {
                "message": "Failed to initialize database schema.",
                "error": str(exc),
            },
        )
    finally:
        if connection is not None:
            connection.close()
