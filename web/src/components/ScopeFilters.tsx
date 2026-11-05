import type { ReactNode } from 'react'
import { useSearchParams } from 'react-router'
import { useViewer } from '../app/viewer'
import type { Vessel } from '../data/model'
import { visibleCustomers, visibleVessels } from '../data/queries'
import { SelectField } from './SelectField'

export interface ScopeFilter {
  customer: string
  vessel: string
  /** Vessels left after the filters, within what the user may see. */
  vessels: Vessel[]
  /** Pick one vessel, e.g. from a vessel name in a table. */
  setVessel: (id: string) => void
  controls: ReactNode
}

/**
 * Customer → vessel filters (FR-24). Each filter shows only when the user can see more than
 * one choice, so a Customer Admin gets no customer filter. They live in the URL (?customer=<id>,
 * ?vessel=<id>), so a link opens them and a link without them clears them. A value outside the
 * user's scope behaves as if it does not exist.
 */
export function useScopeFilter(): ScopeFilter {
  const { user } = useViewer()
  const [params, setParams] = useSearchParams()

  const customerChoices = visibleCustomers(user)
  const askedCustomer = params.get('customer') ?? ''
  const customer = customerChoices.some((c) => c.id === askedCustomer) ? askedCustomer : ''
  const vesselChoices = visibleVessels(user).filter((v) => !customer || v.customer === customer)
  const askedVessel = params.get('vessel') ?? ''
  const vessel = vesselChoices.some((v) => v.id === askedVessel) ? askedVessel : ''
  const selected = vessel ? vesselChoices.filter((v) => v.id === vessel) : vesselChoices

  const change = (edit: (next: URLSearchParams) => void) =>
    setParams(
      (now) => {
        const next = new URLSearchParams(now)
        edit(next)
        return next
      },
      { replace: true },
    )
  const setVessel = (id: string) =>
    change((next) => {
      if (id) next.set('vessel', id)
      else next.delete('vessel')
    })
  const setCustomer = (id: string) =>
    change((next) => {
      next.delete('vessel')
      if (id) next.set('customer', id)
      else next.delete('customer')
    })

  const controls = (
    <>
      {customerChoices.length > 1 && (
        <SelectField
          label="Customer"
          className="w-60"
          value={customer}
          onChange={(e) => setCustomer(e.target.value)}
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

  return { customer, vessel, vessels: selected, setVessel, controls }
}

/** A row of filters above a table. */
export function FilterBar({ children }: { children: ReactNode }) {
  return <div className="flex flex-wrap items-end gap-3">{children}</div>
}
