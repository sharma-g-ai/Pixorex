import { RolesPage } from './RolesPage'
import { TabbedPage } from './TabbedPage'
import { UsersPage } from './UsersPage'

/** FR-22 users, and what each role may see and do (FR-23). */
export function UsersRolesPage() {
  return (
    <TabbedPage
      title="Users"
      subtitle="Who has access, their role and their scope"
      tabs={[
        { key: 'users', label: 'Users', needs: ['manage-users'], content: <UsersPage /> },
        {
          key: 'roles',
          label: 'Roles & permissions',
          needs: ['manage-users'],
          content: <RolesPage />,
        },
      ]}
    />
  )
}
