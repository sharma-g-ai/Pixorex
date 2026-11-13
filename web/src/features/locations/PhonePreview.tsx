import type { Level, LocationNode } from '../../api/locations'
import { phonePicks } from './guideRules'

interface PhonePreviewProps {
  levels: Level[]
  nodes: LocationNode[]
  /** The place picked in the list; null shows a hint. */
  nodeId: string | null
}

/** What a technician's phone shows for one place, with the phone's own rules (plan R7). */
export function PhonePreview({ levels, nodes, nodeId }: PhonePreviewProps) {
  const preview = nodeId ? phonePicks(levels, nodes, nodeId) : null
  return (
    <section
      aria-label="On the technician's phone"
      className="flex w-full shrink-0 flex-col gap-3 rounded-xl border border-line bg-surface p-4 lg:w-72"
    >
      <h2 className="text-small font-semibold text-ink-muted">On the technician's phone</h2>
      {preview ? (
        <div className="flex flex-col gap-2 rounded-2xl border-2 border-ink p-3">
          <p className="text-meta font-semibold text-ink-muted">Where is the equipment?</p>
          <dl className="flex flex-col gap-1.5">
            {preview.picks.map((pick) => (
              <div
                key={pick.level_name}
                className="flex justify-between gap-2 rounded-md border border-line px-2.5 py-1.5"
              >
                <dt className="text-meta text-ink-muted">{pick.level_name}</dt>
                <dd className={pick.name ? 'font-semibold' : 'text-ink-subtle'}>
                  {pick.name ?? 'Skipped'}
                </dd>
              </div>
            ))}
          </dl>
          <p className="text-meta text-ink-muted">{preview.path}</p>
          <p className={preview.canScan ? 'text-small text-success' : 'text-small text-warning'}>
            {preview.canScan
              ? 'Technicians can place a scan here.'
              : "Technicians can't scan here: they pick a place further down."}
          </p>
        </div>
      ) : (
        <p className="text-small text-ink-muted">
          Pick a place in the list to see what technicians choose on the phone.
        </p>
      )}
    </section>
  )
}
