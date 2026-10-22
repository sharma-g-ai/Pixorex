import type { IconName } from '../components/icons'
import type { User } from '../data/model'
import { can, type Permission } from '../data/roles'

export interface NavItem {
  path: string
  label: string
  icon: IconName
  /** BRD requirements the screen covers. */
  brd: string
  /** Hidden from roles without it. */
  needs: Permission
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
        brd: 'FR-20, FR-25, §13',
        needs: 'view-overview',
      },
      {
        path: '/sea-stock',
        label: 'Sea Stock',
        icon: 'box',
        brd: 'FR-09, FR-20, FR-25',
        needs: 'view-stock',
      },
      {
        path: '/consumption',
        label: 'Consumption',
        icon: 'droplet',
        brd: 'FR-07, FR-20, FR-25',
        needs: 'view-stock',
      },
      {
        path: '/activity',
        label: 'Activity',
        icon: 'activity',
        brd: 'FR-01 – FR-05, FR-12, FR-13',
        needs: 'view-stock',
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
        brd: 'FR-21, FR-24',
        needs: 'manage-customers',
      },
      {
        path: '/admin/users',
        label: 'Users',
        icon: 'users',
        brd: 'FR-22, FR-23',
        needs: 'manage-users',
      },
      {
        path: '/admin/products',
        label: 'Products',
        icon: 'list',
        brd: 'FR-26, FR-27',
        needs: 'manage-items',
      },
    ],
  },
]

export function navigationFor(user: User): NavSection[] {
  return sections
    .map((s) => ({ ...s, items: s.items.filter((i) => can(user, i.needs)) }))
    .filter((s) => s.items.length > 0)
}

export function allowedPath(user: User, path: string): boolean {
  const item = sections.flatMap((s) => s.items).find((i) => path.startsWith(i.path))
  return !item || can(user, item.needs)
}

/** Where a role lands after sign-in: a Chief Officer goes straight to their vessel's stock. */
export function homePath(user: User): string {
  return can(user, 'view-overview') ? '/overview' : '/sea-stock'
}
