import type { OfficeRequest, OperationName, UserReference, VariantFormData } from './officeRequest'

const shortId = () => crypto.randomUUID().split('-')[0].toUpperCase()

export const makeVariant = (sourceStyleRef: string, size = '', width = 'STANDARD'): VariantFormData => ({
  id: crypto.randomUUID(),
  sourceVariantRef: `${sourceStyleRef}-${size || shortId()}`,
  size,
  width,
  quantity: 1,
  skuId: '',
})

export const createDefaultRequest = (user: UserReference, operationName: OperationName = 'CREATE_ALL'): OfficeRequest => {
  const id = crypto.randomUUID()
  const suffix = shortId()
  const sourceStyleRef = `OFF-STYLE-${suffix}`
  const now = new Date().toISOString()
  return {
    id,
    officeReference: `OFF-${suffix}`,
    operationName,
    sourceStyleRef,
    sourceOrderRef: `OFF-ORDER-${suffix}`,
    sourceVersion: 1,
    status: 'DRAFT',
    createdBy: user,
    createdAt: now,
    updatedAt: now,
    style: {
      existingStyle: '',
      description: 'Leather Lace Up Trainer',
      shortDescription: 'Leather Trainer',
      department: 100,
      classNumber: 10,
      subclass: 1,
      colourGroup: 'OFFICE_COLOUR',
      colour: 'BLACK',
      sizeGroup: 'SHOE_SIZE',
      widthGroup: 'WIDTH_STD',
      season: 'AW26',
      phase: '1',
    },
    sourcing: {
      supplier: 70001,
      vpn: `OFF-TRAINER-${suffix}`,
      originCountry: 'CN',
      manufacturingCountry: 'CN',
      currencyCode: 'USD',
      costPrice: 22.75,
      nonMerchCost: 1.2,
      rsp: 69.99,
      casePackSize: 1,
      innerPackSize: 1,
    },
    variants: [
      { ...makeVariant(sourceStyleRef, '7'), quantity: 120, sourceVariantRef: `${sourceStyleRef}-UK7` },
      { ...makeVariant(sourceStyleRef, '8'), quantity: 150, sourceVariantRef: `${sourceStyleRef}-UK8` },
    ],
    order: {
      existingOrderNo: '',
      deliveryLocation: 98,
      poType: '2',
      notBeforeDate: '2026-10-12',
      notAfterDate: '2026-10-18',
      otbEowDate: '2026-10-18',
      earliestShipDate: '2026-08-20',
      latestShipDate: '2026-08-30',
      exchangeRate: 1,
      specialInstructions: '',
      dutyCode: '6403.99.00',
      dutyRate: 0.08,
    },
    approvalHistory: [],
  }
}
