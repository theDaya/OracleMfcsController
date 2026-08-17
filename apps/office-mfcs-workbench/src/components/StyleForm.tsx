import { useFormContext, useWatch } from 'react-hook-form'
import { FormField } from './FormField'
import { operationNeedsExistingStyle, operationLabels, type OfficeRequest, type OperationName } from '../models/officeRequest'

const operations = Object.keys(operationLabels) as OperationName[]

export function StyleForm() {
  const { register, formState: { errors }, control } = useFormContext<OfficeRequest>()
  const operation = useWatch({ control, name: 'operationName' })
  return (
    <section className="form-section">
      <div className="section-heading">
        <div><span className="step-kicker">Step 1</span><h2>Operation and style</h2></div>
        <p>Choose the MFCS action first; identifier requirements adjust automatically.</p>
      </div>
      <div className="operation-grid" role="radiogroup" aria-label="Operation">
        {operations.map((value) => (
          <label key={value} className={`operation-option ${operation === value ? 'selected' : ''}`}>
            <input type="radio" value={value} {...register('operationName')} />
            <span>{operationLabels[value]}</span>
            <small>{value.replaceAll('_', ' ')}</small>
          </label>
        ))}
      </div>
      {operationNeedsExistingStyle(operation) && (
        <div className="identifier-callout">
          <FormField label="Existing MFCS style" error={errors.style?.existingStyle?.message} hint="Required for order-only and modify operations.">
            <input {...register('style.existingStyle')} placeholder="e.g. 3500001" />
          </FormField>
        </div>
      )}
      <div className="form-grid three-col">
        <FormField label="Style description" error={errors.style?.description?.message} className="span-2">
          <input {...register('style.description')} />
        </FormField>
        <FormField label="Short description" error={errors.style?.shortDescription?.message}>
          <input {...register('style.shortDescription')} />
        </FormField>
        <FormField label="Department" error={errors.style?.department?.message}>
          <input type="number" {...register('style.department', { valueAsNumber: true })} />
        </FormField>
        <FormField label="Class" error={errors.style?.classNumber?.message}>
          <input type="number" {...register('style.classNumber', { valueAsNumber: true })} />
        </FormField>
        <FormField label="Subclass" error={errors.style?.subclass?.message}>
          <input type="number" {...register('style.subclass', { valueAsNumber: true })} />
        </FormField>
        <FormField label="Colour group" error={errors.style?.colourGroup?.message}>
          <input {...register('style.colourGroup')} />
        </FormField>
        <FormField label="Colour" error={errors.style?.colour?.message}>
          <select {...register('style.colour')}><option>BLACK</option><option>WHITE</option><option>BROWN</option><option>RED</option><option>BLUE</option></select>
        </FormField>
        <FormField label="Size group" error={errors.style?.sizeGroup?.message}>
          <input {...register('style.sizeGroup')} />
        </FormField>
        <FormField label="Width group" error={errors.style?.widthGroup?.message}>
          <input {...register('style.widthGroup')} />
        </FormField>
        <FormField label="Season" error={errors.style?.season?.message}>
          <input {...register('style.season')} />
        </FormField>
        <FormField label="Phase" error={errors.style?.phase?.message}>
          <input {...register('style.phase')} />
        </FormField>
      </div>
    </section>
  )
}
