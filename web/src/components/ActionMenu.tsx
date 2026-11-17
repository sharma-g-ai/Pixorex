import { useEffect, useId, useRef, useState, type KeyboardEvent } from 'react'

export interface MenuAction {
  label: string
  onSelect: () => void
  /** Red text for a destructive action. */
  danger?: boolean
}

interface ActionMenuProps {
  /** Accessible name of the button, e.g. "More for Building C". */
  label: string
  actions: MenuAction[]
}

type Place = { right: number; top?: number; bottom?: number }

// Room one action needs, to decide whether the list fits under the button.
const ACTION_HEIGHT = 40

/**
 * "⋯" button that opens a short list of actions for one row, so the row itself stays clean.
 * Same behaviour as the unit switcher's menu: click outside or Esc closes it. The list is
 * placed on the screen, not inside the row, so a table or list that clips its content can't
 * cut it off; it opens upwards when there is no room below.
 */
export function ActionMenu({ label, actions }: ActionMenuProps) {
  const [place, setPlace] = useState<Place | null>(null)
  const button = useRef<HTMLButtonElement>(null)
  const list = useRef<HTMLDivElement>(null)
  const menuId = useId()

  useEffect(() => {
    if (!place) return
    list.current?.querySelector('button')?.focus()
    const close = () => setPlace(null)
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key !== 'Escape') return
      close()
      button.current?.focus()
    }
    document.addEventListener('keydown', onKey)
    // The list does not follow its row: close it when the page moves under it.
    window.addEventListener('scroll', close, true)
    window.addEventListener('resize', close)
    return () => {
      document.removeEventListener('keydown', onKey)
      window.removeEventListener('scroll', close, true)
      window.removeEventListener('resize', close)
    }
  }, [place])

  const open = () => {
    const rect = button.current?.getBoundingClientRect()
    if (!rect) return
    const right = window.innerWidth - rect.right
    const fitsBelow = window.innerHeight - rect.bottom > actions.length * ACTION_HEIGHT + 16
    setPlace(
      fitsBelow
        ? { right, top: rect.bottom + 4 }
        : { right, bottom: window.innerHeight - rect.top + 4 },
    )
  }

  /** Arrow keys, Home and End move between the actions. */
  const move = (e: KeyboardEvent) => {
    const items = Array.from(list.current?.querySelectorAll('button') ?? [])
    const at = items.indexOf(document.activeElement as HTMLButtonElement)
    const to =
      e.key === 'ArrowDown'
        ? (at + 1) % items.length
        : e.key === 'ArrowUp'
          ? (at - 1 + items.length) % items.length
          : e.key === 'Home'
            ? 0
            : e.key === 'End'
              ? items.length - 1
              : -1
    if (to < 0) return
    e.preventDefault()
    items[to]?.focus()
  }

  return (
    <>
      <button
        ref={button}
        type="button"
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={place !== null}
        aria-controls={place ? menuId : undefined}
        className="rounded-md px-2 text-lg leading-7 font-bold text-ink-muted hover:bg-page hover:text-ink aria-expanded:bg-page aria-expanded:text-ink"
        onClick={() => (place ? setPlace(null) : open())}
      >
        ⋯
      </button>
      {place && (
        <>
          <button
            type="button"
            aria-label="Close menu"
            tabIndex={-1}
            className="fixed inset-0 z-10 cursor-default"
            onClick={() => setPlace(null)}
          />
          <div
            ref={list}
            id={menuId}
            role="menu"
            aria-label={label}
            className="fixed z-20 min-w-36 overflow-hidden rounded-lg border border-line bg-surface py-1 shadow-2xl"
            style={place}
            onKeyDown={move}
          >
            {actions.map((action) => (
              <button
                key={action.label}
                type="button"
                role="menuitem"
                className={`block w-full px-3.5 py-2 text-left text-body font-semibold hover:bg-page focus-visible:bg-page ${
                  action.danger ? 'text-danger' : 'text-ink'
                }`}
                onClick={() => {
                  setPlace(null)
                  action.onSelect()
                }}
              >
                {action.label}
              </button>
            ))}
          </div>
        </>
      )}
    </>
  )
}
