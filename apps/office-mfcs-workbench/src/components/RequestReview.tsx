import { Code2 } from 'lucide-react'
import { operationLabels, operationTouchesOrder, type OfficeRequest } from '../models/officeRequest'
import type { IntegrationPayload } from '../models/integrationPayload'

const DataItem = ({ label, value }: { label: string; value: string | number | null | undefined }) => (
  <div className="data-item"><span>{label}</span><strong>{value === null || value === undefined || value === '' ? 'Not set' : value}</strong></div>
)

export function RequestReview({ request, payload }: { request: OfficeRequest; payload?: IntegrationPayload }) {
  const totalQuantity = request.variants.reduce((sum, variant) => sum + (Number(variant.quantity) || 0), 0)
  const totalCost = totalQuantity * (Number(request.sourcing.costPrice) || 0)
  return (
    <section className="review-shell">
      <div className="review-title"><div><span className="step-kicker">Review</span><h2>{request.style.description || 'Untitled style'}</h2></div><span className="operation-tag">{operationLabels[request.operationName]}</span></div>
      <div className="review-band">
        <h3>Style</h3>
        <div className="data-grid"><DataItem label="Existing style" value={request.style.existingStyle} /><DataItem label="Hierarchy" value={`${request.style.department} / ${request.style.classNumber} / ${request.style.subclass}`} /><DataItem label="Colour" value={`${request.style.colourGroup} / ${request.style.colour}`} /><DataItem label="Season / phase" value={`${request.style.season} / ${request.style.phase}`} /><DataItem label="Size group" value={request.style.sizeGroup} /><DataItem label="Width group" value={request.style.widthGroup} /></div>
      </div>
      <div className="review-band">
        <h3>Sourcing and cost</h3>
        <div className="data-grid"><DataItem label="Supplier" value={request.sourcing.supplier} /><DataItem label="VPN" value={request.sourcing.vpn} /><DataItem label="Origin" value={request.sourcing.originCountry} /><DataItem label="Manufacturing" value={request.sourcing.manufacturingCountry} /><DataItem label="Unit cost" value={`${request.sourcing.currencyCode || 'USD'} ${request.sourcing.costPrice.toFixed(2)}`} /><DataItem label="RSP" value={`${request.sourcing.currencyCode || 'USD'} ${request.sourcing.rsp.toFixed(2)}`} /></div>
      </div>
      <div className="review-band">
        <div className="band-heading"><h3>Variants and quantities</h3><span>{request.variants.length} SKUs · {totalQuantity.toLocaleString()} units · ${totalCost.toLocaleString(undefined, { minimumFractionDigits: 2 })}</span></div>
        <div className="table-wrap"><table><thead><tr><th>Size</th><th>Width</th><th>Quantity</th><th>MFCS SKU</th><th>Source reference</th></tr></thead><tbody>{request.variants.map((variant) => <tr key={variant.id}><td>{variant.size}</td><td>{variant.width || 'None'}</td><td>{variant.quantity.toLocaleString()}</td><td>{variant.skuId || 'Generated on create'}</td><td className="mono-cell">{variant.sourceVariantRef}</td></tr>)}</tbody></table></div>
      </div>
      {operationTouchesOrder(request.operationName) && (
        <div className="review-band">
          <h3>Order and delivery</h3>
          <div className="data-grid"><DataItem label="Existing order" value={request.order.existingOrderNo} /><DataItem label="Delivery location" value={request.order.deliveryLocation} /><DataItem label="PO type" value={request.order.poType} /><DataItem label="Not-before / after" value={`${request.order.notBeforeDate} / ${request.order.notAfterDate}`} /><DataItem label="Ship window" value={`${request.order.earliestShipDate} / ${request.order.latestShipDate}`} /><DataItem label="Exchange rate" value={request.order.exchangeRate} /></div>
        </div>
      )}
      {payload && (
        <details className="technical-details"><summary><Code2 size={17} /> View API payload</summary><pre>{JSON.stringify(payload, null, 2)}</pre></details>
      )}
    </section>
  )
}
