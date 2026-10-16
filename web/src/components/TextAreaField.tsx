import { useId, type TextareaHTMLAttributes } from 'react'

type TextAreaFieldProps = TextareaHTMLAttributes<HTMLTextAreaElement> & {
  label: string
  error?: string
}

/** Labelled multi-line text box, styled like TextField. */
export function TextAreaField({
  label,
  error,
  id,
  className = '',
  rows = 3,
  ...rest
}: TextAreaFieldProps) {
  const autoId = useId()
  const inputId = id ?? autoId
  return (
    <div className={className}>
      <label htmlFor={inputId} className="mb-1.5 block text-small font-semibold text-ink-muted">
        {label}
      </label>
      <textarea
        id={inputId}
        rows={rows}
        aria-invalid={error ? true : undefined}
        className={`w-full rounded-lg border-[1.5px] bg-surface px-3 py-2 text-sm text-ink outline-none focus:border-brand-navy ${
          error ? 'border-danger' : 'border-line-strong'
        }`}
        {...rest}
      />
      {error && <p className="mt-1.5 text-xs text-danger">{error}</p>}
    </div>
  )
}
