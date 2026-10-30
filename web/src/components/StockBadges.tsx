import type { ComponentType, DeliveryNote, LineResult, TransactionType } from '../data/model'
import { daysSince } from '../data/queries'
import { formatAgo, formatDateTime } from '../lib/format'
import { Badge } from './Badge'

const componentLooks: Record<ComponentType, string> = {
  Base: 'bg-base-soft text-base',
  Hardener: 'bg-hardener-soft text-hardener',
  '1K': 'bg-onek-soft text-onek',
}

export function ComponentBadge({ type }: { type: ComponentType }) {
  return (
    <span
      className={`inline-block rounded-md px-2 py-0.5 text-meta font-semibold ${componentLooks[type]}`}
    >
      {type}
    </span>
  )
}

const typeLabels: Record<
  TransactionType,
  { label: string; tone: 'success' | 'warning' | 'neutral' | 'danger' }
> = {
  receipt: { label: 'Receipt', tone: 'success' },
  consumption: { label: 'Consumption', tone: 'warning' },
  adjustment: { label: 'Adjustment', tone: 'neutral' },
  baseline: { label: 'Baseline', tone: 'neutral' },
}

export function TransactionBadge({ type }: { type: TransactionType }) {
  const t = typeLabels[type]
  return <Badge tone={t.tone}>{t.label}</Badge>
}

const results: Record<
  LineResult,
  { label: string; tone: 'success' | 'warning' | 'danger' | 'neutral' }
> = {
  matched: { label: 'Matched', tone: 'success' },
  short: { label: 'Short', tone: 'warning' },
  over: { label: 'Over', tone: 'warning' },
  'not-on-note': { label: 'Not on note', tone: 'warning' },
  'not-received': { label: 'Not received', tone: 'danger' },
}

export function LineResultBadge({ result }: { result: LineResult }) {
  const r = results[result]
  return <Badge tone={r.tone}>{r.label}</Badge>
}

/**
 * Last sync of a vessel's device (FR-20). A-07 expects vessel-to-shore sync every 1–3 days,
 * so anything older is shown as late.
 */
const imoChecks: Record<DeliveryNote['imoCheck'], { label: string; tone: 'success' | 'warning' | 'neutral' }> = {
  match: { label: 'IMO matches', tone: 'success' },
  mismatch: { label: 'IMO mismatch', tone: 'warning' },
  not_read: { label: 'IMO not read', tone: 'neutral' },
}

/** The IMO read from a delivery note against the vessel's (checked, never used to choose the vessel). */
export function ImoCheckBadge({ check }: { check: DeliveryNote['imoCheck'] }) {
  return <Badge tone={imoChecks[check].tone}>{imoChecks[check].label}</Badge>
}

export function SyncAge({ at }: { at: string | null }) {
  const days = daysSince(at)
  if (at === null) return <Badge tone="neutral">Never synced</Badge>
  return (
    <span className="inline-flex flex-col">
      <span className={days !== null && days > 3 ? 'font-semibold text-warning' : ''}>
        {formatAgo(days)}
      </span>
      <span className="text-caption text-ink-subtle">{formatDateTime(at)}</span>
    </span>
  )
}
