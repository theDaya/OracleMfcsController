import { Plus, Trash2 } from 'lucide-react'
import { useFieldArray, useFormContext, useWatch } from 'react-hook-form'
import { makeVariant } from '../models/defaults'
import { operationNeedsExistingSkus, type OfficeRequest } from '../models/officeRequest'

export function SizeCurveEditor() {
  const { register, control, formState: { errors } } = useFormContext<OfficeRequest>()
  const { fields, append, remove } = useFieldArray({ control, name: 'variants' })
  const operation = useWatch({ control, name: 'operationName' })
  const sourceStyleRef = useWatch({ control, name: 'sourceStyleRef' })
  const requiresSku = operationNeedsExistingSkus(operation)
  return (
    <section className="form-section">
      <div className="section-heading row-heading">
        <div><span className="step-kicker">Step 3</span><h2>Size curve and quantities</h2></div>
        <button type="button" className="secondary-button" onClick={() => append(makeVariant(sourceStyleRef))}><Plus size={16} /> Add row</button>
      </div>
      <div className="table-wrap">
        <table className="edit-table">
          <thead><tr><th>Size</th><th>Width</th><th>Quantity</th>{requiresSku && <th>Existing SKU</th>}<th>Source variant reference</th><th><span className="sr-only">Actions</span></th></tr></thead>
          <tbody>
            {fields.map((field, index) => (
              <tr key={field.id}>
                <td><input aria-label={`Size row ${index + 1}`} {...register(`variants.${index}.size`)} /><span className="cell-error">{errors.variants?.[index]?.size?.message}</span></td>
                <td><select aria-label={`Width row ${index + 1}`} {...register(`variants.${index}.width`)}><option value="STANDARD">STANDARD</option><option value="WIDE">WIDE</option><option value="NARROW">NARROW</option><option value="">None</option></select><span className="cell-error">{errors.variants?.[index]?.width?.message}</span></td>
                <td><input aria-label={`Quantity row ${index + 1}`} type="number" {...register(`variants.${index}.quantity`, { valueAsNumber: true })} /><span className="cell-error">{errors.variants?.[index]?.quantity?.message}</span></td>
                {requiresSku && <td><input aria-label={`SKU row ${index + 1}`} placeholder="MFCS SKU" {...register(`variants.${index}.skuId`)} /><span className="cell-error">{errors.variants?.[index]?.skuId?.message}</span></td>}
                <td><input className="reference-input" aria-label={`Source reference row ${index + 1}`} {...register(`variants.${index}.sourceVariantRef`)} /></td>
                <td><button type="button" className="icon-button danger-icon" title="Remove row" aria-label={`Remove variant ${index + 1}`} disabled={fields.length === 1} onClick={() => remove(index)}><Trash2 size={17} /></button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  )
}
