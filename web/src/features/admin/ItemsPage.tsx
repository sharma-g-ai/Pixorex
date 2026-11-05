import { useState } from 'react'
import { useViewer } from '../../app/viewer'
import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { Icon } from '../../components/icons'
import { ImportDialog } from './ImportDialog'
import { SectionBar } from './SectionBar'
import { Card, Mono, Muted, Note } from '../../components/Page'
import { FilterBar } from '../../components/ScopeFilters'
import { SelectField } from '../../components/SelectField'
import { ComponentBadge } from '../../components/StockBadges'
import { TextField } from '../../components/TextField'
import type { ComponentType, Item } from '../../data/model'
import { items } from '../../data/sample'
import { addItems, useStore } from '../../data/store'
import { componentOptions, itemMatches } from '../../lib/filters'
import { formatLiters } from '../../lib/format'

/** FR-25: the master item list, with additions and bulk load. It only grows: articles are never retired. */
export function ItemsPage() {
  useStore()
  const { user } = useViewer()
  const rows = items
  const [component, setComponent] = useState<ComponentType | ''>('')
  const [search, setSearch] = useState('')
  const [adding, setAdding] = useState(false)
  const [bulk, setBulk] = useState(false)
  const shown = rows.filter((i) => itemMatches(i, component, search))

  return (
    <>
      <SectionBar
        title="Master item list"
        subtitle="Every Sea Stock product PPG recognises, by article number"
        actions={
          <>
            <Button variant="secondary" onClick={() => setBulk(true)}>
              <Icon name="upload" /> Bulk load
            </Button>
            <Button onClick={() => setAdding(true)}>
              <Icon name="plus" /> Add item
            </Button>
          </>
        }
      />
      <>
        <FilterBar>
          <SelectField
            label="Component type"
            className="w-40"
            value={component}
            onChange={(e) => setComponent(e.target.value as ComponentType | '')}
            options={componentOptions}
          />
          <TextField
            label="Search"
            placeholder="Article no., product or shade"
            className="w-64"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </FilterBar>
        <Card flush>
          <div className="p-4">
            <DataTable
              label="Master item list"
              rows={shown}
              rowKey={(i) => i.articleNo}
              empty="No items match these filters"
              columns={[
                { header: 'Article no.', width: 0.8, cell: (i) => <Mono>{i.articleNo}</Mono> },
                { header: 'Product', width: 1.5, cell: (i) => <b>{i.product}</b> },
                {
                  header: 'Shade',
                  width: 1.1,
                  cell: (i) => i.shade || <span className="text-ink-subtle">—</span>,
                },
                { header: 'Type', width: 0.5, cell: (i) => i.productType },
                {
                  header: 'Component',
                  width: 0.9,
                  cell: (i) => <ComponentBadge type={i.componentType} />,
                },
                { header: 'Pack size', width: 0.7, align: 'right', cell: (i) => i.packSize },
                {
                  header: 'Unit volume',
                  width: 0.8,
                  align: 'right',
                  cell: (i) => formatLiters(i.unitVolume),
                },
              ]}
            />
          </div>
        </Card>
        <Note>
          The master list only grows: articles are never retired or deleted. Pack size is as printed; unit
          volume is the liters per can used for inventory (to confirm with PPG whether the two ever differ).
        </Note>
      </>

      {adding && (
        <ItemDialog
          existing={rows.map((r) => r.articleNo)}
          onClose={() => setAdding(false)}
          onSave={(i) => {
            addItems([i], user)
            setAdding(false)
          }}
        />
      )}
      {bulk && <BulkLoadDialog onClose={() => setBulk(false)} />}
    </>
  )
}

