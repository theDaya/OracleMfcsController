import { useMemo, useState } from 'react';
import { PIPELINE, STEPS, OPERATIONS, SKU_FLOW, FAILURE_FLOW, PACKAGES } from './flowData';

// A guided, clickable picture of how the middleware works end to end: the
// journey a document takes, the step flow per operation, the SKU/colour logic,
// and what happens when things fail. Everything rendered here comes from
// flowData.js - keep that file honest and this tab stays honest.

const SECTIONS = [
  { id: 'journey', label: 'The journey' },
  { id: 'operations', label: 'Operations' },
  { id: 'skus', label: 'Colour & SKU logic' },
  { id: 'failure', label: 'Failure & resume' },
  { id: 'packages', label: 'Packages' },
];

function MethodTag({ method }) {
  if (!method) return <span className="method">LOCAL</span>;
  const cls = method.startsWith('POST') ? 'm-post' : method.startsWith('PUT') ? 'm-put' : method.startsWith('GET') ? 'm-get' : '';
  return <span className={`method ${cls}`}>{method}</span>;
}

function Gotchas({ items }) {
  if (!items || items.length === 0) return null;
  return (
    <div className="flow-gotchas">
      <h4>Worth knowing</h4>
      <ul>
        {items.map((g) => (
          <li key={g}>{g}</li>
        ))}
      </ul>
    </div>
  );
}

function DetailPanel({ title, subtitle, method, endpoint, handler, mapper, payload, detail, gotchas, extra }) {
  return (
    <div className="panel flow-detail">
      <h2>{title}</h2>
      {subtitle && <p className="explain">{subtitle}</p>}
      {(method || endpoint) && (
        <div className="flow-endpoint">
          <MethodTag method={method} />
          <code>{endpoint || 'no MFCS call - handled inside the integration layer'}</code>
        </div>
      )}
      {handler && (
        <div className="flow-kv">
          <span className="fg-label">Handled by</span>
          <code>{handler}</code>
        </div>
      )}
      {mapper && (
        <div className="flow-kv">
          <span className="fg-label">Payload mapper</span>
          <code>payload_pkg.build_request → {mapper}</code>
        </div>
      )}
      <p className="flow-prose">{detail}</p>
      {payload && (
        <>
          <h4 className="flow-h4">Payload shape</h4>
          <pre className="flow-pre">{payload}</pre>
        </>
      )}
      <Gotchas items={gotchas} />
      {extra}
    </div>
  );
}

// ---------------------------------------------------------------- journey ---
function Journey() {
  const [sel, setSel] = useState('document');
  const node = PIPELINE.find((n) => n.id === sel);
  return (
    <div className="flow-layout">
      <div className="panel">
        <h2>What happens to a document, start to finish</h2>
        <p className="explain">
          Every operation takes this same road. Click a stage for what it does and why it exists.
          The short version: the console (or Office) sends one JSON document; everything after
          that - validation, idempotency, the step graph, payload construction, the MFCS calls -
          lives in the database.
        </p>
        <div className="flow-chain">
          {PIPELINE.map((n, i) => (
            <div key={n.id} className="flow-chain-item">
              {i > 0 && <div className="flow-arrow">↓</div>}
              <button
                type="button"
                className={`flow-node ${sel === n.id ? 'sel' : ''} ${n.pkg ? '' : 'flow-node-ext'}`}
                onClick={() => setSel(n.id)}
              >
                <span className="flow-node-title">{n.title}</span>
                {n.pkg && <code className="flow-node-pkg">{n.pkg}</code>}
                <span className="flow-node-blurb">{n.blurb}</span>
              </button>
            </div>
          ))}
        </div>
      </div>
      <DetailPanel
        title={node.title}
        handler={node.pkg}
        detail={node.detail}
        gotchas={node.gotchas}
      />
    </div>
  );
}

