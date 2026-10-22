import { Badge, type BadgeTone } from './Badge'

export type Status = 'active' | 'inactive' | 'retired' | 'invited' | 'disabled'

const looks: Record<Status, { label: string; tone: BadgeTone }> = {
  active: { label: 'Active', tone: 'success' },
  inactive: { label: 'Inactive', tone: 'neutral' },
  retired: { label: 'Retired', tone: 'neutral' },
  invited: { label: 'Invited', tone: 'warning' },
  disabled: { label: 'Disabled', tone: 'neutral' },
}

/** The status of a customer, vessel, product or user, shown the same way on every screen. */
export function StatusBadge({ status }: { status: Status }) {
  return <Badge tone={looks[status].tone}>{looks[status].label}</Badge>
}
