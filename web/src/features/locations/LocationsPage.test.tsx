import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { LocationSetup } from '../../api/locations'
import { LocationsPage } from './LocationsPage'

const calls = {
  setLevels: vi.fn(),
  skeleton: vi.fn(),
  addNodes: vi.fn(),
  updateNode: vi.fn(),
  deleteNode: vi.fn(),
  publish: vi.fn(),
}
let setup: LocationSetup
let check: {
  placeholders_left: number
  empty_branches: unknown[]
  sample_path: string | null
  can_publish: boolean
} = {
  placeholders_left: 0,
  empty_branches: [] as unknown[],
  sample_path: 'Plant 04 › Bin 05',
  can_publish: true,
}

const mutation = (fn: ReturnType<typeof vi.fn>) => ({ mutateAsync: fn, isPending: false })
vi.mock('../../api/businessUnits', () => ({
  useBusinessUnits: () => ({ data: unitList }),
}))
const plant04 = {
  bu_id: 'p04',
  name: 'PPG Plant 04',
  facility_name: 'Plant 04',
  bu_admin: null,
  locations_status: 'not_published',
}
let unitList = [plant04]
vi.mock('../../api/locations', () => ({
  useLocationSetup: () => ({ data: setup, isPending: false, isError: false }),
  useSetLevels: () => mutation(calls.setLevels),
  useCreateSkeleton: () => mutation(calls.skeleton),
  useAddNodes: () => mutation(calls.addNodes),
  useUpdateNode: () => mutation(calls.updateNode),
  useDeleteNode: () => mutation(calls.deleteNode),
  usePublishCheck: () => ({ data: check, isPending: false, isError: false }),
  usePublishLocations: () => mutation(calls.publish),
}))

const levels = [
  { level_id: 'fac', level_name: 'Facility', level_order: 1, requirement: 'required' as const },
  { level_id: 'bin', level_name: 'Bin', level_order: 2, requirement: 'required' as const },
]
const withTree: LocationSetup = {
  version_id: 'v',
  status: 'not_published',
  levels,
  nodes: [
    {
      node_id: 'f',
      parent_id: null,
      level_id: 'fac',
      name: 'Plant 04',
      is_placeholder: false,
      child_count: 1,
    },
    {
      node_id: 'b1',
      parent_id: 'f',
      level_id: 'bin',
      name: 'Bin 01',
      is_placeholder: false,
      child_count: 0,
    },
  ],
}

const topNode = {
  node_id: 'f',
  parent_id: null,
  level_id: 'fac',
  name: 'Plant 04',
  is_placeholder: false,
  child_count: 1,
}

function renderPage() {
  render(
    <MemoryRouter initialEntries={['/locations?unit=p04']}>
      <LocationsPage />
    </MemoryRouter>,
  )
}
const dialog = () => within(screen.getByRole('dialog'))

beforeEach(() => {
  for (const fn of Object.values(calls)) fn.mockReset().mockResolvedValue({})
  unitList = [plant04]
  setup = withTree
  check = {
    placeholders_left: 0,
    empty_branches: [],
    sample_path: 'Plant 04 › Bin 05',
    can_publish: true,
  }
})

const empty: LocationSetup = { version_id: 'v', status: 'not_published', levels: [], nodes: [] }
const [fac, bin] = levels as [(typeof levels)[0], (typeof levels)[0]]
const sent = ({ level_id, level_name, requirement }: (typeof levels)[0]) => ({
  level_id,
  level_name,
  requirement,
})
const type = (label: string, value: string) =>
  fireEvent.change(screen.getByLabelText(label), { target: { value } })
const click = (name: string) => fireEvent.click(screen.getByRole('button', { name }))
const tree = () => within(screen.getByRole('list', { name: 'Location tree' }))
/** Picks an action from a place's "⋯" menu. */
const pick = (place: string, action: string) => {
  click(`More for ${place}`)
  fireEvent.click(screen.getByRole('menuitem', { name: action }))
}
// What the screens say for an error that is not an API problem (errorMessage).
const WENT_WRONG = 'Something went wrong. Please try again.'

