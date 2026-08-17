import { useFormContext } from 'react-hook-form'
import type { OfficeRequest } from '../models/officeRequest'
import { FormField } from './FormField'

export function SourcingForm() {
  const { register, formState: { errors } } = useFormContext<OfficeRequest>()
  return (
    <section className="form-section">
      <div className="section-heading">
        <div><span className="step-kicker">Step 2</span><h2>Sourcing and commercial</h2></div>
        <p>Supplier, origin, cost, retail and packing information.</p>
      </div>
      <div className="form-grid three-col">
        <FormField label="Supplier" error={errors.sourcing?.supplier?.message}>
          <input type="number" {...register('sourcing.supplier', { valueAsNumber: true })} />
        </FormField>
        <FormField label="VPN" error={errors.sourcing?.vpn?.message} className="span-2">
          <input {...register('sourcing.vpn')} />
        </FormField>
        <FormField label="Country of origin" error={errors.sourcing?.originCountry?.message}>
          <select {...register('sourcing.originCountry')}><option value="CN">China</option><option value="ZA">South Africa</option><option value="US">United States</option></select>
        </FormField>
        <FormField label="Manufacturing country" error={errors.sourcing?.manufacturingCountry?.message}>
          <select {...register('sourcing.manufacturingCountry')}><option value="CN">China</option><option value="ZA">South Africa</option><option value="US">United States</option></select>
        </FormField>
        <FormField label="Currency" error={errors.sourcing?.currencyCode?.message}>
          <select {...register('sourcing.currencyCode')}><option value="USD">USD</option><option value="ZAR">ZAR</option><option value="EUR">EUR</option><option value="GBP">GBP</option></select>
        </FormField>
        <FormField label="Cost price" error={errors.sourcing?.costPrice?.message}>
          <div className="input-prefix"><span>$</span><input type="number" step="0.01" {...register('sourcing.costPrice', { valueAsNumber: true })} /></div>
        </FormField>
        <FormField label="Non-merchandise cost" error={errors.sourcing?.nonMerchCost?.message}>
          <div className="input-prefix"><span>$</span><input type="number" step="0.01" {...register('sourcing.nonMerchCost', { valueAsNumber: true })} /></div>
        </FormField>
        <FormField label="RSP" error={errors.sourcing?.rsp?.message}>
          <div className="input-prefix"><span>$</span><input type="number" step="0.01" {...register('sourcing.rsp', { valueAsNumber: true })} /></div>
        </FormField>
        <FormField label="Case pack size" error={errors.sourcing?.casePackSize?.message}>
          <input type="number" {...register('sourcing.casePackSize', { valueAsNumber: true })} />
        </FormField>
        <FormField label="Inner pack size" error={errors.sourcing?.innerPackSize?.message}>
          <input type="number" {...register('sourcing.innerPackSize', { valueAsNumber: true })} />
        </FormField>
      </div>
      <div className="defaults-strip"><span>PACK_IND <b>N</b></span><span>UPDATE_COST_IND <b>Y</b></span><span>UPDATE_RSP_IND <b>Y</b></span></div>
    </section>
  )
}
