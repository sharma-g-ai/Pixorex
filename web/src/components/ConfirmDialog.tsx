import { useState, type ReactNode } from 'react'
import { errorMessage } from '../api/client'
import { Alert } from './Alert'
import { Button } from './Button'
import { Dialog } from './Dialog'

interface ConfirmDialogProps {
  title: string
  /** Button text, e.g. "Yes, delete" or "Publish and lock". */
  confirmLabel: string
  /** Red button for destructive actions. */
  danger?: boolean
  cancelLabel?: string
  /** Runs the action; an error it throws is shown in the dialog. */
  onConfirm: () => Promise<unknown>
  onClose: () => void
  /** Blocks the button, e.g. while checks fail. */
  disabled?: boolean
  children: ReactNode
}

/** "Are you sure?" dialog with one action; shows busy state and any error. */
export function ConfirmDialog({
  title,
  confirmLabel,
  danger = false,
  cancelLabel = 'Cancel',
  onConfirm,
  onClose,
  disabled = false,
  children,
}: ConfirmDialogProps) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const confirm = async () => {
    setBusy(true)
    setError(null)
    try {
      await onConfirm()
    } catch (err) {
      setError(errorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Dialog
      title={title}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            {cancelLabel}
          </Button>
          <Button
            variant={danger ? 'danger' : 'primary'}
            disabled={busy || disabled}
            onClick={() => void confirm()}
          >
            {busy ? 'Working…' : confirmLabel}
          </Button>
        </>
      }
    >
      {children}
      {error && (
        <Alert tone="danger" className="mt-3">
          {error}
        </Alert>
      )}
    </Dialog>
  )
}
