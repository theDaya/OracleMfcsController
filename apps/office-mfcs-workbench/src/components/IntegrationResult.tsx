import { AlertTriangle, CheckCircle2, RefreshCw, Search, XCircle } from 'lucide-react'
import type { OfficeRequest } from '../models/officeRequest'

export function IntegrationResult({ request, onRetry, onRefresh, busy = false }: { request: OfficeRequest; onRetry?: () => void; onRefresh?: () => void; busy?: boolean }) {
  const response = request.integrationResponse
  if (!response) return null
  const success = request.status === 'POSTED'
  const manual = request.status === 'MANUAL_REVIEW'
  const partial = request.status === 'PARTIALLY_COMPLETED'
  const Icon = success ? CheckCircle2 : manual || partial ? AlertTriangle : XCircle
  return (
    <section className={`integration-result ${success ? 'result-success' : manual || partial ? 'result-warning' : 'result-error'}`}>
      <div className="result-heading"><Icon size={22} /><div><h2>{success ? 'MFCS posting completed' : manual ? 'Outcome requires resolution' : partial ? 'MFCS posting partially completed' : 'MFCS posting failed'}</h2><p>{success ? 'Generated identifiers are stored with this request.' : manual ? 'The request may have reached MFCS. Check status before taking any further action.' : partial ? 'Completed steps will be preserved. Retry with the same action request ID.' : 'Review the errors below before retrying or correcting the request.'}</p></div></div>
      <div className="identifier-grid"><div><span>MFCS style</span><strong>{(response.STYLE ?? request.style.existingStyle) || '—'}</strong></div><div><span>MFCS order</span><strong>{(response.ORDER_NO ?? request.order.existingOrderNo) || '—'}</strong></div><div><span>Action request ID</span><strong className="small-mono">{request.actionRequestId}</strong></div></div>
      {!!response.PLMSizeCurveDtl?.length && <div className="result-skus">{response.PLMSizeCurveDtl.map((variant) => <span key={variant.SOURCE_VARIANT_REF}>{variant.SKU_SIZE}{variant.SKU_WIDTH ? ` / ${variant.SKU_WIDTH}` : ''}<b>{variant.SKU_ID ?? 'Pending'}</b></span>)}</div>}
      {!!response.COMPLETED_STEPS?.length && <div className="completed-steps"><span>Completed steps</span><div>{response.COMPLETED_STEPS.map((step) => <code key={step}>{step}</code>)}</div></div>}
      {response.FAILED_STEP && <p className="failed-step"><b>Failed step:</b> {response.FAILED_STEP}</p>}
      {!!response.ERRORS?.length && <ul className="error-list">{response.ERRORS.map((error, index) => <li key={`${error.CODE ?? error.code}-${index}`}><b>{error.CODE ?? error.code ?? 'ERROR'}</b> {error.MESSAGE ?? error.message}</li>)}</ul>}
      {(response.RETRYABLE || manual) && <div className="result-actions">{response.RETRYABLE && onRetry && <button className="primary-button" onClick={onRetry} disabled={busy}><RefreshCw size={16} className={busy ? 'spin' : ''} /> Retry same request</button>}{manual && onRefresh && <button className="secondary-button" onClick={onRefresh} disabled={busy}><Search size={16} /> Resolve status</button>}</div>}
    </section>
  )
}
