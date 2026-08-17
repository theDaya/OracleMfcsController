import type { MfcsStateResult } from '../models/mfcsState'

export class MfcsStateClient {
  constructor(private readonly baseUrl = import.meta.env.VITE_WORKFLOW_API_BASE_URL ?? '/workflow-api') {}

  async lookup(identifier: string): Promise<MfcsStateResult> {
    const normalized = identifier.trim()
    if (!normalized) throw new Error('Enter an order or style number.')
    const response = await fetch(`${this.baseUrl}/state/${encodeURIComponent(normalized)}`, {
      headers: { Accept: 'application/json' },
    })
    const body = await response.json().catch(() => ({ message: `State API returned HTTP ${response.status}` }))
    if (!response.ok) throw new Error(body.message ?? `State API returned HTTP ${response.status}`)
    return body as MfcsStateResult
  }
}
