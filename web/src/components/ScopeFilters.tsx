import { useState, type ReactNode } from 'react'
import { useSearchParams } from 'react-router'
import { useViewer } from '../app/viewer'
import type { RegionCode, Vessel } from '../data/model'
import { visibleCustomers, visibleVessels } from '../data/queries'
import { regions } from '../data/sample'
import { SelectField } from './SelectField'

export interface ScopeFilter {
  region: RegionCode | ''
  customer: string
  vessel: string
  /** Vessels left after the filters, within what the user may see. */
  vessels: Vessel[]
  /** Pick one vessel, e.g. from a vessel name in a table. */
  setVessel: (id: string) => void
  controls: ReactNode
}

/**
 * Region → customer → vessel filters (FR-24, FR-25). Each filter shows only when the user
 * can see more than one choice, so a Chief Officer sees none. A link can start on one vessel
 * with ?vessel=<id>.
 */
export function useScopeFilter(): ScopeFilter {
  const { user } = useViewer()
  const [params] = useSearchParams()
  const initialVessel = params.get('vessel') ?? ''
  const [region, setRegion] = useState<RegionCode | ''>('')
  const [customer, setCustomer] = useState('')
  const [vessel, setVessel] = useState(initialVessel)

  const allCustomers = visibleCustomers(user)
  const allVessels = visibleVessels(user)
  const regionChoices = regions.filter((r) => allCustomers.some((c) => c.region === r.code))
  const customerChoices = allCustomers.filter((c) => !region || c.region === region)
  const vesselChoices = allVessels.filter((v) =>
    customer ? v.customer === customer : customerChoices.some((c) => c.id === v.customer),
  )
  const selected = vessel ? vesselChoices.filter((v) => v.id === vessel) : vesselChoices

  const controls = (
    <>
      {regionChoices.length > 1 && (
        <SelectField
          label="Region"
          className="w-44"
          value={region}
          onChange={(e) => {
            setRegion(e.target.value as RegionCode | '')
            setCustomer('')
            setVessel('')
          }}
          options={[
            { value: '', label: 'All regions' },
            ...regionChoices.map((r) => ({ value: r.code, label: r.code })),
          ]}
        />
      )}
      {customerChoices.length > 1 && (
        <SelectField
          label="Customer"
          className="w-60"
          value={customer}
          onChange={(e) => {
            setCustomer(e.target.value)
            setVessel('')
          }}
          options={[
            { value: '', label: 'All customers' },
            ...customerChoices.map((c) => ({ value: c.id, label: c.name })),
          ]}
        />
      )}
      {vesselChoices.length > 1 && (
        <SelectField
          label="Vessel"
          className="w-60"
          value={vessel}
          onChange={(e) => setVessel(e.target.value)}
          options={[
            { value: '', label: 'All vessels' },
            ...vesselChoices.map((v) => ({ value: v.id, label: v.name })),
          ]}
        />
      )}
    </>
  )

  return { region, customer, vessel, vessels: selected, setVessel, controls }
}

/** A row of filters above a table. */
export function FilterBar({ children }: { children: ReactNode }) {
  return <div className="flex flex-wrap items-end gap-3">{children}</div>
}
