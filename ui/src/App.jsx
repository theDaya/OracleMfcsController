import { useEffect, useMemo, useState } from 'react';
import {
  buildInboundPayload,
  getReferenceData,
  previewTransaction,
  submitTransaction,
} from './api';
import JsonBlock from './JsonBlock';
import SpecViewer from './SpecViewer';

const OPERATIONS = [
  { id: 'CREATE_STYLE', label: 'Create style', hint: 'Item hierarchy, sourcing, country of manufacture, UDAs, approval.' },
  { id: 'CREATE_ORDER', label: 'Create order', hint: 'Purchase order against an existing style.' },
  { id: 'CREATE_ALL', label: 'Create style + order', hint: 'Full chain, style through to verified purchase order.' },
  { id: 'MODIFY_STYLE', label: 'Modify style', hint: 'PUT updates against an existing item. Requires STYLE.' },
  { id: 'MODIFY_ORDER', label: 'Modify order', hint: 'PUT update against an existing order. Requires ORDER_NO.' },
];

const today = (offset = 0) => {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  return d.toISOString().slice(0, 10);
};

const stamp = () =>
  new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 17);

const initialForm = () => ({
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

function Field({ label, hint, children }) {
  return (
    <label className="field">
      <span className="field-label">
        {label}
        {hint && <em>{hint}</em>}
      </span>
      {children}
    </label>
  );
}

function CallRow({ call, index }) {
  const [open, setOpen] = useState(index < 2);
  const local = call.local;
  return (
    <div className={`call ${local ? 'call-local' : ''}`}>
      <button className="call-head" onClick={() => setOpen(!open)} type="button">
        <span className="seq">{call.sequence}</span>
        <span className={`method m-${(call.method || '').toLowerCase()}`}>{call.method}</span>
        <span className="step">{call.stepCode}</span>
        <span className="path">{call.endpointPath || 'no MFCS call'}</span>
        {!local && <span className="chev">{open ? '−' : '+'}</span>}
      </button>
      {open && !local && (
        <div className="call-body">
          <div className="url">{call.url}</div>
          <JsonBlock value={call.payload} />
        </div>
      )}
      {open && local && <div className="call-body muted">{call.description}</div>}
    </div>
  );
}

export default function App() {
  const [form, setForm] = useState(initialForm);
  const [reference, setReference] = useState(null);
  const [preview, setPreview] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [submitResult, setSubmitResult] = useState(null);
  const [tab, setTab] = useState('outbound');

  useEffect(() => {
    getReferenceData()
      .then((r) => setReference(r.body))
      .catch((e) => setError(`Could not load reference data: ${e.message}`));
  }, []);

  const inbound = useMemo(() => buildInboundPayload(form), [form]);
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });

  const isOrder = ['CREATE_ORDER', 'MODIFY_ORDER', 'CREATE_ALL'].includes(form.operationName);
  const isModify = form.operationName.startsWith('MODIFY');
  const needsStyle = isModify && form.operationName === 'MODIFY_STYLE';
  const needsOrderNo = form.operationName === 'MODIFY_ORDER';

  const runPreview = async () => {
    setBusy(true);
    setError(null);
    setSubmitResult(null);
    try {
      const { body } = await previewTransaction(inbound);
      setPreview(body);
      setTab('outbound');
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  const runSubmit = async () => {
    const ok = window.confirm(
      'This sends the request to the LIVE MFCS dev tenant and creates real records.\n\n' +
        `Operation: ${form.operationName}\nAction request: ${form.actionRequestId}\n\nContinue?`,
    );
    if (!ok) return;
    setBusy(true);
    setError(null);
    try {
      const { status, body } = await submitTransaction(inbound);
      setSubmitResult({ status, body });
      setTab('result');
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  const updateSize = (i, key, value) => {
    const next = form.sizeCurve.map((r, idx) => (idx === i ? { ...r, [key]: value } : r));
    setForm({ ...form, sizeCurve: next });
  };

  const addSize = () =>
    setForm({
      ...form,
      sizeCurve: [
        ...form.sizeCurve,
        { sourceVariantRef: `v-${stamp()}-${form.sizeCurve.length + 1}`, size: '', width: 'ALL', qty: '1', skuId: '' },
      ],
    });

  const removeSize = (i) =>
    setForm({ ...form, sizeCurve: form.sizeCurve.filter((_, idx) => idx !== i) });

  const opMeta = OPERATIONS.find((o) => o.id === form.operationName);
  const mfcsCalls = preview?.MFCS_CALLS || [];
  const runtime = reference?.runtime || {};

  return (
    <div className="app">
      <header>
        <div>
          <h1>Office MFCS Console</h1>
          <p className="sub">
            Enter the key data, then see both payload sets: what goes into this integration layer, and
            what this layer would send to each MFCS endpoint.
          </p>
        </div>
        <div className="runtime">
          <span className="pill live" title={runtime.MFCS_BASE_URL}>
            LIVE MFCS
          </span>
          <span className="pill">{runtime.MFCS_AUTH_MODE || '…'}</span>
          {runtime.FEATURE_ITEM_LOCATIONS_YN === 'N' && <span className="pill off">locations off</span>}
          {runtime.FEATURE_INITIAL_RETAIL_YN === 'N' && <span className="pill off">initial retail off</span>}
        </div>
      </header>

      {error && <div className="banner error">{error}</div>}

      <div className="layout">
        <section className="panel form">
          <h2>Request</h2>

          <Field label="Operation">
            <select value={form.operationName} onChange={set('operationName')}>
              {OPERATIONS.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label}
                </option>
              ))}
            </select>
          </Field>
          <p className="op-hint">{opMeta?.hint}</p>

          <div className="grid2">
            <Field label="Action request ID">
              <input value={form.actionRequestId} onChange={set('actionRequestId')} />
            </Field>
            <Field label="Source system">
              <input value={form.sourceSystem} onChange={set('sourceSystem')} />
            </Field>
          </div>

          <Field label="Description">
            <input value={form.description} onChange={set('description')} />
          </Field>

          <div className="grid2">
            <Field label="Source style ref">
              <input value={form.sourceStyleRef} onChange={set('sourceStyleRef')} />
            </Field>
            {isOrder && (
              <Field label="Source order ref">
                <input value={form.sourceOrderRef} onChange={set('sourceOrderRef')} />
              </Field>
            )}
          </div>

          {(needsStyle || form.operationName === 'CREATE_ORDER') && (
            <Field label="Style (existing MFCS item)" hint="required">
              <input value={form.style} onChange={set('style')} placeholder="100050005" />
            </Field>
          )}
          {needsOrderNo && (
            <Field label="Order number (existing)" hint="required">
              <input value={form.orderNo} onChange={set('orderNo')} placeholder="25005" />
            </Field>
          )}

          <h3>Hierarchy</h3>
          <div className="grid3">
            <Field label="Department">
              <input value={form.department} onChange={set('department')} list="depts" />
            </Field>
            <Field label="Class">
              <input value={form.klass} onChange={set('klass')} />
            </Field>
            <Field label="Subclass">
              <input value={form.subclass} onChange={set('subclass')} />
            </Field>
          </div>
          <datalist id="depts">
            {(reference?.departments || []).map((d) => (
              <option key={d.code} value={d.code} />
            ))}
          </datalist>

          <h3>Sourcing</h3>
          <div className="grid3">
            <Field label="Supplier">
              <input value={form.supplier} onChange={set('supplier')} list="supps" />
            </Field>
            <Field label="Origin country">
              <input value={form.originCountry} onChange={set('originCountry')} />
            </Field>
            <Field label="Currency">
              <input value={form.currencyCode} onChange={set('currencyCode')} />
            </Field>
          </div>
          <datalist id="supps">
            {(reference?.suppliers || []).map((s) => (
              <option key={s.code} value={s.code} />
            ))}
          </datalist>

          <div className="grid3">
            <Field label="Colour diff">
              <input value={form.colour} onChange={set('colour')} list="colours" />
            </Field>
            <Field label="Unit cost">
              <input value={form.unitCost} onChange={set('unitCost')} />
            </Field>
            <Field label="Retail price">
              <input value={form.retailPrice} onChange={set('retailPrice')} />
            </Field>
          </div>
          <datalist id="colours">
            {(reference?.colours || []).map((c) => (
              <option key={c.code} value={c.code} />
            ))}
          </datalist>

          <h3>
            Size curve
            <button type="button" className="link" onClick={addSize}>
              + add size
            </button>
          </h3>
          <table className="sizes">
            <thead>
              <tr>
                <th>Size</th>
                <th>Width</th>
                <th>Qty</th>
                <th>SKU ID</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {form.sizeCurve.map((r, i) => (
                <tr key={i}>
                  <td>
                    <input value={r.size} onChange={(e) => updateSize(i, 'size', e.target.value)} />
                  </td>
                  <td>
                    <input value={r.width} onChange={(e) => updateSize(i, 'width', e.target.value)} />
                  </td>
                  <td>
                    <input value={r.qty} onChange={(e) => updateSize(i, 'qty', e.target.value)} />
                  </td>
                  <td>
                    <input
                      value={r.skuId}
                      placeholder={isModify ? 'required' : 'null on create'}
                      onChange={(e) => updateSize(i, 'skuId', e.target.value)}
                    />
                  </td>
                  <td>
                    <button type="button" className="link danger" onClick={() => removeSize(i)}>
                      ×
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          {isOrder && (
            <>
              <h3>Order</h3>
              <div className="grid3">
                <Field label="Delivery location">
                  <input value={form.deliveryLoc} onChange={set('deliveryLoc')} />
                </Field>
                <Field label="Import country">
                  <input value={form.importCountry} onChange={set('importCountry')} />
                </Field>
                <Field label="Exchange rate">
                  <input value={form.exchangeRate} onChange={set('exchangeRate')} />
                </Field>
              </div>
              <div className="grid3">
                <Field label="Not before">
                  <input type="date" value={form.notBeforeDate} onChange={set('notBeforeDate')} />
                </Field>
                <Field label="Not after">
                  <input type="date" value={form.notAfterDate} onChange={set('notAfterDate')} />
                </Field>
                <Field label="OTB EOW">
                  <input type="date" value={form.otbEowDate} onChange={set('otbEowDate')} />
                </Field>
              </div>
              <div className="grid2">
                <Field label="Earliest ship">
                  <input type="date" value={form.earliestShipDate} onChange={set('earliestShipDate')} />
                </Field>
                <Field label="Latest ship">
                  <input type="date" value={form.latestShipDate} onChange={set('latestShipDate')} />
                </Field>
              </div>
            </>
          )}

          <div className="actions">
            <button type="button" onClick={runPreview} disabled={busy} className="primary">
              {busy ? 'Working…' : 'Preview payloads'}
            </button>
            <button type="button" onClick={runSubmit} disabled={busy} className="danger">
              Submit to live MFCS
            </button>
          </div>
        </section>

        <section className="panel output">
          <div className="tabs">
            <button
              type="button"
              className={tab === 'inbound' ? 'on' : ''}
              onClick={() => setTab('inbound')}
            >
              Inbound — our interface
            </button>
            <button
              type="button"
              className={tab === 'outbound' ? 'on' : ''}
              onClick={() => setTab('outbound')}
            >
              Outbound — MFCS endpoints
              {mfcsCalls.length > 0 && <span className="count">{mfcsCalls.filter((c) => !c.local).length}</span>}
            </button>
            <button
              type="button"
              className={tab === 'spec' ? 'on' : ''}
              onClick={() => setTab('spec')}
            >
              MFCS spec
            </button>
            {submitResult && (
              <button
                type="button"
                className={tab === 'result' ? 'on' : ''}
                onClick={() => setTab('result')}
              >
                Result
              </button>
            )}
          </div>

          {tab === 'inbound' && (
            <div className="tab-body">
              <p className="explain">
                This is what a caller posts to <code>POST /office-mfcs/v1/transactions</code>. It is the
                legacy PLM/Office shape — one document describing the whole intent, before any
                decomposition into MFCS calls.
              </p>
              <JsonBlock value={inbound} />
            </div>
          )}

          {tab === 'outbound' && (
            <div className="tab-body">
              {!preview && <p className="explain">Run a preview to see the MFCS call plan.</p>}
              {preview && preview.VALID === false && (
                <div className="banner warn">
                  <strong>Validation failed — nothing would be sent.</strong>
                  <ul>
                    {(preview.ERRORS || []).map((e, i) => (
                      <li key={i}>
                        <code>{e.FIELD}</code> {e.CODE} — {e.MESSAGE}
                      </li>
                    ))}
                  </ul>
                </div>
              )}
              {preview && preview.VALID && (
                <>
                  <p className="explain">
                    {mfcsCalls.filter((c) => !c.local).length} MFCS calls, in order. Expand any step to
                    see the exact JSON body. {preview.NOTE}
                  </p>
                  {mfcsCalls.map((c, i) => (
                    <CallRow key={c.sequence} call={c} index={i} />
                  ))}
                </>
              )}
            </div>
          )}

          {tab === 'spec' && (
            <div className="tab-body">
              <SpecViewer usedEndpoints={reference?.endpoints} />
            </div>
          )}

          {tab === 'result' && submitResult && (
            <div className="tab-body">
              <p className="explain">
                HTTP {submitResult.status} from <code>POST /office-mfcs/v1/transactions</code>.
              </p>
              <JsonBlock value={submitResult.body} />
            </div>
          )}
        </section>
      </div>
    </div>
  );
}
