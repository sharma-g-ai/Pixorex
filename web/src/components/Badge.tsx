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

/**
 * Small coloured status pill ("Active", "Pending · 22 h left", "Expired"). It stays on one
 * line when it fits and wraps inside a narrow cell instead of running into the next column;
 * rounded-xl is more than half its one-line height, so it still looks like a pill.
 * shrink-0: beside other text in a row it keeps its full width (the text gives way, as before).
 */
export function Badge({ tone, children }: { tone: BadgeTone; children: ReactNode }) {
  return (
    <span
      className={`inline-block max-w-full shrink-0 rounded-xl px-2.5 py-0.5 text-meta font-bold ${tones[tone]}`}
    >
      {children}
    </span>
  )
}
