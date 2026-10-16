import { useEffect, useId, useState } from 'react'
import type { UnitRole } from '../../api/me'
import { Icon } from '../icons'
import { ContextCard, ContextCardText } from './ContextCard'

interface UnitSwitcherProps {
  units: UnitRole[]
  current: UnitRole
  onSelect: (buId: string) => void
  /** True while a switch is being saved. */
  busy?: boolean
}

/** BU Admin unit picker at the top of the sidebar (canvas: BU unit menu). */
export function UnitSwitcher({ units, current, onSelect, busy = false }: UnitSwitcherProps) {
  const [open, setOpen] = useState(false)
  const menuId = useId()
  const label = `Business unit · ${units.length}`
  const title = current.name ?? 'Unnamed unit'

  useEffect(() => {
    if (!open) return
    const close = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    document.addEventListener('keydown', close)
    return () => document.removeEventListener('keydown', close)
  }, [open])

  if (units.length < 2) return <ContextCard label={label} title={title} />

  const choose = (buId: string | null) => {
    setOpen(false)
    if (buId && buId !== current.bu_id) onSelect(buId)
  }

  return (
    <div className="relative">
      <button
        type="button"
        title="Switch business unit"
        aria-label={`Switch business unit. Current: ${title}`}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={menuId}
        disabled={busy}
        onClick={() => setOpen((v) => !v)}
        className="flex w-full items-center justify-between gap-2 rounded-lg bg-white/10 px-3 py-2.5 text-left hover:bg-white/15 disabled:opacity-60"
      >
        <ContextCardText label={label} title={title} />
        <Icon name="chevron-down" size={15} className="shrink-0 text-white/70" />
      </button>

      {open && (
        <>
          <button
            type="button"
            aria-label="Close unit menu"
            className="fixed inset-0 z-10 cursor-default bg-ink/10"
            onClick={() => setOpen(false)}
          />
          <div
            id={menuId}
            role="menu"
            aria-label="Your business units"
            className="absolute top-full left-0 z-20 mt-2 w-80 overflow-hidden rounded-xl border border-line bg-surface shadow-2xl"
          >
            <div className="px-3.5 pt-3 pb-1.5 text-caption font-bold tracking-wider text-ink-subtle uppercase">
              Your business units
            </div>
            {units.map((unit) => {
              const selected = unit.bu_id === current.bu_id
              return (
                <button
                  key={unit.bu_id}
                  type="button"
                  role="menuitemradio"
                  aria-checked={selected}
                  onClick={() => choose(unit.bu_id)}
                  className={`flex w-full items-center justify-between gap-2.5 px-3.5 py-2.5 text-left text-body ${
                    selected ? 'bg-brand-navy-tint font-bold' : 'font-semibold hover:bg-page'
                  }`}
                >
                  {unit.name ?? 'Unnamed unit'}
                  {selected && <Icon name="check" size={14} className="text-brand-navy" />}
                </button>
              )
            })}
            <p className="border-t border-line-soft px-3.5 pt-2.5 pb-3 text-xs leading-snug text-ink-muted">
              Everything you see (review queue, delegations, equipment types, technicians) is for
              the unit you pick. Your Enterprise Admin decides which units you run.
            </p>
          </div>
        </>
      )}
    </div>
  )
}
