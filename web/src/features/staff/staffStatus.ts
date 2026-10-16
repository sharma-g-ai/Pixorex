import type { Technician } from '../../api/technicians'
import type { BadgeStatus } from '../../components/Badge'
import { timeLeft } from '../../lib/time'
import { accountStatus } from '../invites/inviteStatus'

/** True while Keycloak's 30-minute lock is running (contract 1.18, O-13). */
export function isLocked(t: Pick<Technician, 'sign_in_locked_until'>, now = new Date()): boolean {
  return t.sign_in_locked_until !== null && timeLeft(t.sign_in_locked_until, now) !== null
}

/** Badge for a technician row (canvas BU 25). */
export function technicianStatus(t: Technician, now = new Date()): BadgeStatus {
  if (t.status !== 'removed' && t.sign_in_locked_until && isLocked(t, now)) {
    return { label: `Sign-in locked · ${timeLeft(t.sign_in_locked_until, now)}`, tone: 'warning' }
  }
  return accountStatus(t.status)
}

/** Technicians working in the unit, and those removed from it. */
export function splitTechnicians(technicians: Technician[]) {
  return {
    current: technicians.filter((t) => t.status !== 'removed'),
    removed: technicians.filter((t) => t.status === 'removed'),
  }
}
