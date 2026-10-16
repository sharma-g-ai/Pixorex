import { useRemoveTechnician, type Technician } from '../../api/technicians'
import { ConfirmDialog } from '../../components/ConfirmDialog'

interface RemoveTechnicianDialogProps {
  technician: Technician
  buId: string
  unitName: string
  onClose: () => void
  onRemoved: (name: string) => void
}

/** "Remove T. Nguyen from Plant 04?" confirmation (canvas BU 27; contract 1.19). */
export function RemoveTechnicianDialog({
  technician,
  buId,
  unitName,
  onClose,
  onRemoved,
}: RemoveTechnicianDialogProps) {
  const remove = useRemoveTechnician(buId)
  const name = technician.full_name

  return (
    <ConfirmDialog
      title={`Remove ${name} from ${unitName}?`}
      confirmLabel="Remove technician"
      danger
      onClose={onClose}
      onConfirm={async () => {
        await remove.mutateAsync(technician.user_id)
        onRemoved(name)
      }}
    >
      <ul className="flex list-inside list-disc flex-col gap-2">
        <li>
          {name} is signed out of the app for {unitName} straight away.
        </li>
        {technician.active_batch_no && (
          <li>
            Their delegated batch ({technician.active_batch_no}) comes back to your review queue.
          </li>
        )}
        <li>Scans they already captured and decisions they made stay, with their name.</li>
        <li>Recorded in the audit log.</li>
      </ul>
    </ConfirmDialog>
  )
}
