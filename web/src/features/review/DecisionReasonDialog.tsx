import { useState, type ReactNode } from 'react'
import type { RejectCategory } from '../../api/review'
import { ChoiceCard } from '../../components/ChoiceCard'
import { ConfirmDialog } from '../../components/ConfirmDialog'
import { TextAreaField } from '../../components/TextAreaField'
import { rejectCategoryLabels } from './reviewRules'

interface DecisionReasonDialogProps {
  title: string
  confirmLabel: string
  noteLabel: string
  /** Text above the categories, e.g. "The scan changes from Approved to Rejected." */
  intro?: ReactNode
  /** Text under the note, e.g. who is told. */
  outro?: ReactNode
  onSubmit: (category: RejectCategory, note: string) => Promise<unknown>
  onClose: () => void
}

/**
 * Reject or override with a category and a note (canvas BU 21 "Reject this scan",
 * BU 23 "Override ... approval"; contracts 3.5, 3.7).
 */
export function DecisionReasonDialog({
  title,
  confirmLabel,
  noteLabel,
  intro,
  outro,
  onSubmit,
  onClose,
}: DecisionReasonDialogProps) {
  const [category, setCategory] = useState<RejectCategory | null>(null)
  const [note, setNote] = useState('')

  return (
    <ConfirmDialog
      title={title}
      confirmLabel={confirmLabel}
      danger
      disabled={category === null}
      onClose={onClose}
      onConfirm={() => (category ? onSubmit(category, note.trim()) : Promise.resolve())}
    >
      <div className="flex flex-col gap-3.5">
        {intro && <p>{intro}</p>}
        <fieldset className="grid grid-cols-2 gap-2">
          <legend className="mb-1.5 text-small font-semibold text-ink-muted">Reason</legend>
          {(Object.keys(rejectCategoryLabels) as RejectCategory[]).map((key) => (
            <ChoiceCard
              key={key}
              name="reject-category"
              title={rejectCategoryLabels[key]}
              checked={category === key}
              onChange={() => setCategory(key)}
            />
          ))}
        </fieldset>
        <TextAreaField label={noteLabel} value={note} onChange={(e) => setNote(e.target.value)} />
        {outro && <p className="text-small">{outro}</p>}
      </div>
    </ConfirmDialog>
  )
}
