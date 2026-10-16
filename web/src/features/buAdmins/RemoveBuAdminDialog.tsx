import { useState } from 'react'
import { Controller, useForm, useWatch } from 'react-hook-form'
import { useRemoveBuAdmin, type BuAdmin } from '../../api/buAdmins'
import { errorMessage } from '../../api/client'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { ChoiceCard } from '../../components/ChoiceCard'
import { Dialog } from '../../components/Dialog'
import { TextField } from '../../components/TextField'
import { UnitChecklist, type UnitOption } from '../../components/UnitChecklist'
import { zodResolver } from '../../lib/zodResolver'
import { removeBuAdminSchema, type RemoveBuAdminValues } from './buAdminForms'

interface RemoveBuAdminDialogProps {
  admin: BuAdmin
  options: UnitOption[]
  onClose: () => void
  onRemoved: (message: string) => void
}

/** Remove a BU Admin from some or all units (canvas EA 16–18; contract 1.17). */
export function RemoveBuAdminDialog({
  admin,
  options,
  onClose,
  onRemoved,
}: RemoveBuAdminDialogProps) {
  const remove = useRemoveBuAdmin()
  const [formError, setFormError] = useState<string | null>(null)
  const {
    register,
    handleSubmit,
    control,
    formState: { errors },
  } = useForm<RemoveBuAdminValues>({
    resolver: zodResolver(removeBuAdminSchema),
    defaultValues: { bu_ids: options.map((o) => o.bu_id), next: 'later', replacement_email: '' },
  })
  const [picked, next] = useWatch({ control, name: ['bu_ids', 'next'] })

  const pickedNames = options.filter((o) => picked.includes(o.bu_id)).map((o) => o.name)
  const keptNames = options.filter((o) => !picked.includes(o.bu_id)).map((o) => o.name)
  const all = keptNames.length === 0
  const target = all
    ? 'all units'
    : pickedNames.length === 1
      ? (pickedNames[0] ?? '')
      : `${pickedNames.length} units`

  const onSubmit = handleSubmit(async (values) => {
    setFormError(null)
    try {
      await remove.mutateAsync({
        userId: admin.user_id,
        buIds: values.bu_ids,
        replacementEmail: values.next === 'invite' ? values.replacement_email : undefined,
      })
      onRemoved(`${admin.full_name} was removed from ${target}.`)
    } catch (err) {
      setFormError(errorMessage(err))
    }
  })

  return (
    <Dialog
      title={`Remove ${admin.full_name}`}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="danger" type="submit" form="remove-bu-admin" disabled={remove.isPending}>
            {remove.isPending ? 'Removing…' : `Remove from ${target}`}
          </Button>
        </>
      }
    >
      <form id="remove-bu-admin" noValidate onSubmit={onSubmit} className="flex flex-col gap-4">
        <p className="text-small">
          {admin.email} · tick the units to remove them from. Tick all to remove them from every
          unit.
        </p>
        <Controller
          control={control}
          name="bu_ids"
          render={({ field }) => (
            <UnitChecklist
              legend="Units"
              options={options}
              value={field.value}
              onChange={field.onChange}
              error={errors.bu_ids?.message}
            />
          )}
        />
        {picked.length > 0 && (
          <ul className="flex list-inside list-disc flex-col gap-2">
            {all ? (
              <li>
                {admin.full_name} is removed from <b className="text-ink">every unit</b> and signed
                out of the dashboard straight away.
              </li>
            ) : (
              <li>
                {admin.full_name} stays BU Admin for{' '}
                <b className="text-ink">{keptNames.join(', ')}</b> and loses access to{' '}
                {pickedNames.join(', ')} straight away.
              </li>
            )}
            <li>Their account and history are kept — only the unit assignments are removed.</li>
            <li>Recorded in the audit log.</li>
          </ul>
        )}
        <fieldset className="flex flex-col gap-2">
          <legend className="mb-1.5 text-small font-semibold text-ink-muted">
            Who runs {pickedNames.length === 1 ? pickedNames[0] : 'these units'} next?
          </legend>
          <ChoiceCard
            value="invite"
            title="Invite a new BU Admin now"
            description="Magic link by email, valid 24 hours"
            checked={next === 'invite'}
            {...register('next')}
          >
            <TextField
              label="Email"
              type="email"
              autoComplete="off"
              error={errors.replacement_email?.message}
              {...register('replacement_email')}
            />
          </ChoiceCard>
          <ChoiceCard
            value="later"
            title="Decide later"
            description="Their scans that wait over 24 hours come to you until then"
            checked={next === 'later'}
            {...register('next')}
          />
        </fieldset>
        {formError && <Alert tone="danger">{formError}</Alert>}
      </form>
    </Dialog>
  )
}
