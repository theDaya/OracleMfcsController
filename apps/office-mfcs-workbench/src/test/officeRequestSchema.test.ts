import { describe, expect, it } from 'vitest'
import { createDefaultRequest } from '../models/defaults'
import { officeRequestSchema } from '../validation/officeRequestSchema'

describe('officeRequestSchema', () => {
  it('preserves workflow metadata needed after form validation', () => {
    const request = createDefaultRequest({ id: 'buyer-1', name: 'Buyer One', role: 'BUYER' })

    const parsed = officeRequestSchema.parse(request)

    expect(parsed.id).toBe(request.id)
    expect(parsed.officeReference).toBe(request.officeReference)
    expect(parsed.createdBy).toEqual(request.createdBy)
    expect(parsed.sourceVersion).toBe(1)
  })
})
