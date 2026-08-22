// All calls go through the Vite proxy at /api -> ORDS /ords/<schema>/mfcs/v1.

async function call(path, options = {}) {
  const res = await fetch(`/api${path}`, {
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    ...options,
  });
  const text = await res.text();
  let body;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    throw new Error(`Non-JSON response (HTTP ${res.status}): ${text.slice(0, 300)}`);
  }
  return { status: res.status, body };
}

export const getReferenceData = () => call('/reference-data');

export const getRequests = () => call('/requests');

export const previewTransaction = (payload) =>
  call('/transactions/preview', { method: 'POST', body: JSON.stringify(payload) });

export const submitTransaction = (payload) =>
  call('/transactions', { method: 'POST', body: JSON.stringify(payload) });

export const validateTransaction = (payload) =>
  call('/transactions/validate', { method: 'POST', body: JSON.stringify(payload) });

/**
 * Builds the Office/PLM-shaped payload this integration layer accepts.
 * This is deliberately assembled here so the screen can show the caller exactly
 * what would be posted to our own interface, before any MFCS mapping happens.
 */
export function buildInboundPayload(form) {
  const isOrder = ['CREATE_ORDER', 'MODIFY_ORDER', 'CREATE_ALL'].includes(form.operationName);
  const isStyle = ['CREATE_STYLE', 'MODIFY_STYLE', 'CREATE_ALL'].includes(form.operationName);
  const isModify = form.operationName.startsWith('MODIFY');

  const num = (v) => (v === '' || v === null || v === undefined ? null : Number(v));
  const str = (v) => (v === '' || v === null || v === undefined ? null : v);

  const payload = {
    ACTION_REQUEST_ID: form.actionRequestId,
    OPERATION_NAME: form.operationName,
    SOURCE_SYSTEM: form.sourceSystem,
    SOURCE_VERSION: form.sourceVersion,
    USER_ID: form.userId,
    DESCRIPTION: form.description,
  };

  if (isStyle) {
    payload.SOURCE_STYLE_REF = form.sourceStyleRef;
    payload.STYLE = isModify ? str(form.style) : null;
  }
  if (isOrder) {
    payload.SOURCE_ORDER_REF = form.sourceOrderRef;
    payload.ORDER_NO = isModify ? num(form.orderNo) : null;
  }
  if (form.operationName === 'CREATE_ORDER') {
    // An order against an existing style still needs the style identifier.
    payload.SOURCE_STYLE_REF = form.sourceStyleRef;
    payload.STYLE = str(form.style);
  }

  Object.assign(payload, {
    DEPARTMENT: form.department,
    CLASS: form.klass,
    SUBCLASS: form.subclass,
    SUPPLIER: form.supplier,
    ORIGIN_COUNTRY: form.originCountry,
    CURRENCY_CODE: form.currencyCode,
    COLOUR: form.colour,
    UNIT_COST: num(form.unitCost),
    RETAIL_PRICE: num(form.retailPrice),
    PLMSizeCurveDtl: form.sizeCurve.map((r) => ({
      SOURCE_VARIANT_REF: r.sourceVariantRef,
      SKU_SIZE: r.size,
      SKU_WIDTH: r.width,
      SKU_QTY: num(r.qty),
      SKU_ID: str(r.skuId),
    })),
  });

  if (isOrder) {
    Object.assign(payload, {
      IMPORT_COUNTRY: form.importCountry,
      NOT_BEFORE_DATE: form.notBeforeDate,
      NOT_AFTER_DATE: form.notAfterDate,
      OTB_EOW_DATE: form.otbEowDate,
      EARLIEST_SHIP_DATE: form.earliestShipDate,
      LATEST_SHIP_DATE: form.latestShipDate,
      DELIVERY_LOC: num(form.deliveryLoc),
      PO_TYPE: null,
      ORDER_EXCHANGE_RATE: num(form.exchangeRate),
    });
  }

  return payload;
}

// ---------------------------------------------------------------- master data
export const getMasterData = () => call('/master-data');
export const refreshMasterData = () => call('/master-data', { method: 'POST' });

// ---------------------------------------------------------------- browse
export const listStyles = (params = {}) => {
  const q = new URLSearchParams(
    Object.entries(params).filter(([, v]) => v !== '' && v != null),
  ).toString();
  return call(`/styles${q ? `?${q}` : ''}`);
};

export const getStyle = (item, withSkus = false) =>
  call(`/styles/${encodeURIComponent(item)}${withSkus ? '?withSkus=Y' : ''}`);

export const listOrders = (params = {}) => {
  const q = new URLSearchParams(
    Object.entries(params).filter(([, v]) => v !== '' && v != null),
  ).toString();
  return call(`/orders${q ? `?${q}` : ''}`);
};

export const getOrder = (orderNo) => call(`/orders/${encodeURIComponent(orderNo)}`);

export const getTokenStatus = () => call('/token-status');

export const getRequest = (id) => call(`/requests/${encodeURIComponent(id)}`);

export const resumeTransaction = (id) =>
  call(`/transactions/${encodeURIComponent(id)}/resume`, { method: 'POST' });
