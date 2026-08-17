import type { OperationName } from './officeRequest'

export interface IntegrationVariantPayload {
  SOURCE_VARIANT_REF: string
  SKU_SIZE: string
  SKU_WIDTH: string | null
  SKU_QTY: number
  SKU_ID: string | null
}

export interface IntegrationPayload {
  OPERATION_NAME: OperationName
  ACTION_REQUEST_ID: string
  SOURCE_SYSTEM: 'OFFICE_ORDERING'
  SOURCE_STYLE_REF: string
  SOURCE_ORDER_REF: string
  SOURCE_VERSION: string
  USER_ID: string
  DATE_TIME_STAMP: string
  STYLE: string | null
  ORDER_NO: string | null
  DEPARTMENT: number
  CLASS: number
  SUBCLASS: number
  COLOUR_GROUP: string
  COLOUR: string
  SIZE_GROUP: string
  WIDTH_GROUP: string | null
  PACK_IND: 'N'
  STYLE_DESC: string
  STYLE_SHORT_DESC: string
  SUPPLIER: number
  VPN: string
  ORIGIN_COUNTRY: string
  MANUFACTURE_CTRY: string
  CURRENCY_CODE: string
  COST_PRICE: number
  UNIT_COST: number
  NON_MERCH_COST: number
  UPDATE_COST_IND: 'Y'
  PACK_SIZE_CASE: number
  PACK_SIZE_INNER: number
  RSP: number
  RETAIL_PRICE: number
  UPDATE_RSP_IND: 'Y'
  SEASON: string
  PHASE: string
  PLMSizeCurveDtl: IntegrationVariantPayload[]
  PLMPacklotDtl: null
  PLMStyleUDADtl: unknown[]
  NOT_BEFORE_DATE: string
  NOT_AFTER_DATE: string
  OTB_EOW_DATE: string
  EARLIEST_SHIP_DATE: string
  LATEST_SHIP_DATE: string
  DELIVERY_LOC: number
  PO_TYPE: string
  ORDER_EXCHANGE_RATE: number
  VALLEY_PERIOD_IND: 'N'
  ON_HANGER: 'N'
  FIRST_PASS: 'N'
  TICKETS_REQUIRED: 'N'
  PDF_PO_STATUS: 'N'
  SPECIAL_INSTRUCTION: string | null
  DUTY_CODE: string
  DUTY_RATE: number
}
