import { z } from 'zod'
import {
  operationNeedsExistingOrder,
  operationNeedsExistingSkus,
  operationNeedsExistingStyle,
  operationTouchesOrder,
  type OfficeRequest,
} from '../models/officeRequest'

const requiredText = z.string().trim().min(1, 'Required')
const positiveNumber = z.number().positive('Must be greater than zero')

export const officeRequestSchema = z.object({
  operationName: z.enum(['CREATE_ALL', 'CREATE_STYLE', 'CREATE_ORDER', 'MODIFY_STYLE', 'MODIFY_ORDER']),
  style: z.object({
    existingStyle: z.string(),
    description: requiredText,
    shortDescription: requiredText,
    department: z.number().int().positive(),
    classNumber: z.number().int().positive(),
    subclass: z.number().int().positive(),
    colourGroup: requiredText,
    colour: requiredText,
    sizeGroup: requiredText,
    widthGroup: z.string(),
    season: requiredText,
    phase: requiredText,
  }),
  sourcing: z.object({
    supplier: z.number().int().positive(),
    vpn: requiredText,
    originCountry: requiredText,
    manufacturingCountry: requiredText,
    currencyCode: z.string().trim().length(3, 'Use a three-letter currency code'),
    costPrice: z.number().nonnegative(),
    nonMerchCost: z.number().nonnegative(),
    rsp: positiveNumber,
    casePackSize: z.number().int().positive(),
    innerPackSize: z.number().int().positive(),
  }),
  variants: z.array(z.object({
    id: requiredText,
    sourceVariantRef: requiredText,
    size: requiredText,
    width: z.string(),
    quantity: z.number().int().positive('Quantity must be a positive whole number'),
    skuId: z.string(),
  })).min(1, 'At least one variant is required'),
  order: z.object({
    existingOrderNo: z.string(),
    deliveryLocation: z.number().int().positive(),
    poType: requiredText,
    notBeforeDate: z.string(),
    notAfterDate: z.string(),
    otbEowDate: z.string(),
    earliestShipDate: z.string(),
    latestShipDate: z.string(),
    exchangeRate: positiveNumber,
    specialInstructions: z.string(),
    dutyCode: z.string(),
    dutyRate: z.number().nonnegative(),
  }),
}).passthrough().superRefine((request, context) => {
  if (operationNeedsExistingStyle(request.operationName) && !request.style.existingStyle.trim()) {
    context.addIssue({ code: 'custom', path: ['style', 'existingStyle'], message: 'Existing MFCS style is required for this operation' })
  }
  if (operationNeedsExistingOrder(request.operationName) && !request.order.existingOrderNo.trim()) {
    context.addIssue({ code: 'custom', path: ['order', 'existingOrderNo'], message: 'Existing MFCS order is required for MODIFY_ORDER' })
  }
  if (operationNeedsExistingSkus(request.operationName)) {
    request.variants.forEach((variant, index) => {
      if (!variant.skuId.trim()) context.addIssue({ code: 'custom', path: ['variants', index, 'skuId'], message: 'Existing SKU is required' })
    })
  }
  const combinations = new Set<string>()
  request.variants.forEach((variant, index) => {
    const key = `${variant.size.trim().toUpperCase()}|${variant.width.trim().toUpperCase()}`
    if (combinations.has(key)) context.addIssue({ code: 'custom', path: ['variants', index, 'size'], message: 'Size/width combination must be unique' })
    combinations.add(key)
    if (request.style.widthGroup && !variant.width.trim()) context.addIssue({ code: 'custom', path: ['variants', index, 'width'], message: 'Width is required when a width group is selected' })
  })
  if (operationTouchesOrder(request.operationName)) {
    const requiredDates = ['notBeforeDate', 'notAfterDate', 'earliestShipDate', 'latestShipDate'] as const
    requiredDates.forEach((field) => {
      if (!request.order[field]) context.addIssue({ code: 'custom', path: ['order', field], message: 'Required for order operations' })
    })
    if (request.order.notBeforeDate > request.order.notAfterDate) context.addIssue({ code: 'custom', path: ['order', 'notAfterDate'], message: 'Must be on or after the not-before date' })
    if (request.order.earliestShipDate > request.order.latestShipDate) context.addIssue({ code: 'custom', path: ['order', 'latestShipDate'], message: 'Must be on or after the earliest ship date' })
  }
})

export const validateOfficeRequest = (request: OfficeRequest) => officeRequestSchema.safeParse(request)
