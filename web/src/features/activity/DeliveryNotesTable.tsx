import { Link } from 'react-router'
import { Badge } from '../../components/Badge'
import { DataTable } from '../../components/DataTable'
import { Mono, Muted } from '../../components/Page'
import type { DeliveryNote } from '../../data/model'
import { ImoCheckBadge } from '../../components/StockBadges'
import { vesselById } from '../../data/queries'
import { formatDate, formatDateTime, plural } from '../../lib/format'

export function differences(dn: DeliveryNote): number {
  return dn.lines.filter((l) => l.result !== 'matched').length
}

export function receivedCans(dn: DeliveryNote): number {
  return dn.lines.reduce((sum, l) => sum + l.receivedCans, 0)
}

/** Delivery notes received on board and how each tallied (FR-01 – FR-05). */
export function DeliveryNotesTable({
  rows,
  showVessel = true,
}: {
  rows: DeliveryNote[]
  showVessel?: boolean
}) {
  return (
    <DataTable
      label="Delivery notes"
      rows={rows}
      rowKey={(dn) => dn.dnNumber}
      empty="No delivery notes match these filters"
      columns={[
        {
          header: 'Delivery note',
          width: 1.3,
          cell: (dn) => (
            <div>
              <Link
                to={`?tab=notes&dn=${dn.dnNumber}`}
                className="font-semibold text-brand hover:underline"
              >
                DN <Mono>{dn.dnNumber}</Mono>
              </Link>
              <div>
                <Muted>Dated {formatDate(dn.dnDate)}</Muted>
              </div>
            </div>
          ),
        },
        ...(showVessel
          ? [
              {
                header: 'Vessel',
                width: 1.2,
                cell: (dn: DeliveryNote) => vesselById(dn.vessel)?.name,
              },
            ]
          : []),
        {
          header: 'Customer reference',
          width: 1.1,
          cell: (dn) => <Mono>{dn.customerReference}</Mono>,
        },
        { header: 'Lines', align: 'right', width: 0.6, cell: (dn) => dn.lines.length },
        { header: 'Cans in', align: 'right', width: 0.7, cell: (dn) => receivedCans(dn) },
        {
          header: 'Tally',
          width: 1,
          cell: (dn) =>
            differences(dn) === 0 ? (
              <Badge tone="success">All matched</Badge>
            ) : (
              <Badge tone="warning">{plural(differences(dn), 'difference')}</Badge>
            ),
        },
        {
          header: 'IMO check',
          width: 0.9,
          cell: (dn) => <ImoCheckBadge check={dn.imoCheck} />,
        },
        {
          header: 'Confirmed',
          width: 1.3,
          cell: (dn) => (
            <div>
              <div>{formatDateTime(dn.confirmedAt)}</div>
              <Muted>
                Tablet <Mono>{dn.device}</Mono>
              </Muted>
            </div>
          ),
        },
      ]}
    />
  )
}
