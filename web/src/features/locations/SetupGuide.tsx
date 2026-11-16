import { useState } from 'react'
import type { Level } from '../../api/locations'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { ChoiceCard } from '../../components/ChoiceCard'
import { SelectField } from '../../components/SelectField'
import { TextField } from '../../components/TextField'
import { kindOptions, presets } from './locationTree'
import { guideProblems, startGuide, type GuidePart } from './guideRules'

interface SetupGuideProps {
  /** Kinds saved earlier, when the unit was set up half-way under the old screens. */
  levels: Level[]
  /** The unit's facility name: the first place. */
  siteName: string
  busy: boolean
  error: string | null
  onCreate: (parts: GuidePart[]) => void
}

const newPart = (): GuidePart => ({ place: '', kind: '', optional: false, level_id: null })

/**
 * Guided location setup on one screen: each part of one real place is a kind picked from the
 * standard menu and its name (plan section 4; decision 2026-11-16: one screen, no typed kinds).
 */
export function SetupGuide({ levels, siteName, busy, error, onCreate }: SetupGuideProps) {
  const [parts, setParts] = useState(() => startGuide(levels, siteName))
  const [problems, setProblems] = useState<string[]>([])

  const update = (index: number, patch: Partial<GuidePart>) =>
    setParts((all) => all.map((p, i) => (i === index ? { ...p, ...patch } : p)))
  const create = () => {
    const found = guideProblems(parts, levels)
    setProblems(found)
    if (found.length === 0) onCreate(parts)
  }
  const preset = presets[parts.length as keyof typeof presets]

  return (
    <Card title="Describe one place where equipment sits">
      <div className="flex flex-col gap-4">
        <p className="text-body text-ink-muted">
          Biggest to smallest, the way you would tell a new technician where to go. Pick the kind of
          each part and type its name, for example Facility: Plant 04 › Building: Building C › Bin:
          Bin 07. The kinds become the questions technicians answer on the phone.
        </p>
        {preset && (
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-small font-semibold text-ink-muted">Common setups</span>
            <Button
              variant="secondary"
              onClick={() =>
                setParts((all) =>
                  all.map((p, i) => ({
                    ...p,
                    kind: preset[i]?.level_name ?? p.kind,
                    optional: preset[i]?.requirement === 'optional',
                  })),
                )
              }
            >
              {preset.map((l) => l.level_name).join(' › ')}
            </Button>
          </div>
        )}
        <ol className="flex flex-col gap-2.5">
          {parts.map((p, i) => (
            <li key={i} className="flex flex-col gap-2 rounded-lg border border-line p-3">
              <div className="grid grid-cols-[minmax(0,1fr)_minmax(0,2fr)_auto] items-end gap-2.5">
                <SelectField
                  label={`Kind ${i + 1}`}
                  options={kindOptions(p.kind)}
                  value={p.kind}
                  onChange={(e) => update(i, { kind: e.target.value })}
                />
                <TextField
                  label={`Place ${i + 1}`}
                  value={p.place}
                  onChange={(e) => update(i, { place: e.target.value })}
                />
                <button
                  type="button"
                  className={`${buttonClasses('danger-link')} mb-2.5`}
                  aria-label={`Remove place ${i + 1}`}
                  disabled={i === 0 || parts.length <= 2}
                  onClick={() => setParts((all) => all.filter((_, j) => j !== i))}
                >
                  ✕
                </button>
              </div>
              {i > 0 && (
                <ChoiceCard
                  type="checkbox"
                  title={`Not every ${parts[i - 1]?.kind.trim() || 'place above'} has a ${p.kind.trim() || 'place like this'}`}
                  description="Technicians can skip this kind."
                  checked={p.optional}
                  onChange={(e) => update(i, { optional: e.target.checked })}
                />
              )}
            </li>
          ))}
        </ol>
        <div className="flex flex-wrap gap-2.5">
          <Button variant="secondary" onClick={() => setParts((all) => [...all, newPart()])}>
            + Add a smaller part
          </Button>
          <Button className="ml-auto" disabled={busy} onClick={create}>
            {busy ? 'Creating…' : 'Create and add more places'}
          </Button>
        </div>
        {problems.length > 0 && (
          <Alert tone="danger" role="alert">
            <ul className="flex flex-col gap-1">
              {problems.map((p) => (
                <li key={p}>{p}</li>
              ))}
            </ul>
          </Alert>
        )}
        {error && <Alert tone="danger">{error}</Alert>}
      </div>
    </Card>
  )
}
