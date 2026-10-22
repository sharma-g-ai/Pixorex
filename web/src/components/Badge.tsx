import type { ReactNode } from 'react'

export type BadgeTone = 'success' | 'warning' | 'danger' | 'neutral'

/** A status worked out by feature logic, ready to show as a Badge. */
export interface BadgeStatus {
  label: string
  tone: BadgeTone
}

const tones: Record<BadgeTone, string> = {
  success: 'bg-success-soft text-success',
  warning: 'bg-warning-soft text-warning',
  danger: 'bg-danger-soft text-danger',
  neutral: 'bg-page text-ink-muted',
}

/** Small coloured status pill ("Active", "Pending · 22 h left", "Expired"). */
export function Badge({ tone, children }: { tone: BadgeTone; children: ReactNode }) {
  return (
    <span
      className={`inline-block rounded-full px-2.5 py-0.5 text-meta font-bold whitespace-nowrap ${tones[tone]}`}
    >
      {children}
    </span>
  )
}
