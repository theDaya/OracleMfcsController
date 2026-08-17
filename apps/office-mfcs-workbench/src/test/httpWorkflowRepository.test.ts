import { afterEach, describe, expect, it, vi } from 'vitest'
import type { IntegrationPayload } from '../models/integrationPayload'
import type { UserReference } from '../models/officeRequest'
import { HttpWorkflowRepository } from '../workflow/HttpWorkflowRepository'

const manager: UserReference = { id: 'manager-1', name: 'Manager One', role: 'MANAGER' }
const payload = {
  OPERATION_NAME: 'CREATE_ALL',
  ACTION_REQUEST_ID: 'action-1',
} as IntegrationPayload

describe('HttpWorkflowRepository', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('sends approvals only to the Oracle workflow command', async () => {
    const fetchStub = vi.fn().mockResolvedValue(new Response('{}', {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }))
    vi.stubGlobal('fetch', fetchStub)

    await new HttpWorkflowRepository('/workflow-api').approve('request-1', manager, payload)

    expect(fetchStub).toHaveBeenCalledOnce()
    const [url, init] = fetchStub.mock.calls[0] as [string, RequestInit]
    expect(url).toBe('/workflow-api/requests/request-1/approve')
    expect(JSON.parse(String(init.body))).toEqual({ actor: manager, payload })
  })

  it('does not fall back when the Oracle workflow API fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({ message: 'Oracle unavailable' }), {
      status: 503,
      headers: { 'Content-Type': 'application/json' },
    })))

    await expect(new HttpWorkflowRepository('/workflow-api').list()).rejects.toThrow('Oracle unavailable')
  })
})
