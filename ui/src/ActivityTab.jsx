import { useEffect, useState } from 'react';
import { getRequest, getRequests, resumeTransaction } from './api';
import JsonBlock from './JsonBlock';

const STATUS_TONE = {
  COMPLETED: 'ok',
  PARTIALLY_COMPLETED: 'warn',
  OUTCOME_UNKNOWN: 'warn',
  MANUAL_REVIEW: 'warn',
  FAILED_NO_SIDE_EFFECT: 'bad',
  IN_PROGRESS: '',
  RECEIVED: '',
  VALIDATED: '',
};

const STEP_TONE = {
  SUCCEEDED: 'ok',
  FAILED: 'bad',
  OUTCOME_UNKNOWN: 'warn',
  PENDING: '',
  IN_PROGRESS: '',
};

function Attempt({ a }) {
  const [open, setOpen] = useState(a.httpStatus >= 400);
  const bad = a.httpStatus >= 400;
  return (
    <div className={`call ${bad ? 'attempt-bad' : ''}`}>
      <button type="button" className="call-head" onClick={() => setOpen(!open)}>
        <span className={`method m-${(a.method || '').toLowerCase()}`}>{a.method}</span>
        <span className="step">{a.stepCode}</span>
        <span className={`badge ${bad ? 'bad' : 'ok'}`}>HTTP {a.httpStatus ?? '—'}</span>
        <span className="path">try {a.attemptNumber} · {a.startedAt}</span>
        <span className="chev">{open ? '−' : '+'}</span>
      </button>
      {open && (
        <div className="call-body">
          <div className="url">{a.method} {a.endpoint}</div>
          <div className="url">correlation: {a.correlationId}</div>
          <p className="muted small" style={{ margin: '10px 0 4px' }}>Response</p>
          <JsonBlock value={a.responsePayload} />
          <p className="muted small" style={{ margin: '10px 0 4px' }}>Request</p>
          <JsonBlock value={a.requestPayload} />
        </div>
      )}
    </div>
  );
}

