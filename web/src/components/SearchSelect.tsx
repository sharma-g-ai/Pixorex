import { useId, useMemo, useRef, useState, type KeyboardEvent } from 'react'

export interface SearchOption {
  value: string
  label: string
  /** Short line under the name, e.g. "3 open". */
  hint?: string
}

interface SearchSelectProps {
  label: string
  options: readonly SearchOption[]
  /** The picked option's value, or null. */
  value: string | null
  onChange: (value: string | null) => void
  placeholder?: string
  /** What to show before anything is typed. The list itself stays closed until then. */
  idleText?: string
  /** How many matches to list at once; the rest are reached by typing more. */
  maxResults?: number
}

/**
 * Pick ONE option by typing part of its name. The list stays closed until the person types,
 * and shows only the best matches, so it works the same for 5 options or 500.
 */
export function SearchSelect({
  label,
  options,
  value,
  onChange,
  placeholder = 'Search by name',
  idleText = 'Type a name to search.',
  maxResults = 6,
}: SearchSelectProps) {
  const id = useId()
  const inputRef = useRef<HTMLInputElement>(null)
  const picked = options.find((o) => o.value === value) ?? null
  const [query, setQuery] = useState('')
  const [open, setOpen] = useState(false)
  const [active, setActive] = useState(0)

  const term = query.trim().toLowerCase()
  const matches = useMemo(
    () => (term ? options.filter((o) => o.label.toLowerCase().includes(term)) : []),
    [options, term],
  )
  const shown = matches.slice(0, maxResults)
  const listOpen = open && term.length > 0

  const choose = (o: SearchOption) => {
    onChange(o.value)
    setQuery('')
    setOpen(false)
  }
  const clear = () => {
    onChange(null)
    setQuery('')
    inputRef.current?.focus()
  }
  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setOpen(true)
      setActive((a) => Math.min(a + 1, shown.length - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActive((a) => Math.max(a - 1, 0))
    } else if (e.key === 'Enter' && listOpen && shown[active]) {
      e.preventDefault()
      choose(shown[active])
    } else if (e.key === 'Escape' && listOpen) {
      e.stopPropagation() // closes the list, not the dialog around it
      setOpen(false)
    }
  }

  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="text-label font-bold tracking-wider text-ink-muted uppercase">
        {label}
      </label>
      {picked ? (
        <div className="flex items-center justify-between gap-3 rounded-lg border-[1.5px] border-brand-navy bg-brand-navy-tint px-3 py-2">
          <span className="min-w-0">
            <span className="block truncate text-body font-bold">{picked.label}</span>
            {picked.hint && <span className="block text-meta text-ink-muted">{picked.hint}</span>}
          </span>
          <button
            type="button"
            className="shrink-0 text-meta font-semibold text-brand-navy hover:underline"
            aria-label={`Change ${label.toLowerCase()}`}
            onClick={clear}
          >
            Change
          </button>
        </div>
      ) : (
        <div className="relative">
          <input
            ref={inputRef}
            id={id}
            type="text"
            role="combobox"
            autoComplete="off"
            aria-expanded={listOpen}
            aria-controls={`${id}-list`}
            aria-autocomplete="list"
            aria-activedescendant={listOpen && shown[active] ? `${id}-${active}` : undefined}
            className="w-full rounded-lg border-[1.5px] border-line-strong bg-surface px-3 py-2 text-body outline-none focus:border-brand-navy"
            placeholder={placeholder}
            value={query}
            onChange={(e) => {
              setQuery(e.target.value)
              setActive(0)
              setOpen(true)
            }}
            onFocus={() => setOpen(true)}
            onKeyDown={onKeyDown}
          />
          {listOpen && (
            <ul
              id={`${id}-list`}
              role="listbox"
              aria-label={label}
              className="absolute z-10 mt-1 max-h-60 w-full overflow-y-auto rounded-lg border border-line bg-surface py-1 shadow-lg"
            >
              {shown.length === 0 ? (
                <li className="px-3 py-2 text-body text-ink-muted">
                  No match for “{query.trim()}”
                </li>
              ) : (
                shown.map((o, i) => (
                  <li
                    key={o.value}
                    id={`${id}-${i}`}
                    role="option"
                    aria-selected={i === active}
                    className={`cursor-pointer px-3 py-2 ${i === active ? 'bg-brand-navy-tint' : ''}`}
                    onMouseDown={(e) => e.preventDefault()} // keep the input focused
                    onClick={() => choose(o)}
                    onMouseEnter={() => setActive(i)}
                  >
                    <span className="block text-body font-semibold">{o.label}</span>
                    {o.hint && <span className="block text-meta text-ink-muted">{o.hint}</span>}
                  </li>
                ))
              )}
              {matches.length > shown.length && (
                <li className="px-3 py-1.5 text-meta text-ink-subtle">
                  {matches.length - shown.length} more — keep typing to narrow down
                </li>
              )}
            </ul>
          )}
        </div>
      )}
      {!picked && !listOpen && <p className="text-meta text-ink-subtle">{idleText}</p>}
    </div>
  )
}
