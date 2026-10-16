import { Card } from '../../components/Card'
import { NeedsYouItem } from '../../components/NeedsYouItem'
import type { NeedsYou } from './unitSummary'

/** The EA "Needs you" panel (canvas: EA 03). */
export function NeedsYouPanel({ escalated, withoutBuAdmin }: NeedsYou) {
  return (
    <Card title="Needs you">
      <div className="grid grid-cols-1 gap-3.5 md:grid-cols-2">
        <NeedsYouItem
          icon="check-square"
          tone="warning"
          count={escalated}
          title="Scans waiting over 24 hours"
          text="Not approved within 24 hours. Review them yourself or delegate them."
          link={{ to: '/escalations', label: 'View details →' }}
        />
        <NeedsYouItem
          icon="grid"
          tone="navy"
          count={withoutBuAdmin}
          title="Units without a BU Admin"
          text="Until then, their scans that wait over 24 hours come to you."
          link={{ to: '/overview/units-without-bu-admin', label: 'View details →' }}
        />
      </div>
    </Card>
  )
}