export default function ActivityTab() {
  const [rows, setRows] = useState([]);
  const [sel, setSel] = useState(null);
  const [detail, setDetail] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [note, setNote] = useState(null);
  const [view, setView] = useState('steps');

  const load = async () => {
    setBusy(true);
    setError(null);
    try {
      const { body } = await getRequests();
      setRows(body?.items || []);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  const open = async (id) => {
    setSel(id);
    setDetail(null);
    setNote(null);
    setBusy(true);
    try {
      const { body } = await getRequest(id);
      setDetail(body);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  const resume = async () => {
    if (!sel) return;
    if (!window.confirm(`Resume ${sel} against the live MFCS tenant?\n\nSucceeded steps are skipped; the failed step is retried.`)) return;
    setBusy(true);
    setNote(null);
    try {
      const { status, body } = await resumeTransaction(sel);
      setNote(`Resume returned HTTP ${status} — ${body?.STATUS || 'see steps below'}`);
      await open(sel);
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  const failedStep = (detail?.steps || []).find((s) => s.stepStatus === 'FAILED');
  const resumable =
    detail && ['PARTIALLY_COMPLETED', 'OUTCOME_UNKNOWN', 'MANUAL_REVIEW'].includes(detail.requestStatus);

  return (
    <div className="panel">
      <div className="browse-head">
        <h2 style={{ margin: 0, flex: 1 }}>Transactions submitted from here</h2>
        <button type="button" onClick={load} disabled={busy}>
          {busy ? 'Loading…' : 'Reload'}
        </button>
      </div>

      <p className="explain">
        Every request this layer has journalled, newest first. Open one to see its step graph, each
        HTTP attempt with the exact payloads, and the autonomous event log.
      </p>

      {error && <div className="banner error">{error}</div>}

      <div className="browse-layout">
        <div className="browse-list">
          <table className="rows">
            <thead>
              <tr>
                <th>Request</th>
                <th>Operation</th>
                <th>Status</th>
                <th>Steps</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr
                  key={r.actionRequestId}
                  className={sel === r.actionRequestId ? 'sel' : ''}
                  onClick={() => open(r.actionRequestId)}
                >
                  <td>
                    <code>{r.actionRequestId}</code>
                    {r.styleNo && <div className="muted small">style {r.styleNo}{r.orderNo ? ` · order ${r.orderNo}` : ''}</div>}
                  </td>
                  <td className="small">{r.operationName}</td>
                  <td>
                    <span className={`badge ${STATUS_TONE[r.requestStatus] ?? ''}`}>
                      {r.requestStatus}
                    </span>
                  </td>
                  <td className="small">
                    {r.stepsSucceeded}/{r.stepCount}
                  </td>
                </tr>
              ))}
              {rows.length === 0 && !busy && (
                <tr>
                  <td colSpan={4} className="muted">
                    Nothing submitted yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        <div className="browse-detail">
          {!detail && <p className="explain">Select a request to inspect it.</p>}
          {detail && (
            <>
              <div className="detail-actions">
                <span className={`badge ${STATUS_TONE[detail.requestStatus] ?? ''}`}>
                  {detail.requestStatus}
                </span>
                {detail.styleNo && <span className="muted small">style {detail.styleNo}</span>}
                {detail.orderNo && <span className="muted small">order {detail.orderNo}</span>}
                {resumable && (
                  <button type="button" className="danger" onClick={resume} disabled={busy}>
                    Resume against live MFCS
                  </button>
                )}
              </div>

              {failedStep && (
                <div className="banner warn">
                  <strong>Failed at {failedStep.stepCode}</strong>
                  {failedStep.lastErrorMessage && <div>{failedStep.lastErrorMessage}</div>}
                  <div className="muted small" style={{ marginTop: 6 }}>
                    Steps before it succeeded and will not be re-called. Expand the failing attempt
                    below for what MFCS actually said.
                  </div>
                </div>
              )}

              {note && <div className="banner warn">{note}</div>}

              <div className="tabs" style={{ margin: '0 0 14px', padding: '0 0 0 0' }}>
                {['steps', 'attempts', 'events', 'payload'].map((v) => (
                  <button key={v} type="button" className={view === v ? 'on' : ''} onClick={() => setView(v)}>
                    {v[0].toUpperCase() + v.slice(1)}
                    {v === 'attempts' && <span className="count">{detail.attempts.length}</span>}
                    {v === 'events' && <span className="count">{detail.events.length}</span>}
                  </button>
                ))}
              </div>

              {view === 'steps' && (
                <table className="rows">
                  <thead>
                    <tr>
                      <th>Seq</th>
                      <th>Step</th>
                      <th>Status</th>
                      <th>Identifier</th>
                    </tr>
                  </thead>
                  <tbody>
                    {detail.steps.map((s) => (
                      <tr key={s.sequence}>
                        <td className="muted small">{s.sequence}</td>
                        <td><code>{s.stepCode}</code></td>
                        <td>
                          <span className={`badge ${STEP_TONE[s.stepStatus] ?? ''}`}>{s.stepStatus}</span>
                        </td>
                        <td className="small muted">{s.entityIdentifier || ''}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}

              {view === 'attempts' && (
                <div>
                  {detail.attempts.map((a) => (
                    <Attempt key={a.attemptId} a={a} />
                  ))}
                </div>
              )}

              {view === 'events' && (
                <table className="rows">
                  <thead>
                    <tr>
                      <th>When</th>
                      <th>Phase</th>
                      <th>Step</th>
                      <th>Message</th>
                    </tr>
                  </thead>
                  <tbody>
                    {detail.events.map((e) => (
                      <tr key={e.logId} className={e.level === 'ERROR' ? 'evt-error' : ''}>
                        <td className="muted small">{(e.loggedAt || '').replace('T', ' ')}</td>
                        <td className="small"><code>{e.phase}</code></td>
                        <td className="small muted">{e.stepCode || ''}</td>
                        <td className="small">{e.message}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}

              {view === 'payload' && (
                <>
                  <p className="muted small">Inbound document as submitted</p>
                  <JsonBlock value={detail.requestPayload} />
                  {detail.responsePayload && (
                    <>
                      <p className="muted small" style={{ marginTop: 12 }}>Response returned to the caller</p>
                      <JsonBlock value={detail.responsePayload} />
                    </>
                  )}
                </>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
