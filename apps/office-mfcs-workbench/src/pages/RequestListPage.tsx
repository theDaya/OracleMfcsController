import { ArrowRight, FilePlus2, Pencil, Wrench } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useAuth } from '../auth/AuthProvider'
import { RequestStatusBadge } from '../components/RequestStatusBadge'
import { operationLabels } from '../models/officeRequest'
import { useWorkflow } from '../workflow/WorkflowContext'

const formatDate = (value?: string) => value ? new Intl.DateTimeFormat('en-ZA', { dateStyle: 'medium' }).format(new Date(value)) : '—'

export function RequestListPage() {
  const { currentUser } = useAuth()
  const { requests, loading } = useWorkflow()
  const mine = requests.filter((request) => request.createdBy.id === currentUser.id)
  const active = mine.filter((request) => !['POSTED', 'FAILED'].includes(request.status)).length
  const posted = mine.filter((request) => request.status === 'POSTED').length
  return (
    <div className="page-stack">
      <div className="page-header"><div><span className="page-eyebrow">Workspace</span><h1>My requests</h1><p>Drafts, approvals and MFCS posting results for {currentUser.name}.</p></div>{currentUser.role === 'BUYER' && <Link to="/requests/new" className="primary-button"><FilePlus2 size={17} /> New request</Link>}</div>
      <div className="metric-strip"><div><span>Total requests</span><strong>{mine.length}</strong></div><div><span>In progress</span><strong>{active}</strong></div><div><span>Posted to MFCS</span><strong>{posted}</strong></div></div>
      <section className="content-panel">
        {loading ? <div className="empty-state">Loading Oracle workflow data…</div> : mine.length === 0 ? <div className="empty-state"><FilePlus2 size={28} /><h2>No requests yet</h2><p>Create a style, order, or modification request to start the approval flow.</p>{currentUser.role === 'BUYER' && <Link to="/requests/new" className="primary-button">Create first request</Link>}</div> : (
          <div className="table-wrap"><table className="request-table"><thead><tr><th>Office reference</th><th>Operation</th><th>Style</th><th>Supplier</th><th>Updated</th><th>Status</th><th>MFCS IDs</th><th><span className="sr-only">Action</span></th></tr></thead><tbody>{mine.map((request) => {
            const editable = request.status === 'DRAFT'
            const returned = request.status === 'RETURNED'
            return <tr key={request.id}><td><strong>{request.officeReference}</strong><span className="subline">v{request.sourceVersion}</span></td><td>{operationLabels[request.operationName]}</td><td>{request.style.description}</td><td>{request.sourcing.supplier}</td><td>{formatDate(request.updatedAt)}</td><td><RequestStatusBadge status={request.status} /></td><td><span className="id-stack"><b>S</b>{(request.integrationResponse?.STYLE ?? request.style.existingStyle) || '—'} <b>PO</b>{(request.integrationResponse?.ORDER_NO ?? request.order.existingOrderNo) || '—'}</span></td><td><Link className="table-action" to={editable ? `/requests/${request.id}/edit` : `/requests/${request.id}`}>{editable ? <Pencil size={16} /> : returned ? <Wrench size={16} /> : <ArrowRight size={16} />}<span className="sr-only">{editable ? 'Edit' : 'View'}</span></Link></td></tr>
          })}</tbody></table></div>
        )}
      </section>
    </div>
  )
}
