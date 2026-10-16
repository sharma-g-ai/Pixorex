import { useId, type InputHTMLAttributes } from 'react'

type TextFieldProps = InputHTMLAttributes<HTMLInputElement> & {
  label: string
  /** Hide the label visually but keep it for screen readers (e.g. inside a table row). */
  hideLabel?: boolean
  error?: string
}

/** Labelled text input with an error line underneath. */
export function TextField({
  label,
  hideLabel = false,
  error,
  id,
  className = '',
  ...rest
}: TextFieldProps) {
  const autoId = useId()
  const inputId = id ?? autoId
  const errorId = `${inputId}-error`

  return (
    <div className={className}>
      <label
        htmlFor={inputId}
        className={hideLabel ? 'sr-only' : 'mb-1.5 block text-small font-semibold text-ink-muted'}
      >
        {label}
      </label>
      <input
        id={inputId}
        aria-invalid={error ? true : undefined}
        aria-describedby={error ? errorId : undefined}
        className={`h-10.5 w-full rounded-lg border-[1.5px] bg-surface px-3 text-sm outline-none focus:border-brand-navy disabled:bg-page disabled:text-ink-muted ${
          error ? 'border-danger' : 'border-line-strong'
        }`}
        {...rest}
      />
      {error && (
        <p id={errorId} className="mt-1.5 text-xs text-danger">
          {error}
        </p>
      )}
    </div>
  )
}