function ItemDialog({
  existing,
  onClose,
  onSave,
}: {
  existing: string[]
  onClose: () => void
  onSave: (i: Item) => void
}) {
  const [articleNo, setArticleNo] = useState('')
  const [product, setProduct] = useState('')
  const [shade, setShade] = useState('')
  const [kind, setKind] = useState<'1K' | '2K' | ''>('')
  const [component, setComponent] = useState<ComponentType | ''>('')
  const [packSize, setPackSize] = useState('')
  const duplicate = existing.includes(articleNo)
  const volume = Number(packSize.replace(',', '.'))
  const componentType: ComponentType | '' = kind === '1K' ? '1K' : component
  const ready =
    /^\d{6}$/.test(articleNo) && !duplicate && product.trim() && kind && componentType && volume > 0
  return (
    <Dialog
      title="Add item"
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            disabled={!ready}
            onClick={() =>
              componentType &&
              onSave({
                articleNo,
                product: product.trim().toUpperCase(),
                shade: shade.trim(),
                productType: kind === '1K' ? '1K' : '2K',
                componentType,
                packSize: `${volume} L`,
                unitVolume: volume,
              })
            }
          >
            Add item
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <div className="grid grid-cols-2 gap-3">
          <TextField
            label="Article number"
            inputMode="numeric"
            value={articleNo}
            onChange={(e) => setArticleNo(e.target.value.replace(/\D/g, '').slice(0, 6))}
            error={duplicate ? 'Already on the list' : undefined}
          />
          <TextField
            label="Pack size (liters)"
            inputMode="decimal"
            placeholder="e.g. 20"
            value={packSize}
            onChange={(e) => setPackSize(e.target.value)}
          />
        </div>
        <TextField
          label="Product"
          placeholder="e.g. SIGMACOVER 350"
          value={product}
          onChange={(e) => setProduct(e.target.value)}
        />
        <TextField
          label="Shade / colour"
          placeholder="Leave empty for hardeners and thinners"
          value={shade}
          onChange={(e) => setShade(e.target.value)}
        />
        <div className="grid grid-cols-2 gap-3">
          <SelectField
            label="Product type"
            value={kind}
            onChange={(e) => {
              setKind(e.target.value as '1K' | '2K' | '')
              setComponent('')
            }}
            options={[
              { value: '', label: 'Choose…' },
              { value: '1K', label: 'One component (1K)' },
              { value: '2K', label: 'Two components (2K)' },
            ]}
          />
          <SelectField
            label="Component type"
            value={componentType}
            disabled={kind !== '2K'}
            onChange={(e) => setComponent(e.target.value as ComponentType | '')}
            options={
              kind === '1K'
                ? [{ value: '1K', label: '1K' }]
                : [
                    { value: '', label: kind ? 'Choose…' : 'Pick the product type first' },
                    { value: 'Base', label: 'Base' },
                    { value: 'Hardener', label: 'Hardener' },
                  ]
            }
          />
        </div>
        <Muted>
          Rule D-10: a 1K product (thinners included) is component type 1K; a 2K product is Base or
          Hardener.
        </Muted>
      </div>
    </Dialog>
  )
}

/** New rows in the sample PPG file used by the bulk-load preview. */
const bulkSample: Item[] = [
  {
    articleNo: '189955',
    product: 'SIGMASHIELD 1200',
    shade: 'Grey',
    productType: '2K',
    componentType: 'Base',
    packSize: '20 L',
    unitVolume: 20,
  },
  {
    articleNo: '189956',
    product: 'SIGMASHIELD 1200',
    shade: '',
    productType: '2K',
    componentType: 'Hardener',
    packSize: '5 L',
    unitVolume: 5,
  },
  {
    articleNo: '184520',
    product: 'SIGMADUR 520',
    shade: 'Black 9000',
    productType: '2K',
    componentType: 'Base',
    packSize: '20 L',
    unitVolume: 20,
  },
  {
    articleNo: '184521',
    product: 'SIGMADUR 520',
    shade: '',
    productType: '2K',
    componentType: 'Hardener',
    packSize: '5 L',
    unitVolume: 5,
  },
  {
    articleNo: '181205',
    product: 'SIGMAPRIME 200',
    shade: 'Grey',
    productType: '2K',
    componentType: 'Base',
    packSize: '20 L',
    unitVolume: 20,
  },
  {
    articleNo: '100294',
    product: 'PPG THINNER 91-10',
    shade: '',
    productType: '1K',
    componentType: '1K',
    packSize: '5 L',
    unitVolume: 5,
  },
]

/** Bulk load from PPG's Excel list (D-02). Articles already on the list are left as they are. */
function BulkLoadDialog({ onClose }: { onClose: () => void }) {
  const { user } = useViewer()
  const fileRows = [...items.slice(0, 11), ...bulkSample]
  const fresh = fileRows.filter((r) => !items.some((i) => i.articleNo === r.articleNo))
  return (
    <ImportDialog
      title="Bulk load items"
      intro="Upload PPG’s item list as Excel (.xlsx) or CSV with the columns: article number, product, shade, product type, component type, pack size, unit volume. Items missing from the file stay on the list."
      counts={[
        { label: 'New items', count: fresh.length, tone: 'success' },
        { label: 'Already on the list', count: fileRows.length - fresh.length, tone: 'neutral' },
      ]}
      problems={['Row 14: a 2K product needs component type Base or Hardener, not “2K”.']}
      toLoad={fresh.length}
      noun="new items"
      onLoad={() => addItems(fresh, user)}
      onClose={onClose}
    />
  )
}
