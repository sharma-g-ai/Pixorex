import { ItemsPage } from './ItemsPage'
import { LabelSchemaPage } from './LabelSchemaPage'
import { TabbedPage } from './TabbedPage'

/** FR-25 master item list and FR-26 label schema: what the tablet recognises and how it reads labels. */
export function ProductsPage() {
  return (
    <TabbedPage
      title="Products"
      subtitle="The items Sea Stock recognises and how labels are read"
      tabs={[
        { key: 'items', label: 'Master item list', needs: ['manage-items'], content: <ItemsPage /> },
        {
          key: 'label-schema',
          label: 'Label schema',
          needs: ['manage-label-schema'],
          content: <LabelSchemaPage />,
        },
      ]}
    />
  )
}
