import { ArrowLeft, CheckCircle2, RotateCcw } from 'lucide-react'
import { useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useAuth } from '../auth/AuthProvider'
import { RequestReview } from '../components/RequestReview'
import { RequestStatusBadge } from '../components/RequestStatusBadge'
import { useWorkflow } from '../workflow/WorkflowContext'

export function ApprovalReviewPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const { currentUser } = useAuth()
  const { getRequest, approve, returnRequest, loading } = useWorkflow()
  const request = getRequest(id)
  const [returning, setReturning] = useState(false)
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string>()
  if (currentUser.role !== 'MANAGER') return <div className="empty-state"><h2>Manager access required</h2></div>
  if (loading) return <div className="empty-state">Loading request…</div>
  if (!request) return <div className="empty-state"><h2>Request not found</h2></div>
  if (request.status !== 'SUBMITTED') return <div className="empty-state"><h2>This request is no longer awaiting approval</h2><Link to={`/requests/${request.id}`}>View current status</Link></div>

  const approveNow = async () => { setBusy(true); setError(undefined); try { await approve(request.id); navigate(`/requests/${request.id}`) } catch (reason) { setError(reason instanceof Error ? reason.message : 'Approval failed.') } finally { setBusy(false) } }
  const returnNow = async () => { if (!reason.trim()) { setError('A return reason is required.'); return } setBusy(true); setError(undefined); try { await returnRequest(request.id, reason); navigate('/approvals') } catch (failure) { setError(failure instanceof Error ? failure.message : 'Return failed.') } finally { setBusy(false) } }
  return (
    <div className="page-stack">
      <div className="page-header compact"><div><Link to="/approvals" className="back-link"><ArrowLeft size={16} /> Approval queue</Link><div className="title-with-status"><h1>Review {request.officeReference}</h1><RequestStatusBadge status={request.status} /></div><p>Submitted by {request.submittedBy?.name} · source version {request.sourceVersion}</p></div></div>
      {request.createdBy.id === currentUser.id && <div className="message-bar message-error">You cannot approve your own request.</div>}
      <section className="content-panel"><RequestReview request={request} /></section>
      {returning && <section className="return-panel"><label className="form-field"><span className="field-label">Reason for return</span><textarea rows={4} value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Tell the buyer exactly what needs correction." /></label><div><button className="secondary-button" onClick={() => setReturning(false)}>Cancel</button><button className="danger-button" onClick={returnNow} disabled={busy}><RotateCcw size={16} /> Return request</button></div></section>}
      {error && <div className="message-bar message-error">{error}</div>}
      <div className="approval-bar"><button className="danger-button" onClick={() => setReturning(true)} disabled={busy}><RotateCcw size={16} /> Return for correction</button><button className="primary-button" onClick={approveNow} disabled={busy || request.createdBy.id === currentUser.id}><CheckCircle2 size={17} /> Approve and post</button></div>
    </div>
  )
}
