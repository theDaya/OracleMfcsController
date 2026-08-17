import { afterEach, describe, expect, it, vi } from 'vitest'
import { MfcsStateClient } from '../api/MfcsStateClient'

const state = {
  query: '3000024',
  foundBy: 'STYLE',
  styles: [],
  items: [],
  sourcing: [],
  locations: [],
  udas: [],
  orders: [],
  events: [],
}

describe('MfcsStateClient', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('loads state by an encoded identifier', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify(state), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }))
    vi.stubGlobal('fetch', fetchMock)

    await expect(new MfcsStateClient('/workflow-api').lookup(' 3000024 ')).resolves.toEqual(state)
    expect(fetchMock).toHaveBeenCalledWith('/workflow-api/state/3000024', { headers: { Accept: 'application/json' } })
  })

  it('surfaces the Oracle not-found message', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({ message: 'No MFCS record.' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    })))

    await expect(new MfcsStateClient('/workflow-api').lookup('99999999')).rejects.toThrow('No MFCS record.')
  })

  it('rejects a blank lookup before calling the API', async () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    await expect(new MfcsStateClient('/workflow-api').lookup('   ')).rejects.toThrow('Enter an order or style number.')
    expect(fetchMock).not.toHaveBeenCalled()
  })
})
