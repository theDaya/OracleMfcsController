import type { IntegrationPayload } from '../models/integrationPayload'
import type { OfficeRequest, UserReference } from '../models/officeRequest'

export class HttpWorkflowRepository {
  constructor(private readonly baseUrl: string) {}

  private async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const response = await fetch(`${this.baseUrl}${path}`, {
      ...init,
      headers: {
        Accept: 'application/json',
        ...(init.body ? { 'Content-Type': 'application/json' } : {}),
        ...init.headers,
      },
    })
    if (response.status === 204) return undefined as T
    const body = await response.json().catch(() => ({ message: `Workflow API returned HTTP ${response.status}` }))
    if (!response.ok) throw new Error(body.message ?? `Workflow API returned HTTP ${response.status}`)
    return body as T
  }

  list() { return this.request<OfficeRequest[]>('/requests') }
  get(id: string) { return this.request<OfficeRequest>(`/requests/${encodeURIComponent(id)}`).catch((error) => { if (error instanceof Error && error.message.includes('not found')) return undefined; throw error }) }
  save(request: OfficeRequest) { return this.request<void>(`/requests/${encodeURIComponent(request.id)}`, { method: 'PUT', body: JSON.stringify(request) }) }
  remove(id: string) { return this.request<void>(`/requests/${encodeURIComponent(id)}`, { method: 'DELETE' }) }
  submit(id: string, actor: UserReference) { return this.command(id, 'submit', actor) }
  correct(id: string, actor: UserReference) { return this.command(id, 'correct', actor) }
  returnRequest(id: string, actor: UserReference, reason: string) { return this.command(id, 'return', { actor, reason }) }
  approve(id: string, actor: UserReference, payload: IntegrationPayload) { return this.command(id, 'approve', { actor, payload }) }
  retry(id: string, actor: UserReference) { return this.command(id, 'retry', actor) }
  resolveStatus(id: string, actor: UserReference) { return this.command(id, 'status', actor) }

  private command<T>(id: string, command: string, body: T) {
    return this.request<OfficeRequest>(`/requests/${encodeURIComponent(id)}/${command}`, { method: 'POST', body: JSON.stringify(body) })
  }
}
