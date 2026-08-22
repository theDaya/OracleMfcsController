import { useEffect, useState } from 'react';
import { getOrder, getStyle, listOrders, listStyles } from './api';
import { orderToForm, styleToForm } from './formState';
import RecordDetail from './RecordDetail';

export default function BrowseTab({ form, setForm, goToTransactions }) {
  const [mode, setMode] = useState('styles');
  const [rows, setRows] = useState([]);
  const [selected, setSelected] = useState(null);
  const [order, setOrder] = useState(null);
  const [style, setStyle] = useState(null);
  const [skus, setSkus] = useState([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [limit, setLimit] = useState('25');
  const [filter, setFilter] = useState('');

  const load = async () => {
    setBusy(true);
    setError(null);
    setSelected(null);
    setOrder(null);
    setStyle(null);
    setSkus([]);
    try {
      const { body } =
        mode === 'styles'
          ? await listStyles({ limit, itemLevel: '1' })
          : await listOrders({ limit });
      setRows(body?.items || []);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode]);

  /**
   * Assembles the full picture for one row.
   *
   * An order is one order to one style, so selecting an order pulls the style it
   * resolved to and that style's SKUs. Selecting a style skips the order half.
   */
  const open = async (row) => {
    setBusy(true);
    setError(null);
    setOrder(null);
    setStyle(null);
    setSkus([]);
    try {
      if (mode === 'orders') {
        const { body } = await getOrder(row.orderNo);
        const ord = body?.items?.[0] || null;
        setOrder(ord);
        setSelected(ord);
        const styleNo = ord?.resolved?.style;
        if (styleNo) {
          const st = await getStyle(styleNo, true);
          const doc = st.body?.items?.[0] || null;
          setStyle(doc);
          setSkus(doc?.resolved?.skus || []);
        }
      } else {
        const { body } = await getStyle(row.item, true);
        const doc = body?.items?.[0] || null;
        setStyle(doc);
        setSelected(doc);
        setSkus(doc?.resolved?.skus || []);
      }
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  const loadIntoModify = () => {
    if (mode === 'orders' && order) {
      setForm(orderToForm(order, form));
    } else if (style) {
      setForm(styleToForm(style, form));
    } else {
      return;
    }
    goToTransactions();
  };

  const visible = rows.filter((r) => {
    if (!filter.trim()) return true;
    const q = filter.toLowerCase();
    return JSON.stringify(r).toLowerCase().includes(q);
  });

  return (
    <div className="panel">
      <div className="browse-head">
        <div className="segmented">
          <button
            type="button"
            className={mode === 'styles' ? 'on' : ''}
            onClick={() => setMode('styles')}
          >
            Styles
          </button>
          <button
            type="button"
            className={mode === 'orders' ? 'on' : ''}
            onClick={() => setMode('orders')}
          >
            Orders
          </button>
        </div>
        <input
          className="grow"
          placeholder="Filter loaded rows…"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        />
        <select value={limit} onChange={(e) => setLimit(e.target.value)}>
          {['10', '25', '50', '100'].map((n) => (
            <option key={n} value={n}>
              {n} rows
            </option>
          ))}
        </select>
        <button type="button" onClick={load} disabled={busy}>
          {busy ? 'Loading…' : 'Reload'}
        </button>
      </div>

      <p className="explain">
        Live from MFCS. These are publish feeds, so they show approved and published records only —
        a style still in worksheet status will not appear here. Click a row to load the full document,
        then push it into the modify form.
      </p>

      {error && <div className="banner error">{error}</div>}

      <div className="browse-layout">
        <div className="browse-list">
          <table className="rows">
            <thead>
              {mode === 'styles' ? (
                <tr>
                  <th>Item</th>
                  <th>Description</th>
                  <th>Dept</th>
                  <th>St</th>
                </tr>
              ) : (
                <tr>
                  <th>Order</th>
                  <th>Supplier</th>
                  <th>Dept</th>
                  <th>St</th>
                </tr>
              )}
            </thead>
            <tbody>
              {visible.map((r) => {
                const key = mode === 'styles' ? r.item : r.orderNo;
                const isSel =
                  selected &&
                  (mode === 'styles' ? selected.item === r.item : selected.orderNo === r.orderNo);
                return (
                  <tr
                    key={key}
                    onClick={() => open(r)}
                    className={isSel ? 'sel' : ''}
                  >
                    {mode === 'styles' ? (
                      <>
                        <td><code>{r.item}</code></td>
                        <td className="ellipsis" title={r.itemDescription}>{r.itemDescription}</td>
                        <td>{r.dept}</td>
                        <td>{r.status}</td>
                      </>
                    ) : (
                      <>
                        <td><code>{r.orderNo}</code></td>
                        <td>{r.supplier}</td>
                        <td>{r.dept}</td>
                        <td>{r.status}</td>
                      </>
                    )}
                  </tr>
                );
              })}
              {visible.length === 0 && !busy && (
                <tr>
                  <td colSpan={4} className="muted">
                    No rows.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
          <p className="muted small">{visible.length} of {rows.length} shown</p>
        </div>

        <div className="browse-detail">
          {!selected && !busy && (
            <p className="explain">Select a row to see how it hangs together in MFCS.</p>
          )}
          {selected && (
            <div className="detail-actions">
              <button type="button" className="primary" onClick={loadIntoModify}>
                {mode === 'styles' ? 'Load into Modify Style' : 'Load into Modify Order'}
              </button>
              <span className="muted small">
                {mode === 'styles'
                  ? 'Add size rows with SKU IDs before previewing a modify.'
                  : 'Order lines carry real item numbers, so the size curve fills in automatically.'}
              </span>
            </div>
          )}
          {(order || style) && (
            <RecordDetail order={order} style={style} skus={skus} loading={busy && !style && !order} />
          )}
        </div>
      </div>
    </div>
  );
}
