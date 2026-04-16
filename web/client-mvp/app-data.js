function getCollectionKey(userKey, collection) {
  return `nordledger:${encodeURIComponent(String(userKey))}:${collection}`;
}

function readArray(key) {
  try {
    const raw = localStorage.getItem(key);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    return [];
  }
}

function writeArray(key, value) {
  localStorage.setItem(key, JSON.stringify(value, null, 2));
}

export function getCustomers(userKey) {
  return readArray(getCollectionKey(userKey, "customers"));
}

export function saveCustomers(userKey, customers) {
  writeArray(getCollectionKey(userKey, "customers"), customers);
}

export function getInvoices(userKey) {
  return readArray(getCollectionKey(userKey, "invoices"));
}

export function saveInvoices(userKey, invoices) {
  writeArray(getCollectionKey(userKey, "invoices"), invoices);
}

export function generateUniqueDigits(existingIds, length) {
  let attempts = 0;

  while (attempts < 10000) {
    let id = "";

    for (let index = 0; index < length; index += 1) {
      id += Math.floor(Math.random() * 10);
    }

    if (!existingIds.has(id)) {
      return id;
    }

    attempts += 1;
  }

  throw new Error("Unable to generate a unique ID.");
}

export function findCustomerById(customers, customerId) {
  return customers.find((customer) => String(customer.customer_id) === String(customerId)) || null;
}

export function calculateInvoiceTotal(invoice) {
  const entries = Array.isArray(invoice?.entries) ? invoice.entries : [];

  return entries.reduce((sum, entry) => {
    const quantity = Number(entry?.quantity);
    const unitPrice = Number(entry?.unit_price);

    if (!Number.isFinite(quantity) || !Number.isFinite(unitPrice)) {
      return sum;
    }

    return sum + quantity * unitPrice;
  }, 0);
}
