import type { Invite } from '../../api/invites'
import type { Batch, QueueCounts } from '../../api/review'
import type { NeedsYouItemProps } from '../../components/NeedsYouItem'
import { inviteExpired } from '../invites/inviteStatus'
import { batchStatus } from '../review/reviewRules'

/** "Good morning, Robert" by the viewer's local hour. */
export function greeting(fullName: string, now: Date = new Date()): string {
  const hour = now.getHours()
  const part = hour < 12 ? 'morning' : hour < 18 ? 'afternoon' : 'evening'
  const first = fullName.split(' ')[0] ?? fullName
  return `Good ${part}, ${first}`
}

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`

/**
 * What needs the BU Admin today (canvas BU 03): long waits, stuck batches and expired
 * invites. Empty when nothing is urgent.
 */
export function buNeedsYou(
  counts: QueueCounts | undefined,
  batches: Batch[],
  invites: Invite[],
  now: Date = new Date(),
): NeedsYouItemProps[] {
  const stuck = batches.filter((b) => batchStatus(b, now).label.startsWith('No progress'))
  const expired = invites.filter((i) => inviteExpired(i, now))
  const items: NeedsYouItemProps[] = [
    {
      icon: 'check-square',
      tone: 'warning',
      count: counts?.over_1w ?? 0,
      title: 'Waiting over a week',
      text: 'Your Enterprise Admin sees these too.',
      link: { to: '/review-queue', label: 'Review →' },
    },
    {
      icon: 'check-square',
      tone: 'warning',
      count: counts?.over_1d ?? 0,
      title: 'Waiting over a day',
      text: 'Review them or delegate to technicians.',
      link: { to: '/review-queue', label: 'Review →' },
    },
    {
      icon: 'delegate',
      tone: 'navy',
      count: stuck.length,
      title: stuck.length === 1 ? 'Batch with no progress' : 'Batches with no progress',
      text: stuck
        .map((b) => `${b.batch_no} · ${b.assigned_to_name} · 0 of ${b.scan_count}`)
        .join(', '),
      link: { to: '/delegations', label: 'Remind or take back →' },
    },
    {
      icon: 'users',
      tone: 'navy',
      count: expired.length,
      title: expired.length === 1 ? 'Invite expired' : 'Invites expired',
      text: `${expired.map((i) => i.email).join(', ')} · resend from Technicians`,
      link: { to: '/technicians', label: 'Resend →' },
    },
  ]
  return items.filter((item) => item.count > 0)
}

/** "6 scans are waiting review, all under 24 hours." */
export function calmSummary(waiting: number): string {
  if (waiting === 0) return 'No scans are waiting review. No stuck batches.'
  return `${plural(waiting, 'scan is', 'scans are')} waiting review, all under 24 hours. No stuck batches.`
}
