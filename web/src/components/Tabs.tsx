export interface Tab<Key extends string> {
  key: Key
  label: string
  /** Optional count shown after the label. */
  count?: number
}

interface TabsProps<Key extends string> {
  label: string
  tabs: Tab<Key>[]
  current: Key
  onChange: (key: Key) => void
  /** 'pills': rounded chips, e.g. the unit filter on Scans (canvas EA 20). */
  look?: 'underline' | 'pills'
}

const looks = {
  underline: {
    row: 'flex gap-1 border-b border-line',
    tab: '-mb-px border-b-2 px-3.5 py-2.5 text-body font-semibold',
    on: 'border-brand-navy text-brand-navy',
    off: 'border-transparent text-ink-muted hover:text-ink',
  },
  pills: {
    row: 'flex flex-wrap gap-2',
    tab: 'rounded-full border px-3.25 py-1.75 text-small font-semibold',
    on: 'border-brand-navy bg-brand-navy text-surface',
    off: 'border-line bg-surface text-ink hover:border-line-strong',
  },
}

/** Row of tab buttons; the page shows the matching content below. */
export function Tabs<Key extends string>({
  label,
  tabs,
  current,
  onChange,
  look = 'underline',
}: TabsProps<Key>) {
  const style = looks[look]
  return (
    <div role="tablist" aria-label={label} className={style.row}>
      {tabs.map((tab) => {
        const selected = tab.key === current
        return (
          <button
            key={tab.key}
            type="button"
            role="tab"
            aria-selected={selected}
            onClick={() => onChange(tab.key)}
            className={`${style.tab} ${selected ? style.on : style.off}`}
          >
            {tab.label}
            {tab.count !== undefined && (
              <span
                className={
                  look === 'pills' ? 'ml-1' : 'ml-1.5 rounded-full bg-page px-1.5 text-caption'
                }
              >
                {look === 'pills' ? `· ${tab.count}` : tab.count}
              </span>
            )}
          </button>
        )
      })}
    </div>
  )
}
