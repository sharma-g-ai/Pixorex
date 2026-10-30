import { cleanup, render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { users } from '../data/sample'
import { App } from './App'

const paths = [
  '/',
  '/sea-stock?vessel=v01',
  '/activity?tab=notes',
  '/activity?dn=5324641215',
  '/admin/customers?tab=vessels',
  '/admin/customers?tab=tablets',
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
  for (const userId of ['u01', 'u03', 'u06', 'u08', 'u11']) {
    for (const path of paths) {
      it(`${users.find((u) => u.id === userId)?.role} ${path}`, async () => {
        sessionStorage.setItem('seastock.session', userId)
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
  sessionStorage.setItem('seastock.session', userId)
  window.history.pushState({}, '', path)
  render(<App />)
  await screen.findByRole('heading', { level: 1 })
}

describe('merged screens keep what they took over', () => {
  it('a Customer Admin manages their vessels and tablets, not customers', async () => {
    await open('u06', '/admin/customers')
    expect(screen.getByRole('tab', { name: 'Vessels' })).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: 'Tablets' })).toBeInTheDocument()
    expect(screen.queryByRole('tab', { name: 'Customers' })).not.toBeInTheDocument()
    expect(screen.getByRole('table', { name: 'Vessels' })).toHaveTextContent('Nordhavn Aurora')
    expect(screen.getByRole('table', { name: 'Vessels' })).not.toHaveTextContent('Meridian Valencia')
    expect(screen.queryByRole('button', { name: /Add vessel/ })).not.toBeInTheDocument()
  })

  it('Overview shows late sync, negative stock and unrecognised scans', async () => {
    await open('u01', '/overview')
    expect(screen.getByRole('table', { name: 'Late sync' })).toHaveTextContent('Gulf Sentinel')
    expect(screen.getByRole('table', { name: 'Negative stock' })).toHaveTextContent(
      'Meridian Genoa',
    )
    expect(screen.getByRole('table', { name: 'Unrecognised scans' })).toHaveTextContent('17906l')
    expect(screen.getByRole('table', { name: 'Held sync events' })).toHaveTextContent('Pacific Crest')
    expect(screen.getByRole('table', { name: 'IMO mismatches' })).toHaveTextContent('5324664017')
  })

  it('only a PPG Admin matches unrecognised scans', async () => {
    await open('u01', '/overview')
    expect(screen.getAllByRole('button', { name: 'Match to article' })).not.toHaveLength(0)
    cleanup()
    await open('u06', '/overview')
    expect(screen.queryByRole('button', { name: 'Match to article' })).not.toBeInTheDocument()
  })

  it('Sea Stock rolls up by customer for PPG, not for a Customer Admin', async () => {
    await open('u01', '/sea-stock')
    expect(screen.getByRole('tab', { name: 'By customer' })).toBeInTheDocument()
    cleanup()
    await open('u06', '/sea-stock')
    expect(screen.queryByRole('tab', { name: 'By customer' })).not.toBeInTheDocument()
    expect(screen.getByRole('tab', { name: 'By vessel' })).toBeInTheDocument()
  })

  it('a delivery note opens with its tally from Activity', async () => {
    await open('u01', '/activity?tab=notes&dn=5324641215')
    expect(screen.getByRole('table', { name: 'Tally' })).toHaveTextContent('Not on note')
  })

  it('a delivery note outside the user’s scope does not open', async () => {
    await open('u06', '/activity?dn=5324650871')
    expect(screen.queryByRole('table', { name: 'Tally' })).not.toBeInTheDocument()
  })

  it('admin screens hold their tabs', async () => {
    await open('u01', '/admin/customers')
    for (const name of ['Customers', 'Vessels', 'Tablets'])
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

describe('two portal roles', () => {
  it('uses the names from the reference screens', async () => {
    const { roles } = await import('../data/roles')
    expect(roles.map((r) => r.label)).toEqual(['PPG Admin', 'Customer Admin'])
  })

  it('only a PPG Admin runs master data; a Customer Admin manages their own fleet', async () => {
    const { can } = await import('../data/roles')
    const { users } = await import('../data/sample')
    const byId = (id: string) => {
      const user = users.find((u) => u.id === id)
      if (!user) throw new Error(id)
      return user
    }
    expect(can(byId('u01'), 'manage-customers')).toBe(true)
    expect(can(byId('u01'), 'match-scans')).toBe(true)
    expect(can(byId('u06'), 'manage-customers')).toBe(false) // Customer Admin
    expect(can(byId('u06'), 'match-scans')).toBe(false)
    expect(can(byId('u06'), 'manage-items')).toBe(false)
    expect(can(byId('u06'), 'manage-users')).toBe(true) // own customer
    expect(can(byId('u06'), 'manage-tablets')).toBe(true) // own vessels
  })
})

describe('sign-in', () => {
  async function signIn(email: string, password = 'SeaStock@2026') {
    const { fireEvent } = await import('@testing-library/react')
    sessionStorage.clear()
    window.history.pushState({}, '', '/sign-in')
    render(<App />)
    fireEvent.change(screen.getByLabelText('Work e-mail'), { target: { value: email } })
    fireEvent.change(screen.getByLabelText('Password'), { target: { value: password } })
    fireEvent.click(screen.getByRole('button', { name: 'Sign in' }))
  }

  it('a page needs sign-in first', async () => {
    sessionStorage.clear()
    window.history.pushState({}, '', '/sea-stock')
    render(<App />)
    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
  })

  it('PPG Admin lands on the overview with administration in the menu', async () => {
    await signIn('dana.whitfield@ppg.example')
    expect(await screen.findByRole('heading', { level: 1, name: 'Overview' })).toBeInTheDocument()
    expect(screen.getByText('Administration')).toBeInTheDocument()
  })

  it('Customer Admin lands on their customer only', async () => {
    await signIn('ingrid.solberg@nordhavn.example')
    expect(
      await screen.findByText('Nordhavn Bulk Carriers', { selector: 'div' }),
    ).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /Products/ })).not.toBeInTheDocument()
  })

  it('wrong password, disabled and invited accounts cannot sign in', async () => {
    await signIn('dana.whitfield@ppg.example', 'wrong')
    expect(screen.getByRole('alert')).toHaveTextContent('E-mail or password is incorrect.')
    cleanup()
    await signIn('tom.hughes@ppg.example')
    expect(screen.getByRole('alert')).toHaveTextContent('disabled')
    cleanup()
    await signIn('nur.aisyah@straits.example')
    expect(screen.getByRole('alert')).toHaveTextContent('not set up yet')
  })

  it('sign out goes back to sign-in', async () => {
    const { fireEvent } = await import('@testing-library/react')
    await signIn('dana.whitfield@ppg.example')
    fireEvent.click(await screen.findByRole('button', { name: 'Sign out' }))
    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
  })
})

describe('changes show on other screens', () => {
  it('a customer added on one screen can be picked when adding a vessel', async () => {
    const { fireEvent, within } = await import('@testing-library/react')
    sessionStorage.setItem('seastock.session', 'u01')
    window.history.pushState({}, '', '/admin/customers')
    render(<App />)
    fireEvent.click(await screen.findByRole('button', { name: 'Add customer' }))
    const form = within(screen.getByRole('dialog'))
    fireEvent.change(form.getByLabelText('Customer name'), { target: { value: 'Test Lines' } })
    fireEvent.change(form.getByLabelText('Customer ID (as in PPG systems)'), {
      target: { value: 'C-999' },
    })
    fireEvent.click(form.getByRole('button', { name: 'Add customer' }))
    expect(await screen.findByText('Test Lines')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Vessels' }))
    fireEvent.click(await screen.findByRole('button', { name: 'Add vessel' }))
    expect(
      within(screen.getByRole('dialog')).getByRole('option', { name: 'Test Lines · C-999' }),
    ).toBeInTheDocument()
  })
})

describe('roles screen', () => {
  it('shows permissions in the shared table', async () => {
    sessionStorage.setItem('seastock.session', 'u01')
    window.history.pushState({}, '', '/admin/users?tab=roles')
    render(<App />)
    expect(await screen.findByRole('table', { name: 'Permissions' })).toHaveTextContent(
      'Maintain the label schema',
    )
  })
})
