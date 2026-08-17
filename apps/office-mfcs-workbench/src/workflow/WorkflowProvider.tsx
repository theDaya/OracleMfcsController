import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { useAuth } from '../auth/AuthProvider'
import { mapRequestToPayload } from '../mapping/integrationPayloadMapper'
import type { OfficeRequest } from '../models/officeRequest'
import { HttpWorkflowRepository } from './HttpWorkflowRepository'
import { WorkflowContext, type WorkflowContextValue } from './WorkflowContext'

export function WorkflowProvider({ children }: { children: ReactNode }) {
  const { currentUser } = useAuth()
  const repository = useMemo(() => new HttpWorkflowRepository(import.meta.env.VITE_WORKFLOW_API_BASE_URL ?? '/workflow-api'), [])
  const [requests, setRequests] = useState<OfficeRequest[]>([])
  const [loading, setLoading] = useState(true)

  const reload = useCallback(async () => {
    setRequests(await repository.list())
    setLoading(false)
  }, [repository])

  useEffect(() => { void reload() }, [reload])

  const persist = useCallback(async (request: OfficeRequest) => {
    await repository.save(request)
    await reload()
  }, [reload, repository])

  const acceptRemote = useCallback(async (request: OfficeRequest) => {
    await reload()
    return request
  }, [reload])

  const value = useMemo<WorkflowContextValue>(() => ({
    requests,
    loading,
    getRequest: (id) => requests.find((request) => request.id === id),
    saveDraft: async (request) => { await persist({ ...request, updatedAt: new Date().toISOString() }) },
    deleteDraft: async (id) => { await repository.remove(id); await reload() },
    submit: async (request) => acceptRemote(await repository.submit(request.id, currentUser)),
    correct: async (id) => {
      if (!requests.some((request) => request.id === id)) throw new Error('Request not found.')
      return acceptRemote(await repository.correct(id, currentUser))
    },
    returnRequest: async (id, reason) => {
      if (!requests.some((request) => request.id === id)) throw new Error('Request not found.')
      return acceptRemote(await repository.returnRequest(id, currentUser, reason))
    },
    approve: async (id) => {
      const request = requests.find((candidate) => candidate.id === id)
      if (!request) throw new Error('Request not found.')
      if (request.submittedBy?.id === currentUser.id || request.createdBy.id === currentUser.id) throw new Error('The submitter cannot approve their own request.')
      const approvedRequest = { ...request, actionRequestId: request.actionRequestId ?? crypto.randomUUID() }
      return acceptRemote(await repository.approve(id, currentUser, mapRequestToPayload(approvedRequest, currentUser)))
    },
    retry: async (id) => {
      if (!requests.some((request) => request.id === id)) throw new Error('Request not found.')
      return acceptRemote(await repository.retry(id, currentUser))
    },
    refreshStatus: async (id) => {
      const request = requests.find((candidate) => candidate.id === id)
      if (!request?.actionRequestId) throw new Error('No action request ID is available.')
      return acceptRemote(await repository.resolveStatus(id, currentUser))
    },
  }), [acceptRemote, currentUser, loading, persist, reload, repository, requests])

  return <WorkflowContext.Provider value={value}>{children}</WorkflowContext.Provider>
}
