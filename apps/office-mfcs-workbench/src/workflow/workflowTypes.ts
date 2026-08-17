export type WorkflowStatus =
  | 'DRAFT'
  | 'SUBMITTED'
  | 'RETURNED'
  | 'APPROVED'
  | 'POSTING'
  | 'POSTED'
  | 'PARTIALLY_COMPLETED'
  | 'FAILED'
  | 'MANUAL_REVIEW'

export type ApprovalAction = 'SUBMITTED' | 'RETURNED' | 'APPROVED' | 'RETRIED'

export interface ApprovalHistoryEntry {
  id: string
  action: ApprovalAction
  actorId: string
  actorName: string
  at: string
  sourceVersion: number
  comment?: string
}
