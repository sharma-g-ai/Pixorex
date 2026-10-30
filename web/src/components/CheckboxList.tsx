export interface CheckboxOption<Value extends string> {
  value: Value
  label: string
}

interface CheckboxListProps<Value extends string> {
  label: string
  options: CheckboxOption<Value>[]
  value: Value[]
  onChange: (value: Value[]) => void
}

/** A labelled group of checkboxes for picking several values, e.g. customers. */
export function CheckboxList<Value extends string>({
  label,
  options,
  value,
  onChange,
}: CheckboxListProps<Value>) {
  return (
    <fieldset>
      <legend className="mb-1.5 text-small font-semibold text-ink-muted">{label}</legend>
      <div className="flex flex-col gap-1.5 rounded-lg border border-line p-3">
        {options.map((o) => (
          <label key={o.value} className="flex items-center gap-2 text-body text-ink">
            <input
              type="checkbox"
              className="size-4 accent-brand"
              checked={value.includes(o.value)}
              onChange={(e) =>
                onChange(
                  e.target.checked ? [...value, o.value] : value.filter((x) => x !== o.value),
                )
              }
            />
            {o.label}
          </label>
        ))}
      </div>
    </fieldset>
  )
}
