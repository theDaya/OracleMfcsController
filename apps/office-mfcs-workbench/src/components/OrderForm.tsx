import { useFormContext, useWatch } from 'react-hook-form'
import { FormField } from './FormField'
import { operationNeedsExistingOrder, operationTouchesOrder, type OfficeRequest } from '../models/officeRequest'

export function OrderForm() {
  const { register, formState: { errors }, control } = useFormContext<OfficeRequest>()
  const operation = useWatch({ control, name: 'operationName' })
  const orderActive = operationTouchesOrder(operation)
  return (
    <section className="form-section">
      <div className="section-heading">
        <div><span className="step-kicker">Step 4</span><h2>Order and delivery</h2></div>
        <p>{orderActive ? 'Dates, destination and purchase-order controls.' : 'Retained with the draft; this style-only operation will not post a purchase order.'}</p>
      </div>
      {operationNeedsExistingOrder(operation) && (
        <div className="identifier-callout"><FormField label="Existing MFCS order" error={errors.order?.existingOrderNo?.message}><input {...register('order.existingOrderNo')} placeholder="e.g. 10740001" /></FormField></div>
      )}
      <fieldset disabled={!orderActive} className={!orderActive ? 'disabled-section' : ''}>
        <div className="form-grid three-col">
          <FormField label="Delivery location" error={errors.order?.deliveryLocation?.message}><input type="number" {...register('order.deliveryLocation', { valueAsNumber: true })} /></FormField>
          <FormField label="PO type" error={errors.order?.poType?.message}><select {...register('order.poType')}><option value="2">2 - Fashion</option><option value="1">1 - Basic</option></select></FormField>
          <FormField label="Exchange rate" error={errors.order?.exchangeRate?.message}><input type="number" step="0.0001" {...register('order.exchangeRate', { valueAsNumber: true })} /></FormField>
          <FormField label="Not-before date" error={errors.order?.notBeforeDate?.message}><input type="date" {...register('order.notBeforeDate')} /></FormField>
          <FormField label="Not-after date" error={errors.order?.notAfterDate?.message}><input type="date" {...register('order.notAfterDate')} /></FormField>
          <FormField label="OTB end-of-week"><input type="date" {...register('order.otbEowDate')} /></FormField>
          <FormField label="Earliest ship date" error={errors.order?.earliestShipDate?.message}><input type="date" {...register('order.earliestShipDate')} /></FormField>
          <FormField label="Latest ship date" error={errors.order?.latestShipDate?.message}><input type="date" {...register('order.latestShipDate')} /></FormField>
          <FormField label="Duty code"><input {...register('order.dutyCode')} /></FormField>
          <FormField label="Duty rate"><input type="number" step="0.01" {...register('order.dutyRate', { valueAsNumber: true })} /></FormField>
          <FormField label="Special instructions" className="span-2"><textarea rows={3} {...register('order.specialInstructions')} /></FormField>
        </div>
      </fieldset>
      <div className="defaults-strip"><span>VALLEY_PERIOD <b>N</b></span><span>ON_HANGER <b>N</b></span><span>FIRST_PASS <b>N</b></span><span>TICKETS <b>N</b></span><span>PDF_PO <b>N</b></span></div>
    </section>
  )
}
