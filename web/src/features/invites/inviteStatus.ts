import type { Invite } from '../../api/invites'
import type { BadgeStatus } from '../../components/Badge'
import { timeLeft } from '../../lib/time'

/** Expired, or still pending but past its 24 hours (the API may not have marked it yet). */
export function inviteExpired(invite: Invite, now = new Date()): boolean {
  return (
    invite.status === 'expired' ||
    (invite.status === 'pending' && timeLeft(invite.expires_at, now) === null)
  )
}

/** Badge for an invite row; null for invites that no longer show (accepted, cancelled). */
export function inviteStatus(invite: Invite, now = new Date()): BadgeStatus | null {
  if (inviteExpired(invite, now)) return { label: 'Expired', tone: 'danger' }
  if (invite.status !== 'pending') return null
  return { label: `Pending · ${timeLeft(invite.expires_at, now)}`, tone: 'warning' }
}

/** Badge for a user account (BU Admin or technician) by its status. */
export function accountStatus(status: 'invited' | 'active' | 'removed'): BadgeStatus {
  if (status === 'removed') return { label: 'Removed · needs new invite', tone: 'danger' }
  if (status === 'invited') return { label: 'Not activated yet', tone: 'neutral' }
  return { label: 'Active', tone: 'success' }
}
