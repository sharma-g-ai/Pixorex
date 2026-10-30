import { useState } from 'react'
import { Link } from 'react-router'
import { useViewer } from '../../app/viewer'
import { Button } from '../../components/Button'
import { Card, Detail, Mono, Note } from '../../components/Page'
import { SyncAge } from '../../components/StockBadges'
import type { Vessel } from '../../data/model'
import { activeDevice, customerById, imoLabel } from '../../data/queries'
import { can } from '../../data/roles'
import { formatDate, formatDateTime } from '../../lib/format'
import { AdjustStockDialog } from './AdjustStockDialog'

/** Shown on Sea Stock when one vessel is picked: who it belongs to, its tablet and last sync. */
export function VesselDetails({ vessel }: { vessel: Vessel }) {
  const { user } = useViewer()
  const [adjusting, setAdjusting] = useState(false)
  const customer = customerById(vessel.customer)
  const tablet = activeDevice(vessel.id)
  return (
    <>
      <Card
        title={vessel.name}
        subtitle={`${imoLabel(vessel.imo)} (the vessel ID)`}
        actions={
          <div className="flex items-center gap-4 text-small font-semibold">
            <Link to={`/consumption?vessel=${vessel.id}`} className="text-brand hover:underline">
              Consumption →
            </Link>
            <Link to={`/activity?vessel=${vessel.id}`} className="text-brand hover:underline">
              Activity →
            </Link>
            {can(user, 'adjust-stock') && vessel.status === 'active' && (
              <Button variant="secondary" onClick={() => setAdjusting(true)}>
                Adjust stock
              </Button>
            )}
          </div>
        }
      >
        <div className="grid grid-cols-2 gap-5 md:grid-cols-3 xl:grid-cols-6">
          <Detail label="Customer">
            {customer?.name} · <Mono>{customer?.customerCode}</Mono>
          </Detail>
          <Detail label="Tablet">
            {tablet ? (
              <>
                <Mono>{tablet.id}</Mono> · {tablet.model} · app {tablet.appVersion}
              </>
            ) : (
              'No tablet paired'
            )}
          </Detail>
          <Detail label="Receiving">{vessel.receivingMode === 'scan' ? 'Scan labels' : 'Enter by hand'}</Detail>
          <Detail label="Opening stock">{vessel.baselineOn ? formatDate(vessel.baselineOn) : 'Not captured yet'}</Detail>
          <Detail label="Vessel sign-in">
            {vessel.lastSignInAt ? `Last ${formatDateTime(vessel.lastSignInAt)}` : 'Never signed in'}
          </Detail>
          <Detail label="Last sync">
            <SyncAge at={vessel.lastSync} />
          </Detail>
        </div>
        {vessel.lastSync && (
          <p className="mt-4 text-small text-ink-muted">
            Stock is as of the last sync, {formatDateTime(vessel.lastSync)} UTC. Anything recorded on the tablet
            since then appears after the next sync.
          </p>
        )}
      </Card>
      {!vessel.baselineOn && (
        <Note tone="warning">
          The opening stock for this vessel has not been captured yet. Sea Stock starts once the crew completes the
          opening count on the tablet and it syncs.
        </Note>
      )}
      {adjusting && <AdjustStockDialog vessel={vessel} onClose={() => setAdjusting(false)} />}
    </>
  )
}
