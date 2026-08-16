'use strict';

const http = require('node:http');
const https = require('node:https');
const fs = require('node:fs');
const { randomUUID } = require('node:crypto');

const DEFAULT_PORT = Number(process.env.PORT || 18080);
const TOKEN = 'public-contract-token';

function createState() {
  return {
    nextItem: 3000000,
    nextOrder: 10700000,
    reservations: new Map(),
    items: new Map(),
    orders: new Map(),
    metrics: new Map(),
    faults: new Map(),
  };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > 2 * 1024 * 1024) {
        reject(new Error('Request payload exceeds 2 MiB.'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function jsonResponse(res, statusCode, body, correlationId) {
  const serialized = JSON.stringify(body);
  const headers = {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(serialized),
  };
  if (correlationId) headers['X-Correlation-ID'] = correlationId;
  res.writeHead(statusCode, headers);
  res.end(serialized);
  return serialized;
}

function oracleError(field, error, inputValue = null) {
  return {
    status: 'ERROR',
    message: 'Error found in validation of input payload',
    validationErrors: [{ error, field, inputValue }],
  };
}

function validateArrayEnvelope(body) {
  if (!body || !Array.isArray(body.items)) {
    return oracleError('items', 'must be an array');
  }
  if (body.collectionSize !== undefined && body.collectionSize !== body.items.length) {
    return oracleError('collectionSize', 'must match items length', body.collectionSize);
  }
  return null;
}

function validateRmsItems(body) {
  const envelopeError = validateArrayEnvelope(body);
  if (envelopeError) return envelopeError;
  for (let i = 0; i < body.items.length; i += 1) {
    const item = body.items[i];
    if (!item.item) return oracleError(`items[${i}].item`, 'is required');
    if (item.dataLoadingDestination !== 'RMS') {
      return oracleError(
        `items[${i}].dataLoadingDestination`,
        'must be RMS for direct Merchandising creation',
        item.dataLoadingDestination,
      );
    }
  }
  return null;
}

function validateHeaders(req) {
  if (req.headers.authorization !== `Bearer ${TOKEN}`) {
    return { status: 401, body: oracleError('Authorization', 'valid Bearer token is required') };
  }
  if (!String(req.headers.accept || '').includes('application/json')) {
    return { status: 400, body: oracleError('Accept', 'application/json is required') };
  }
  if (!String(req.headers['content-type'] || '').includes('application/json')) {
    return { status: 400, body: oracleError('Content-Type', 'application/json is required') };
  }
  if (!req.headers['x-correlation-id']) {
    return { status: 400, body: oracleError('X-Correlation-ID', 'is required') };
  }
  if (!req.headers['x-client-principal-user']) {
    return { status: 400, body: oracleError('X-Client-Principal-User', 'is required') };
  }
  return null;
}

function metricRecord(req, path, correlationId, requestBody) {
  return {
    requestId: randomUUID(),
    xCorrelationId: correlationId,
    method: req.method,
    path,
    responseCode: null,
    requestTimestamp: new Date().toISOString(),
    responseTimestamp: null,
    durationMillisecond: null,
    requestSizeByte: Buffer.byteLength(requestBody || ''),
    responseSizeByte: null,
    clientName: 'office-mfcs-public-contract-client',
    serviceUrl: `http://${req.headers.host}${req.url}`,
    requestPayload: requestBody || null,
    responsePayload: null,
    startedAt: Date.now(),
  };
}

function completeMetric(state, metric, statusCode, responsePayload) {
  metric.responseCode = String(statusCode);
  metric.responseTimestamp = new Date().toISOString();
  metric.durationMillisecond = Date.now() - metric.startedAt;
  metric.responseSizeByte = Buffer.byteLength(responsePayload || '');
  metric.responsePayload = responsePayload;
  delete metric.startedAt;
  state.metrics.set(metric.xCorrelationId, metric);
}

function createMfcsServer(options = {}) {
  const state = options.state || createState();

  const handler = async (req, res) => {
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const path = url.pathname;

    if (path === '/health' && req.method === 'GET') {
      jsonResponse(res, 200, { status: 'UP', service: 'oracle-mfcs-public-contract-mock' });
      return;
    }

    if (path === '/__admin/state' && req.method === 'GET') {
      jsonResponse(res, 200, {
        reservations: [...state.reservations.values()],
        items: [...state.items.values()],
        orders: [...state.orders.values()],
        metrics: [...state.metrics.values()],
      });
      return;
    }

    if (path === '/__admin/reset' && req.method === 'POST') {
      const replacement = createState();
      Object.assign(state, replacement);
      jsonResponse(res, 200, { status: 'SUCCESS' });
      return;
    }

    if (path === '/oauth2/v1/token' && req.method === 'POST') {
      const form = new URLSearchParams(await readBody(req));
      if (form.get('grant_type') !== 'client_credentials') {
        jsonResponse(res, 400, { error: 'unsupported_grant_type' });
        return;
      }
      jsonResponse(res, 200, { access_token: TOKEN, token_type: 'Bearer', expires_in: 300 });
      return;
    }

    if (path === '/MerchIntegrations/services/administration/operations/restService/status' && req.method === 'GET') {
      if (req.headers.authorization !== `Bearer ${TOKEN}`) {
        jsonResponse(res, 401, oracleError('Authorization', 'valid Bearer token is required'));
        return;
      }
      const correlationId = url.searchParams.get('xCorrelationId');
      const metric = state.metrics.get(correlationId);
      const items = metric ? [metric] : [];
      jsonResponse(res, 200, {
        items,
        hasMore: false,
        limit: 1000,
        count: items.length,
        links: [],
      });
      return;
    }

    const correlationId = req.headers['x-correlation-id'];
    let requestText = '';
    let body = null;
    try {
      requestText = await readBody(req);
      body = requestText ? JSON.parse(requestText) : {};
    } catch (error) {
      jsonResponse(res, 400, oracleError('$', `invalid JSON: ${error.message}`), correlationId);
      return;
    }

    const metric = metricRecord(req, path, correlationId || randomUUID(), requestText);
    const finish = (statusCode, responseBody) => {
      const serialized = JSON.stringify(responseBody);
      completeMetric(state, metric, statusCode, serialized);
      jsonResponse(res, statusCode, responseBody, metric.xCorrelationId);
    };

    const headerError = validateHeaders(req);
    if (headerError) {
      finish(headerError.status, headerError.body);
      return;
    }

    const fault = state.faults.get(path);
    if (fault) {
      finish(fault.status || 500, fault.body || { status: 'ERROR', businessError: ['Injected fault'] });
      return;
    }

    if (path === '/MerchIntegrations/services/item/itemNumbers/reserve' && req.method === 'POST') {
      if (!body.itemNumberType || !Number.isInteger(body.quantity) || body.quantity < 1 || !Number.isInteger(body.daysUntilExpiry) || body.daysUntilExpiry < 1) {
        finish(400, oracleError('reserve', 'itemNumberType, positive integer quantity, and positive integer daysUntilExpiry are required'));
        return;
      }
      const expiryDate = new Date(Date.now() + body.daysUntilExpiry * 86400000).toISOString().slice(0, 10);
      const items = [];
      for (let i = 0; i < body.quantity; i += 1) {
        const item = String(state.nextItem++);
        const reservation = { item, itemNumberType: body.itemNumberType, expiryDate };
        state.reservations.set(item, reservation);
        items.push(reservation);
      }
      finish(200, { items });
      return;
    }

    if (path === '/MerchIntegrations/services/items/create' && req.method === 'POST') {
      const validationError = validateRmsItems(body);
      if (validationError) { finish(400, validationError); return; }
      for (const item of body.items) {
        if (!state.reservations.has(String(item.item))) {
          finish(400, { status: 'ERROR', message: 'Business validation failed', businessError: [`Item ${item.item} is not reserved`] });
          return;
        }
        state.reservations.delete(String(item.item));
        state.items.set(String(item.item), { ...item, status: item.status || 'W' });
      }
      finish(200, { status: 'SUCCESS' });
      return;
    }

    if (path === '/MerchIntegrations/services/items/update' && req.method === 'PUT') {
      const validationError = validateRmsItems(body);
      if (validationError) { finish(400, validationError); return; }
      for (const item of body.items) {
        const existing = state.items.get(String(item.item)) || { item: String(item.item) };
        state.items.set(String(item.item), { ...existing, ...item });
      }
      finish(200, { status: 'SUCCESS' });
      return;
    }

    if (/\/MerchIntegrations\/services\/item\/(suppliers|uda|locations)\/(create|update)/.test(path)) {
      const expectedMethod = path.endsWith('/create') ? 'POST' : 'PUT';
      if (req.method !== expectedMethod) {
        finish(405, oracleError('method', `must be ${expectedMethod}`, req.method));
        return;
      }
      const validationError = validateRmsItems(body);
      if (validationError) { finish(400, validationError); return; }
      for (const item of body.items) {
        if (!state.items.has(String(item.item))) {
          finish(400, { status: 'ERROR', message: 'Business validation failed', businessError: [`Item ${item.item} does not exist`] });
          return;
        }
      }
      finish(200, { status: 'SUCCESS' });
      return;
    }

    if (path === '/MerchIntegrations/services/purchaseOrder/preIssuedOrderNumber/create' && req.method === 'POST') {
      if (!Number.isInteger(body.quantity) || body.quantity < 1 || !Number.isInteger(body.expiryDays) || body.expiryDays < 1) {
        finish(400, oracleError('quantity', 'positive integer quantity and expiryDays are required'));
        return;
      }
      const expiryDate = new Date(Date.now() + body.expiryDays * 86400000).toISOString().slice(0, 10);
      const orderNumbers = [];
      for (let i = 0; i < body.quantity; i += 1) {
        orderNumbers.push({ supplier: body.supplier || null, orderNo: state.nextOrder++, expiryDate });
      }
      finish(200, { orderNumbers });
      return;
    }

    if (path === '/MerchIntegrations/services/purchaseOrders/create' && req.method === 'POST') {
      const validationError = validateArrayEnvelope(body);
      if (validationError) { finish(400, validationError); return; }
      for (const order of body.items) {
        if (!order.orderNo) { finish(400, oracleError('items.orderNo', 'is required')); return; }
        if (order.dataLoadingDestination !== 'RMS') {
          finish(400, oracleError('items.dataLoadingDestination', 'must be RMS', order.dataLoadingDestination));
          return;
        }
        for (const detail of order.details || []) {
          if (!state.items.has(String(detail.item))) {
            finish(400, { status: 'ERROR', message: 'Business validation failed', businessError: [`Order item ${detail.item} does not exist`] });
            return;
          }
        }
        state.orders.set(String(order.orderNo), { ...order });
      }
      finish(200, { status: 'SUCCESS' });
      return;
    }

    if (path === '/MerchIntegrations/services/purchaseOrders/update' && req.method === 'PUT') {
      const validationError = validateArrayEnvelope(body);
      if (validationError) { finish(400, validationError); return; }
      for (const order of body.items) {
        if (!order.orderNo) { finish(400, oracleError('items.orderNo', 'is required')); return; }
        const existing = state.orders.get(String(order.orderNo)) || { orderNo: order.orderNo };
        state.orders.set(String(order.orderNo), { ...existing, ...order });
      }
      finish(200, { status: 'SUCCESS' });
      return;
    }

    const orderMatch = path.match(/^\/MerchIntegrations\/services\/procurement\/order\/(\d+)$/);
    if (orderMatch && req.method === 'GET') {
      const order = state.orders.get(orderMatch[1]);
      if (!order) { finish(404, oracleError('orderNo', 'order was not found', orderMatch[1])); return; }
      finish(200, { items: [order], hasMore: false, limit: 1000, count: 1, links: [] });
      return;
    }

    finish(404, oracleError('path', 'endpoint is not implemented by the public-contract mock', path));
  };

  const server = options.tls
    ? https.createServer(options.tls, handler)
    : http.createServer(handler);

  return { server, state };
}

if (require.main === module) {
  const keyPath = process.env.TLS_KEY_PATH;
  const certPath = process.env.TLS_CERT_PATH;
  if ((keyPath && !certPath) || (!keyPath && certPath)) {
    throw new Error('TLS_KEY_PATH and TLS_CERT_PATH must be supplied together.');
  }
  const tls = keyPath
    ? { key: fs.readFileSync(keyPath), cert: fs.readFileSync(certPath) }
    : undefined;
  const protocol = tls ? 'https' : 'http';
  const { server } = createMfcsServer({ tls });
  server.listen(DEFAULT_PORT, '0.0.0.0', () => {
    process.stdout.write(`Oracle MFCS public-contract mock listening on ${protocol}://0.0.0.0:${DEFAULT_PORT}\n`);
  });
}

module.exports = { createMfcsServer, createState, TOKEN };
