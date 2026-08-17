import { zodResolver } from '@hookform/resolvers/zod'
import { ArrowLeft, ArrowRight, CheckCircle2, Save } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { FormProvider, useForm, type Resolver } from 'react-hook-form'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useAuth } from '../auth/AuthProvider'
import { OrderForm } from '../components/OrderForm'
import { RequestReview } from '../components/RequestReview'
import { SizeCurveEditor } from '../components/SizeCurveEditor'
import { SourcingForm } from '../components/SourcingForm'
import { StyleForm } from '../components/StyleForm'
import { mapRequestToPayload } from '../mapping/integrationPayloadMapper'
import { createDefaultRequest } from '../models/defaults'
import type { OfficeRequest } from '../models/officeRequest'
import { officeRequestSchema } from '../validation/officeRequestSchema'
import { useWorkflow } from '../workflow/WorkflowContext'

const steps = ['Style', 'Sourcing', 'Variants', 'Order', 'Review']

export function CreateRequestPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { currentUser } = useAuth()
  const { getRequest, saveDraft, submit, loading } = useWorkflow()
  const existing = id ? getRequest(id) : undefined
  const defaults = useMemo(() => existing ?? createDefaultRequest(currentUser), [currentUser, existing])
  const methods = useForm<OfficeRequest>({ defaultValues: defaults, resolver: zodResolver(officeRequestSchema) as unknown as Resolver<OfficeRequest> })
  const [step, setStep] = useState(0)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<string>()
  const draft = methods.watch()

  useEffect(() => { if (existing) methods.reset(existing) }, [existing, methods])
  if (id && loading) return <div className="empty-state">Loading request…</div>
  if (id && !existing) return <div className="empty-state"><h2>Request not found</h2><Link to="/requests">Return to requests</Link></div>
  if (currentUser.role !== 'BUYER') return <div className="empty-state"><h2>Buyer access required</h2><p>Switch to Jane Buyer to create or edit requests.</p></div>
  if (existing && existing.status !== 'DRAFT') return <div className="empty-state"><h2>This request is read-only</h2><Link to={`/requests/${existing.id}`}>View request</Link></div>

  const preview = mapRequestToPayload({ ...draft, actionRequestId: draft.actionRequestId ?? 'ASSIGNED-ON-APPROVAL' }, currentUser)
  const save = async () => {
    setBusy(true); setMessage(undefined)
    try { await saveDraft(methods.getValues()); setMessage('Draft saved to Oracle.'); if (!id) navigate(`/requests/${draft.id}/edit`, { replace: true }) } catch (error) { setMessage(error instanceof Error ? error.message : 'Draft save failed.') } finally { setBusy(false) }
  }
  const submitRequest = methods.handleSubmit(async (values) => {
    setBusy(true); setMessage(undefined)
    try { await saveDraft(values); const submitted = await submit(values); navigate(`/requests/${submitted.id}`) } catch (error) { setMessage(error instanceof Error ? error.message : 'Submission failed.') } finally { setBusy(false) }
  })

  return (
    <FormProvider {...methods}>
      <form className="page-stack" onSubmit={submitRequest}>
        <div className="page-header compact"><div><Link to="/requests" className="back-link"><ArrowLeft size={16} /> My requests</Link><h1>{existing ? 'Edit request' : 'New MFCS request'}</h1><p>{draft.officeReference} · Source version {draft.sourceVersion}</p></div><button type="button" className="secondary-button" onClick={save} disabled={busy}><Save size={16} /> Save draft</button></div>
        <ol className="wizard-steps">{steps.map((label, index) => <li key={label} className={index === step ? 'active' : index < step ? 'complete' : ''}><button type="button" onClick={() => setStep(index)}><span>{index < step ? <CheckCircle2 size={16} /> : index + 1}</span>{label}</button></li>)}</ol>
        <div className="content-panel form-panel">
          {step === 0 && <StyleForm />}
          {step === 1 && <SourcingForm />}
          {step === 2 && <SizeCurveEditor />}
          {step === 3 && <OrderForm />}
          {step === 4 && <RequestReview request={draft} payload={preview} />}
        </div>
        {message && <div className={`message-bar ${message.includes('saved') ? 'message-success' : 'message-error'}`}>{message}</div>}
        {Object.keys(methods.formState.errors).length > 0 && step === 4 && <div className="message-bar message-error">Review the highlighted fields before submitting.</div>}
        <div className="wizard-actions"><button type="button" className="secondary-button" disabled={step === 0} onClick={() => setStep((value) => value - 1)}><ArrowLeft size={16} /> Back</button><div>{step < steps.length - 1 ? <button type="button" className="primary-button" onClick={() => setStep((value) => value + 1)}>Continue <ArrowRight size={16} /></button> : <button type="submit" className="primary-button" disabled={busy}><CheckCircle2 size={16} /> Submit for approval</button>}</div></div>
      </form>
    </FormProvider>
  )
}
