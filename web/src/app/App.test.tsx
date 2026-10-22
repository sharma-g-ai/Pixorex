import { cleanup, render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { users } from '../data/sample'
import { App } from './App'
import { previewUsers } from './viewer'

const paths = [
  '/',
  '/sea-stock?vessel=v01',
  '/activity?tab=notes',
  '/activity?dn=5324641215',
  '/admin/customers?tab=vessels',
  '/admin/customers?tab=regions',
  '/admin/users?tab=roles',
  '/admin/products?tab=label-schema',
  '/overview',
  '/sea-stock',

  '/consumption',

  '/activity',

  '/admin/customers',

  '/admin/users',
  '/admin/products',

  '/sign-in',
]

describe('every screen renders for every preview role', () => {
  for (const userId of previewUsers) {
    for (const path of paths) {
      it(`${users.find((u) => u.id === userId)?.role} ${path}`, async () => {
        sessionStorage.setItem('seastock.preview-user', userId)
        window.history.pushState({}, '', path)
        render(<App />)
        expect(await screen.findByRole('heading', { level: 1 })).toBeInTheDocument()
      })
    }
  }
})

describe('sample data', () => {
  it('sea stock is worked out from transactions and one line goes negative for review', async () => {
    const { negativeStock, stockLines } = await import('../data/queries')
    expect(negativeStock(['v06']).map((l) => [l.item.articleNo, l.cans])).toEqual([['184103', -2]])
    // v01: baseline 10 + DN 8 − consumed 7 of article 179061
    expect(stockLines(['v01']).find((l) => l.item.articleNo === '179061')?.cans).toBe(11)
  })
})

async function open(userId: string, path: string) {
  sessionStorage.setItem('seastock.preview-user', userId)
  window.history.pushState({}, '', path)
  render(<App />)
  await screen.findByRole('heading', { level: 1 })
}

describe('merged screens keep what they took over', () => {
  it('a Chief Officer lands on their own vessel on Sea Stock', async () => {
    await open('u12', '/')
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Sea Stock')
    expect(screen.getByRole('heading', { name: 'Nordhavn Aurora' })).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /Overview/ })).not.toBeInTheDocument()
  })

  it('Overview shows late sync, negative stock and unrecognised scans', async () => {
    await open('u01', '/overview')
    expect(screen.getByRole('table', { name: 'Late sync' })).toHaveTextContent('Gulf Sentinel')
    expect(screen.getByRole('table', { name: 'Negative stock' })).toHaveTextContent(
      'Meridian Genoa',
    )
    expect(screen.getByRole('table', { name: 'Unrecognised scans' })).toHaveTextContent('17906l')
  })

  it('Sea Stock rolls up by region for PPG, not for a customer', async () => {
    await open('u01', '/sea-stock')
    expect(screen.getByRole('tab', { name: 'By region' })).toBeInTheDocument()
    cleanup()
    await open('u06', '/sea-stock')
    expect(screen.queryByRole('tab', { name: 'By region' })).not.toBeInTheDocument()
    expect(screen.getByRole('tab', { name: 'By vessel' })).toBeInTheDocument()
  })

  it('a delivery note opens with its tally from Activity', async () => {
    await open('u01', '/activity?tab=notes&dn=5324641215')
    expect(screen.getByRole('table', { name: 'Tally' })).toHaveTextContent('Not on note')
  })

  it('a delivery note outside the user’s scope does not open', async () => {
    await open('u12', '/activity?dn=5324650871')
    expect(screen.queryByRole('table', { name: 'Tally' })).not.toBeInTheDocument()
  })

  it('admin screens hold their tabs', async () => {
    await open('u01', '/admin/customers')
    for (const name of ['Customers', 'Vessels', 'Regions'])
      expect(screen.getByRole('tab', { name })).toBeInTheDocument()
    cleanup()
    await open('u01', '/admin/products')
    for (const name of ['Master item list', 'Label schema'])
      expect(screen.getByRole('tab', { name })).toBeInTheDocument()
    cleanup()
    await open('u06', '/admin/users')
    expect(screen.getByRole('tab', { name: 'Roles & permissions' })).toBeInTheDocument()
  })
})
