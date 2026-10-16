import type { InputHTMLAttributes, ReactNode } from 'react'

type ChoiceCardProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> & {
  /** One of several (radio, default) or any number (checkbox). */
  type?: 'radio' | 'checkbox'
  title: string
  description?: ReactNode
  /** Shown under the card while it is selected, e.g. the field that goes with this choice. */
  children?: ReactNode
}

/** One option in a set of choices, drawn as a bordered card. */
export function ChoiceCard({
  type = 'radio',
  title,
  description,
  children,
  checked,
  ...rest
}: ChoiceCardProps) {
  return (
    <div>
      <label
        className={`flex items-start gap-2.5 rounded-lg border-[1.5px] px-3 py-2.5 ${
          rest.disabled
            ? 'cursor-not-allowed border-line opacity-60'
            : checked
              ? 'cursor-pointer border-brand-navy bg-brand-navy-tint'
              : 'cursor-pointer border-line hover:bg-page'
        }`}
      >
        <input
          type={type}
          checked={checked}
          className="mt-0.5 size-4.5 shrink-0 accent-brand-navy"
          {...rest}
        />
        <span>
          <span className={`block text-body ${checked ? 'font-bold' : 'font-semibold'}`}>
            {title}
          </span>
          {description && (
            <span className="mt-px block text-xs text-ink-subtle">{description}</span>
          )}
        </span>
      </label>
      {checked && children && <div className="pt-2 pb-1 pl-7">{children}</div>}
    </div>
  )
}
