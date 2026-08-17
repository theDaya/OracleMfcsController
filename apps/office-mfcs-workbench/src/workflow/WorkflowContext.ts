import { createContext, useContext } from 'react'
import type { OfficeRequest } from '../models/officeRequest'

export interface WorkflowContextValue {
  requests: OfficeRequest[]
  loading: boolean
  getRequest: (id: string) => OfficeRequest | undefined
  saveDraft: (request: OfficeRequest) => Promise<void>
  deleteDraft: (id: string) => Promise<void>
  submit: (request: OfficeRequest) => Promise<OfficeRequest>
  correct: (id: string) => Promise<OfficeRequest>
  returnRequest: (id: string, reason: string) => Promise<OfficeRequest>
  approve: (id: string) => Promise<OfficeRequest>
  retry: (id: string) => Promise<OfficeRequest>
  refreshStatus: (id: string) => Promise<OfficeRequest>
}

export const WorkflowContext = createContext<WorkflowContextValue | null>(null)

export function useWorkflow() {
  const context = useContext(WorkflowContext)
  if (!context) throw new Error('useWorkflow must be used inside WorkflowProvider')
  return context
}
