import { ItemsPage } from './ItemsPage'
import { TabbedPage } from './TabbedPage'

/** FR-25 master item list. The label schema (FR-26) is deferred past the pilot (data model review, 2 Nov). */
export function ProductsPage() {
  return (
    <TabbedPage
      title="Products"
      subtitle="The items Sea Stock recognises"
      tabs={[
        { key: 'items', label: 'Master item list', needs: ['manage-items'], content: <ItemsPage /> },
      ]}
    />
  )
}
