import { useState } from 'react';
import { refreshMasterData } from './api';

const LABELS = {
  DEPARTMENT: 'Departments',
  CLASS: 'Classes',
  SUBCLASS: 'Subclasses',
  SUPPLIER: 'Suppliers',
  DIFF_C: 'Colour differentiators',
  DIFF_S: 'Size differentiators',
  BRAND: 'Brands',
  SEASON: 'Seasons',
  ORG_HIER: 'Organisation hierarchy',
  CURRENCY: 'Currencies',
  TERMS: 'Payment terms',
  UOM: 'Units of measure',
  LOCATION_W: 'Virtual warehouses',
  LOCATION_P: 'Physical locations',
};

export default function MasterDataTab({ masterData, reloadMasterData }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [openType, setOpenType] = useState(null);
  const [filter, setFilter] = useState('');

  const types = masterData?.types || {};
  const log = masterData?.log || [];

  const refresh = async () => {
    setBusy(true);
    setError(null);
    try {
      await refreshMasterData();
      await reloadMasterData();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  const empties = log.filter((l) => l.rowCount === 0 && l.httpStatus !== 401);
  const unauthorised = log.filter((l) => l.httpStatus === 401);

  return (
    <div className="panel">
      <div className="browse-head">
        <h2 style={{ margin: 0, flex: 1 }}>Master data cache</h2>
        <button type="button" className="primary" onClick={refresh} disabled={busy}>
          {busy ? 'Refreshing from MFCS…' : 'Refresh from MFCS'}
        </button>
      </div>

      <p className="explain">
        Cached locally in <code>OFFICE_MFCS_MASTER_DATA</code> so the entry form can offer dropdowns
        without a call per keystroke. Each row records where it came from.
      </p>

      {error && <div className="banner error">{error}</div>}

      {unauthorised.length > 0 && (
        <div className="banner error">
          <strong>MFCS rejected the bearer token (HTTP 401).</strong> The stored token has most likely
          expired — they last one hour. Re-run <em>Get OAuth Token</em> in the Postman collection and
          apply the <code>MERGE</code> it prints to <code>OFFICE_MFCS_SECRET</code>, then refresh again.
          Nothing was cached from this attempt.
        </div>
      )}

      <div className="banner warn">
        <strong>Two sources, and the difference matters.</strong>
        <br />
        <code>ENDPOINT:</code> read straight from a foundation service. <code>DERIVED:</code> harvested
        from the item or order feed, because the matching foundation service returns HTTP 200 with zero
        rows on this tenant — those publish queues have never been seeded. Derived values are therefore
        only as complete as the items and orders that exist; they are real, but they are not the full
        tenant master.
        {empties.length > 0 && (
          <>
            <br />
            <br />
            Still empty: {empties.map((e) => e.dataType.replace('_SVC', '')).join(', ')}.
          </>
        )}
      </div>

      <input
        placeholder="Filter values…"
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        style={{ marginBottom: 12 }}
      />

      <div className="md-grid">
        {Object.entries(types)
          .sort(([a], [b]) => a.localeCompare(b))
          .map(([type, values]) => {
            const shown = values.filter((v) => {
              if (!filter.trim()) return true;
              const q = filter.toLowerCase();
              return (
                String(v.code).toLowerCase().includes(q) ||
                String(v.description || '').toLowerCase().includes(q)
              );
            });
            if (filter.trim() && shown.length === 0) return null;
            const isOpen = openType === type;
            return (
              <div key={type} className={`md-card ${isOpen ? 'open' : ''}`}>
                <button type="button" className="md-head" onClick={() => setOpenType(isOpen ? null : type)}>
                  <span className="md-name">{LABELS[type] || type}</span>
                  <span className="count">{shown.length}</span>
                </button>
                {isOpen && (
                  <div className="md-body">
                    <table className="rows">
                      <thead>
                        <tr>
                          <th>Code</th>
                          <th>Description</th>
                          <th>Parent</th>
                        </tr>
                      </thead>
                      <tbody>
                        {shown.slice(0, 500).map((v) => (
                          <tr key={`${v.code}-${v.parent || ''}`}>
                            <td><code>{v.code}</code></td>
                            <td className="ellipsis">{v.description || ''}</td>
                            <td className="muted">{v.parent || ''}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                    {shown.length > 500 && (
                      <p className="muted small">Showing first 500 of {shown.length}.</p>
                    )}
                  </div>
                )}
              </div>
            );
          })}
      </div>

      <h3>Last refresh</h3>
      <table className="rows">
        <thead>
          <tr>
            <th>Source</th>
            <th>HTTP</th>
            <th>Rows</th>
            <th>Note</th>
            <th>Completed</th>
          </tr>
        </thead>
        <tbody>
          {log.map((l) => (
            <tr key={l.dataType} className={l.rowCount === 0 ? 'dim' : ''}>
              <td>
                <code>{l.dataType}</code>
                <br />
                <span className="muted small">{l.source}</span>
              </td>
              <td>{l.httpStatus}</td>
              <td>{l.rowCount}</td>
              <td className="muted">{l.message || ''}</td>
              <td className="muted small">{l.completedAt}</td>
            </tr>
          ))}
          {log.length === 0 && (
            <tr>
              <td colSpan={5} className="muted">
                Never refreshed. Use the button above.
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}
