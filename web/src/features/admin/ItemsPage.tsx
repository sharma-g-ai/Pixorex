import { useState } from 'react'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { StatusBadge } from '../../components/StatusBadge'
import { DataTable } from '../../components/DataTable'
import { FilePicker } from '../../components/FilePicker'
import { Dialog } from '../../components/Dialog'
import { Icon } from '../../components/icons'
import { SectionBar } from './SectionBar'
import { Card, Mono, Muted, Note } from '../../components/Page'
import { FilterBar } from '../../components/ScopeFilters'
import { SelectField } from '../../components/SelectField'
import { ComponentBadge } from '../../components/StockBadges'
import { TextField } from '../../components/TextField'
import type { ComponentType, Item } from '../../data/model'
import { items } from '../../data/sample'
import { addItems, setItemStatus, useStore } from '../../data/store'
import { formatLiters } from '../../lib/format'

/** FR-26: the master item list, with additions, retirements and bulk load. */
export function ItemsPage() {
  useStore()
  const rows = items
  const [component, setComponent] = useState('')
  const [status, setStatus] = useState('active')
  const [search, setSearch] = useState('')
  const [adding, setAdding] = useState(false)
  const [bulk, setBulk] = useState(false)
  const [retiring, setRetiring] = useState<Item | null>(null)
  const shown = rows.filter(
    (i) =>
      (!component || i.componentType === component) &&
      (!status || i.status === status) &&
      `${i.articleNo} ${i.product} ${i.shade}`.toLowerCase().includes(search.trim().toLowerCase()),
  )

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
            onChange={(e) => setComponent(e.target.value)}
            options={[
              { value: '', label: 'All' },
              { value: 'Base', label: 'Base' },
              { value: 'Hardener', label: 'Hardener' },
              { value: '1K', label: '1K' },
            ]}
          />
          <SelectField
            label="Status"
            className="w-36"
            value={status}
            onChange={(e) => setStatus(e.target.value)}
            options={[
              { value: 'active', label: 'Active' },
              { value: 'retired', label: 'Retired' },
              { value: '', label: 'All' },
            ]}
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
                {
                  header: 'Status',
                  width: 0.7,
                  cell: (i) => <StatusBadge status={i.status} />,
                },
                {
                  header: '',
                  width: 0.6,
                  align: 'right',
                  cell: (i) =>
                    i.status === 'active' ? (
                      <Button variant="danger-link" onClick={() => setRetiring(i)}>
                        Retire
                      </Button>
                    ) : (
                      <Button variant="link" onClick={() => setItemStatus(i.articleNo, 'active')}>
                        Restore
                      </Button>
                    ),
                },
              ]}
            />
          </div>
        </Card>
        <Note>
          Retired items stay on the list so past transactions keep their product details; the tablet
          stops offering them for new scans. Pack size is as printed; unit volume is the liters per
          can used for inventory (to confirm with PPG whether the two ever differ).
        </Note>
      </>

      {adding && (
        <ItemDialog
          existing={rows.map((r) => r.articleNo)}
          onClose={() => setAdding(false)}
          onSave={(i) => {
            addItems([i])
            setAdding(false)
          }}
        />
      )}
      {bulk && <BulkLoadDialog onClose={() => setBulk(false)} />}
      {retiring && (
        <Dialog
          title={`Retire ${retiring.articleNo}?`}
          onClose={() => setRetiring(null)}
          footer={
            <>
              <Button variant="secondary" onClick={() => setRetiring(null)}>
                Cancel
              </Button>
              <Button
                variant="danger"
                onClick={() => {
                  setItemStatus(retiring.articleNo, 'retired')
                  setRetiring(null)
                }}
              >
                Retire item
              </Button>
            </>
          }
        >
          {retiring.product} {retiring.shade || retiring.componentType}, {retiring.packSize}. Stock
          already on board stays in Sea Stock; new scans of this article will be flagged for review.
        </Dialog>
      )}
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
    /^\d{6}$/.test(articleNo) && !duplicate && product.trim() && componentType && volume > 0
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
                componentType,
                packSize: `${volume} L`,
                unitVolume: volume,
                status: 'active',
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
    componentType: 'Base',
    packSize: '20 L',
    unitVolume: 20,
    status: 'active',
  },
  {
    articleNo: '189956',
    product: 'SIGMASHIELD 1200',
    shade: '',
    componentType: 'Hardener',
    packSize: '5 L',
    unitVolume: 5,
    status: 'active',
  },
  {
    articleNo: '184520',
    product: 'SIGMADUR 520',
    shade: 'Black 9000',
    componentType: 'Base',
    packSize: '20 L',
    unitVolume: 20,
    status: 'active',
  },
  {
    articleNo: '184521',
    product: 'SIGMADUR 520',
    shade: '',
    componentType: 'Hardener',
    packSize: '5 L',
    unitVolume: 5,
    status: 'active',
  },
  {
    articleNo: '181205',
    product: 'SIGMAPRIME 200',
    shade: 'Grey',
    componentType: 'Base',
    packSize: '20 L',
    unitVolume: 20,
    status: 'active',
  },
  {
    articleNo: '100294',
    product: 'PPG THINNER 91-10',
    shade: '',
    componentType: '1K',
    packSize: '5 L',
    unitVolume: 5,
    status: 'active',
  },
]

/** Bulk load from PPG's Excel list (D-02). The preview shows what the file would change. */
function BulkLoadDialog({ onClose }: { onClose: () => void }) {
  const [file, setFile] = useState<string | null>(null)
  // Static screens: whatever file is picked, its rows are this sample of PPG's list.
  const fileRows = [...items.slice(0, 11), ...bulkSample]
  const fresh = fileRows.filter((r) => !items.some((i) => i.articleNo === r.articleNo))
  const preview = [
    { label: 'New items', count: fresh.length, tone: 'success' as const },
    {
      label: 'Already on the list',
      count: fileRows.length - fresh.length,
      tone: 'neutral' as const,
    },
    { label: 'Rows with errors — skipped', count: 1, tone: 'danger' as const },
  ]
  return (
    <Dialog
      title="Bulk load items"
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            disabled={!file || fresh.length === 0}
            onClick={() => {
              addItems(fresh)
              onClose()
            }}
          >
            {fresh.length === 0 ? 'Nothing new to load' : `Load ${fresh.length} new items`}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <p>
          Upload PPG’s item list as Excel (.xlsx) or CSV with the columns: article number, product,
          shade, component type, pack size, unit volume. Items missing from the file are not retired
          automatically.
        </p>
        <FilePicker
          accept=".xlsx,.csv"
          hint=".xlsx or .csv"
          fileName={file}
          onPick={(f) => setFile(f.name)}
        />
        {file && (
          <div className="flex flex-col gap-2">
            {preview.map((p) => (
              <div key={p.label} className="flex items-center justify-between">
                <span>{p.label}</span>
                <Badge tone={p.tone}>{p.count}</Badge>
              </div>
            ))}
            <Note tone="warning">
              Row 14: component type “2K” is not allowed — use Base or Hardener.
            </Note>
          </div>
        )}
      </div>
    </Dialog>
  )
}
