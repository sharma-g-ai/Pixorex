import type { ComponentType, Item } from '../data/model'

/** The component type filter, the same on every screen. */
export const componentOptions: { value: ComponentType | ''; label: string }[] = [
  { value: '', label: 'All' },
  { value: 'Base', label: 'Base' },
  { value: 'Hardener', label: 'Hardener' },
  { value: '1K', label: '1K' },
]

/** True when an item passes the component type filter and the search box. */
export function itemMatches(item: Item, component: ComponentType | '', search: string): boolean {
  const text = `${item.articleNo} ${item.product} ${item.shade}`.toLowerCase()
  return (!component || item.componentType === component) && text.includes(search.trim().toLowerCase())
}
