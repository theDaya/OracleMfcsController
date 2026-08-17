import { Boxes, Database, MapPin, PackageSearch, Search, ServerCog, ShoppingCart, Truck } from 'lucide-react'
import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { useSearchParams } from 'react-router-dom'
import { MfcsStateClient } from '../api/MfcsStateClient'
import { mfcsStatusClass, mfcsStatusLabel, type MfcsStateResult } from '../models/mfcsState'

type StateTab = 'overview' | 'items' | 'sourcing' | 'orders' | 'locations' | 'events'

const tabs: Array<{ id: StateTab; label: string }> = [
  { id: 'overview', label: 'Overview' },
  { id: 'items', label: 'Items' },
  { id: 'sourcing', label: 'Sourcing' },
  { id: 'orders', label: 'Orders' },
  { id: 'locations', label: 'Locations' },
  { id: 'events', label: 'REST history' },
]

const formatNumber = (value: number) => new Intl.NumberFormat('en-ZA').format(value)
const formatMoney = (value: number | null, currency = 'USD') => value === null
  ? '-'
  : new Intl.NumberFormat('en-ZA', { style: 'currency', currency }).format(value)
const formatTime = (value: string | null) => value
  ? new Intl.DateTimeFormat('en-ZA', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  : '-'
const status = (value: string) => <span className={`status-badge ${mfcsStatusClass(value)}`}>{mfcsStatusLabel(value)}</span>

function EmptyTable({ text }: { text: string }) {
  return <div className="state-empty-row">{text}</div>
}

function Overview({ state }: { state: MfcsStateResult }) {
  return (
    <div className="state-view-grid">
      <section className="state-block">
        <div className="state-block-heading"><Boxes size={18} /><h2>Style summary</h2></div>
        {state.styles.map((style) => <div className="state-record" key={style.item}>
          <div className="state-record-title"><div><span>Style</span><strong>{style.item}</strong></div>{status(style.status)}</div>
          <h3>{style.description}</h3>
          <dl className="state-definition-grid">
            <div><dt>Hierarchy</dt><dd>{style.department} / {style.classNumber} / {style.subclass}</dd></div>
            <div><dt>Approval</dt><dd>{style.approved === 'Y' ? 'Approved' : 'Not approved'}</dd></div>
            <div><dt>Original retail</dt><dd>{formatMoney(style.originalRetail)}</dd></div>
            <div><dt>Approved by</dt><dd>{style.approvedBy ?? '-'}</dd></div>
            <div><dt>Approved at</dt><dd>{formatTime(style.approvedAt)}</dd></div>
          </dl>
        </div>)}
      </section>
      <section className="state-block">
        <div className="state-block-heading"><ShoppingCart size={18} /><h2>Order summary</h2></div>
        {state.orders.length === 0 ? <EmptyTable text="No related purchase orders." /> : state.orders.map((order) => <div className="state-record" key={order.orderNo}>
          <div className="state-record-title"><div><span>Order</span><strong>{order.orderNo}</strong></div>{status(order.status)}</div>
          <dl className="state-definition-grid">
            <div><dt>Supplier</dt><dd>{order.supplier}</dd></div>
            <div><dt>Quantity</dt><dd>{formatNumber(order.totalQuantity)}</dd></div>
            <div><dt>Total cost</dt><dd>{formatMoney(order.totalCost, order.currencyCode)}</dd></div>
            <div><dt>Delivery window</dt><dd>{order.notBeforeDate ?? '-'} to {order.notAfterDate ?? '-'}</dd></div>
            <div><dt>Source</dt><dd>{order.sourceSystem}</dd></div>
          </dl>
        </div>)}
      </section>
      <section className="state-block state-block-wide">
        <div className="state-block-heading"><Database size={18} /><h2>RMS footprint</h2></div>
        <div className="footprint-grid">
          <div><strong>{state.items.length}</strong><span>ITEM_MASTER</span></div>
          <div><strong>{state.sourcing.length}</strong><span>ITEM_SUPPLIER / COUNTRY</span></div>
          <div><strong>{state.locations.length}</strong><span>ITEM_LOC</span></div>
          <div><strong>{state.orders.length}</strong><span>ORDHEAD</span></div>
          <div><strong>{state.orders.reduce((sum, order) => sum + order.lines.length, 0)}</strong><span>ORDLOC</span></div>
          <div><strong>{state.udas.length}</strong><span>ITEM_UDA</span></div>
        </div>
      </section>
    </div>
  )
}

function Items({ state }: { state: MfcsStateResult }) {
  return <div className="table-wrap"><table className="state-table"><thead><tr><th>Item</th><th>Level</th><th>Parent</th><th>Description</th><th>Differentiators</th><th>Retail</th><th>Status</th></tr></thead><tbody>{state.items.map((item) => <tr key={item.item}><td><strong>{item.item}</strong></td><td>{item.itemLevel} / {item.transactionLevel}</td><td>{item.itemParent ?? '-'}</td><td>{item.description}</td><td><span className="diff-stack">{[item.diff1, item.diff2, item.diff3, item.diff4].filter(Boolean).map((diff) => <code key={diff}>{diff}</code>)}</span></td><td>{formatMoney(item.originalRetail)}</td><td>{status(item.status)}</td></tr>)}</tbody></table></div>
}

function Sourcing({ state }: { state: MfcsStateResult }) {
  if (state.sourcing.length === 0) return <EmptyTable text="No sourcing rows." />
  return <div className="table-wrap"><table className="state-table"><thead><tr><th>Item</th><th>Supplier</th><th>VPN</th><th>Origin</th><th>Unit cost</th><th>Lead time</th><th>Pack</th><th>Primary</th></tr></thead><tbody>{state.sourcing.map((row, index) => <tr key={`${row.item}-${row.supplier}-${row.originCountry}-${index}`}><td><strong>{row.item}</strong></td><td>{row.supplier}<span className="subline">{row.supplierName}</span></td><td>{row.vpn ?? '-'}</td><td>{row.originCountry ?? '-'}</td><td>{formatMoney(row.unitCost, row.currencyCode ?? 'USD')}</td><td>{row.leadTime ?? '-'} days</td><td>{row.supplierPackSize ?? '-'}</td><td>{row.primarySupplier === 'Y' ? 'Yes' : 'No'}</td></tr>)}</tbody></table></div>
}

function Orders({ state }: { state: MfcsStateResult }) {
  if (state.orders.length === 0) return <EmptyTable text="No related purchase orders." />
  return <div className="order-state-list">{state.orders.map((order) => <section className="order-state" key={order.orderNo}>
    <div className="order-state-header"><div><span>Purchase order</span><h2>{order.orderNo}</h2></div>{status(order.status)}<dl><div><dt>Supplier</dt><dd>{order.supplier}</dd></div><div><dt>Quantity</dt><dd>{formatNumber(order.totalQuantity)}</dd></div><div><dt>Total</dt><dd>{formatMoney(order.totalCost, order.currencyCode)}</dd></div><div><dt>Ship window</dt><dd>{order.earliestShipDate ?? '-'} to {order.latestShipDate ?? '-'}</dd></div></dl></div>
    <div className="table-wrap"><table className="state-table"><thead><tr><th>Item</th><th>Description</th><th>Location</th><th>Origin</th><th>Ordered</th><th>Received</th><th>Cancelled</th><th>Unit cost</th><th>Retail</th></tr></thead><tbody>{order.lines.map((line) => <tr key={`${line.item}-${line.location}`}><td><strong>{line.item}</strong><span className="subline">{[line.diff1, line.diff2, line.diff3].filter(Boolean).join(' / ')}</span></td><td>{line.description}</td><td>{line.location} / {line.locationType}</td><td>{line.originCountry}</td><td>{formatNumber(line.quantityOrdered)}</td><td>{formatNumber(line.quantityReceived)}</td><td>{formatNumber(line.quantityCancelled)}</td><td>{formatMoney(line.unitCost, order.currencyCode)}</td><td>{formatMoney(line.unitRetail, order.currencyCode)}</td></tr>)}</tbody></table></div>
  </section>)}</div>
}

function Locations({ state }: { state: MfcsStateResult }) {
  if (state.locations.length === 0) return <EmptyTable text="No item-location rows." />
  return <div className="table-wrap"><table className="state-table"><thead><tr><th>Item</th><th>Location</th><th>Type</th><th>Retail</th><th>Primary supplier</th><th>Source</th><th>Status</th></tr></thead><tbody>{state.locations.map((row) => <tr key={`${row.item}-${row.location}-${row.locationType}`}><td><strong>{row.item}</strong></td><td>{row.location}<span className="subline">{row.locationName ?? '-'}</span></td><td>{row.locationType === 'S' ? 'Store' : 'Warehouse'}</td><td>{formatMoney(row.unitRetail)}</td><td>{row.primarySupplier ?? '-'}</td><td>{row.sourceMethod}</td><td>{status(row.status)}</td></tr>)}</tbody></table></div>
}

function Events({ state }: { state: MfcsStateResult }) {
  if (state.events.length === 0) return <EmptyTable text="No matching REST journal events." />
  return <div className="table-wrap"><table className="state-table"><thead><tr><th>Event</th><th>Service</th><th>Method</th><th>HTTP</th><th>Correlation ID</th><th>Completed</th></tr></thead><tbody>{state.events.map((event) => <tr key={event.eventId}><td>{event.eventId}</td><td><strong>{event.serviceName}</strong></td><td><code>{event.httpMethod}</code></td><td>{event.responseCode}</td><td className="mono-cell">{event.correlationId}</td><td>{formatTime(event.completedAt)}</td></tr>)}</tbody></table></div>
}

export function MfcsStateViewerPage() {
  const client = useMemo(() => new MfcsStateClient(), [])
  const [searchParams, setSearchParams] = useSearchParams()
  const routeQuery = searchParams.get('q') ?? ''
  const [query, setQuery] = useState(routeQuery)
  const [state, setState] = useState<MfcsStateResult>()
  const [activeTab, setActiveTab] = useState<StateTab>('overview')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string>()

  useEffect(() => {
    if (!routeQuery) { setState(undefined); setError(undefined); return }
    let current = true
    setLoading(true)
    setError(undefined)
    void client.lookup(routeQuery).then((result) => {
      if (current) { setState(result); setActiveTab('overview') }
    }).catch((reason) => {
      if (current) { setState(undefined); setError(reason instanceof Error ? reason.message : 'Lookup failed.') }
    }).finally(() => { if (current) setLoading(false) })
    return () => { current = false }
  }, [client, routeQuery])

  const submit = (event: FormEvent) => {
    event.preventDefault()
    const normalized = query.trim()
    if (!normalized) { setError('Enter an order or style number.'); return }
    setSearchParams({ q: normalized })
  }

  return <div className="page-stack state-page">
    <div className="page-header compact"><div><span className="page-eyebrow">Local MFCS</span><h1>State viewer</h1><p>Oracle RMS simulator</p></div><span className="read-only-indicator"><ServerCog size={16} /> Read only</span></div>
    <form className="state-search" onSubmit={submit} role="search">
      <label htmlFor="mfcs-state-query">Order or style number</label>
      <div><PackageSearch size={20} /><input id="mfcs-state-query" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="10700008 or 3000024" inputMode="numeric" autoComplete="off" /><button className="primary-button" type="submit" disabled={loading}><Search size={16} /> {loading ? 'Searching' : 'Search'}</button></div>
    </form>
    {error && <div className="message-bar message-error">{error}</div>}
    {!routeQuery && !state && <div className="state-waiting"><PackageSearch size={34} /><h2>No record selected</h2></div>}
    {loading && <div className="state-waiting"><span className="state-loader" /><h2>Reading Oracle state</h2></div>}
    {state && !loading && <>
      <section className="state-identity">
        <div><span>{state.foundBy}</span><h2>{state.styles[0]?.description ?? `Order ${state.query}`}</h2><p>Lookup {state.query}</p></div>
        <div className="state-metrics"><div><Boxes size={17} /><strong>{state.styles.length}</strong><span>Styles</span></div><div><PackageSearch size={17} /><strong>{Math.max(state.items.length - state.styles.length, 0)}</strong><span>SKUs</span></div><div><ShoppingCart size={17} /><strong>{state.orders.length}</strong><span>Orders</span></div><div><MapPin size={17} /><strong>{state.locations.length}</strong><span>Locations</span></div></div>
      </section>
      <div className="state-tabs" role="tablist" aria-label="MFCS state views">{tabs.map((tab) => <button key={tab.id} role="tab" type="button" aria-selected={activeTab === tab.id} className={activeTab === tab.id ? 'active' : ''} onClick={() => setActiveTab(tab.id)}>{tab.label}</button>)}</div>
      <section className="state-tab-panel" role="tabpanel">
        {activeTab === 'overview' && <Overview state={state} />}
        {activeTab === 'items' && <Items state={state} />}
        {activeTab === 'sourcing' && <Sourcing state={state} />}
        {activeTab === 'orders' && <Orders state={state} />}
        {activeTab === 'locations' && <Locations state={state} />}
        {activeTab === 'events' && <Events state={state} />}
      </section>
    </>}
  </div>
}
