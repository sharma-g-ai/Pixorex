import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
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

function renderPage() {
  render(
    <MemoryRouter initialEntries={['/locations?unit=p04']}>
      <LocationsPage />
    </MemoryRouter>,
  )
}
const dialog = () => within(screen.getByRole('dialog'))
const openTab = (name: RegExp) => fireEvent.click(screen.getByRole('tab', { name }))

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

describe('Levels', () => {
  it('GIVEN a new unit WHEN quick start 4 levels is saved THEN contract 2.2 gets the 4 levels', async () => {
    setup = { version_id: 'v', status: 'not_published', levels: [], nodes: [] }
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: '4 levels' }))
    fireEvent.click(screen.getByRole('button', { name: 'Save levels' }))

    await waitFor(() => expect(calls.setLevels).toHaveBeenCalled())
    expect(calls.setLevels.mock.calls[0]?.[0]).toEqual([
      { level_name: 'Facility', requirement: 'required' },
      { level_name: 'Building', requirement: 'required' },
      { level_name: 'Shop', requirement: 'optional' },
      { level_name: 'Bin', requirement: 'required' },
    ])
  })

  it('GIVEN a published unit THEN levels are read-only', () => {
    setup = { ...withTree, status: 'published' }
    renderPage()
    expect(screen.getByText(/Published and locked to protect scan history/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Save levels' })).not.toBeInTheDocument()
  })
})

describe('Locations tree', () => {
  it('GIVEN levels but no locations THEN the skeleton can be created (contract 2.3)', async () => {
    setup = { ...withTree, nodes: [] }
    renderPage()
    openTab(/2 · Locations/)
    fireEvent.click(screen.getByRole('button', { name: 'Create the skeleton' }))
    await waitFor(() => expect(calls.skeleton).toHaveBeenCalled())
  })

  it('GIVEN Add several WHEN Bin 02–04 THEN contract 2.4 gets three names with one key', async () => {
    renderPage()
    openTab(/2 · Locations/)
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
    openTab(/2 · Locations/)
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
    openTab(/2 · Locations/)
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
    openTab(/2 · Locations/)
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
    expect(dialog().getByText(/Name the placeholders first \(2 left\)/)).toBeInTheDocument()
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
