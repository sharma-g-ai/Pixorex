import { useState } from 'react'
import { useForm, useWatch, type UseFormRegisterReturn } from 'react-hook-form'
import { Link, useNavigate } from 'react-router'
import { useBuAdmins, type BuAdmin } from '../../api/buAdmins'
import { useCreateBusinessUnit } from '../../api/businessUnits'
import { ApiError, errorMessage, problemCode } from '../../api/client'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { PageHeader } from '../../components/layout/PageHeader'
import { ChoiceCard } from '../../components/ChoiceCard'
import { TextField } from '../../components/TextField'
import { zodResolver } from '../../lib/zodResolver'
import {
  createUnitSchema,
  emptyCreateUnit,
  serverFieldFor,
  serverMessages,
  toCreateUnitBody,
  type CreateUnitValues,
} from './createUnitForm'

/** EA-01 Create business unit with its BU Admin (canvas: EA 11; contract 1.13). */
export function CreateUnitPage() {
  const navigate = useNavigate()
  const createUnit = useCreateBusinessUnit()
  const buAdmins = useBuAdmins()
  // One key per form: a retried submit can never create the unit twice.
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const [formError, setFormError] = useState<string | null>(null)

  const {
    register,
    handleSubmit,
    control,
    setError,
    formState: { errors },
  } = useForm<CreateUnitValues>({
    resolver: zodResolver(createUnitSchema),
    defaultValues: emptyCreateUnit,
  })
  const [mode, pickedAdmin] = useWatch({ control, name: ['admin_mode', 'user_id'] })

  const onSubmit = handleSubmit(async (values) => {
    setFormError(null)
    try {
      const unit = await createUnit.mutateAsync({
        body: toCreateUnitBody(values),
        idempotencyKey,
      })
      navigate(`/locations?unit=${unit.bu_id}`, { state: { createdUnit: unit.name } })
    } catch (err) {
      if (!(err instanceof ApiError)) return setFormError(errorMessage(err))
      const { problem } = err
      const code = problemCode(problem)
      const field = serverFieldFor[code]
      if (field) return setError(field, { message: serverMessages[code] ?? problem.title })
      for (const e of problem.errors ?? []) {
        const target = serverFieldFor[e.field]
        if (target) setError(target, { message: e.message })
      }
      if (!problem.errors?.length) setFormError(errorMessage(err))
    }
  })

  return (
    <>
      <PageHeader title="Create business unit" subtitle="Overview › New unit" />
      <form
        noValidate
        onSubmit={onSubmit}
        className="flex grow flex-col gap-5 overflow-y-auto px-8 pt-6 pb-8 lg:flex-row lg:items-start"
      >
        <div className="flex min-w-0 grow flex-col gap-4">
          <Card title="1 · Unit details">
            <div className="grid grid-cols-1 gap-3.5 md:grid-cols-2">
              <TextField
                label="Unit name"
                placeholder="PPG Plant 12 — Adhesives"
                error={errors.name?.message}
                {...register('name')}
              />
              <TextField
                label="Facility (top location level)"
                placeholder="Plant 12 — Akron, OH"
                error={errors.facility_name?.message}
                {...register('facility_name')}
              />
            </div>
          </Card>

          <Card title="2 · BU Admin">
            <fieldset className="flex flex-col gap-2">
              <legend className="sr-only">BU Admin</legend>
              <ChoiceCard
                value="invite"
                title="Invite a new BU Admin"
                description="Magic link by email, valid 24 hours"
                checked={mode === 'invite'}
                {...register('admin_mode')}
              >
                <TextField
                  label="Email"
                  type="email"
                  autoComplete="off"
                  placeholder="name@company.com"
                  error={errors.invite_email?.message}
                  {...register('invite_email')}
                />
              </ChoiceCard>
              <ChoiceCard
                value="existing"
                title="Use an existing BU Admin"
                description="One BU Admin can run several units"
                checked={mode === 'existing'}
                {...register('admin_mode')}
              >
                <ExistingAdmins
                  admins={buAdmins.data}
                  loading={buAdmins.isPending}
                  picked={pickedAdmin}
                  error={errors.user_id?.message}
                  field={register('user_id')}
                />
              </ChoiceCard>
            </fieldset>
          </Card>
        </div>

        <aside className="flex w-full shrink-0 flex-col gap-3.5 lg:w-85">
          <Card title="After you create it">
            <ol className="flex list-inside list-decimal flex-col gap-2.5 text-body-sm leading-normal text-ink-muted">
              <li>Set up the unit’s location levels and tree.</li>
              <li>The BU Admin accepts the invite and adds equipment types.</li>
              <li>Invite field technicians.</li>
            </ol>
          </Card>
          <Alert tone="info">
            Each unit has exactly one BU Admin. Until they accept, this unit's scans that wait over
            24 hours come to you.
          </Alert>
          {formError && <Alert tone="danger">{formError}</Alert>}
          <div className="flex gap-2.5">
            <Link to="/overview" className={buttonClasses('secondary')}>
              Cancel
            </Link>
            <Button type="submit" disabled={createUnit.isPending}>
              {createUnit.isPending ? 'Creating…' : 'Create unit & set up locations'}
            </Button>
          </div>
        </aside>
      </form>
    </>
  )
}

interface ExistingAdminsProps {
  admins: BuAdmin[] | undefined
  loading: boolean
  picked: string
  error?: string
  field: UseFormRegisterReturn<'user_id'>
}

function ExistingAdmins({ admins, loading, picked, error, field }: ExistingAdminsProps) {
  if (loading) return <p className="text-small text-ink-muted">Loading BU Admins…</p>
  if (!admins?.length)
    return <p className="text-small text-ink-muted">There are no BU Admins yet.</p>

  return (
    <div role="radiogroup" aria-label="Existing BU Admins" className="flex flex-col gap-2">
      {admins.map((admin) => (
        <ChoiceCard
          key={admin.user_id}
          value={admin.user_id}
          title={admin.full_name}
          description={
            admin.units
              .map((u) => u.name)
              .filter(Boolean)
              .join(', ') || 'No units yet'
          }
          checked={picked === admin.user_id}
          {...field}
        />
      ))}
      {error && <p className="text-xs text-danger">{error}</p>}
    </div>
  )
}
