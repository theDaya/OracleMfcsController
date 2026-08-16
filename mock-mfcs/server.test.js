'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createMfcsServer, TOKEN } = require('./server');

let server;
let baseUrl;

test.before(async () => {
  ({ server } = createMfcsServer());
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test.after(async () => {
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
});

function headers(correlationId) {
  return {
    Authorization: `Bearer ${TOKEN}`,
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'X-Correlation-ID': correlationId,
    'X-Client-Principal-User': 'contract.test@example.com',
  };
}

async function request(path, method, body, correlationId) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: headers(correlationId),
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

test('issues an OAuth client-credentials token', async () => {
  const response = await fetch(`${baseUrl}/oauth2/v1/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'grant_type=client_credentials&client_id=test&client_secret=test&scope=test',
  });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).access_token, TOKEN);
});

test('runs the documented item and purchase-order chain', async () => {
  const reservation = await request(
    '/MerchIntegrations/services/item/itemNumbers/reserve',
    'POST',
    { itemNumberType: 'ITEM', quantity: 3, daysUntilExpiry: 14 },
    '00000000-0000-4000-8000-000000000001',
  );
  assert.equal(reservation.status, 200);
  assert.equal(reservation.body.items.length, 3);

  const [style, sku1, sku2] = reservation.body.items.map((item) => item.item);
  const createItems = await request(
    '/MerchIntegrations/services/items/create',
    'POST',
    {
      collectionSize: 3,
      items: [
        { item: style, itemLevel: 1, tranLevel: 2, dataLoadingDestination: 'RMS' },
        { item: sku1, itemParent: style, itemLevel: 2, tranLevel: 2, dataLoadingDestination: 'RMS' },
        { item: sku2, itemParent: style, itemLevel: 2, tranLevel: 2, dataLoadingDestination: 'RMS' },
      ],
    },
    '00000000-0000-4000-8000-000000000002',
  );
  assert.equal(createItems.status, 200);
  assert.equal(createItems.body.status, 'SUCCESS');

  const poNumber = await request(
    '/MerchIntegrations/services/purchaseOrder/preIssuedOrderNumber/create',
    'POST',
    { supplier: 70001, quantity: 1, expiryDays: 14 },
    '00000000-0000-4000-8000-000000000003',
  );
  assert.equal(poNumber.status, 200);
  const orderNo = poNumber.body.orderNumbers[0].orderNo;

  const createPo = await request(
    '/MerchIntegrations/services/purchaseOrders/create',
    'POST',
    {
      items: [{
        orderNo,
        supplier: 70001,
        dataLoadingDestination: 'RMS',
        details: [{ item: sku1, location: 98, qtyOrdered: 10 }],
      }],
    },
    '00000000-0000-4000-8000-000000000004',
  );
  assert.equal(createPo.status, 200);

  const getPo = await request(
    `/MerchIntegrations/services/procurement/order/${orderNo}`,
    'GET',
    undefined,
    '00000000-0000-4000-8000-000000000005',
  );
  assert.equal(getPo.status, 200);
  assert.equal(getPo.body.items[0].orderNo, orderNo);
});

test('returns documented service metrics by correlation ID', async () => {
  const correlationId = '00000000-0000-4000-8000-000000000010';
  await request(
    '/MerchIntegrations/services/item/itemNumbers/reserve',
    'POST',
    { itemNumberType: 'ITEM', quantity: 1, daysUntilExpiry: 14 },
    correlationId,
  );

  const response = await fetch(
    `${baseUrl}/MerchIntegrations/services/administration/operations/restService/status?xCorrelationId=${correlationId}&includePayload=Y`,
    { headers: { Authorization: `Bearer ${TOKEN}`, Accept: 'application/json' } },
  );
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.count, 1);
  assert.equal(body.items[0].responseCode, '200');
  assert.equal(body.items[0].xCorrelationId, correlationId);
});

test('rejects missing MFCS headers and staging destinations', async () => {
  const noHeaders = await fetch(`${baseUrl}/MerchIntegrations/services/item/itemNumbers/reserve`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ itemNumberType: 'ITEM', quantity: 1, daysUntilExpiry: 14 }),
  });
  assert.equal(noHeaders.status, 401);

  const reservation = await request(
    '/MerchIntegrations/services/item/itemNumbers/reserve',
    'POST',
    { itemNumberType: 'ITEM', quantity: 1, daysUntilExpiry: 14 },
    '00000000-0000-4000-8000-000000000020',
  );
  const invalidDestination = await request(
    '/MerchIntegrations/services/items/create',
    'POST',
    { collectionSize: 1, items: [{ item: reservation.body.items[0].item, dataLoadingDestination: 'STG' }] },
    '00000000-0000-4000-8000-000000000021',
  );
  assert.equal(invalidDestination.status, 400);
  assert.match(invalidDestination.body.validationErrors[0].field, /dataLoadingDestination/);
});
