import {
  useCallback,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { createPortal } from 'react-dom'
import { Button } from './Button'
import { buttonClasses } from './buttonClasses'
import { Icon } from './icons'

/**
 * Filters and sorting in a table's column headers: a funnel that opens a small panel, a sort
 * arrow, and a row of chips saying what is applied. The panel is drawn in a portal so the
 * table's rounded edge never clips it.
 */

interface ColumnFilterProps {
  /** The column's name, for screen readers ("Filter by Schema"). */
  label: string
  /** A filter is applied: the funnel turns navy. */
  active: boolean
  /** Which edge of the funnel the panel lines up with. */
  align?: 'left' | 'right'
  /** The panel's contents; [close] closes it and puts focus back on the funnel. */
  children: (close: () => void) => ReactNode
}

const PANEL_WIDTH = 264

export function ColumnFilter({ label, active, align = 'left', children }: ColumnFilterProps) {
  const [open, setOpen] = useState(false)
  const [spot, setSpot] = useState<{ top: number; left: number } | null>(null)
  const button = useRef<HTMLButtonElement>(null)
  const panel = useRef<HTMLDivElement>(null)
  const panelId = useId()

  const place = useCallback(() => {
    const rect = button.current?.getBoundingClientRect()
    if (!rect) return
    const wanted = align === 'right' ? rect.right - PANEL_WIDTH : rect.left
    const left = Math.max(8, Math.min(wanted, window.innerWidth - PANEL_WIDTH - 8))
    setSpot({ top: rect.bottom + 6, left })
  }, [align])

  // Done and Escape put focus back on the funnel; a click elsewhere leaves it where it landed.
  // Closing only counts up here; the effect below does the focusing (no ref is touched in close).
  const [focusBack, setFocusBack] = useState(0)
  const close = useCallback(() => {
    setOpen(false)
    setFocusBack((n) => n + 1)
  }, [])
  useEffect(() => {
    if (focusBack > 0) button.current?.focus()
  }, [focusBack])

  useLayoutEffect(() => {
    if (!open) return
    place()
    window.addEventListener('resize', place)
    window.addEventListener('scroll', place, true)
    return () => {
      window.removeEventListener('resize', place)
      window.removeEventListener('scroll', place, true)
    }
  }, [open, place])

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close()
    }
    const onPointer = (e: MouseEvent) => {
      const target = e.target as Node
      if (panel.current?.contains(target) || button.current?.contains(target)) return
      setOpen(false)
    }
    document.addEventListener('keydown', onKey)
    document.addEventListener('mousedown', onPointer)
    return () => {
      document.removeEventListener('keydown', onKey)
      document.removeEventListener('mousedown', onPointer)
    }
  }, [open, close])

  useEffect(() => {
    if (open && spot) {
      panel.current
        ?.querySelector<HTMLElement>('input:not([disabled]), button:not([disabled])')
        ?.focus()
    }
    // Focus once when the panel first appears, not on every move.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, spot === null])

  return (
    <>
      <button
        ref={button}
        type="button"
        aria-label={`Filter by ${label}`}
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-controls={open ? panelId : undefined}
        data-active={active ? 'true' : undefined}
        onClick={() => setOpen((o) => !o)}
        className={`grid size-6 place-items-center rounded-md hover:bg-page ${
          active ? 'bg-brand-navy-soft text-brand-navy' : 'text-ink-subtle'
        }`}
      >
        <Icon name="filter" size={13} />
      </button>
      {open &&
        spot &&
        createPortal(
          <div
            ref={panel}
            id={panelId}
            role="dialog"
            aria-label={`${label} filter`}
            style={{ top: spot.top, left: spot.left, width: PANEL_WIDTH }}
            className="fixed z-50 rounded-xl border border-line bg-surface p-3.5 text-body font-normal tracking-normal text-ink normal-case shadow-xl"
          >
            {children(close)}
          </div>,
          document.body,
        )}
    </>
  )
}

interface Option {
  value: string
  label: string
}

interface CheckListProps {
  title: string
  options: Option[]
  selected: string[]
  onChange: (values: string[]) => void
  onDone: () => void
  /** A search box above the choices, for long lists. */
  searchable?: boolean
}

/** Tick one or more choices; nothing ticked means no filter. */
export function CheckListFilter({
  title,
  options,
  selected,
  onChange,
  onDone,
  searchable = false,
}: CheckListProps) {
  const [query, setQuery] = useState('')
  const shown = options.filter((o) => o.label.toLowerCase().includes(query.trim().toLowerCase()))
  const toggle = (value: string, on: boolean) =>
    onChange(on ? [...selected, value] : selected.filter((v) => v !== value))
  return (
    <div className="flex flex-col gap-2.5">
      <h3 className="text-label font-bold tracking-wider text-ink-muted uppercase">{title}</h3>
      {searchable && (
        <input
          type="search"
          aria-label={`Search ${title}`}
          placeholder="Search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="h-9 rounded-lg border-[1.5px] border-line-strong px-2.5 text-small outline-none focus:border-brand-navy"
        />
      )}
      <div role="group" aria-label={title} className="flex max-h-48 flex-col overflow-y-auto">
        {shown.length === 0 && <p className="py-2 text-small text-ink-muted">Nothing found.</p>}
        {shown.map((o) => (
          <label key={o.value} className="flex cursor-pointer items-center gap-2.5 py-1.5">
            <input
              type="checkbox"
              className="size-4 accent-brand-navy"
              checked={selected.includes(o.value)}
              onChange={(e) => toggle(o.value, e.target.checked)}
            />
            <span className="min-w-0 truncate text-small">{o.label}</span>
          </label>
        ))}
      </div>
      <div className="flex items-center justify-between">
        <button
          type="button"
          className={buttonClasses('link')}
          disabled={selected.length === 0}
          onClick={() => onChange([])}
        >
          Clear
        </button>
        <Button onClick={onDone}>Done</Button>
      </div>
    </div>
  )
}

interface TextSearchProps {
  title: string
  value: string
  onChange: (value: string) => void
  onDone: () => void
  placeholder?: string
  hint?: string
}

/** One box to type in; the list follows after a short pause, so each key is not a request. */
export function TextSearchFilter({
  title,
  value,
  onChange,
  onDone,
  placeholder = 'Search',
  hint,
}: TextSearchProps) {
  const [text, setText] = useState(value)
  const sent = useRef(value)
  useEffect(() => {
    if (text === sent.current) return
    const timer = setTimeout(() => {
      sent.current = text
      onChange(text)
    }, 300)
    return () => clearTimeout(timer)
  }, [text, onChange])
  const finish = () => {
    sent.current = text
    onChange(text)
    onDone()
  }
  return (
    <form
      className="flex flex-col gap-2.5"
      onSubmit={(e) => {
        e.preventDefault()
        finish()
      }}
    >
      <h3 className="text-label font-bold tracking-wider text-ink-muted uppercase">{title}</h3>
      <input
        type="search"
        aria-label={`Search ${title}`}
        placeholder={placeholder}
        value={text}
        onChange={(e) => setText(e.target.value)}
        className="h-9 rounded-lg border-[1.5px] border-line-strong px-2.5 text-small outline-none focus:border-brand-navy"
      />
      {hint && <p className="text-caption text-ink-subtle">{hint}</p>}
      <div className="flex items-center justify-between">
        <button
          type="button"
          className={buttonClasses('link')}
          disabled={!text && !value}
          onClick={() => {
            setText('')
            sent.current = ''
            onChange('')
          }}
        >
          Clear
        </button>
        <Button type="submit">Done</Button>
      </div>
    </form>
  )
}

export interface DayRange {
  from: string
  to: string
}

interface DateRangeProps {
  title: string
  value: DayRange
  onChange: (range: DayRange) => void
  onDone: () => void
  hint?: string
  /** Last day that can be picked (the latest Indian day), YYYY-MM-DD. */
  max?: string
}

/** From and To dates only. A side left empty has no limit. */
export function DateRangeFilter({ title, value, onChange, onDone, hint, max }: DateRangeProps) {
  const fromId = useId()
  const toId = useId()
  // Moving one date past the other drags the other with it, so the range is never backwards.
  const setFrom = (from: string) =>
    onChange({ from, to: from && value.to && from > value.to ? from : value.to })
  const setTo = (to: string) =>
    onChange({ to, from: to && value.from && to < value.from ? to : value.from })
  const field =
    'h-9 w-full rounded-lg border-[1.5px] border-line-strong px-2 text-small outline-none focus:border-brand-navy'
  return (
    <div className="flex flex-col gap-2.5">
      <h3 className="text-label font-bold tracking-wider text-ink-muted uppercase">{title}</h3>
      <div className="grid grid-cols-2 gap-2.5">
        <div>
          <label htmlFor={fromId} className="mb-1 block text-caption text-ink-muted">
            From
          </label>
          <input
            id={fromId}
            type="date"
            max={max}
            value={value.from}
            onChange={(e) => setFrom(e.target.value)}
            className={field}
          />
        </div>
        <div>
          <label htmlFor={toId} className="mb-1 block text-caption text-ink-muted">
            To
          </label>
          <input
            id={toId}
            type="date"
            max={max}
            value={value.to}
            onChange={(e) => setTo(e.target.value)}
            className={field}
          />
        </div>
      </div>
      {hint && <p className="text-caption text-ink-subtle">{hint}</p>}
      <div className="flex items-center justify-between">
        <button
          type="button"
          className={buttonClasses('link')}
          disabled={!value.from && !value.to}
          onClick={() => onChange({ from: '', to: '' })}
        >
          Clear
        </button>
        <Button onClick={onDone}>Done</Button>
      </div>
    </div>
  )
}

interface SortToggleProps {
  /** The column's name, for screen readers. */
  label: string
  /** 'oldest_first' shows an up arrow, 'newest_first' a down arrow. */
  direction: 'oldest_first' | 'newest_first'
  onToggle: () => void
}

/** The sort arrow next to a date column's name. Only that column sorts. */
export function SortToggle({ label, direction, onToggle }: SortToggleProps) {
  const oldest = direction === 'oldest_first'
  const now = oldest ? 'oldest first' : 'newest first'
  const next = oldest ? 'newest first' : 'oldest first'
  return (
    <button
      type="button"
      onClick={onToggle}
      title={`${label}: ${now}. Click for ${next}.`}
      aria-label={`Sort by ${label}, ${now}. Click for ${next}.`}
      className="grid size-6 place-items-center rounded-md text-ink-muted hover:bg-page"
    >
      <span aria-hidden="true" className="text-[10px] leading-none">
        {oldest ? '▲' : '▼'}
      </span>
    </button>
  )
}

interface ColumnHeaderProps {
  label: string
  children?: ReactNode
}

/** A column name with its controls (sort arrow, funnel) beside it. */
export function ColumnHeader({ label, children }: ColumnHeaderProps) {
  return (
    <span className="inline-flex items-center gap-0.5">
      {label}
      {children}
    </span>
  )
}

export interface Chip {
  key: string
  text: string
  onRemove: () => void
}

/** What a list is filtered by, each with a ✕, and "Clear all" once there are two or more. */
export function FilterChips({ chips, onClearAll }: { chips: Chip[]; onClearAll: () => void }) {
  if (chips.length === 0) return null
  return (
    <ul aria-label="Filters applied" className="flex flex-wrap items-center gap-2">
      {chips.map((c) => (
        <li
          key={c.key}
          className="flex items-center gap-1.5 rounded-full bg-brand-navy-soft py-0.5 pr-1 pl-3 text-meta font-semibold text-brand-navy"
        >
          {c.text}
          <button
            type="button"
            aria-label={`Remove filter ${c.text}`}
            className="grid size-5 place-items-center rounded-full hover:bg-brand-navy/10"
            onClick={c.onRemove}
          >
            ✕
          </button>
        </li>
      ))}
      {chips.length > 1 && (
        <li>
          <button type="button" className={buttonClasses('link')} onClick={onClearAll}>
            Clear all
          </button>
        </li>
      )}
    </ul>
  )
}
