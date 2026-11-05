import { useState, type ReactNode } from 'react'
import { daysAgo } from '../data/queries'
import { NOW } from '../data/sample'
import { SelectField } from './SelectField'
import { TextField } from './TextField'

export interface Period {
  from: string
  to: string
  controls: ReactNode
}

const TODAY = NOW.slice(0, 10)

const presets: Record<string, { label: string; from: string; to: string }> = {
  '30d': { label: 'Last 30 days', from: daysAgo(29), to: TODAY },
  'this-month': { label: 'October 2026', from: '2026-10-01', to: TODAY },
  'last-month': { label: 'September 2026', from: '2026-09-01', to: '2026-09-30' },
}

/** Date range with month presets (A-07: monthly reporting accuracy is acceptable). */
export function usePeriod(initial: keyof typeof presets = '30d'): Period {
  const [preset, setPreset] = useState<string>(initial)
  const [from, setFrom] = useState(presets[initial]?.from ?? TODAY)
  const [to, setTo] = useState(presets[initial]?.to ?? TODAY)

  const controls = (
    <>
      <SelectField
        label="Period"
        className="w-44"
        value={preset}
        onChange={(e) => {
          setPreset(e.target.value)
          const p = presets[e.target.value]
          if (p) {
            setFrom(p.from)
            setTo(p.to)
          }
        }}
        options={[
          ...Object.entries(presets).map(([value, p]) => ({ value, label: p.label })),
          { value: 'custom', label: 'Custom dates' },
        ]}
      />
      {preset === 'custom' && (
        <>
          <TextField
            label="From"
            type="date"
            className="w-40"
            value={from}
            max={to}
            onChange={(e) => {
              if (e.target.value) setFrom(e.target.value)
            }}
          />
          <TextField
            label="To"
            type="date"
            className="w-40"
            value={to}
            min={from}
            max={TODAY}
            onChange={(e) => {
              if (e.target.value) setTo(e.target.value)
            }}
          />
        </>
      )}
    </>
  )
  return { from, to, controls }
}
