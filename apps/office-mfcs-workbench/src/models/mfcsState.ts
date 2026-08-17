export type MfcsLookupType = 'ORDER' | 'STYLE' | 'SKU'

export interface MfcsStyleState {
  item: string
  description: string
  shortDescription: string | null
  department: number
  classNumber: number
  subclass: number
  status: string
  approved: string
  originalRetail: number | null
  approvedBy: string | null
  approvedAt: string | null
}

export interface MfcsItemState {
  item: string
  itemParent: string | null
  itemGrandparent: string | null
  itemLevel: number
  transactionLevel: number
  description: string
  status: string
  approved: string
  standardUom: string
  diff1: string | null
  diff2: string | null
  diff3: string | null
  diff4: string | null
  originalRetail: number | null
}

export interface MfcsSourcingState {
  item: string
  supplier: number
  supplierName: string
  primarySupplier: string
  vpn: string | null
  originCountry: string | null
  primaryCountry: string | null
  unitCost: number | null
  currencyCode: string | null
  leadTime: number | null
  pickupLeadTime: number | null
  defaultUop: string | null
  supplierPackSize: number | null
}

export interface MfcsLocationState {
  item: string
  location: number
  locationType: string
  locationName: string | null
  status: string
  primarySupplier: number | null
  sourceMethod: string
  unitRetail: number | null
}

export interface MfcsUdaState {
  item: string
  udaId: number
  value: string
}

export interface MfcsOrderLineState {
  item: string
  description: string
  diff1: string | null
  diff2: string | null
  diff3: string | null
  location: number
  locationType: string
  originCountry: string
  quantityOrdered: number
  quantityReceived: number
  quantityCancelled: number
  unitCost: number
  unitRetail: number | null
  earliestShipDate: string | null
  latestShipDate: string | null
}

export interface MfcsOrderState {
  orderNo: number
  orderType: string
  supplier: number
  department: number
  status: string
  currencyCode: string
  exchangeRate: number
  notBeforeDate: string | null
  notAfterDate: string | null
  earliestShipDate: string | null
  latestShipDate: string | null
  totalQuantity: number
  totalCost: number
  sourceSystem: string
  approvedBy: string | null
  approvedAt: string | null
  lines: MfcsOrderLineState[]
}

export interface MfcsRestEventState {
  eventId: number
  correlationId: string
  serviceName: string
  httpMethod: string
  responseCode: number
  startedAt: string
  completedAt: string
}

export interface MfcsStateResult {
  query: string
  foundBy: MfcsLookupType
  styles: MfcsStyleState[]
  items: MfcsItemState[]
  sourcing: MfcsSourcingState[]
  locations: MfcsLocationState[]
  udas: MfcsUdaState[]
  orders: MfcsOrderState[]
  events: MfcsRestEventState[]
}

export const mfcsStatusLabel = (status: string) => ({
  W: 'Worksheet',
  S: 'Submitted',
  A: 'Approved',
  I: 'Inactive',
  D: 'Deleted',
  C: 'Closed',
}[status] ?? status)

export const mfcsStatusClass = (status: string) => status === 'A'
  ? 'status-posted'
  : status === 'W' || status === 'S'
    ? 'status-submitted'
    : status === 'I' || status === 'C'
      ? 'status-returned'
      : 'status-draft'