describe('A unit with no place yet', () => {
  it('GIVEN a new unit THEN its facility is there with the add form, offering the standard kinds', () => {
    setup = empty
    renderPage()
    expect(tree().getByText('Plant 04')).toBeInTheDocument()
    expect(screen.getByText(/Add the first places inside Plant 04/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Review & publish' })).not.toBeInTheDocument()
    const kinds = within(screen.getByLabelText('What you are adding')).getAllByRole('option')
    expect(kinds.map((o) => o.textContent)).toEqual(['Building', 'Shop', 'Bin', 'Sub-bin'])
  })

  it('GIVEN the first add THEN the top place is made, then the kind, then the places (2.2–2.5)', async () => {
    setup = empty
    const top = { ...topNode, child_count: 0, is_placeholder: true }
    calls.setLevels
      .mockResolvedValueOnce({ ...empty, levels: [fac] })
      .mockResolvedValueOnce({ ...empty, levels })
    calls.skeleton.mockResolvedValue({ ...empty, levels: [fac], nodes: [top] })
    renderPage()
    type('What you are adding', 'Bin')
    type('Names, inside Plant 04', 'Bin 01, Bin 02')
    click('Add')

    await waitFor(() => expect(calls.addNodes).toHaveBeenCalled())
    expect(calls.setLevels.mock.calls).toEqual([
      [[{ level_id: null, level_name: 'Facility', requirement: 'required' }]],
      [[sent(fac), { level_id: null, level_name: 'Bin', requirement: 'required' }]],
    ])
    expect(calls.skeleton).toHaveBeenCalledTimes(1)
    // Renaming the top place to its own name clears the temporary-name flag.
    expect(calls.updateNode).toHaveBeenCalledWith({ nodeId: 'f', name: 'Plant 04' })
    expect(calls.addNodes).toHaveBeenCalledWith({
      parent_id: 'f',
      level_id: 'bin',
      names: ['Bin 01', 'Bin 02'],
      idempotencyKey: expect.any(String),
    })
    expect(await screen.findByText(/2 places added inside Plant 04/)).toBeInTheDocument()
    expect(screen.getByText(/Technicians will now be asked for a bin/)).toBeInTheDocument()
  })

  it('GIVEN the first add fails THEN the reason stays on the page', async () => {
    setup = empty
    calls.setLevels.mockRejectedValue(new Error('offline'))
    renderPage()
    type('Names, inside Plant 04', 'Hall A')
    click('Add')
    expect((await screen.findAllByText(WENT_WRONG)).length).toBeGreaterThan(0)
    expect(calls.addNodes).not.toHaveBeenCalled()
  })

  it('GIVEN the unit list arrives after the page THEN the facility still shows its name', () => {
    setup = empty
    unitList = []
    const page = () => (
      <MemoryRouter initialEntries={['/locations?unit=p04']}>
        <LocationsPage />
      </MemoryRouter>
    )
    const view = render(page())
    expect(screen.queryByLabelText('Names, inside Plant 04')).not.toBeInTheDocument()
    unitList = [plant04]
    view.rerender(page())
    expect(screen.getByLabelText('Names, inside Plant 04')).toBeInTheDocument()
  })
})

describe('Places, added and changed in the row', () => {
  it('GIVEN names with a range THEN contract 2.4 gets every name, and no kind is saved', async () => {
    renderPage()
    click('Add inside Plant 04')
    type('What you are adding', 'Bin')
    type('Names, inside Plant 04', 'Bin 02-04')
    expect(screen.getByText('Bin 04')).toBeInTheDocument() // "Adds 3: Bin 02 … Bin 04"
    click('Add')
    await waitFor(() =>
      expect(calls.addNodes).toHaveBeenCalledWith({
        parent_id: 'f',
        level_id: 'bin',
        names: ['Bin 02', 'Bin 03', 'Bin 04'],
        idempotencyKey: expect.any(String),
      }),
    )
    expect(calls.setLevels).not.toHaveBeenCalled()
    expect(await screen.findByText('3 places added inside Plant 04.')).toBeInTheDocument()
  })

  it('GIVEN a kind not used yet THEN it is saved at its place first, then the places', async () => {
    const bld = { level_id: 'bld', level_name: 'Building', level_order: 2, requirement: 'optional' }
    calls.setLevels.mockResolvedValue({
      ...withTree,
      levels: [fac, bld, { ...bin, level_order: 3 }],
    })
    renderPage()
    click('Add inside Plant 04')
    const kinds = within(screen.getByLabelText('What you are adding')).getAllByRole('option')
    // Sub-bin is not offered inside the facility: Bin, in between, is always asked.
    expect(kinds.map((o) => o.textContent)).toEqual(['Building', 'Shop', 'Bin'])
    type('What you are adding', 'Building')
    type('Names, inside Plant 04', 'Hall A')
    click('Add')
    await waitFor(() =>
      expect(calls.addNodes).toHaveBeenCalledWith({
        parent_id: 'f',
        level_id: 'bld',
        names: ['Hall A'],
        idempotencyKey: expect.any(String),
      }),
    )
    expect(calls.setLevels).toHaveBeenCalledWith([
      sent(fac),
      { level_id: null, level_name: 'Building', requirement: 'required' },
      sent(bin),
    ])
    // The API saved it as optional, because bins already sit below it.
    expect(await screen.findByText(/Building was added as "can be skipped"/)).toBeInTheDocument()
  })

  it('GIVEN the add fails after a new kind was saved THEN the kind is taken back', async () => {
    const bld = { level_id: 'bld', level_name: 'Building', level_order: 2, requirement: 'optional' }
    calls.setLevels.mockResolvedValue({ ...withTree, levels: [fac, bld, bin] })
    calls.addNodes.mockRejectedValue(new Error('offline'))
    renderPage()
    click('Add inside Plant 04')
    type('What you are adding', 'Building')
    type('Names, inside Plant 04', 'Hall A')
    click('Add')
    expect(await screen.findByText(WENT_WRONG)).toBeInTheDocument()
    expect(calls.setLevels).toHaveBeenLastCalledWith([sent(fac), sent(bin)])
  })

  it('GIVEN a name already used here, or too many names THEN refused before sending', () => {
    renderPage()
    click('Add inside Plant 04')
    type('What you are adding', 'Bin')
    click('Add')
    expect(screen.getByText('Type at least one name.')).toBeInTheDocument()
    type('Names, inside Plant 04', 'bin 01')
    click('Add')
    expect(screen.getByText('bin 01 already exists here.')).toBeInTheDocument()
    type('Names, inside Plant 04', 'Bin 1-60')
    click('Add')
    expect(screen.getByText(/more than 50 names/)).toBeInTheDocument()
    expect(calls.addNodes).not.toHaveBeenCalled()
  })

  it('GIVEN Rename THEN the name is edited in the row and contract 2.5 gets it', async () => {
    renderPage()
    pick('Bin 01', 'Rename')
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    type('New name for Bin 01', 'Bin 1A')
    click('Save name')
    await waitFor(() =>
      expect(calls.updateNode).toHaveBeenCalledWith({ nodeId: 'b1', name: 'Bin 1A' }),
    )
    expect(await screen.findByText('Renamed to Bin 1A.')).toBeInTheDocument()
  })

  it('GIVEN Delete of the last bin THEN 2.6, and the kind nothing uses is removed (2.2)', async () => {
    renderPage()
    pick('Bin 01', 'Delete')
    expect(dialog().getByText('Nothing is inside it.')).toBeInTheDocument()
    fireEvent.click(dialog().getByRole('button', { name: 'Yes, delete' }))
    await waitFor(() => expect(calls.setLevels).toHaveBeenCalledWith([sent(fac)]))
    expect(calls.deleteNode).toHaveBeenCalledWith('b1')
    expect(
      await screen.findByText(/No bin is left, so technicians are no longer asked/),
    ).toBeInTheDocument()
  })

  it('GIVEN the top place THEN it can be renamed, not moved or deleted', () => {
    renderPage()
    click('More for Plant 04')
    expect(screen.getAllByRole('menuitem').map((i) => i.textContent)).toEqual(['Rename'])
    fireEvent.click(screen.getByRole('button', { name: 'Close menu' }))
    click('More for Bin 01')
    expect(screen.getAllByRole('menuitem').map((i) => i.textContent)).toEqual([
      'Rename',
      'Move',
      'Delete',
    ])
  })

  it('GIVEN a search or a closed place THEN only the matching or open rows show', () => {
    renderPage()
    click('Close Plant 04')
    expect(tree().queryByText('Bin 01')).not.toBeInTheDocument()
    click('Open Plant 04')
    expect(tree().getByText('Bin 01')).toBeInTheDocument()
    // A short tree has no search box; a long one does.
    expect(screen.queryByLabelText('Search locations')).not.toBeInTheDocument()
    const bin01 = withTree.nodes[1]
    if (!bin01) throw new Error('fixture')
    const more = Array.from({ length: 8 }, (_, i) => ({
      ...bin01,
      node_id: `m${i}`,
      name: `Bin 1${i}`,
    }))
    setup = { ...withTree, nodes: [...withTree.nodes, ...more] }
    cleanup()
    renderPage()
    type('Search locations', 'Bin 13')
    expect(tree().getByText('Bin 13')).toBeInTheDocument()
    expect(tree().getByText('Plant 04')).toBeInTheDocument()
    expect(tree().queryByText('Bin 14')).not.toBeInTheDocument()
    type('Search locations', 'zzz')
    expect(screen.getByText('No location matches your search.')).toBeInTheDocument()
  })

  it('GIVEN a place to fix THEN its row is tinted and says why', () => {
    const bin01 = withTree.nodes[1]
    if (!bin01) throw new Error('fixture')
    setup = { ...withTree, nodes: [topNode, { ...bin01, name: 'Bin', is_placeholder: true }] }
    renderPage()
    expect(screen.getByText(/Rename 1 temporary name before you can publish/)).toBeInTheDocument()
    expect(tree().getByText('⚠ Placeholder').closest('#place-b1')).toHaveClass('bg-warning-soft')
    // A building with no bin: technicians could not finish picking there.
    const bld = {
      level_id: 'bld',
      level_name: 'Building',
      level_order: 2,
      requirement: 'required' as const,
    }
    const hall = { ...bin01, node_id: 'h', level_id: 'bld', name: 'Hall A' }
    setup = { ...withTree, levels: [fac, bld, { ...bin, level_order: 3 }], nodes: [topNode, hall] }
    cleanup()
    renderPage()
    expect(screen.getByText(/1 place has nothing inside yet/)).toBeInTheDocument()
    expect(tree().getByText('⚠ Needs a Bin').closest('#place-h')).toHaveClass('bg-warning-soft')
    setup = withTree
    cleanup()
    renderPage()
    expect(document.querySelector('.bg-warning-soft')).toBeNull()
  })

  it('GIVEN only the facility THEN there is nothing to publish yet', () => {
    setup = { ...withTree, levels: [fac], nodes: [{ ...topNode, child_count: 0 }] }
    renderPage()
    expect(screen.getByText(/Add the first places inside Plant 04/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Review & publish' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add inside Plant 04' })).toBeInTheDocument()
  })
})

describe('Kinds, on the same screen', () => {
  const picks = () => within(screen.getByRole('list', { name: 'What technicians pick' }))

  it('GIVEN a kind WHEN clicked THEN it becomes "can be skipped" (contract 2.2)', async () => {
    renderPage()
    expect(screen.queryByRole('button', { name: 'Edit kinds' })).not.toBeInTheDocument()
    fireEvent.click(picks().getByRole('button', { name: 'Bin' }))
    await waitFor(() =>
      expect(calls.setLevels).toHaveBeenCalledWith([
        sent(fac),
        { ...sent(bin), requirement: 'optional' },
      ]),
    )
    expect(await screen.findByText('Bin can now be skipped.')).toBeInTheDocument()
  })

  it('GIVEN a place that goes past a kind THEN the kind has to stay "can be skipped"', async () => {
    const shop = {
      level_id: 'shp',
      level_name: 'Shop',
      level_order: 2,
      requirement: 'optional' as const,
    }
    setup = { ...withTree, levels: [fac, shop, { ...bin, level_order: 3 }] }
    renderPage()
    fireEvent.click(picks().getByRole('button', { name: 'Shop · can be skipped' }))
    expect(
      await screen.findByText(/Shop has to stay "can be skipped": 1 place has/),
    ).toBeInTheDocument()
    expect(calls.setLevels).not.toHaveBeenCalled()
  })

  it('GIVEN a published unit THEN kinds and places are shown, not changed', () => {
    setup = { ...withTree, status: 'published' }
    renderPage()
    expect(screen.getByText(/Published — locked to protect scan history/)).toBeInTheDocument()
    expect(picks().getByText('Bin')).toBeInTheDocument()
    expect(picks().queryByRole('button')).not.toBeInTheDocument()
    expect(tree().queryByRole('button', { name: /Add inside|More for/ })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Review & publish' })).not.toBeInTheDocument()
  })
})

describe('Review & publish', () => {
  it('GIVEN placeholders left THEN publishing is blocked with the reason', () => {
    check = { placeholders_left: 2, empty_branches: [], sample_path: null, can_publish: false }
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Review & publish' }))
    expect(dialog().getByText(/Rename 2 temporary names first/)).toBeInTheDocument()
    expect(dialog().getByRole('button', { name: 'Publish and lock' })).toBeDisabled()
  })

  it('GIVEN the dialog THEN the warning comes first, counts use kind names (R9)', () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Review & publish' }))
    const text = screen.getByRole('dialog').textContent ?? ''
    expect(text.indexOf("This can't be undone")).toBeLessThan(text.indexOf('You are publishing'))
    expect(dialog().getByText('Facility')).toBeInTheDocument()
    expect(dialog().getByText('Bin')).toBeInTheDocument()
  })

  it('GIVEN an empty place THEN it is named, publishing is still allowed, Show me outlines it', () => {
    check = {
      placeholders_left: 0,
      empty_branches: [{ node_id: 'f', path: 'Plant 04' }],
      sample_path: 'Plant 04 › Bin 01',
      can_publish: true,
    }
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Review & publish' }))
    expect(dialog().getByText(/Plant 04 has nothing inside yet/)).toBeInTheDocument()
    expect(dialog().getByRole('button', { name: 'Publish and lock' })).toBeEnabled()
    fireEvent.click(dialog().getByRole('button', { name: 'Show me Plant 04' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(document.getElementById('place-f')).toHaveClass('outline-brand-navy')
  })

  it('GIVEN no place a technician could scan at THEN publishing is blocked with the reason', () => {
    check = { placeholders_left: 0, empty_branches: [], sample_path: null, can_publish: true }
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Review & publish' }))
    expect(dialog().getByText(/Technicians could not scan anywhere yet/)).toBeInTheDocument()
    expect(dialog().getByRole('button', { name: 'Publish and lock' })).toBeDisabled()
  })

  it('GIVEN all checks pass WHEN published THEN contract 2.8 is called and a notice shows', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Review & publish' }))
    expect(dialog().getByText('Plant 04 › Bin 05')).toBeInTheDocument()
    fireEvent.click(dialog().getByRole('button', { name: 'Publish and lock' }))
    expect(await screen.findByText(/PPG Plant 04 is published/)).toBeInTheDocument()
    expect(calls.publish).toHaveBeenCalled()
  })
})
