import { useId, type SelectHTMLAttributes } from 'react'

export interface SelectOption {
  value: string
  label: string
}

type SelectFieldProps = Omit<SelectHTMLAttributes<HTMLSelectElement>, 'children'> & {
  label: string
  /** Hide the label visually but keep it for screen readers (e.g. inside a table row). */
  hideLabel?: boolean
  options: SelectOption[]
  error?: string
}

/** Labelled native dropdown, styled like TextField. */
export function SelectField({
  label,
  hideLabel = false,
  options,
  error,
  id,
  className = '',
  ...rest
}: SelectFieldProps) {
  const autoId = useId()
  const selectId = id ?? autoId
  return (
    <div className={className}>
      <label
        htmlFor={selectId}
        className={hideLabel ? 'sr-only' : 'mb-1.5 block text-small font-semibold text-ink-muted'}
      >
        {label}
      </label>
      <select
        id={selectId}
        aria-invalid={error ? true : undefined}
        className={`h-10.5 w-full rounded-lg border-[1.5px] bg-surface px-3 text-sm outline-none focus:border-brand-navy disabled:bg-page disabled:text-ink-muted ${
          error ? 'border-danger' : 'border-line-strong'
        }`}
        {...rest}
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
      {error && <p className="mt-1.5 text-xs text-danger">{error}</p>}
    </div>
  )
}
