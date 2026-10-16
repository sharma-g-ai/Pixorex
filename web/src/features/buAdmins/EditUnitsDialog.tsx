import { useState } from 'react'
import { Controller, useForm } from 'react-hook-form'
import { useSetBuAdminUnits, type BuAdmin } from '../../api/buAdmins'
import { ApiError, errorMessage, problemCode } from '../../api/client'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { Dialog } from '../../components/Dialog'
import { Person } from '../../components/Person'
import { UnitChecklist, type UnitOption } from '../../components/UnitChecklist'
import { zodResolver } from '../../lib/zodResolver'
import { editUnitsSchema, type EditUnitsValues } from './buAdminForms'

interface EditUnitsDialogProps {
  admin: BuAdmin
  options: UnitOption[]
  onClose: () => void
  onSaved: (name: string) => void
  onRemove: () => void
}

/** "Edit units" for one BU Admin (canvas EA 15; contract 1.16). */
export function EditUnitsDialog({
  admin,
  options,
  onClose,
  onSaved,
  onRemove,
}: EditUnitsDialogProps) {
  const save = useSetBuAdminUnits()
  const [formError, setFormError] = useState<string | null>(null)
  const {
    handleSubmit,
    control,
    setError,
    formState: { errors },
  } = useForm<EditUnitsValues>({
    resolver: zodResolver(editUnitsSchema),
    defaultValues: { bu_ids: admin.units.map((u) => u.bu_id) },
  })

  const onSubmit = handleSubmit(async ({ bu_ids }) => {
    setFormError(null)
    try {
      await save.mutateAsync({ userId: admin.user_id, buIds: bu_ids })
      onSaved(admin.full_name)
    } catch (err) {
      if (err instanceof ApiError && problemCode(err.problem) === 'unit-has-bu-admin') {
        return setError('bu_ids', {
          message: 'One of these units got another BU Admin meanwhile. Refresh and try again.',
        })
      }
      setFormError(errorMessage(err))
    }
  })

  return (
    <Dialog
      title="Edit units"
      onClose={onClose}
      footer={
        <>
          <Button variant="danger-link" className="mr-auto" onClick={onRemove}>
            Remove
          </Button>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" form="edit-units" disabled={save.isPending}>
            {save.isPending ? 'Saving…' : 'Save changes'}
          </Button>
        </>
      }
    >
      <form id="edit-units" noValidate onSubmit={onSubmit} className="flex flex-col gap-4">
        <Person name={admin.full_name} detail={`BU Admin · ${admin.email}`} />
        <Controller
          control={control}
          name="bu_ids"
          render={({ field }) => (
            <UnitChecklist
              legend="Units they run"
              options={options}
              value={field.value}
              onChange={field.onChange}
              error={errors.bu_ids?.message}
            />
          )}
        />
        <Alert tone="info">
          They switch between their units from the dashboard sidebar. The change is recorded in the
          audit log.
        </Alert>
        {formError && <Alert tone="danger">{formError}</Alert>}
      </form>
    </Dialog>
  )
}
