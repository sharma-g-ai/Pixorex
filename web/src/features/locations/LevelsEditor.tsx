import { useState } from 'react'
import { errorMessage } from '../../api/client'
import { useSetLevels, type LevelInput, type LocationSetup } from '../../api/locations'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { SelectField } from '../../components/SelectField'
import { TextField } from '../../components/TextField'
import { countsByLevel, presets, requirementLabels, sortLevels } from './locationTree'

interface LevelsEditorProps {
  buId: string
  setup: LocationSetup
  onDone: () => void
}

const ruleOptions = (['required', 'optional', 'off'] as const).map((value) => ({
  value,
  label: requirementLabels[value],
}))

/** Tab 1 · Levels (canvas EA 12): the levels this unit uses, top to bottom. */
export function LevelsEditor({ buId, setup, onDone }: LevelsEditorProps) {
  const saved = sortLevels(setup.levels)
  const [draft, setDraft] = useState<LevelInput[]>(() =>
    saved.map(({ level_id, level_name, requirement }) => ({ level_id, level_name, requirement })),
  )
  const [error, setError] = useState<string | null>(null)
  const setLevels = useSetLevels(buId)

  const locked = setup.status === 'published'
  const hasNodes = setup.nodes.length > 0
  const inUse = new Map(
    countsByLevel(setup.levels, setup.nodes).map((c) => [c.level.level_id, c.count]),
  )
  const changed =
    JSON.stringify(draft) !==
    JSON.stringify(
      saved.map(({ level_id, level_name, requirement }) => ({ level_id, level_name, requirement })),
    )

  const update = (index: number, patch: Partial<LevelInput>) =>
    setDraft((rows) => rows.map((row, i) => (i === index ? { ...row, ...patch } : row)))
  const swap = (index: number, by: -1 | 1) =>
    setDraft((rows) => {
      const next = [...rows]
      const other = next[index + by]
      const current = next[index]
      if (!other || !current) return rows
      next[index] = other
      next[index + by] = current
      return next
    })

  const save = async () => {
    setError(null)
    if (draft.length < 2) return setError('Keep at least 2 levels.')
    if (draft.some((l) => !l.level_name.trim())) return setError('Every level needs a name.')
    try {
      await setLevels.mutateAsync(
        draft.map((l, i) => ({
          ...l,
          level_name: l.level_name.trim(),
          requirement: i === 0 ? 'required' : l.requirement,
        })),
      )
      onDone()
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <div className="flex flex-col gap-4 lg:flex-row lg:items-start">
      <Card title="Levels" className="min-w-0 grow">
        {locked ? (
          <Alert tone="info" className="mb-3">
            Published and locked to protect scan history. Levels can't be added, renamed, reordered
            or removed.
          </Alert>
        ) : (
          <p className="mb-3 text-body text-ink-muted">
            You can still change anything here until you publish. After that, the levels are locked.
          </p>
        )}

        {!locked && !hasNodes && (
          <div className="mb-4 flex flex-wrap items-center gap-2">
            <span className="text-small font-semibold text-ink-muted">Quick start</span>
            {([2, 3, 4, 5] as const).map((n) => (
              <Button key={n} variant="secondary" onClick={() => setDraft(presets[n])}>
                {n} levels
              </Button>
            ))}
            <span className="text-small text-ink-subtle">or add your own below</span>
          </div>
        )}

        <ol className="flex flex-col gap-2">
          {draft.map((level, i) => (
            <li
              key={level.level_id ?? `new-${i}`}
              className="grid grid-cols-[2rem_minmax(0,2fr)_minmax(0,1.4fr)_minmax(0,1fr)_auto] items-center gap-3 rounded-lg border border-line px-3 py-2"
            >
              <span className="font-mono text-small text-ink-subtle">{i + 1}</span>
              <TextField
                label={`Level ${i + 1} name`}
                hideLabel
                value={level.level_name}
                disabled={locked}
                onChange={(e) => update(i, { level_name: e.target.value })}
              />
              {i === 0 ? (
                <span className="text-small text-ink-muted">Top level · always required</span>
              ) : (
                <SelectField
                  label={`Rule for ${level.level_name || `level ${i + 1}`}`}
                  hideLabel
                  options={ruleOptions}
                  value={level.requirement}
                  disabled={locked}
                  onChange={(e) =>
                    update(i, { requirement: e.target.value as LevelInput['requirement'] })
                  }
                />
              )}
              <span className="text-small text-ink-muted">
                {level.level_id ? `${inUse.get(level.level_id) ?? 0} in use` : 'Not used yet'}
              </span>
              {!locked && (
                <div className="flex gap-2.5">
                  <button
                    type="button"
                    className={buttonClasses('link')}
                    disabled={hasNodes || i === 0}
                    aria-label={`Move ${level.level_name || 'level'} up`}
                    onClick={() => swap(i, -1)}
                  >
                    ↑
                  </button>
                  <button
                    type="button"
                    className={buttonClasses('link')}
                    disabled={hasNodes || i === draft.length - 1}
                    aria-label={`Move ${level.level_name || 'level'} down`}
                    onClick={() => swap(i, 1)}
                  >
                    ↓
                  </button>
                  <button
                    type="button"
                    className={buttonClasses('danger-link')}
                    disabled={
                      i === 0 || (level.level_id ? (inUse.get(level.level_id) ?? 0) > 0 : false)
                    }
                    aria-label={`Remove ${level.level_name || 'level'}`}
                    onClick={() => setDraft((rows) => rows.filter((_, j) => j !== i))}
                  >
                    Remove
                  </button>
                </div>
              )}
            </li>
          ))}
        </ol>
        {hasNodes && !locked && (
          <p className="mt-2 text-xs text-ink-subtle">
            Order can't change once locations use these levels. A new level starts as Optional so
            existing locations stay valid.
          </p>
        )}

        {!locked && (
          <div className="mt-4 flex flex-wrap items-center gap-2.5">
            <Button
              variant="secondary"
              onClick={() =>
                setDraft((rows) => [
                  ...rows,
                  {
                    level_id: null,
                    level_name: '',
                    requirement: hasNodes ? 'optional' : 'required',
                  },
                ])
              }
            >
              + Add level
            </Button>
            <Button
              className="ml-auto"
              disabled={!changed || setLevels.isPending}
              onClick={() => void save()}
            >
              {setLevels.isPending ? 'Saving…' : 'Save levels'}
            </Button>
          </div>
        )}
        {error && (
          <Alert tone="danger" className="mt-3">
            {error}
          </Alert>
        )}
      </Card>

      <Card title="How the levels nest" className="w-full shrink-0 lg:w-80">
        <ol className="flex flex-col gap-1.5">
          {draft.map((level, i) => (
            <li
              key={level.level_id ?? `nest-${i}`}
              className="text-body"
              style={{ paddingLeft: `calc(var(--spacing) * ${i * 4})` }}
            >
              {level.level_name || `Level ${i + 1}`}
              {level.requirement === 'optional' && (
                <span className="ml-1.5 text-xs text-ink-subtle">optional</span>
              )}
              {level.requirement === 'off' && (
                <span className="ml-1.5 text-xs text-ink-subtle">off</span>
              )}
            </li>
          ))}
        </ol>
        <ul className="mt-4 flex flex-col gap-1.5 text-small text-ink-muted">
          <li>
            <b className="text-ink">Required</b> — every location above must contain one.
          </li>
          <li>
            <b className="text-ink">Optional</b> — can be skipped, e.g. bins straight inside a
            building.
          </li>
          <li>
            <b className="text-ink">Off</b> — kept but not used.
          </li>
        </ul>
      </Card>
    </div>
  )
}
