import type { WorkflowStatus } from '../workflow/workflowTypes'

const labels: Record<WorkflowStatus, string> = {
  DRAFT: 'Draft',
  SUBMITTED: 'Awaiting approval',
  RETURNED: 'Returned',
  APPROVED: 'Approved',
  POSTING: 'Posting',
  POSTED: 'Posted',
  PARTIALLY_COMPLETED: 'Partially completed',
  FAILED: 'Failed',
  MANUAL_REVIEW: 'Manual review',
}

export function RequestStatusBadge({ status }: { status: WorkflowStatus }) {
  return <span className={`status-badge status-${status.toLowerCase()}`}>{labels[status]}</span>
}
