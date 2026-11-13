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
  useBusinessUnits: () => ({
    data: [
      {
        bu_id: 'p04',
        name: 'PPG Plant 04',
        facility_name: 'Plant 04',
        bu_admin: null,
        locations_status: 'not_published',
      },
    ],
  }),
}))
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
  setup = withTree
  check = {
    placeholders_left: 0,
    empty_branches: [],
    sample_path: 'Plant 04 › Bin 05',
    can_publish: true,
  }
})

describe('Guided setup and the working page (plan R4–R6)', () => {
  const type = (label: string, value: string) =>
    fireEvent.change(screen.getByLabelText(label), { target: { value } })

  it('GIVEN a new unit WHEN Create THEN 2.2, 2.3, then one 2.5 per place, top included (R4)', async () => {
    setup = { version_id: 'v', status: 'not_published', levels: [], nodes: [] }
    calls.skeleton.mockResolvedValue({
      ...withTree,
      nodes: withTree.nodes.map((n) => ({
        ...n,
        name: n.level_id === 'fac' ? 'Plant 04' : 'Bin',
        is_placeholder: true,
      })),
    })
    renderPage()
    expect(screen.queryByRole('tab')).not.toBeInTheDocument()
    type('Place 2', 'Bin 07')
    fireEvent.click(screen.getByRole('button', { name: 'Next' }))
    type('Kind of Plant 04', 'Facility')
    type('Kind of Bin 07', 'Bin')
    fireEvent.click(screen.getByRole('button', { name: 'Create and add more places' }))

    await waitFor(() => expect(calls.updateNode).toHaveBeenCalledTimes(2))
    expect(calls.setLevels).toHaveBeenCalledWith([
      { level_id: null, level_name: 'Facility', requirement: 'required' },
      { level_id: null, level_name: 'Bin', requirement: 'required' },
    ])
    expect(calls.skeleton).toHaveBeenCalledTimes(1)
    expect(calls.updateNode.mock.calls).toEqual([
      [{ nodeId: 'f', name: 'Plant 04' }],
      [{ nodeId: 'b1', name: 'Bin 07' }],
    ])
  })

  it('GIVEN a rename fails during Create THEN it says the places can be renamed here (R5)', async () => {
    setup = { version_id: 'v', status: 'not_published', levels: [], nodes: [] }
    calls.skeleton.mockResolvedValue(withTree)
    calls.updateNode.mockRejectedValue(new Error('offline'))
    renderPage()
    type('Place 2', 'Bin 07')
    fireEvent.click(screen.getByRole('button', { name: 'Next' }))
    type('Kind of Plant 04', 'Facility')
    type('Kind of Bin 07', 'Bin')
    fireEvent.click(screen.getByRole('button', { name: 'Create and add more places' }))
    expect(await screen.findByText(/Some places kept a temporary name/)).toBeInTheDocument()
  })

  it('GIVEN levels saved but no places THEN the guided setup opens with those kinds', () => {
    setup = { ...withTree, nodes: [] }
    renderPage()
    type('Place 2', 'Bin 07')
    fireEvent.click(screen.getByRole('button', { name: 'Next' }))
    expect(screen.getByLabelText('Kind of Bin 07')).toHaveValue('Bin')
  })

  it('GIVEN places THEN the working page with the tree; Edit kinds opens the level editor (R6)', () => {
    renderPage()
    expect(screen.getByRole('table', { name: 'Location tree' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Edit kinds' }))
    expect(screen.getByRole('button', { name: 'Save levels' })).toBeInTheDocument()
  })

  it('GIVEN the working page THEN the kinds show above the list, top to bottom', () => {
    renderPage()
    expect(screen.getByText('Kinds: Facility › Bin')).toBeInTheDocument()
  })

  it('GIVEN the working page WHEN a place is picked THEN the phone preview shows it (R7)', () => {
    renderPage()
    const phone = () => within(screen.getByRole('region', { name: "On the technician's phone" }))
    expect(phone().getByText('Plant 04 › Bin 01')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Preview Plant 04 on the phone' }))
    expect(phone().getByText(/pick a place further down/)).toBeInTheDocument()
  })

  it('GIVEN placeholders or empty places THEN the banner says what is left to fix', () => {
    setup = {
      ...withTree,
      nodes: [{ ...topNode, child_count: 0, is_placeholder: true }],
    }
    renderPage()
    expect(screen.getByText(/Rename 1 temporary name before you can publish/)).toBeInTheDocument()
    setup = { ...withTree, nodes: [{ ...topNode, child_count: 0 }] }
    cleanup()
    renderPage()
    expect(screen.getByText(/1 place has nothing inside yet/)).toBeInTheDocument()
  })

  it('GIVEN a published unit THEN the kinds can be viewed but not changed', () => {
    setup = { ...withTree, status: 'published' }
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'View kinds' }))
    expect(screen.getByText(/Published and locked to protect scan history/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Save levels' })).not.toBeInTheDocument()
  })
})

describe('Locations tree', () => {
  it('GIVEN Add several WHEN Bin 02–04 THEN contract 2.4 gets three names with one key', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Add inside Plant 04' }))
    fireEvent.click(dialog().getByLabelText('Add several'))
    fireEvent.change(dialog().getByLabelText('Name starts with'), { target: { value: 'Bin ' } })
    fireEvent.change(dialog().getByLabelText('From'), { target: { value: '02' } })
    fireEvent.change(dialog().getByLabelText('To'), { target: { value: '04' } })
    fireEvent.click(dialog().getByRole('button', { name: 'Create' }))

    await waitFor(() =>
      expect(calls.addNodes).toHaveBeenCalledWith({
        parent_id: 'f',
        level_id: 'bin',
        names: ['Bin 02', 'Bin 03', 'Bin 04'],
        idempotencyKey: expect.any(String),
      }),
    )
  })

  it('GIVEN a name already used among siblings THEN it is refused before sending', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Add inside Plant 04' }))
    fireEvent.change(dialog().getByLabelText('Name of the new bin'), {
      target: { value: 'bin 01' },
    })
    fireEvent.click(dialog().getByRole('button', { name: 'Create' }))

    expect(await dialog().findByText('bin 01 already exists here.')).toBeInTheDocument()
    expect(calls.addNodes).not.toHaveBeenCalled()
  })

  it('GIVEN Rename THEN contract 2.5 gets the new name', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Rename Bin 01' }))
    fireEvent.change(dialog().getByLabelText('Name technicians see'), {
      target: { value: 'Bin 1A' },
    })
    fireEvent.click(dialog().getByRole('button', { name: 'Save name' }))
    await waitFor(() =>
      expect(calls.updateNode).toHaveBeenCalledWith({ nodeId: 'b1', name: 'Bin 1A' }),
    )
  })

  it('GIVEN Delete THEN contract 2.6 is called after confirming', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Delete Bin 01' }))
    expect(dialog().getByText('Nothing is inside it.')).toBeInTheDocument()
    fireEvent.click(dialog().getByRole('button', { name: 'Yes, delete' }))
    await waitFor(() => expect(calls.deleteNode).toHaveBeenCalledWith('b1'))
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

  it('GIVEN an empty place THEN it is named, publishing is still allowed, Show me previews it', () => {
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
    const phone = within(screen.getByRole('region', { name: "On the technician's phone" }))
    expect(phone.getByText(/pick a place further down/)).toBeInTheDocument()
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
