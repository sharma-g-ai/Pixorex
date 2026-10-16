import type { ReactNode } from 'react'

type AlertTone = 'info' | 'warning' | 'danger'

const tones: Record<AlertTone, string> = {
  info: 'bg-info-soft text-brand-navy-dark',
  warning: 'bg-warning-soft text-warning',
  danger: 'bg-danger-soft text-danger-strong',
}

interface AlertProps {
  tone: AlertTone
  /**
   * How screen readers announce it: 'alert' (errors, default for danger),
   * 'status' (a result after an action), or none (static help text, default for info).
   */
  role?: 'alert' | 'status'
  className?: string
  children: ReactNode
}

/** Coloured message box: help text, success notices and errors. */
export function Alert({ tone, role, className = '', children }: AlertProps) {
  return (
    <div
      role={role ?? (tone === 'danger' ? 'alert' : undefined)}
      className={`rounded-lg px-3.5 py-2.5 text-small leading-normal ${tones[tone]} ${className}`}
    >
      {children}
    </div>
  )
}
