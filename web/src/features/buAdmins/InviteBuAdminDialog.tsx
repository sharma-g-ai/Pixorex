import { useState } from 'react'
import { Controller, useForm } from 'react-hook-form'
import { ApiError, errorMessage, problemCode } from '../../api/client'
import { useCreateInvite } from '../../api/invites'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { Dialog } from '../../components/Dialog'
import { TextField } from '../../components/TextField'
import { UnitChecklist, type UnitOption } from '../../components/UnitChecklist'
import { zodResolver } from '../../lib/zodResolver'
import { inviteBuAdminSchema, type InviteBuAdminValues } from './buAdminForms'

interface InviteBuAdminDialogProps {
  options: UnitOption[]
  /** Units ticked when the dialog opens, e.g. the unit the EA came from. */
  initialUnitIds?: string[]
  onClose: () => void
  onSent: (email: string) => void
}

/** "Invite a BU Admin" (canvas EA 14; contract 1.8 with role bu_admin). */
export function InviteBuAdminDialog({
  options,
  initialUnitIds = [],
  onClose,
  onSent,
}: InviteBuAdminDialogProps) {
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
  } = useForm<InviteBuAdminValues>({
    resolver: zodResolver(inviteBuAdminSchema),
    defaultValues: { email: '', bu_ids: initialUnitIds },
  })

  const onSubmit = handleSubmit(async (values) => {
    setFormError(null)
    try {
      await createInvite.mutateAsync({
        body: { role: 'bu_admin', email: values.email, bu_ids: values.bu_ids },
        idempotencyKey,
      })
      onSent(values.email)
    } catch (err) {
      if (err instanceof ApiError && problemCode(err.problem) === 'unit-has-bu-admin') {
        return setError('bu_ids', {
          message: 'One of these units got a BU Admin meanwhile. Refresh and pick again.',
        })
      }
      setFormError(errorMessage(err))
    }
  })

  return (
    <Dialog
      title="Invite a BU Admin"
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" form="invite-bu-admin" disabled={createInvite.isPending}>
            {createInvite.isPending ? 'Sending…' : 'Send invite'}
          </Button>
        </>
      }
    >
      <form id="invite-bu-admin" noValidate onSubmit={onSubmit} className="flex flex-col gap-4">
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
              legend="Units they'll run"
              options={options}
              value={field.value}
              onChange={field.onChange}
              error={errors.bu_ids?.message}
            />
          )}
        />
        <Alert tone="info">
          They get a magic link by email, valid 24 hours, to confirm their name and verify their
          email with a code — no password. Until they accept, they show under <b>Pending invites</b>
          .
        </Alert>
        {formError && <Alert tone="danger">{formError}</Alert>}
      </form>
    </Dialog>
  )
}
