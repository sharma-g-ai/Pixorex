import { cleanup, render, screen, within } from '@testing-library/react'
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
    const toCheck = screen.getByRole('table', { name: 'Delivery notes to check' })
    expect(toCheck).toHaveTextContent('5324664017') // IMO mismatch
    expect(toCheck).toHaveTextContent('5324655402') // IMO not read
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
      'Maintain the master item list',
    )
    expect(screen.getByRole('table', { name: 'Permissions' })).not.toHaveTextContent('label schema')
  })
})

describe('portal fixes', () => {
  it('sign-in returns to the page that was asked for', async () => {
    const { fireEvent } = await import('@testing-library/react')
    sessionStorage.clear()
    window.history.pushState({}, '', '/activity?tab=audit')
    render(<App />)
    fireEvent.change(await screen.findByLabelText('Work e-mail'), { target: { value: 'dana.whitfield@ppg.example' } })
    fireEvent.change(screen.getByLabelText('Password'), { target: { value: 'SeaStock@2026' } })
    fireEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByRole('table', { name: 'Audit log' })).toBeInTheDocument()
    expect(window.location.search).toBe('?tab=audit')
  })

  it('days go by the calendar, not by 24-hour periods', async () => {
    const { daysSince } = await import('../data/queries')
    expect(daysSince('2026-10-21T00:05')).toBe(0)
    expect(daysSince('2026-10-20T22:40')).toBe(1) // 17 hours ago, but yesterday
    expect(daysSince('2026-10-14T11:30')).toBe(7)
    expect(daysSince('2026-10-01')).toBe(20)
    expect(daysSince(null)).toBeNull()
  })

  it('a custom date cannot be emptied', async () => {
    const { fireEvent } = await import('@testing-library/react')
    await open('u01', '/consumption')
    fireEvent.change(screen.getByLabelText('Period'), { target: { value: 'custom' } })
    fireEvent.change(screen.getByLabelText('From'), { target: { value: '' } })
    fireEvent.change(screen.getByLabelText('To'), { target: { value: '' } })
    expect(document.body).not.toHaveTextContent('NaN')
    expect(document.body).not.toHaveTextContent('undefined')
  })

  it('the sidebar shows a new name straight away', async () => {
    const { act } = await import('@testing-library/react')
    const { saveUser } = await import('../data/store')
    const { users } = await import('../data/sample')
    await open('u01', '/overview')
    const dana = users.find((u) => u.id === 'u01')
    if (!dana) throw new Error('sample missing')
    act(() => saveUser({ ...dana, name: 'Dana Renamed' }, dana))
    expect(screen.getByRole('complementary')).toHaveTextContent('Dana Renamed')
  })

  it('the sidebar link clears a vessel from a link, from the filter and from a customer', async () => {
    const { fireEvent } = await import('@testing-library/react')
    await open('u01', '/sea-stock?vessel=v01')
    expect(screen.getByRole('main')).toHaveTextContent('1 vessel ·')
    const seaStock = () => within(screen.getByRole('complementary')).getByRole('link', { name: /Sea Stock/ })
    fireEvent.click(seaStock())
    expect(await screen.findByText(/^12 vessels/)).toBeInTheDocument()

    fireEvent.change(screen.getByLabelText('Vessel'), { target: { value: 'v02' } })
    expect(window.location.search).toBe('?vessel=v02')
    expect(await screen.findByRole('heading', { name: 'Nordhavn Borealis' })).toBeInTheDocument()
    fireEvent.click(seaStock())
    expect(await screen.findByText(/^12 vessels/)).toBeInTheDocument()

    fireEvent.change(screen.getByLabelText('Customer'), { target: { value: 'c1' } })
    expect(await screen.findByText(/^4 vessels/)).toBeInTheDocument()
    fireEvent.click(seaStock())
    expect(await screen.findByText(/^12 vessels/)).toBeInTheDocument()
  })

  it('a vessel outside the user’s scope is ignored, on every filtered screen', async () => {
    for (const path of ['/sea-stock?vessel=v05', '/consumption?vessel=v05', '/activity?vessel=v05&customer=c2']) {
      await open('u06', path)
      expect(screen.getByRole('main')).not.toHaveTextContent('Meridian')
      expect(screen.getByRole('main')).not.toHaveTextContent('0 vessels')
      if (path.includes('sea-stock')) expect(screen.getByRole('main')).toHaveTextContent('4 vessels')
      cleanup()
    }
  })

  it('Activity keeps the vessel filter across tabs and delivery notes', async () => {
    const { fireEvent } = await import('@testing-library/react')
    await open('u01', '/activity?vessel=v01')
    fireEvent.click(screen.getByRole('tab', { name: 'Delivery notes' }))
    expect(new URLSearchParams(window.location.search).get('vessel')).toBe('v01')
    fireEvent.click(await screen.findByRole('link', { name: /5324641215/ }))
    const search = new URLSearchParams(window.location.search)
    expect([search.get('vessel'), search.get('tab'), search.get('dn')]).toEqual(['v01', 'notes', '5324641215'])
    expect(await screen.findByRole('table', { name: 'Tally' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Close' }))
    expect(new URLSearchParams(window.location.search).get('vessel')).toBe('v01')
    fireEvent.click(screen.getByRole('tab', { name: 'Transactions' }))
    expect(window.location.search).toBe('?vessel=v01')
  })
})

describe('Consumption (FR-20, FR-24)', () => {
  it('shows the last sync, for one vessel and across vessels', async () => {
    const { fireEvent } = await import('@testing-library/react')
    await open('u01', '/consumption?vessel=v01')
    expect(screen.getByText('Last sync')).toBeInTheDocument()
    expect(screen.getByRole('main')).toHaveTextContent('21 Oct 2026, 08:12')
    cleanup()
    await open('u01', '/consumption')
    expect(screen.getByText('Oldest sync of these vessels')).toBeInTheDocument()
    // Straits Endeavour never synced, but it has no consumption, so it does not count here.
    expect(screen.getByRole('main')).toHaveTextContent('12 Oct 2026, 16:00')
    expect(screen.getByRole('main')).not.toHaveTextContent('Never synced')
    fireEvent.click(screen.getByRole('tab', { name: 'By vessel' }))
    const byVessel = await screen.findByRole('table', { name: 'Consumption by vessel' })
    expect(byVessel).toHaveTextContent('Last sync')
    expect(byVessel).toHaveTextContent('21 Oct 2026, 08:12')
    fireEvent.click(screen.getByRole('tab', { name: 'By customer' }))
    expect(await screen.findByRole('table', { name: 'Consumption by customer' })).toHaveTextContent('Oldest sync')
  })

  it('filters by component type and search, and the totals follow', async () => {
    const { fireEvent } = await import('@testing-library/react')
    await open('u01', '/consumption')
    const table = () => screen.getByRole('table', { name: 'Consumption by product' })
    expect(table()).toHaveTextContent('Hardener')
    fireEvent.change(screen.getByLabelText('Component type'), { target: { value: 'Base' } })
    expect(table()).not.toHaveTextContent('Hardener')
    fireEvent.change(screen.getByLabelText('Component type'), { target: { value: '' } })
    fireEvent.change(screen.getByLabelText('Search'), { target: { value: '100293' } })
    expect(table()).toHaveTextContent('PPG THINNER 21-06')
    expect(table()).not.toHaveTextContent('SIGMACOVER')
  })

  it('oldest sync is null when a vessel has never synced', async () => {
    const { oldestSync } = await import('../data/queries')
    const { vessels } = await import('../data/sample')
    const pick = (...ids: string[]) => vessels.filter((v) => ids.includes(v.id))
    expect(oldestSync(pick('v01', 'v04'))).toBe('2026-10-14T11:30')
    expect(oldestSync(pick('v01', 'v12'))).toBeNull()
    expect(oldestSync([])).toBeNull()
  })
})

describe('data model V2', () => {
  const pickFile = async (name: string) => {
    const { fireEvent } = await import('@testing-library/react')
    const input = screen.getByRole('dialog').querySelector('input[type="file"]')
    if (!input) throw new Error('no file input')
    fireEvent.change(input, { target: { files: [new File(['x'], name)] } })
  }

  it('Products has the master item list only, with no label schema and no retiring', async () => {
    await open('u01', '/admin/products')
    expect(screen.queryByRole('tab')).not.toBeInTheDocument()
    expect(screen.getByRole('table', { name: 'Master item list' })).toHaveTextContent('175510')
    expect(screen.queryByRole('button', { name: 'Retire' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Restore' })).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Status')).not.toBeInTheDocument()
    expect(document.body).not.toHaveTextContent('Label schema')
    expect(document.body).not.toHaveTextContent('Retired')
  })

  it('an old link to the label schema opens the master item list', async () => {
    await open('u01', '/admin/products?tab=label-schema')
    expect(screen.getByRole('table', { name: 'Master item list' })).toBeInTheDocument()
  })

  it('a tablet offers prepare to retire, retire now and revoke; retire now asks first', async () => {
    const { fireEvent, within } = await import('@testing-library/react')
    await open('u01', '/admin/customers?tab=tablets')
    const row = within(screen.getByRole('table', { name: 'Tablets' })).getByText('TAB-0101').closest('[role="row"], tr')
    if (!(row instanceof HTMLElement)) throw new Error('no row')
    within(row).getByRole('button', { name: 'Prepare to retire' })
    within(row).getByRole('button', { name: 'Revoke' })
    fireEvent.click(within(row).getByRole('button', { name: 'Prepare to retire' }))
    expect(await within(row).findByText('Retires at next sync')).toBeInTheDocument()
    expect(within(row).queryByRole('button', { name: 'Prepare to retire' })).not.toBeInTheDocument()

    fireEvent.click(within(row).getByRole('button', { name: 'Retire now' }))
    const dialog = within(screen.getByRole('dialog'))
    expect(dialog.getByText(/Anything still on it will not reach Sea Stock/)).toBeInTheDocument()
    fireEvent.click(dialog.getByRole('button', { name: 'Retire now' }))
    expect(await within(row).findByText('Retired')).toBeInTheDocument()
    expect(within(row).getByText('No longer paired')).toBeInTheDocument()
  })

  it('pairing has no replace option and warns while the vessel still has a tablet', async () => {
    const { fireEvent, within } = await import('@testing-library/react')
    await open('u01', '/admin/customers?tab=vessels')
    const row = within(screen.getByRole('table', { name: 'Vessels' })).getByText('Nordhavn Aurora').closest('[role="row"], tr')
    if (!(row instanceof HTMLElement)) throw new Error('no row')
    fireEvent.click(within(row).getByRole('button', { name: 'Pair tablet' }))
    const dialog = within(screen.getByRole('dialog'))
    expect(dialog.queryByRole('checkbox')).not.toBeInTheDocument()
    expect(dialog.getByText(/is still active/)).toBeInTheDocument()
  })

  it('an open code is never shown again; a new one is shown once', async () => {
    const { fireEvent, within } = await import('@testing-library/react')
    await open('u01', '/admin/customers?tab=vessels')
    const row = within(screen.getByRole('table', { name: 'Vessels' })).getByText('Straits Endeavour').closest('[role="row"], tr')
    if (!(row instanceof HTMLElement)) throw new Error('no row')
    fireEvent.click(within(row).getByRole('button', { name: 'Pair tablet' }))
    const dialog = within(screen.getByRole('dialog'))
    expect(dialog.getByText(/A code is open/)).toBeInTheDocument()
    expect(document.body).not.toHaveTextContent('K7QM')
    fireEvent.click(dialog.getByRole('button', { name: 'Issue a new code' }))
    expect(await dialog.findByText(/only time the code is shown/)).toBeInTheDocument()
    expect(dialog.getByTitle('Enrolment QR code')).toBeInTheDocument()
  })

  it('a vessel’s customer cannot be changed; a new vessel’s can be chosen', async () => {
    const { fireEvent, within } = await import('@testing-library/react')
    await open('u01', '/admin/customers?tab=vessels')
    fireEvent.click(screen.getAllByRole('button', { name: 'Edit' })[0] as HTMLElement)
    expect(within(screen.getByRole('dialog')).getByLabelText('Customer')).toBeDisabled()
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Cancel' }))
    fireEvent.click(screen.getByRole('button', { name: 'Add vessel' }))
    expect(within(screen.getByRole('dialog')).getByLabelText('Customer')).toBeEnabled()
  })

  it('one bad row refuses a vessel file; a clean file loads', async () => {
    const { fireEvent, within } = await import('@testing-library/react')
    await open('u01', '/admin/customers?tab=vessels')
    fireEvent.click(screen.getByRole('button', { name: /Import from Excel/ }))
    await pickFile('vessels-error.xlsx')
    const dialog = within(screen.getByRole('dialog'))
    expect(dialog.getByText('File refused — nothing was loaded')).toBeInTheDocument()
    expect(dialog.getByText(/fails the check digit/)).toBeInTheDocument()
    expect(dialog.getByText(/belongs to another customer\.$/)).toBeInTheDocument()
    expect(dialog.getByRole('button', { name: 'File refused' })).toBeDisabled()
    expect(dialog.queryByText('New vessels')).not.toBeInTheDocument()

    await pickFile('vessels.xlsx')
    expect(await dialog.findByText('New vessels')).toBeInTheDocument()
    expect(dialog.getByRole('button', { name: /^Load / })).toBeEnabled()
  })

  it('one bad row refuses a customer file too', async () => {
    const { fireEvent, within } = await import('@testing-library/react')
    await open('u01', '/admin/customers')
    fireEvent.click(screen.getByRole('button', { name: /Import from Excel/ }))
    await pickFile('customers-error.csv')
    expect(within(screen.getByRole('dialog')).getByRole('button', { name: 'File refused' })).toBeDisabled()
  })

  it('a bulk load of items still skips bad rows and loads the rest', async () => {
    const { fireEvent, within } = await import('@testing-library/react')
    await open('u01', '/admin/products')
    fireEvent.click(screen.getByRole('button', { name: /Bulk load/ }))
    await pickFile('items-error.xlsx')
    const dialog = within(screen.getByRole('dialog'))
    expect(dialog.getByText('Rows with errors — skipped')).toBeInTheDocument()
    expect(dialog.getByRole('button', { name: /^Load / })).toBeEnabled()
  })

  it('a delivery note line not in the master list is shown as held, then as matched', async () => {
    const { within } = await import('@testing-library/react')
    const { matchScan } = await import('../data/store')
    const { unrecognisedScans, users } = await import('../data/sample')
    await open('u01', '/activity?tab=notes&dn=5324655402')
    expect(within(screen.getByRole('table', { name: 'Tally' })).getByText(/Not in the master list/)).toBeInTheDocument()
    cleanup()
    const scan = unrecognisedScans.find((s) => s.id === 'us1')
    const dana = users.find((u) => u.id === 'u01')
    if (!scan || !dana) throw new Error('sample missing')
    matchScan(scan, '179061', dana)
    await open('u01', '/activity?tab=notes&dn=5324655402')
    const tally = screen.getByRole('table', { name: 'Tally' })
    expect(tally).toHaveTextContent('matched to 179061')
    expect(tally).not.toHaveTextContent('Not in the master list')
  })

  it('Sea Stock updates straight after a portal adjustment', async () => {
    const { act } = await import('@testing-library/react')
    const { adjustStock } = await import('../data/store')
    const { users } = await import('../data/sample')
    await open('u01', '/sea-stock?vessel=v04')
    const before = screen.getByRole('table', { name: 'Sea Stock' }).textContent
    const dana = users.find((u) => u.id === 'u01')
    if (!dana) throw new Error('sample missing')
    act(() => adjustStock('v04', '179061', 5, 'Test', dana))
    expect(screen.getByRole('table', { name: 'Sea Stock' }).textContent).not.toBe(before)
  })

  it('a new user’s e-mail is saved in lower case', async () => {
    const { fireEvent, within } = await import('@testing-library/react')
    const { users } = await import('../data/sample')
    await open('u01', '/admin/users')
    fireEvent.click(screen.getByRole('button', { name: /Invite user/ }))
    const form = within(screen.getByRole('dialog'))
    fireEvent.change(form.getByLabelText('Full name'), { target: { value: 'Test Person' } })
    fireEvent.change(form.getByLabelText('Work e-mail'), { target: { value: 'Test.Person@PPG.example' } })
    fireEvent.click(form.getByRole('button', { name: 'Send invite' }))
    expect(users.some((u) => u.email === 'test.person@ppg.example')).toBe(true)
  })
})
