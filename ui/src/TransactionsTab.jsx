import { useMemo, useState } from 'react';
import { buildInboundPayload, previewTransaction, submitTransaction } from './api';
import { OPERATIONS, stamp } from './formState';
import JsonBlock from './JsonBlock';

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

/**
 * Combo input: a datalist rather than a hard <select>.
 * Master data for hierarchy, diffs and suppliers is derived from the item feed,
 * so it is real but not guaranteed complete. A datalist offers the known values
 * while still allowing a code the cache has not seen yet.
 */
function Combo({ id, value, onChange, options, placeholder }) {
  return (
    <>
      <input list={id} value={value} onChange={onChange} placeholder={placeholder} />
      <datalist id={id}>
        {(options || []).map((o) => (
          <option key={`${o.code}-${o.parent || ''}`} value={o.code}>
            {o.description || ''}
          </option>
        ))}
      </datalist>
    </>
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

export default function TransactionsTab({ form, setForm, masterData }) {
  const [preview, setPreview] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [submitResult, setSubmitResult] = useState(null);
  const [tab, setTab] = useState('outbound');

  const md = masterData?.types || {};
  const inbound = useMemo(() => buildInboundPayload(form), [form]);
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });

  const isOrder = ['CREATE_ORDER', 'MODIFY_ORDER', 'CREATE_ALL'].includes(form.operationName);
  const isModify = form.operationName.startsWith('MODIFY');
  const needsStyle = form.operationName === 'MODIFY_STYLE' || form.operationName === 'CREATE_ORDER';
  const needsOrderNo = form.operationName === 'MODIFY_ORDER';

  // Hierarchy cascades: classes belong to a dept, subclasses to dept.class.
  const classes = (md.CLASS || []).filter((c) => !form.department || c.parent === form.department);
  const subclasses = (md.SUBCLASS || []).filter(
    (s) => !form.department || !form.klass || s.parent === `${form.department}.${form.klass}`,
  );

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

  const updateSize = (i, key, value) =>
    setForm({
      ...form,
      sizeCurve: form.sizeCurve.map((r, idx) => (idx === i ? { ...r, [key]: value } : r)),
    });

  const addSize = () =>
    setForm({
      ...form,
      sizeCurve: [
        ...form.sizeCurve,
        {
          sourceVariantRef: `v-${stamp()}-${form.sizeCurve.length + 1}`,
          size: '',
          width: 'ALL',
          qty: '1',
          skuId: '',
        },
      ],
    });

  const removeSize = (i) =>
    setForm({ ...form, sizeCurve: form.sizeCurve.filter((_, idx) => idx !== i) });

  const opMeta = OPERATIONS.find((o) => o.id === form.operationName);
  const mfcsCalls = preview?.MFCS_CALLS || [];

  return (
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

        {needsStyle && (
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
            <Combo id="md-dept" value={form.department} onChange={set('department')} options={md.DEPARTMENT} />
          </Field>
          <Field label="Class">
            <Combo id="md-class" value={form.klass} onChange={set('klass')} options={classes} />
          </Field>
          <Field label="Subclass">
            <Combo id="md-subclass" value={form.subclass} onChange={set('subclass')} options={subclasses} />
          </Field>
        </div>

        <h3>Sourcing</h3>
        <div className="grid3">
          <Field label="Supplier">
            <Combo id="md-supp" value={form.supplier} onChange={set('supplier')} options={md.SUPPLIER} />
          </Field>
          <Field label="Origin country">
            <input value={form.originCountry} onChange={set('originCountry')} />
          </Field>
          <Field label="Currency">
            <Combo id="md-ccy" value={form.currencyCode} onChange={set('currencyCode')} options={md.CURRENCY} />
          </Field>
        </div>

        <div className="grid3">
          <Field label="Colour diff">
            <Combo id="md-colour" value={form.colour} onChange={set('colour')} options={md.DIFF_C} />
          </Field>
          <Field label="Unit cost">
            <input value={form.unitCost} onChange={set('unitCost')} />
          </Field>
          <Field label="Retail price">
            <input value={form.retailPrice} onChange={set('retailPrice')} />
          </Field>
        </div>

        <h3>
          Size curve
          <button type="button" className="link" onClick={addSize}>
            + add size
          </button>
        </h3>
        {form.sizeCurve.length === 0 && (
          <p className="muted small">
            No size rows.{' '}
            {isModify
              ? 'MODIFY needs at least one row with a SKU ID.'
              : 'Create operations need at least one row.'}
          </p>
        )}
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
                  <Combo
                    id={`md-size-${i}`}
                    value={r.size}
                    onChange={(e) => updateSize(i, 'size', e.target.value)}
                    options={md.DIFF_S}
                  />
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
                <Combo
                  id="md-loc"
                  value={form.deliveryLoc}
                  onChange={set('deliveryLoc')}
                  options={md.LOCATION_P}
                />
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
          <button type="button" className={tab === 'inbound' ? 'on' : ''} onClick={() => setTab('inbound')}>
            Inbound — our interface
          </button>
          <button type="button" className={tab === 'outbound' ? 'on' : ''} onClick={() => setTab('outbound')}>
            Outbound — MFCS endpoints
            {mfcsCalls.length > 0 && (
              <span className="count">{mfcsCalls.filter((c) => !c.local).length}</span>
            )}
          </button>
          {submitResult && (
            <button type="button" className={tab === 'result' ? 'on' : ''} onClick={() => setTab('result')}>
              Result
            </button>
          )}
        </div>

        {error && <div className="banner error">{error}</div>}

        {tab === 'inbound' && (
          <div className="tab-body">
            <p className="explain">
              What a caller posts to <code>POST /mfcs/v1/transactions</code> — the legacy
              PLM/Office shape, one document describing the whole intent before any decomposition.
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
                  {mfcsCalls.filter((c) => !c.local).length} MFCS calls, in order. Expand any step for
                  the exact JSON body. {preview.NOTE}
                </p>
                {mfcsCalls.map((c, i) => (
                  <CallRow key={c.sequence} call={c} index={i} />
                ))}
              </>
            )}
          </div>
        )}

        {tab === 'result' && submitResult && (
          <div className="tab-body">
            <p className="explain">
              HTTP {submitResult.status} from <code>POST /mfcs/v1/transactions</code>.
            </p>
            <JsonBlock value={submitResult.body} />
          </div>
        )}
      </section>
    </div>
  );
}
