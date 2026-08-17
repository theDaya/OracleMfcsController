import { ArrowRight, ClipboardCheck } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useAuth } from '../auth/AuthProvider'
import { operationLabels } from '../models/officeRequest'
import { useWorkflow } from '../workflow/WorkflowContext'

const formatDate = (value?: string) => value ? new Intl.DateTimeFormat('en-ZA', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '—'

export function ApprovalQueuePage() {
  const { currentUser } = useAuth()
  const { requests, loading } = useWorkflow()
  if (currentUser.role !== 'MANAGER') return <div className="empty-state"><h2>Manager access required</h2><p>Switch to Michael Manager to review approvals.</p></div>
  const queue = requests.filter((request) => request.status === 'SUBMITTED')
  return (
    <div className="page-stack">
      <div className="page-header"><div><span className="page-eyebrow">Manager workspace</span><h1>Approval queue</h1><p>Requests waiting for an independent review.</p></div><div className="queue-count"><ClipboardCheck size={19} /><strong>{queue.length}</strong><span>awaiting review</span></div></div>
      <section className="content-panel">
        {loading ? <div className="empty-state">Loading Oracle workflow data…</div> : queue.length === 0 ? <div className="empty-state"><ClipboardCheck size={28} /><h2>Queue is clear</h2><p>Submitted requests will appear here.</p></div> : <div className="table-wrap"><table><thead><tr><th>Order reference</th><th>Operation</th><th>Style description</th><th>Supplier</th><th>Quantity</th><th>Total cost</th><th>Buyer</th><th>Submitted</th><th>Version</th><th /></tr></thead><tbody>{queue.map((request) => { const quantity = request.variants.reduce((sum, variant) => sum + variant.quantity, 0); return <tr key={request.id}><td><strong>{request.sourceOrderRef}</strong></td><td>{operationLabels[request.operationName]}</td><td>{request.style.description}</td><td>{request.sourcing.supplier}</td><td>{quantity.toLocaleString()}</td><td>${(quantity * request.sourcing.costPrice).toLocaleString(undefined, { minimumFractionDigits: 2 })}</td><td>{request.createdBy.name}</td><td>{formatDate(request.submittedAt)}</td><td>v{request.sourceVersion}</td><td><Link className="table-action" to={`/approvals/${request.id}`}><ArrowRight size={17} /><span className="sr-only">Review</span></Link></td></tr> })}</tbody></table></div>}
      </section>
    </div>
  )
}
