import { useState, type FormEvent } from 'react'
import { errorMessage } from '../../api/client'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { SelectField } from '../../components/SelectField'
import { TextField } from '../../components/TextField'
import { MAX_NAMES, typedNames, type AddChoice } from './locationTree'

interface AddInsideProps {
  parentName: string
  /** The kinds that may go straight inside this place; the first is the usual one. */
  choices: AddChoice[]
  /** Names already used inside this place. */
  siblings: string[]
  busy: boolean
  onAdd: (kind: string, names: string[], idempotencyKey: string) => Promise<void>
  onCancel: () => void
}

/** "Add inside", in the row itself: what kind, and one or several names (contract 2.4). */
export function AddInside({
  parentName,
  choices,
  siblings,
  busy,
  onAdd,
  onCancel,
}: AddInsideProps) {
  const [kind, setKind] = useState(choices[0]?.level_name ?? '')
  const [text, setText] = useState('')
  const [error, setError] = useState<string | null>(null)
  // One key per request as typed: a retried add can never create the places twice, and a
  // changed one is a new request.
  const [idempotencyKey, setKey] = useState(() => crypto.randomUUID())
  const typed = (change: () => void) => {
    change()
    setKey(crypto.randomUUID())
  }
  const names = typedNames(text)

  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (names.length === 0) return setError('Type at least one name.')
    if (names.length > MAX_NAMES)
      return setError(`That is more than ${MAX_NAMES} names. Add up to ${MAX_NAMES} at a time.`)
    const taken = new Set(siblings.map((s) => s.toLowerCase()))
    const twice = names.find((n, i) => {
      const lower = n.toLowerCase()
      return taken.has(lower) || names.findIndex((x) => x.toLowerCase() === lower) !== i
    })
    if (twice) return setError(`${twice} already exists here.`)
    setError(null)
    onAdd(kind, names, idempotencyKey).catch((err: unknown) => setError(errorMessage(err)))
  }

  return (
    <form
      aria-label={`Add inside ${parentName}`}
      className="flex flex-wrap items-end gap-2.5 border-b border-line-soft bg-brand-navy-tint px-4.5 py-3"
      onSubmit={submit}
    >
      <SelectField
        label="What you are adding"
        className="w-44"
        options={choices.map((c) => ({ value: c.level_name, label: c.level_name }))}
        value={kind}
        onChange={(e) => typed(() => setKind(e.target.value))}
      />
      <TextField
        label={`Names, inside ${parentName}`}
        className="min-w-60 grow basis-60"
        placeholder={`${kind} 01, ${kind} 02`}
        autoFocus
        value={text}
        onChange={(e) => typed(() => setText(e.target.value))}
      />
      <Button type="submit" disabled={busy}>
        {busy ? 'Adding…' : 'Add'}
      </Button>
      <Button variant="secondary" onClick={onCancel}>
        Cancel
      </Button>
      <p className="basis-full text-xs text-ink-muted">
        {names.length > 1 && names.length <= MAX_NAMES ? (
          <>
            Adds {names.length}: <b className="text-ink">{names[0]}</b> …{' '}
            <b className="text-ink">{names[names.length - 1]}</b>
          </>
        ) : (
          `Several at once: separate them with commas, or type a range like ${kind} 01-20 (up to ${MAX_NAMES}).`
        )}
      </p>
      {error && (
        <Alert tone="danger" className="basis-full">
          {error}
        </Alert>
      )}
    </form>
  )
}
