import { CustomersPage } from './CustomersPage'
import { TabbedPage } from './TabbedPage'
import { TabletsPage } from './TabletsPage'
import { VesselsAdminPage } from './VesselsAdminPage'

/** FR-21 customers and vessels, and the tablet paired to each vessel. */
export function CustomersVesselsPage() {
  return (
    <TabbedPage
      title="Customers & vessels"
      subtitle="Who PPG supplies, their vessels and each vessel’s tablet"
      tabs={[
        { key: 'customers', label: 'Customers', needs: ['manage-customers'], content: <CustomersPage /> },
        {
          key: 'vessels',
          label: 'Vessels',
          needs: ['manage-vessels', 'import-vessels', 'manage-tablets', 'reset-vessel-password'],
          content: <VesselsAdminPage />,
        },
        { key: 'tablets', label: 'Tablets', needs: ['manage-tablets'], content: <TabletsPage /> },
      ]}
    />
  )
}
