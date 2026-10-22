import { Link } from 'react-router'
import { Card, Detail, Mono, Note } from '../../components/Page'
import { SyncAge } from '../../components/StockBadges'
import type { Vessel } from '../../data/model'
import { customerById } from '../../data/queries'
import { regions } from '../../data/sample'
import { formatDate, formatDateTime } from '../../lib/format'

/** Shown on Sea Stock when one vessel is picked: who it belongs to, its tablet and last sync. */
export function VesselDetails({ vessel }: { vessel: Vessel }) {
  const customer = customerById(vessel.customer)
  const region = regions.find((r) => r.code === customer?.region)
  return (
    <>
      <Card
        title={vessel.name}
        subtitle={`${vessel.imo} · Vessel ID ${vessel.vesselId}`}
        actions={
          <div className="flex gap-4 text-small font-semibold">
            <Link to={`/consumption?vessel=${vessel.id}`} className="text-brand hover:underline">
              Consumption →
            </Link>
            <Link to={`/activity?vessel=${vessel.id}`} className="text-brand hover:underline">
              Activity →
            </Link>
          </div>
        }
      >
        <div className="grid grid-cols-2 gap-5 md:grid-cols-3 xl:grid-cols-6">
          <Detail label="Customer">{customer?.name}</Detail>
          <Detail label="Customer ID">
            <Mono>{customer?.customerId}</Mono>
          </Detail>
          <Detail label="Region">{region ? `${region.code} · ${region.name}` : '—'}</Detail>
          <Detail label="Tablet">
            {vessel.device ? (
              <>
                <Mono>{vessel.device.id}</Mono> · {vessel.device.platform} · app{' '}
                {vessel.device.appVersion}
              </>
            ) : (
              'No tablet paired'
            )}
          </Detail>
          <Detail label="Opening stock">
            {vessel.baselineOn ? formatDate(vessel.baselineOn) : 'Not captured yet'}
          </Detail>
          <Detail label="Last sync">
            <SyncAge at={vessel.lastSync} />
          </Detail>
        </div>
        {vessel.lastSync && (
          <p className="mt-4 text-small text-ink-muted">
            Stock is as of the last sync, {formatDateTime(vessel.lastSync)} UTC. Anything recorded
            on the tablet since then appears after the next sync.
          </p>
        )}
      </Card>
      {!vessel.baselineOn && (
        <Note tone="warning">
          The opening stock for this vessel has not been captured yet (FR-08). Sea Stock starts once
          the crew completes the baseline count on the tablet and it syncs.
        </Note>
      )}
    </>
  )
}
