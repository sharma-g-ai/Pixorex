import { useState } from 'react'
import { Controller, useForm } from 'react-hook-form'
import { ApiError, errorMessage, problemCode } from '../../api/client'
import { useCreateInvite } from '../../api/invites'
import type { UnitRole } from '../../api/me'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { Dialog } from '../../components/Dialog'
import { TextField } from '../../components/TextField'
import { UnitChecklist } from '../../components/UnitChecklist'
import { zodResolver } from '../../lib/zodResolver'
import { inviteSchema, inviteServerErrors, type InviteValues } from './inviteForm'

interface InviteTechnicianDialogProps {
  /** Units the BU Admin runs; they can invite into any of them. */
  units: UnitRole[]
  /** Pre-ticked unit (the current one). */
  currentBuId: string
  /** Pre-filled email, e.g. when re-inviting a removed technician. */
  email?: string
  onClose: () => void
  onSent: (email: string) => void
}

/** "Invite a technician" dialog (canvas BU 26; contract 1.8). */
export function InviteTechnicianDialog({
  units,
  currentBuId,
  email = '',
  onClose,
  onSent,
}: InviteTechnicianDialogProps) {
  const createInvite = useCreateInvite()
  // One key per dialog: a retried send can never invite twice.
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const [formError, setFormError] = useState<string | null>(null)
  const {
    register,
    handleSubmit,
    control,
    setError,
    formState: { errors },
  } = useForm<InviteValues>({
    resolver: zodResolver(inviteSchema),
    defaultValues: { email, bu_ids: [currentBuId] },
  })

  const onSubmit = handleSubmit(async (values) => {
    setFormError(null)
    try {
      await createInvite.mutateAsync({
        body: { role: 'field_technician', email: values.email, bu_ids: values.bu_ids },
        idempotencyKey,
      })
      onSent(values.email)
    } catch (err) {
      const known =
        err instanceof ApiError ? inviteServerErrors[problemCode(err.problem)] : undefined
      if (known) return setError(known.field, { message: known.message })
      setFormError(errorMessage(err))
    }
  })

  return (
    <Dialog
      title="Invite a technician"
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" form="invite-technician" disabled={createInvite.isPending}>
            {createInvite.isPending ? 'Sending…' : 'Send invite'}
          </Button>
        </>
      }
    >
      <form id="invite-technician" noValidate onSubmit={onSubmit} className="flex flex-col gap-4">
        <TextField
          label="Work email"
          type="email"
          autoComplete="off"
          error={errors.email?.message}
          {...register('email')}
        />
        <Controller
          control={control}
          name="bu_ids"
          render={({ field }) => (
            <UnitChecklist
              legend="Units"
              options={units.map((u) => ({
                bu_id: u.bu_id ?? '',
                name: u.name ?? 'Unnamed unit',
                note: 'You run this unit',
              }))}
              value={field.value}
              onChange={field.onChange}
              error={errors.bu_ids?.message}
            />
          )}
        />
        <Alert tone="info">
          They get an email with a link to activate the mobile app, valid 24 hours. They never get
          dashboard access. Until they activate, they show under <b>Invites</b>.
        </Alert>
        {formError && <Alert tone="danger">{formError}</Alert>}
      </form>
    </Dialog>
  )
}
