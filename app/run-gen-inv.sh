#!/bin/bash

CUSTOMERS_FILE="data_customers.json"
INVOICES_FILE="data_invoices.json"
PYTHON_SCRIPT="generate_invoice.py"
OUTPUT_DIR="invoices"

if [ ! -f "$CUSTOMERS_FILE" ]; then
  echo "Error: $CUSTOMERS_FILE not found."
  exit 1
fi

if [ ! -f "$INVOICES_FILE" ]; then
  echo "Error: $INVOICES_FILE not found."
  exit 1
fi

if [ ! -f "$PYTHON_SCRIPT" ]; then
  echo "Error: $PYTHON_SCRIPT not found."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is not installed."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

jq -c '.[]' "$INVOICES_FILE" | while IFS= read -r invoice; do
  invoice_id=$(printf '%s\n' "$invoice" | jq -r '.invoice_id')

  echo "Processing $invoice_id"

  python3 "$PYTHON_SCRIPT" "$CUSTOMERS_FILE" "$INVOICES_FILE" "$invoice_id" "$OUTPUT_DIR"

  if [ $? -ne 0 ]; then
    echo "Error while processing invoice $invoice_id."
    exit 1
  fi
done