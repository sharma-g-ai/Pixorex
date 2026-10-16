import { useState } from 'react'
import { Link } from 'react-router'
import type { BusinessUnit } from '../../api/businessUnits'
import type { Escalation } from '../../api/escalations'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { DataTable, type Column } from '../../components/DataTable'
import { MAX_BATCH, SelectionBar } from '../review/SelectionBar'
import { waitingStatus } from '../review/reviewRules'
import { whyText, type UnitEscalations } from './escalationRules'

interface UnitEscalationsViewProps {
  group: UnitEscalations
  unit?: BusinessUnit
  onRemind: () => void
  onDelegate: (scanIds: string[]) => void
}

/** One unit's escalated scans: pick some and delegate, or open one to decide (canvas EA 29–30). */
export function UnitEscalationsView({
  group,
  unit,
  onRemind,
  onDelegate,
}: UnitEscalationsViewProps) {
  const [selected, setSelected] = useState<string[]>([])
  const admin = unit?.bu_admin?.full_name
  const toggle = (scanId: string, on: boolean) =>
    setSelected((s) => (on ? [...s, scanId].slice(0, MAX_BATCH) : s.filter((id) => id !== scanId)))

  const columns: Column<Escalation>[] = [
    {
      header: 'Select',
      width: 0.3,
      cell: (e) =>
        e.batch_no ? null : (
          <input
            type="checkbox"
            className="size-4.5 accent-brand-navy"
            aria-label={`Select ${e.record_no}`}
            checked={selected.includes(e.scan_id)}
            disabled={!selected.includes(e.scan_id) && selected.length >= MAX_BATCH}
            onChange={(ev) => toggle(e.scan_id, ev.target.checked)}
          />
        ),
    },
    {
      header: 'Scan',
      width: 1.6,
      cell: (e) => (
        <Link to={`/escalations/${e.scan_id}`} className="block min-w-0 hover:underline">
          <span className="block truncate font-semibold">{e.equipment_type_name}</span>
          <span className="font-mono text-meta text-ink-subtle">{e.record_no}</span>
        </Link>
      ),
    },
    { header: 'Unit', width: 0.8, cell: (e) => e.bu_name },
    { header: 'Captured by', width: 1, cell: (e) => e.captured_by_name },
    {
      header: "Why it's with you",
      width: 1.6,
      cell: (e) => <Badge tone="warning">{whyText(e.reason, admin)}</Badge>,
    },
    {
      header: 'Waiting',
      width: 0.8,
      cell: (e) => {
        const status = waitingStatus(e.escalated_at)
        return <Badge tone={status.tone}>{status.label}</Badge>
      },
    },
    {
      header: 'Batch',
      width: 0.8,
      cell: (e) => e.batch_no ?? '—',
    },
  ]

  return (
    <>
      <div className="flex flex-wrap items-center gap-3.5 rounded-xl border border-line bg-surface px-5 py-4">
        <div className="min-w-0 grow">
          <h2 className="text-unit-title font-bold">{group.buName}</h2>
          <p className="text-small text-ink-muted">
            {admin ? `BU Admin ${admin}` : 'No BU Admin'} · oldest waiting{' '}
            {waitingStatus(group.oldest).label}
          </p>
        </div>
        {admin && (
          <Button variant="secondary" onClick={onRemind}>
            Remind {admin}
          </Button>
        )}
        <Button
          variant="secondary"
          onClick={() => onDelegate(group.items.filter((e) => !e.batch_no).map((e) => e.scan_id))}
        >
          Delegate to technicians
        </Button>
      </div>
      <SelectionBar
        count={selected.length}
        hint={`${group.buName} · delegate them to ${group.buName}'s technicians`}
        onClear={() => setSelected([])}
        onDelegate={() => onDelegate(selected)}
      />
      <DataTable
        label={`Escalated scans in ${group.buName}`}
        columns={columns}
        rows={group.items}
        rowKey={(e) => e.escalation_id}
        empty="Nothing escalated in this unit."
      />
    </>
  )
}
