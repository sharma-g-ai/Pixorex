import { useState } from 'react'
import type { Level } from '../../api/locations'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { ChoiceCard } from '../../components/ChoiceCard'
import { TextField } from '../../components/TextField'
import { presets } from './locationTree'
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

/** Guided location setup: describe one real place, then name each kind (plan section 4). */
export function SetupGuide({ levels, siteName, busy, error, onCreate }: SetupGuideProps) {
  const [parts, setParts] = useState(() => startGuide(levels, siteName))
  const [step, setStep] = useState<1 | 2>(1)
  const [problems, setProblems] = useState<string[]>([])

  const update = (index: number, patch: Partial<GuidePart>) =>
    setParts((all) => all.map((p, i) => (i === index ? { ...p, ...patch } : p)))
  const tryStep = (scope: 'places' | 'all', then: () => void) => {
    const found = guideProblems(parts, levels, scope)
    setProblems(found)
    if (found.length === 0) then()
  }
  const preset = presets[parts.length as keyof typeof presets]

  return (
    <Card
      title={
        step === 1
          ? 'Step 1 of 2 · Describe one place where equipment sits'
          : 'Step 2 of 2 · What do you call each kind of place?'
      }
    >
      <div className="flex flex-col gap-4">
        {step === 1 ? (
          <>
            <p className="text-body text-ink-muted">
              Biggest to smallest, the way you would tell a new technician where to go. For example:
              Plant 04 › Building C › Paint Shop › Bin 07.
            </p>
            <ol className="flex flex-col gap-2">
              {parts.map((p, i) => (
                <li key={i} className="flex items-end gap-2.5">
                  <TextField
                    label={`Place ${i + 1}`}
                    className="grow"
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
                </li>
              ))}
            </ol>
            <div className="flex flex-wrap gap-2.5">
              <Button variant="secondary" onClick={() => setParts((all) => [...all, newPart()])}>
                + Add a smaller part
              </Button>
              <Button className="ml-auto" onClick={() => tryStep('places', () => setStep(2))}>
                Next
              </Button>
            </div>
          </>
        ) : (
          <>
            <p className="text-body text-ink-muted">
              Give each part a general name. These names become the questions technicians answer on
              the phone, for example Building, Shop, Bin.
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
            <ol className="grid grid-cols-1 gap-3 md:grid-cols-2">
              {parts.map((p, i) => (
                <li key={i} className="flex flex-col gap-2 rounded-lg border border-line p-3">
                  <TextField
                    label={`Kind of ${p.place.trim()}`}
                    value={p.kind}
                    onChange={(e) => update(i, { kind: e.target.value })}
                  />
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
              <Button
                variant="secondary"
                onClick={() => {
                  setProblems([])
                  setStep(1)
                }}
              >
                Back
              </Button>
              <Button
                className="ml-auto"
                disabled={busy}
                onClick={() => tryStep('all', () => onCreate(parts))}
              >
                {busy ? 'Creating…' : 'Create and add more places'}
              </Button>
            </div>
          </>
        )}
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
