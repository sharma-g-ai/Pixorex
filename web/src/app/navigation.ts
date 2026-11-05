import type { IconName } from '../components/icons'
import type { User } from '../data/model'
import { can, type Permission } from '../data/roles'

export interface NavItem {
  path: string
  label: string
  icon: IconName
  /** BRD requirements the screen covers. */
  brd: string
  /** Shown to roles with any of these. */
  needs: Permission[]
}

export interface NavSection {
  title?: string
  items: NavItem[]
}

const sections: NavSection[] = [
  {
    items: [
      {
        path: '/overview',
        label: 'Overview',
        icon: 'grid',
        brd: 'FR-20, FR-24, §13',
        needs: ['view-stock'],
      },
      {
        path: '/sea-stock',
        label: 'Sea Stock',
        icon: 'box',
        brd: 'FR-09, FR-13, FR-20, FR-24',
        needs: ['view-stock'],
      },
      {
        path: '/consumption',
        label: 'Consumption',
        icon: 'droplet',
        brd: 'FR-07, FR-20, FR-24',
        needs: ['view-stock'],
      },
      {
        path: '/activity',
        label: 'Activity',
        icon: 'activity',
        brd: 'FR-01 – FR-05, FR-12, FR-13',
        needs: ['view-stock'],
      },
    ],
  },
  {
    title: 'Administration',
    items: [
      {
        path: '/admin/customers',
        label: 'Customers & vessels',
        icon: 'building',
        brd: 'FR-21, A-14',
        needs: ['manage-customers', 'manage-tablets'],
      },
      {
        path: '/admin/users',
        label: 'Users',
        icon: 'users',
        brd: 'FR-22, FR-23',
        needs: ['manage-users'],
      },
      {
        path: '/admin/products',
        label: 'Products',
        icon: 'list',
        brd: 'FR-25',
        needs: ['manage-items'],
      },
    ],
  },
]

export function navigationFor(user: User): NavSection[] {
  return sections
    .map((s) => ({ ...s, items: s.items.filter((i) => i.needs.some((p) => can(user, p))) }))
    .filter((s) => s.items.length > 0)
}

export function allowedPath(user: User, path: string): boolean {
  const item = sections.flatMap((s) => s.items).find((i) => path.startsWith(i.path))
  return !item || item.needs.some((p) => can(user, p))
}

/** Where every portal user lands after sign-in. */
export const HOME_PATH = '/overview'
