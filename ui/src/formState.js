export const OPERATIONS = [
  { id: 'CREATE_STYLE', label: 'Create style', hint: 'Item hierarchy, sourcing, country of manufacture, UDAs, approval.' },
  { id: 'CREATE_ORDER', label: 'Create order', hint: 'Purchase order against an existing style.' },
  { id: 'CREATE_ALL', label: 'Create style + order', hint: 'Full chain, style through to verified purchase order.' },
  { id: 'MODIFY_STYLE', label: 'Modify style', hint: 'PUT updates against an existing item. Requires STYLE.' },
  { id: 'MODIFY_ORDER', label: 'Modify order', hint: 'PUT update against an existing order. Requires ORDER_NO.' },
];

export const today = (offset = 0) => {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  return d.toISOString().slice(0, 10);
};

export const stamp = () => new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 17);

export const initialForm = () => ({
  operationName: 'CREATE_ALL',
  actionRequestId: `UI-${stamp()}`,
  sourceSystem: 'OFFICE_DEV',
  sourceVersion: '1',
  userId: 'office.buyer@example.com',
  description: 'Console test',
  sourceStyleRef: `Console style ${stamp()}`,
  sourceOrderRef: `Console order ${stamp()}`,
  style: '',
  orderNo: '',
  department: '1517',
  klass: '6892',
  subclass: '1128',
  supplier: '700087',
  originCountry: 'GB',
  importCountry: 'GB',
  currencyCode: 'ZAR',
  colour: '08610',
  unitCost: '48.49',
  retailPrice: '100',
  deliveryLoc: '1927',
  exchangeRate: '1',
  notBeforeDate: today(0),
  notAfterDate: today(0),
  otbEowDate: today(2),
  earliestShipDate: today(0),
  latestShipDate: today(19),
  sizeCurve: [
    { sourceVariantRef: `v-${stamp()}-7`, size: '7', width: 'ALL', qty: '1', skuId: '' },
    { sourceVariantRef: `v-${stamp()}-8`, size: '8', width: 'ALL', qty: '1', skuId: '' },
  ],
});

/**
 * Maps a live MFCS item document onto the form as a MODIFY_STYLE request.
 * Child SKUs are not returned by the parent item read, so the size curve is left
 * for the user to complete — MODIFY_STYLE needs a SKU_ID per row.
 */
export function styleToForm(item, existing) {
  const sup = Array.isArray(item.supplier) ? item.supplier[0] : null;
  const cos = sup && Array.isArray(sup.countryOfSourcing) ? sup.countryOfSourcing[0] : null;
  return {
    ...existing,
    operationName: 'MODIFY_STYLE',
    actionRequestId: `UI-MODSTYLE-${stamp()}`,
    sourceStyleRef: item.itemDescription || existing.sourceStyleRef,
    description: item.itemDescription || '',
    style: String(item.item ?? ''),
    department: item.dept != null ? String(item.dept) : existing.department,
    klass: item.class != null ? String(item.class) : existing.klass,
    subclass: item.subclass != null ? String(item.subclass) : existing.subclass,
    supplier: sup?.supplier != null ? String(sup.supplier) : existing.supplier,
    originCountry: cos?.originCountry || existing.originCountry,
    unitCost: cos?.unitCost != null ? String(cos.unitCost) : existing.unitCost,
    retailPrice: item.unitRetail != null ? String(item.unitRetail) : existing.retailPrice,
    colour: item.diff1 || existing.colour,
    sizeCurve: [],
  };
}

/**
 * Maps a live MFCS order document onto the form as a MODIFY_ORDER request.
 * Order detail lines carry real item numbers, so the size curve can be filled in
 * fully here — which is what makes a modify-order round trip testable.
 */
export function orderToForm(order, existing) {
  const details = Array.isArray(order.details) ? order.details : [];
  const first = details[0] || {};

  // The order READ and the order WRITE use different field names for the same
  // things. Read gives physicalQuantityOrdered / originCountryId; write expects
  // quantityOrdered / originCountry. Location lives on the detail lines, not the
  // header, on a read. Fall back across both spellings so a browsed order maps
  // cleanly back onto a modify request.
  const qtyOf = (d) => d.physicalQuantityOrdered ?? d.quantityOrdered;
  const countryOf = (d) => d.originCountryId || d.originCountry;
  const physLoc = order.physicalLocation ?? first.physicalLocation;

  // GET /orders/:orderNo enriches the document server-side with what an order
  // read does not carry but MODIFY_ORDER validation demands: the parent style
  // behind the SKUs, and each line's display size reverse-mapped from its size
  // diff. Without these the request fails validation on STYLE and SKU_SIZE.
  const meta = order.officeMfcs || {};
  return {
    ...existing,
    operationName: 'MODIFY_ORDER',
    actionRequestId: `UI-MODORDER-${stamp()}`,
    sourceOrderRef: order.commentDesc || `Order ${order.orderNo}`,
    description: order.commentDesc || `Order ${order.orderNo}`,
    orderNo: String(order.orderNo ?? ''),
    style: meta.style || '',
    department: order.dept != null ? String(order.dept) : existing.department,
    supplier: order.supplier != null ? String(order.supplier) : existing.supplier,
    currencyCode: order.currencyCode || existing.currencyCode,
    colour: meta.colour || existing.colour,
    originCountry: countryOf(first) || existing.originCountry,
    importCountry: order.importCountry || existing.importCountry,
    unitCost: first.unitCost != null ? String(first.unitCost) : existing.unitCost,
    exchangeRate: order.exchangeRate != null ? String(order.exchangeRate) : existing.exchangeRate,
    deliveryLoc: physLoc != null ? String(physLoc) : existing.deliveryLoc,
    notBeforeDate: order.notBeforeDate || existing.notBeforeDate,
    notAfterDate: order.notAfterDate || existing.notAfterDate,
    otbEowDate: order.otbEowDate || existing.otbEowDate,
    earliestShipDate: order.earliestShipDate || existing.earliestShipDate,
    latestShipDate: order.latestShipDate || existing.latestShipDate,
    sizeCurve: details.map((d, i) => ({
      sourceVariantRef: `ord-${order.orderNo}-${i + 1}`,
      size: d.officeMfcs?.displaySize || '',
      width: 'ALL',
      qty: qtyOf(d) != null ? String(qtyOf(d)) : '1',
      skuId: String(d.item ?? ''),
    })),
  };
}
