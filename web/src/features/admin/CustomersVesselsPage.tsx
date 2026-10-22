import { CustomersPage } from './CustomersPage'
import { RegionsPage } from './RegionsPage'
import { TabbedPage } from './TabbedPage'
import { VesselsAdminPage } from './VesselsAdminPage'

/** FR-21 customers and vessels, and the regions that scope them (FR-24). */
export function CustomersVesselsPage() {
  return (
    <TabbedPage
      title="Customers & vessels"
      subtitle="Who PPG supplies, their vessels and the region each customer sits in"
      tabs={[
        {
          key: 'customers',
          label: 'Customers',
          needs: 'manage-customers',
          content: <CustomersPage />,
        },
        {
          key: 'vessels',
          label: 'Vessels',
          needs: 'manage-vessels',
          content: <VesselsAdminPage />,
        },
        { key: 'regions', label: 'Regions', needs: 'manage-geography', content: <RegionsPage /> },
      ]}
    />
  )
}
