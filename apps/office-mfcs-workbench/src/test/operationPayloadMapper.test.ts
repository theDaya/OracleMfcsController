import { describe, expect, it } from 'vitest'
import { createDefaultRequest } from '../models/defaults'
import type { OperationName, UserReference } from '../models/officeRequest'
import { mapRequestToPayload } from '../mapping/integrationPayloadMapper'

const buyer: UserReference = { id: 'jane.buyer@office.example', name: 'Jane Buyer', role: 'BUYER' }
const manager: UserReference = { id: 'michael.manager@office.example', name: 'Michael Manager', role: 'MANAGER' }

const payloadFor = (operation: OperationName) => {
  const request = createDefaultRequest(buyer, operation)
  request.actionRequestId = 'fixed-action-id'
  request.style.existingStyle = '3500001'
  request.order.existingOrderNo = '10740001'
  request.variants.forEach((variant, index) => { variant.skuId = `1030000${index + 1}` })
  return mapRequestToPayload(request, manager, new Date('2026-08-17T00:00:00Z'))
}

describe('five-operation payload mapper', () => {
  it.each([
    ['CREATE_ALL', null, null, null],
    ['CREATE_STYLE', null, null, null],
    ['CREATE_ORDER', '3500001', null, '10300001'],
    ['MODIFY_STYLE', '3500001', null, '10300001'],
    ['MODIFY_ORDER', '3500001', '10740001', '10300001'],
  ] as const)('maps %s identifier semantics', (operation, style, order, sku) => {
    const payload = payloadFor(operation)
    expect(payload.STYLE).toBe(style)
    expect(payload.ORDER_NO).toBe(order)
    expect(payload.PLMSizeCurveDtl[0].SKU_ID).toBe(sku)
    expect(payload.ACTION_REQUEST_ID).toBe('fixed-action-id')
    expect(payload.CURRENCY_CODE).toBe('USD')
  })
})
