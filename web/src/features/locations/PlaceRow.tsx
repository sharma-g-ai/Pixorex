import { useState, type FormEvent, type ReactNode } from 'react'
import { errorMessage } from '../../api/client'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { TextField } from '../../components/TextField'

interface PlaceRowProps {
  /** Used to scroll to the row ("Show me" in Review & publish). */
  id?: string
  name: string
  kind: string
  /** How deep in the tree: 0 is the top place. */
  depth: number
  /** What is wrong with this place; it tints the row. */
  warning?: string
  highlighted?: boolean
  /** Present when the place has something inside: opens and closes it. */
  fold?: { closed: boolean; onToggle: () => void }
  /** Present while renaming: saves the new name. */
  rename?: { startEmpty: boolean; onSave: (name: string) => Promise<void>; onCancel: () => void }
  /** Present when something can be added inside this place: the button before the "⋯". */
  onAddInside?: () => void
  /** The row's other actions, on the right (its "⋯" menu). */
  children?: ReactNode
}

/** One place in the location tree: its name, its kind, what it needs, and its actions. */
export function PlaceRow({
  id,
  name,
  kind,
  depth,
  warning,
  highlighted = false,
  fold,
  rename,
  onAddInside,
  children,
}: PlaceRowProps) {
  return (
    <div
      id={id}
      className={`flex flex-wrap items-center justify-between gap-x-3.5 gap-y-1 border-b border-line-soft py-2.5 pr-4.5 text-body ${
        // The row lights up under the pointer, so its actions on the far right clearly belong
        // to it; a row to fix keeps its tint.
        warning ? 'bg-warning-soft' : 'hover:bg-page focus-within:bg-page'
      } ${highlighted ? 'outline-2 -outline-offset-2 outline-brand-navy' : ''}`}
      style={{ paddingLeft: `calc(var(--spacing) * ${4.5 + depth * 5})` }}
    >
      <div className="flex min-w-0 grow basis-48 items-center gap-2">
        {fold ? (
          <button
            type="button"
            className="w-4 shrink-0 text-ink-muted"
            aria-expanded={!fold.closed}
            aria-label={`${fold.closed ? 'Open' : 'Close'} ${name}`}
            onClick={fold.onToggle}
          >
            {fold.closed ? '▸' : '▾'}
          </button>
        ) : (
          <span className="w-4 shrink-0" />
        )}
        {rename ? (
          <RenameInline name={name} {...rename} />
        ) : (
          <div className="min-w-0">
            <div className="flex min-w-0 items-baseline gap-2.5">
              <span className="truncate font-semibold" title={name}>
                {name}
              </span>
              <span className="shrink-0 text-meta text-ink-muted">{kind}</span>
            </div>
            {warning && <div className="text-xs font-semibold text-warning">⚠ {warning}</div>}
          </div>
        )}
      </div>
      {!rename && (onAddInside || children) && (
        <div className="flex shrink-0 items-center gap-x-3">
          {/* Right side, before the "⋯": the main thing to do in a row, always in the same
              place, so the names on the left stay easy to scan. */}
          {onAddInside && (
            <button
              type="button"
              className={buttonClasses('link')}
              aria-label={`Add inside ${name}`}
              onClick={onAddInside}
            >
              + Add inside
            </button>
          )}
          {children}
        </div>
      )}
    </div>
  )
}

/** Rename in the row itself (contract 2.5). A temporary name starts empty. */
function RenameInline({
  name,
  startEmpty,
  onSave,
  onCancel,
}: { name: string } & NonNullable<PlaceRowProps['rename']>) {
  const [value, setValue] = useState(startEmpty ? '' : name)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (!value.trim()) return setError('Enter a name.')
    setBusy(true)
    onSave(value.trim()).catch((err: unknown) => {
      setError(errorMessage(err))
      setBusy(false)
    })
  }

  return (
    <form className="flex min-w-0 grow flex-wrap items-start gap-2" onSubmit={submit}>
      <TextField
        label={`New name for ${name}`}
        hideLabel
        className="min-w-40 grow"
        autoFocus
        value={value}
        error={error ?? undefined}
        onChange={(e) => setValue(e.target.value)}
      />
      <Button type="submit" disabled={busy}>
        {busy ? 'Saving…' : 'Save name'}
      </Button>
      <Button variant="secondary" onClick={onCancel}>
        Cancel
      </Button>
    </form>
  )
}