// ------------------------------------------------------------- operations ---
function Operations() {
  const [opId, setOpId] = useState('CREATE_ALL');
  const [selStep, setSelStep] = useState(null);
  const op = OPERATIONS.find((o) => o.id === opId);
  const step = selStep ? STEPS[selStep] : null;
  const resolved = step && (op.mode === 'update' ? step.update || step.create : step.create);

  return (
    <div>
      <div className="flow-ops">
        {OPERATIONS.map((o) => (
          <button
            key={o.id}
            type="button"
            className={`flow-op ${opId === o.id ? 'on' : ''}`}
            onClick={() => {
              setOpId(o.id);
              setSelStep(null);
            }}
          >
            {o.label}
          </button>
        ))}
      </div>
      <div className="flow-layout">
        <div className="panel">
          <h2>{op.label}</h2>
          <p className="explain">{op.blurb}</p>
          <p className={`flow-proven ${op.proven.includes('open') || op.proven.includes('ignored') ? 'warn' : ''}`}>
            {op.proven}
          </p>
          <div className="flow-chain">
            {op.steps.map((s, i) => {
              const def = STEPS[s.code];
              const r = op.mode === 'update' ? def.update || def.create : def.create;
              return (
                <div key={s.code} className="flow-chain-item">
                  {i > 0 && <div className="flow-arrow">↓</div>}
                  <button
                    type="button"
                    className={`flow-node ${selStep === s.code ? 'sel' : ''} ${def.kind === 'local' ? 'flow-node-local' : ''} ${def.kind === 'subflow' ? 'flow-node-sub' : ''}`}
                    onClick={() => setSelStep(s.code)}
                  >
                    <span className="seq">{s.seq}</span>
                    <MethodTag method={def.kind === 'call' ? r?.method : def.kind === 'subflow' ? 'MIXED' : null} />
                    <span className="flow-node-title">{def.title}</span>
                    {def.kind === 'call' && r && <span className="flow-node-blurb">{r.endpoint}</span>}
                    {def.kind === 'subflow' && (
                      <span className="flow-node-blurb">reads the tenant, creates only what is missing → see Colour &amp; SKU logic</span>
                    )}
                    {s.flag && <span className="pill off">flag: {s.flag}</span>}
                  </button>
                </div>
              );
            })}
          </div>
        </div>
        {step ? (
          <DetailPanel
            title={step.title}
            method={step.kind === 'call' ? resolved?.method : null}
            endpoint={step.kind === 'call' ? resolved?.endpoint : null}
            handler={step.handler}
            mapper={step.mapper}
            payload={step.payload}
            detail={step.detail}
            gotchas={step.gotchas}
            extra={
              step.create && step.update && step.create.endpoint !== step.update.endpoint ? (
                <div className="flow-gotchas">
                  <h4>Create vs update</h4>
                  <ul>
                    <li>
                      New style (CREATE_STYLE / CREATE_ALL): <code>{step.create.method} {step.create.endpoint}</code>
                    </li>
                    <li>
                      Existing style (MODIFY_STYLE / CREATE_ORDER / MODIFY_ORDER): <code>{step.update.method} {step.update.endpoint}</code>
                    </li>
                    <li>
                      Decided by <code>orchestrator_pkg.resolve_step</code> from the operation name alone - one case
                      statement resolves endpoint, method and mapper together so they cannot disagree.
                    </li>
                  </ul>
                </div>
              ) : null
            }
          />
        ) : (
          <div className="panel flow-detail">
            <h2>Pick a step</h2>
            <p className="explain">
              Each node shows its sequence number, HTTP method and MFCS endpoint. Click one for the
              handling packages, the payload it sends, and the tenant behaviour that shaped it.
              Colours: <span className="method m-post">POST</span> creates,{' '}
              <span className="method m-put">PUT</span> updates, <span className="method m-get">GET</span>{' '}
              verification reads, grey steps never leave the database.
            </p>
            <p className="explain">
              The design rule behind every flow here: <strong>an operation sends its whole write set,
              every time.</strong> The document states what the style should now be - not what changed -
              and MFCS answers a no-op write with SUCCESS, so a skipped step would fail silently.
              The only conditional step is the SKU check, and it conditions on the tenant.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

// -------------------------------------------------------------------- sku ---
function SkuFlow() {
  const [sel, setSel] = useState('read');
  const node = SKU_FLOW.find((n) => n.id === sel);
  return (
    <div className="flow-layout">
      <div className="panel">
        <h2>ENSURE_STYLE_SKUS: the colour / missing-SKU logic</h2>
        <p className="explain">
          Why this exists: <strong>a colour change cannot be applied to an existing SKU.</strong> In
          the RMS model the colour/size diff pair <em>defines</em> the item, and MFCS answers an
          in-place diff change with HTTP 200 SUCCESS while ignoring it (proven live). So every
          operation against an existing style starts by reconciling what the request needs against
          what the style actually has - and creating the difference as new child items.
        </p>
        <div className="flow-chain">
          {SKU_FLOW.map((n, i) => (
            <div key={n.id} className="flow-chain-item">
              {i > 0 && <div className="flow-arrow">↓</div>}
              {n.kind === 'decision' ? (
                <button
                  type="button"
                  className={`flow-node flow-node-decision ${sel === n.id ? 'sel' : ''}`}
                  onClick={() => setSel(n.id)}
                >
                  <span className="flow-node-title">◆ {n.title}</span>
                  <span className="flow-node-blurb">
                    <strong>yes</strong> → {n.yes}
                  </span>
                  <span className="flow-node-blurb">
                    <strong>no</strong> → {n.no}
                  </span>
                </button>
              ) : (
                <button
                  type="button"
                  className={`flow-node ${sel === n.id ? 'sel' : ''} ${n.kind === 'local' ? 'flow-node-local' : ''}`}
                  onClick={() => setSel(n.id)}
                >
                  <MethodTag method={n.kind === 'call' ? n.method : null} />
                  <span className="flow-node-title">{n.title}</span>
                  {n.tag && <code className="flow-node-pkg">{n.tag}</code>}
                  {n.endpoint && <span className="flow-node-blurb">{n.endpoint}</span>}
                </button>
              )}
            </div>
          ))}
        </div>
      </div>
      <DetailPanel
        title={node.title}
        method={node.kind === 'call' ? node.method : null}
        endpoint={node.endpoint}
        handler={node.tag}
        detail={node.detail}
        gotchas={node.gotchas}
      />
    </div>
  );
}

// ---------------------------------------------------------------- failure ---
function Failure() {
  return (
    <div className="flow-layout">
      <div className="panel">
        <h2>When a call goes wrong</h2>
        <p className="explain">
          client_pkg classifies every failure into one of three kinds, because they demand three
          different reactions. The classification is on status codes and SQLCODEs, never on message
          wording - that distinction was learned live.
        </p>
        {FAILURE_FLOW.classes.map((c) => (
          <div key={c.code} className={`flow-fail flow-fail-${c.colour}`}>
            <div className="flow-fail-head">
              <code>{c.code}</code>
              <strong>{c.name}</strong>
            </div>
            <p className="flow-prose">{c.detail}</p>
          </div>
        ))}
      </div>
      <div className="panel">
        <h2>Resume &amp; recovery</h2>
        <p className="explain">
          Every step and every HTTP attempt is journalled (STEP, ATTEMPT, EVENT_LOG - the Activity
          tab reads these). That journal is what makes a half-finished request continuable instead
          of a mess.
        </p>
        {FAILURE_FLOW.recovery.map((r) => (
          <div key={r.id} className="flow-fail">
            <div className="flow-fail-head">
              <strong>{r.title}</strong>
            </div>
            <p className="flow-prose">{r.detail}</p>
          </div>
        ))}
      </div>
    </div>
  );
}

// --------------------------------------------------------------- packages ---
function Packages() {
  return (
    <div className="panel">
      <h2>The fifteen packages, in load order</h2>
      <p className="explain">
        File numbering in <code>database/20_packages/</code> is dependency order, not decoration:
        each file holds spec and body, so anything a body calls must already exist. That is what
        makes a missing payload mapper a compile error instead of a runtime surprise.
      </p>
      <table className="rows">
        <thead>
          <tr>
            <th>#</th>
            <th>Package</th>
            <th>What it owns</th>
          </tr>
        </thead>
        <tbody>
          {PACKAGES.map((p) => (
            <tr key={p.name} className="norow">
              <td className="mono">{p.n}</td>
              <td>
                <code>{p.name}</code>
              </td>
              <td className="muted">{p.role}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default function FlowTab() {
  const [section, setSection] = useState('journey');
  const body = useMemo(() => {
    switch (section) {
      case 'operations':
        return <Operations />;
      case 'skus':
        return <SkuFlow />;
      case 'failure':
        return <Failure />;
      case 'packages':
        return <Packages />;
      default:
        return <Journey />;
    }
  }, [section]);

  return (
    <div>
      <div className="tabs rd-tabs">
        {SECTIONS.map((s) => (
          <button
            key={s.id}
            type="button"
            className={section === s.id ? 'on' : ''}
            onClick={() => setSection(s.id)}
          >
            {s.label}
          </button>
        ))}
      </div>
      {body}
    </div>
  );
}
