export interface IntegrationError {
  FIELD?: string
  CODE?: string
  MESSAGE?: string
  field?: string
  code?: string
  message?: string
}

export interface GeneratedVariant {
  SOURCE_VARIANT_REF: string
  SKU_SIZE: string
  SKU_WIDTH?: string
  SKU_ID?: string | null
}

export interface IntegrationResponse {
  OPERATION_NAME?: string
  ACTION_REQUEST_ID?: string
  STATUS: string
  RETRYABLE?: boolean
  STYLE?: string | null
  ORDER_NO?: string | number | null
  PLMSizeCurveDtl?: GeneratedVariant[]
  COMPLETED_STEPS?: string[]
  FAILED_STEP?: string | null
  GENERATED_IDENTIFIERS?: Record<string, string | number | null>
  ERRORS?: IntegrationError[]
}

export interface ValidationResponse {
  valid: boolean
  errors: IntegrationError[]
  raw?: IntegrationResponse
}
