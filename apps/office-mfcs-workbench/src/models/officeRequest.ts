import type { IntegrationPayload } from './integrationPayload'
import type { IntegrationResponse } from './integrationResponse'
import type { ApprovalHistoryEntry, WorkflowStatus } from '../workflow/workflowTypes'

export type OperationName =
  | 'CREATE_ALL'
  | 'CREATE_STYLE'
  | 'CREATE_ORDER'
  | 'MODIFY_STYLE'
  | 'MODIFY_ORDER'

export type UserRole = 'BUYER' | 'MANAGER'

export interface UserReference {
  id: string
  name: string
  role: UserRole
}

export interface StyleFormData {
  existingStyle: string
  description: string
  shortDescription: string
  department: number
  classNumber: number
  subclass: number
  colourGroup: string
  colour: string
  sizeGroup: string
  widthGroup: string
  season: string
  phase: string
}

export interface SourcingFormData {
  supplier: number
  vpn: string
  originCountry: string
  manufacturingCountry: string
  currencyCode: string
  costPrice: number
  nonMerchCost: number
  rsp: number
  casePackSize: number
  innerPackSize: number
}

export interface VariantFormData {
  id: string
  sourceVariantRef: string
  size: string
  width: string
  quantity: number
  skuId: string
}

export interface OrderFormData {
  existingOrderNo: string
  deliveryLocation: number
  poType: string
  notBeforeDate: string
  notAfterDate: string
  otbEowDate: string
  earliestShipDate: string
  latestShipDate: string
  exchangeRate: number
  specialInstructions: string
  dutyCode: string
  dutyRate: number
}

export interface OfficeRequest {
  id: string
  officeReference: string
  operationName: OperationName
  sourceStyleRef: string
  sourceOrderRef: string
  sourceVersion: number
  actionRequestId?: string
  status: WorkflowStatus
  createdBy: UserReference
  submittedBy?: UserReference
  approvedBy?: UserReference
  createdAt: string
  updatedAt: string
  submittedAt?: string
  approvedAt?: string
  style: StyleFormData
  sourcing: SourcingFormData
  variants: VariantFormData[]
  order: OrderFormData
  approvalHistory: ApprovalHistoryEntry[]
  integrationPayload?: IntegrationPayload
  integrationResponse?: IntegrationResponse
}

export const operationLabels: Record<OperationName, string> = {
  CREATE_ALL: 'Create style + order',
  CREATE_STYLE: 'Create style only',
  CREATE_ORDER: 'Create order only',
  MODIFY_STYLE: 'Modify style',
  MODIFY_ORDER: 'Modify order',
}

export const operationNeedsExistingStyle = (operation: OperationName) =>
  operation === 'CREATE_ORDER' || operation === 'MODIFY_STYLE' || operation === 'MODIFY_ORDER'

export const operationNeedsExistingSkus = operationNeedsExistingStyle

export const operationNeedsExistingOrder = (operation: OperationName) => operation === 'MODIFY_ORDER'

export const operationCreatesOrder = (operation: OperationName) =>
  operation === 'CREATE_ALL' || operation === 'CREATE_ORDER'

export const operationTouchesOrder = (operation: OperationName) =>
  operation === 'CREATE_ALL' || operation === 'CREATE_ORDER' || operation === 'MODIFY_ORDER'
