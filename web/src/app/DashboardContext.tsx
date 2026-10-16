import { createContext, useContext } from 'react'
import type { Me, UnitRole } from '../api/me'
import type { DashboardRole } from './access'

export interface Dashboard {
  me: Me
  role: DashboardRole
  /** The BU Admin's current unit; null for the Enterprise Admin. */
  unit: UnitRole | null
}

export const DashboardContext = createContext<Dashboard | null>(null)

/** The signed-in user, their dashboard role and current unit. Use inside the shell only. */
export function useDashboard(): Dashboard {
  const value = useContext(DashboardContext)
  if (!value) throw new Error('useDashboard must be used inside the dashboard shell')
  return value
}

/** Page subtitle: the company for the EA, the current unit for a BU Admin. */
export function contextLine({ me, unit }: Dashboard): string {
  return unit?.name ?? me.tenant_name
}
