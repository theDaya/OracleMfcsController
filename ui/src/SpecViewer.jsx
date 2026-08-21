import { useEffect, useMemo, useState } from 'react';
import JsonBlock from './JsonBlock';

const METHODS = ['get', 'post', 'put', 'patch', 'delete'];

function Operation({ method, op }) {
  const [showSchema, setShowSchema] = useState(false);
  const params = op.parameters || [];
  const body = op.requestBody?.content?.['application/json']?.schema;

  return (
    <div className="spec-op">
      <div className="spec-op-head">
        <span className={`method m-${method}`}>{method.toUpperCase()}</span>
        <strong>{op.summary || '(no summary)'}</strong>
      </div>

      {op.description && <p className="spec-desc">{op.description}</p>}

      {params.length > 0 && (
        <table className="spec-params">
          <thead>
            <tr>
              <th>Parameter</th>
              <th>In</th>
              <th>Type</th>
              <th>Req</th>
              <th>Description</th>
            </tr>
          </thead>
          <tbody>
            {params.map((p) => (
              <tr key={`${p.in}-${p.name}`}>
                <td>
                  <code>{p.name}</code>
                </td>
                <td>{p.in}</td>
                <td>{p.schema?.type || '—'}</td>
                <td>{p.required ? 'yes' : ''}</td>
                <td className="muted">{p.description || ''}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {body && (
        <>
          <button type="button" className="link" onClick={() => setShowSchema(!showSchema)}>
            {showSchema ? 'hide' : 'show'} request schema
          </button>
          {showSchema && <JsonBlock value={body} />}
        </>
      )}
    </div>
  );
}

export default function SpecViewer({ usedEndpoints }) {
  const [spec, setSpec] = useState(null);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);
  const [filter, setFilter] = useState('');
  const [methodFilter, setMethodFilter] = useState('all');
  const [usedOnly, setUsedOnly] = useState(false);
  const [open, setOpen] = useState(null);

  useEffect(() => {
    setLoading(true);
    fetch('/openapi.json')
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status} loading /openapi.json`);
        return r.json();
      })
      .then(setSpec)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  // Configured endpoint paths, normalised for comparison against spec keys.
  const used = useMemo(() => {
    const set = new Set();
    (usedEndpoints || []).forEach((e) => {
      if (e.mapped) set.add(e.mapped.replace('/MerchIntegrations', ''));
    });
    return set;
  }, [usedEndpoints]);

  const rows = useMemo(() => {
    if (!spec?.paths) return [];
    const q = filter.trim().toLowerCase();
    return Object.entries(spec.paths)
      .map(([path, item]) => ({
        path,
        item,
        methods: METHODS.filter((m) => item[m]),
        isUsed: used.has(path),
      }))
      .filter((r) => r.methods.length > 0)
      .filter((r) => (methodFilter === 'all' ? true : r.methods.includes(methodFilter)))
      .filter((r) => (usedOnly ? r.isUsed : true))
      .filter((r) => {
        if (!q) return true;
        if (r.path.toLowerCase().includes(q)) return true;
        return r.methods.some((m) => (r.item[m].summary || '').toLowerCase().includes(q));
      })
      .sort((a, b) => a.path.localeCompare(b.path));
  }, [spec, filter, methodFilter, usedOnly, used]);

  const totals = useMemo(() => {
    if (!spec?.paths) return null;
    const t = { paths: 0, ops: 0, used: 0 };
    Object.entries(spec.paths).forEach(([path, item]) => {
      const ms = METHODS.filter((m) => item[m]);
      if (!ms.length) return;
      t.paths += 1;
      t.ops += ms.length;
      if (used.has(path)) t.used += 1;
    });
    return t;
  }, [spec, used]);

  if (loading) return <p className="explain">Loading tenant spec…</p>;
  if (error)
    return (
      <div className="banner error">
        {error}
        <br />
        Expected <code>docs/mfcs-openapi/openapi.json</code> to be served at <code>/openapi.json</code>.
      </div>
    );
  if (!spec) return null;

  return (
    <div>
      <p className="explain">
        <strong>{spec.info?.title}</strong> version <code>{spec.info?.version}</code> — the tenant's own
        contract, pulled from <code>/MerchIntegrations/services/openapi.json</code>. This is the
        authoritative source for paths, methods and query parameters.
        {totals && (
          <>
            {' '}
            {totals.paths} paths, {totals.ops} operations, {totals.used} wired into this bridge.
          </>
        )}
      </p>

      <div className="spec-controls">
        <input
          placeholder="Filter by path or summary…"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        />
        <select value={methodFilter} onChange={(e) => setMethodFilter(e.target.value)}>
          <option value="all">All methods</option>
          {METHODS.map((m) => (
            <option key={m} value={m}>
              {m.toUpperCase()}
            </option>
          ))}
        </select>
        <label className="check">
          <input type="checkbox" checked={usedOnly} onChange={(e) => setUsedOnly(e.target.checked)} />
          Only endpoints this bridge uses
        </label>
      </div>

      <p className="muted small">{rows.length} matching</p>

      <div className="spec-list">
        {rows.map((r) => (
          <div key={r.path} className={`spec-row ${r.isUsed ? 'used' : ''}`}>
            <button type="button" className="spec-row-head" onClick={() => setOpen(open === r.path ? null : r.path)}>
              <span className="spec-methods">
                {r.methods.map((m) => (
                  <span key={m} className={`method m-${m}`}>
                    {m.toUpperCase()}
                  </span>
                ))}
              </span>
              <code className="spec-path">{r.path}</code>
              {r.isUsed && <span className="badge">in use</span>}
            </button>
            {open === r.path && (
              <div className="spec-row-body">
                {r.methods.map((m) => (
                  <Operation key={m} method={m} op={r.item[m]} />
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
