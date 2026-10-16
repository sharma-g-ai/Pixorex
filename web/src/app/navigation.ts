import type { IconName } from '../components/icons'
import type { DashboardRole } from './access'

export interface NavItem {
  path: string
  label: string
  icon: IconName
  /** Task that builds the screen; shown on the placeholder until then. */
  task: string
}

/** Sidebar menus, in the order the design canvas shows them. */
export const navigation: Record<DashboardRole, NavItem[]> = {
  enterprise_admin: [
    { path: '/overview', label: 'Overview', icon: 'grid', task: 'PX-04-T10 (EA-01)' },
    { path: '/bu-admins', label: 'BU Admins', icon: 'users', task: 'PX-04-T08 (EA-01)' },
    { path: '/locations', label: 'Locations', icon: 'pin', task: 'SPEC-PX-05 (EA-02), Sprint 3' },
    { path: '/scans', label: 'Scans', icon: 'table', task: 'SPEC-PX-08 (EA-03), Sprint 4' },
    {
      path: '/escalations',
      label: 'Escalated scans',
      icon: 'check-square',
      task: 'SPEC-PX-08 (EA-03), Sprint 4',
    },
    { path: '/audit-log', label: 'Audit log', icon: 'file', task: 'SPEC-PX-07 (EA-04), Sprint 4' },
  ],
  bu_admin: [
    { path: '/home', label: 'Home', icon: 'home', task: 'BU home, Sprint 4' },
    {
      path: '/review-queue',
      label: 'Review queue',
      icon: 'check-square',
      task: 'SPEC-PX-08 (BU-03), Sprint 4',
    },
    {
      path: '/delegations',
      label: 'Delegations',
      icon: 'delegate',
      task: 'SPEC-PX-08 (BU-04), Sprint 4',
    },
    {
      path: '/equipment-types',
      label: 'Equipment types',
      icon: 'tag',
      task: 'SPEC-PX-06 (BU-02), Sprint 3',
    },
    { path: '/technicians', label: 'Technicians', icon: 'users', task: 'PX-04-T11 (BU-01)' },
    { path: '/audit-log', label: 'Audit log', icon: 'file', task: 'Decision D-06, Sprint 4' },
  ],
}

export const roleLabel: Record<DashboardRole, string> = {
  enterprise_admin: 'Enterprise Admin',
  bu_admin: 'BU Admin',
}

/** The page a role lands on. */
export function homePath(role: DashboardRole): string {
  return navigation[role][0]?.path ?? '/'
}
