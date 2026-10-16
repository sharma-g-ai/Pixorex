import { ChoiceCard } from './ChoiceCard'

export interface UnitOption {
  bu_id: string
  name: string
  /** Grey line under the name, e.g. "No BU Admin" or "23 waiting scans". */
  note?: string
  /** Set when the unit can't be picked, e.g. "Already run by S. Alvi". */
  disabledReason?: string
}

interface UnitChecklistProps {
  legend: string
  options: UnitOption[]
  value: string[]
  onChange: (buIds: string[]) => void
  error?: string
}

/**
 * Tick-box list of units. Controlled: it always works with a list of unit IDs,
 * even when only one unit is shown.
 */
export function UnitChecklist({ legend, options, value, onChange, error }: UnitChecklistProps) {
  const toggle = (buId: string, on: boolean) =>
    onChange(on ? [...value, buId] : value.filter((id) => id !== buId))

  return (
    <fieldset className="flex flex-col gap-2">
      <legend className="mb-1.5 text-small font-semibold text-ink-muted">{legend}</legend>
      {options.map((unit) => (
        <ChoiceCard
          key={unit.bu_id}
          type="checkbox"
          name="units"
          value={unit.bu_id}
          title={unit.name}
          description={unit.disabledReason ?? unit.note}
          disabled={unit.disabledReason !== undefined}
          checked={value.includes(unit.bu_id)}
          onChange={(e) => toggle(unit.bu_id, e.target.checked)}
        />
      ))}
      {error && <p className="text-xs text-danger">{error}</p>}
    </fieldset>
  )
}
