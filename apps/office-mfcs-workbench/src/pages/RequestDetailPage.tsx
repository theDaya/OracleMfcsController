import { ArrowLeft, Code2, Pencil, Wrench } from 'lucide-react'
import { useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useAuth } from '../auth/AuthProvider'
import { IntegrationResult } from '../components/IntegrationResult'
import { RequestReview } from '../components/RequestReview'
import { RequestStatusBadge } from '../components/RequestStatusBadge'
import { operationLabels } from '../models/officeRequest'
import { useWorkflow } from '../workflow/WorkflowContext'

const formatTime = (value?: string) => value ? new Intl.DateTimeFormat('en-ZA', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '—'

export function RequestDetailPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const { currentUser } = useAuth()
  const { getRequest, correct, retry, refreshStatus, loading } = useWorkflow()
  const request = getRequest(id)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string>()
  if (loading) return <div className="empty-state">Loading request…</div>
  if (!request) return <div className="empty-state"><h2>Request not found</h2><Link to="/requests">Return to requests</Link></div>

  const run = async (action: () => Promise<unknown>) => { setBusy(true); setError(undefined); try { await action() } catch (reason) { setError(reason instanceof Error ? reason.message : 'Action failed.') } finally { setBusy(false) } }
  const startCorrection = () => run(async () => { await correct(request.id); navigate(`/requests/${request.id}/edit`) })
  return (
    <div className="page-stack">
      <div className="page-header compact"><div><Link to="/requests" className="back-link"><ArrowLeft size={16} /> My requests</Link><div className="title-with-status"><h1>{request.officeReference}</h1><RequestStatusBadge status={request.status} /></div><p>{operationLabels[request.operationName]} · Source version {request.sourceVersion}</p></div><div className="header-actions">{request.status === 'DRAFT' && request.createdBy.id === currentUser.id && <Link className="secondary-button" to={`/requests/${request.id}/edit`}><Pencil size={16} /> Edit</Link>}{request.status === 'RETURNED' && request.createdBy.id === currentUser.id && <button className="primary-button" onClick={startCorrection} disabled={busy}><Wrench size={16} /> Correct request</button>}</div></div>
      <section className="request-meta"><div><span>Buyer</span><strong>{request.createdBy.name}</strong></div><div><span>Submitted</span><strong>{formatTime(request.submittedAt)}</strong></div><div><span>Approved by</span><strong>{request.approvedBy?.name ?? '—'}</strong></div><div><span>Approved</span><strong>{formatTime(request.approvedAt)}</strong></div></section>
      <IntegrationResult request={request} busy={busy} onRetry={currentUser.role === 'MANAGER' ? () => run(() => retry(request.id)) : undefined} onRefresh={currentUser.role === 'MANAGER' ? () => run(() => refreshStatus(request.id)) : undefined} />
      {error && <div className="message-bar message-error">{error}</div>}
      <section className="content-panel"><RequestReview request={request} payload={request.integrationPayload} /></section>
      <section className="content-panel history-panel"><h2>Approval history</h2>{request.approvalHistory.length === 0 ? <p className="muted">No workflow actions recorded yet.</p> : <ol className="history-list">{[...request.approvalHistory].reverse().map((entry) => <li key={entry.id}><span className="history-dot" /><div><strong>{entry.action.replaceAll('_', ' ')}</strong><p>{entry.actorName} · {formatTime(entry.at)} · version {entry.sourceVersion}</p>{entry.comment && <blockquote>{entry.comment}</blockquote>}</div></li>)}</ol>}</section>
      <details className="technical-details content-panel"><summary><Code2 size={17} /> Technical record</summary><div className="technical-grid"><div><h3>Action request ID</h3><pre>{request.actionRequestId ?? 'Not assigned'}</pre></div><div><h3>Frontend model</h3><pre>{JSON.stringify(request, null, 2)}</pre></div><div><h3>Latest API response</h3><pre>{JSON.stringify(request.integrationResponse ?? null, null, 2)}</pre></div></div></details>
    </div>
  )
}
