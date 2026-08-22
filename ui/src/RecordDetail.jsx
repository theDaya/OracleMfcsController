import { useState } from 'react';
import JsonBlock from './JsonBlock';

/** Flat field grid, four per row. */
function Fields({ fields }) {
  const shown = fields.filter(([, v]) => v !== undefined);
  return (
    <div className="fieldgrid">
      {shown.map(([label, value]) => (
        <div key={label} className="fg-cell">
          <span className="fg-label">{label}</span>
          <span className={`fg-value ${value === null || value === '' ? 'empty' : ''}`}>
            {value === null || value === '' ? '—' : String(value)}
          </span>
        </div>
      ))}
    </div>
  );
}

function Section({ title, subtitle, children, defaultOpen = true }) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <section className="rd-section">
      <button type="button" className="rd-head" onClick={() => setOpen(!open)}>
        <span className="rd-title">{title}</span>
        {subtitle && <span className="muted small">{subtitle}</span>}
        <span className="chev">{open ? '−' : '+'}</span>
      </button>
      {open && <div className="rd-body">{children}</div>}
    </section>
  );
}

function Grid({ columns, rows, empty }) {
  if (!rows || rows.length === 0) return <p className="muted small">{empty}</p>;
  return (
    <div className="grid-scroll">
      <table className="rows">
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.key}>{c.label}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i} className="norow">
              {columns.map((c) => (
                <td key={c.key} className={c.mono ? 'mono' : ''}>
                  {r[c.key] === null || r[c.key] === undefined || r[c.key] === '' ? (
                    <span className="muted">—</span>
                  ) : (
                    String(r[c.key])
                  )}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

const orderFields = (o) => [
  ['Order no', o.orderNo],
  ['Status', o.status],
  ['Order type', o.orderType],
  ['Doc type', o.docType],
  ['Supplier', o.supplier],
  ['Dept', o.dept],
  ['Dept name', o.deptName],
  ['Currency', o.currencyCode],
  ['Terms', o.terms],
  ['Terms code', o.termsCode],
  ['Freight terms', o.freightTerms],
  ['Exchange rate', o.exchangeRate],
  ['Not before', o.notBeforeDate],
  ['Not after', o.notAfterDate],
  ['OTB EOW', o.otbEowDate],
  ['Close date', o.closeDate],
  ['Earliest ship', o.earliestShipDate],
  ['Latest ship', o.latestShipDate],
  ['Written date', o.writtenDate],
  ['Import country', o.importCountry],
  ['Physical loc', o.physicalLocation],
  ['Virtual WH', o.virtualWarehouse],
  ['Loc type', o.physicalLocationType],
  ['QC indicator', o.qualityControlInd],
];

const styleFields = (s) => [
  ['Item', s.item],
  ['Description', s.itemDescription],
  ['Status', s.status],
  ['Item number type', s.itemNumberType],
  ['Item level', s.itemLevel],
  ['Tran level', s.tranLevel],
  ['Parent', s.itemParent],
  ['Grandparent', s.itemGrandparent],
  ['Dept', s.dept],
  ['Dept name', s.deptName],
  ['Class', s.class],
  ['Class name', s.className],
  ['Subclass', s.subclass],
  ['Subclass name', s.subclassName],
  ['Diff 1', s.diff1],
  ['Diff 1 type', s.diff1Type],
  ['Diff 2', s.diff2],
  ['Diff 2 type', s.diff2Type],
  ['Standard UOM', s.standardUom],
  ['Cost zone group', s.costZoneGroupId],
  ['Unit retail', s.unitRetail],
  ['Brand', s.brandName],
  ['Merchandise', s.merchandiseInd],
  ['Sellable', s.sellableInd],
  ['Orderable', s.orderableInd],
  ['Inventoried', s.inventoryInd],
];

/** Flattens itemSupplier across the style and its SKUs, tagged with the owning item. */
function supplierRows(items) {
  const out = [];
  items.forEach((it) => {
    (it.itemSupplier || []).forEach((sup) => {
      out.push({
        item: it.item,
        supplier: sup.supplier,
        primary: sup.primarySupplierInd,
        vpn: sup.vpn,
        label: sup.supplierLabel,
        pallet: sup.palletName,
        cases: sup.caseName,
        inner: sup.innerName,
      });
    });
  });
  return out;
}

function countryRows(items) {
  const out = [];
  items.forEach((it) => {
    (it.itemSupplier || []).forEach((sup) => {
      (sup.itemSupplierCountry || []).forEach((c) => {
        out.push({
          item: it.item,
          supplier: sup.supplier,
          country: c.originCountryId ?? c.originCountry,
          primary: c.primaryCountryInd,
          unitCost: c.unitCost,
          uop: c.defaultUop,
          costUom: c.costUom,
          packSize: c.supplierPackSize,
          inner: c.innerPackSize,
        });
      });
    });
  });
  return out;
}

function manufactureRows(items) {
  const out = [];
  items.forEach((it) => {
    (it.itemSupplier || []).forEach((sup) => {
      (sup.itemSupplierCountryOfManufacture || []).forEach((c) => {
        out.push({
          item: it.item,
          supplier: sup.supplier,
          country: c.manufacturerCountry ?? c.manufacturerCountryId,
          primary: c.primaryManufacturerCountryInd,
        });
      });
    });
  });
  return out;
}

function udaRows(items) {
  const out = [];
  items.forEach((it) => {
    const u = it.itemUda;
    if (!u) return;
    ['udaLov', 'udaFreeform', 'udaDate'].forEach((kind) => {
      (u[kind] || []).forEach((r) => {
        out.push({
          item: it.item,
          kind: kind.replace('uda', ''),
          uda: r.uda ?? r.udaId,
          value: r.udaValue ?? r.udaText ?? r.udaDate ?? r.udaValueDesc,
        });
      });
    });
  });
  return out;
}

export default function RecordDetail({ order, style, skus, loading }) {
  const [tab, setTab] = useState('detail');
  const [region, setRegion] = useState('skus');

  if (loading) return <p className="explain">Loading…</p>;
  if (!order && !style) return null;

  // Supplier, country and UDA data hang off each item, so aggregate the style and
  // its SKUs and tag each row with the item it came from.
  const items = [style, ...(skus || [])].filter(Boolean);
  const lines = order?.details || [];
  const sup = supplierRows(items);
  const ctry = countryRows(items);
  const manu = manufactureRows(items);
  const udas = udaRows(items);

  const REGIONS = [
    { id: 'skus', label: 'SKUs', n: (skus || []).length },
    ...(order ? [{ id: 'lines', label: 'Order lines', n: lines.length }] : []),
    { id: 'suppliers', label: 'Item supplier', n: sup.length },
    { id: 'countries', label: 'Supp. countries', n: ctry.length },
    { id: 'manufacture', label: 'Countries of mfr', n: manu.length },
    { id: 'udas', label: 'UDAs', n: udas.length },
  ];

  return (
    <div>
      <div className="tabs rd-tabs">
        <button type="button" className={tab === 'detail' ? 'on' : ''} onClick={() => setTab('detail')}>
          Detail
        </button>
        <button type="button" className={tab === 'json' ? 'on' : ''} onClick={() => setTab('json')}>
          JSON
        </button>
      </div>

      {tab === 'json' && (
        <>
          {order && (
            <>
              <p className="muted small">Order document</p>
              <JsonBlock value={order} />
            </>
          )}
          {style && (
            <>
              <p className="muted small" style={{ marginTop: 12 }}>Style document</p>
              <JsonBlock value={style} />
            </>
          )}
        </>
      )}

      {tab === 'detail' && (
        <>
          {order && (
            <Section title="Order" subtitle={`#${order.orderNo}`}>
              <Fields fields={orderFields(order)} />
            </Section>
          )}

          {style ? (
            <Section
              title="Style"
              subtitle={order ? 'resolved from the order lines — one order, one style' : undefined}
            >
              <Fields fields={styleFields(style)} />
            </Section>
          ) : (
            order && (
              <Section title="Style">
                <p className="muted small">
                  No parent style could be resolved from this order's lines.
                </p>
              </Section>
            )
          )}

          <div className="rd-regions">
            <div className="tabs" style={{ margin: 0, padding: '0 0 0 0' }}>
              {REGIONS.map((r) => (
                <button
                  key={r.id}
                  type="button"
                  className={region === r.id ? 'on' : ''}
                  onClick={() => setRegion(r.id)}
                >
                  {r.label}
                  <span className="count">{r.n}</span>
                </button>
              ))}
            </div>

            <div className="rd-region-body">
              {region === 'skus' && style?.resolved?.truncated && (
                <div className="banner warn">
                  <strong>SKU list may be incomplete.</strong> The scan hit its page cap after
                  {' '}{style.resolved.itemsScanned} items without reaching the end of the feed.
                </div>
              )}
              {region === 'skus' && style?.resolved?.note && (
                <p className="muted small" style={{ marginBottom: 8 }}>
                  {style.resolved.note} Scanned {style.resolved.itemsScanned} item(s).
                </p>
              )}
              {region === 'skus' && (
                <Grid
                  columns={[
                    { key: 'item', label: 'SKU', mono: true },
                    { key: 'itemDescription', label: 'Description' },
                    { key: 'diff1', label: 'Colour', mono: true },
                    { key: 'diff2', label: 'Size', mono: true },
                    { key: 'status', label: 'St' },
                    { key: 'unitRetail', label: 'Retail' },
                  ]}
                  rows={skus || []}
                  empty="No child SKUs found."
                />
              )}

              {region === 'lines' && (
                <Grid
                  columns={[
                    { key: 'item', label: 'Item', mono: true },
                    { key: 'physicalQuantityOrdered', label: 'Qty' },
                    { key: 'unitCost', label: 'Unit cost' },
                    { key: 'originCountryId', label: 'Origin' },
                    { key: 'supplierPackSize', label: 'Pack' },
                    { key: 'virtualWarehouse', label: 'VWH' },
                    { key: 'earliestShipDate', label: 'Earliest' },
                    { key: 'latestShipDate', label: 'Latest' },
                  ]}
                  rows={lines}
                  empty="No order lines."
                />
              )}

              {region === 'suppliers' && (
                <Grid
                  columns={[
                    { key: 'item', label: 'Item', mono: true },
                    { key: 'supplier', label: 'Supplier', mono: true },
                    { key: 'primary', label: 'Primary' },
                    { key: 'vpn', label: 'VPN' },
                    { key: 'pallet', label: 'Pallet' },
                    { key: 'cases', label: 'Case' },
                    { key: 'inner', label: 'Inner' },
                  ]}
                  rows={sup}
                  empty="No item-supplier records."
                />
              )}

              {region === 'countries' && (
                <Grid
                  columns={[
                    { key: 'item', label: 'Item', mono: true },
                    { key: 'supplier', label: 'Supplier', mono: true },
                    { key: 'country', label: 'Origin' },
                    { key: 'primary', label: 'Primary' },
                    { key: 'unitCost', label: 'Unit cost' },
                    { key: 'uop', label: 'UOP' },
                    { key: 'costUom', label: 'Cost UOM' },
                    { key: 'packSize', label: 'Pack' },
                  ]}
                  rows={ctry}
                  empty="No item-supplier-country records."
                />
              )}

              {region === 'manufacture' && (
                <Grid
                  columns={[
                    { key: 'item', label: 'Item', mono: true },
                    { key: 'supplier', label: 'Supplier', mono: true },
                    { key: 'country', label: 'Manufacture country' },
                    { key: 'primary', label: 'Primary' },
                  ]}
                  rows={manu}
                  empty="No countries of manufacture. Item approval fails without one."
                />
              )}

              {region === 'udas' && (
                <Grid
                  columns={[
                    { key: 'item', label: 'Item', mono: true },
                    { key: 'kind', label: 'Kind' },
                    { key: 'uda', label: 'UDA' },
                    { key: 'value', label: 'Value' },
                  ]}
                  rows={udas}
                  empty="No UDA values. The bridge sends an empty array because the tenant's UDA definitions have never been published."
                />
              )}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
