import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { EquipmentType } from '../../api/equipmentTypes'
import type { Me } from '../../api/me'
import { DashboardContext } from '../../app/DashboardContext'
import { EquipmentTypesPage } from './EquipmentTypesPage'

const calls = {
  create: vi.fn(),
  addField: vi.fn(),
  updateField: vi.fn(),
  publish: vi.fn(),
  suggest: vi.fn(),
}
const motor: EquipmentType = {
  type_id: 'motor',
  name: 'Motor Nameplate',
  status: 'not_published',
  created_via: 'blank',
  version_no: 1,
  field_count: 1,
  fields: [
    {
      field_id: 'sn',
      field_key: 'serial_number',
      label: 'Serial Number',
      data_type: 'text',
      is_required: true,
      is_critical: false,
      sort_order: 1,
      origin: 'manual',
      flag_below_confidence: 0.85,
    },
  ],
}
let types: EquipmentType[] = []

const mutation = (fn: ReturnType<typeof vi.fn>) => ({
  mutateAsync: fn,
  mutate: fn,
  isPending: false,
})
vi.mock('../../api/equipmentTypes', () => ({
  useEquipmentTypes: () => ({ data: types, isPending: false, isError: false }),
  useEquipmentType: (id: string) => ({
    data: types.find((t) => t.type_id === id),
    isPending: false,
    isError: false,
  }),
  useCreateType: () => mutation(calls.create),
  useAddField: () => mutation(calls.addField),
  useUpdateField: () => mutation(calls.updateField),
  useDeleteField: () => mutation(vi.fn()),
  useReorderFields: () => mutation(vi.fn()),
  useRenameType: () => mutation(vi.fn()),
  useDeleteType: () => mutation(vi.fn()),
  usePublishType: () => mutation(calls.publish),
  useSuggestFields: () => mutation(calls.suggest),
}))

function renderPage() {
  const unit = { bu_id: 'p04', name: 'Plant 04', role: 'bu_admin' as const, is_primary: true }
  render(
    <DashboardContext.Provider value={{ me: {} as Me, role: 'bu_admin', unit }}>
      <EquipmentTypesPage />
    </DashboardContext.Provider>,
  )
}
const dialog = () => within(screen.getByRole('dialog'))

beforeEach(() => {
  for (const fn of Object.values(calls))
    fn.mockReset().mockResolvedValue({ type_id: 'new', name: 'New' })
  types = [
    motor,
    { ...motor, type_id: 'valve', name: 'Control Valve', status: 'published', fields: [] },
  ]
})

describe('EquipmentTypesPage', () => {
  it('GIVEN types THEN the register lists them and the first is open with its fields', () => {
    renderPage()
    expect(screen.getByRole('button', { name: /Control Valve/ })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Motor Nameplate' })).toBeInTheDocument()
    expect(
      within(screen.getByRole('table', { name: 'Fields of Motor Nameplate' })).getByText(
        'Serial Number',
      ),
    ).toBeInTheDocument()
  })

  it('GIVEN a published type THEN its fields cannot be changed', () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: /Control Valve/ }))
    expect(screen.getByText(/Published and locked\./)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: '+ Add field' })).not.toBeInTheDocument()
  })

  it('GIVEN Required is clicked THEN contract 2.16 flips it', () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Required', pressed: true }))
    expect(calls.updateField).toHaveBeenCalledWith({ fieldId: 'sn', is_required: false })
  })

  it('GIVEN a dropdown with one choice THEN it asks for 2; with 2 it sends contract 2.15', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: '+ Add field' }))
    fireEvent.change(dialog().getByLabelText('Field name technicians see'), {
      target: { value: 'Hazard Class' },
    })
    fireEvent.change(dialog().getByLabelText('Type of value'), { target: { value: 'dropdown' } })
    fireEvent.change(dialog().getByLabelText('Choice 1'), { target: { value: 'Flammable' } })
    fireEvent.click(dialog().getByRole('button', { name: 'Add field' }))
    expect(await dialog().findByText('Add at least 2 choices.')).toBeInTheDocument()

    fireEvent.change(dialog().getByLabelText('Choice 2'), { target: { value: 'Toxic' } })
    fireEvent.click(dialog().getByRole('button', { name: 'Add field' }))
    await waitFor(() => expect(calls.addField).toHaveBeenCalled())
    expect(calls.addField.mock.calls[0]?.[0].body).toMatchObject({
      label: 'Hazard Class',
      data_type: 'dropdown',
      options: ['Flammable', 'Toxic'],
    })
  })

  it('GIVEN a field name already used THEN it is refused before sending', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: '+ Add field' }))
    fireEvent.change(dialog().getByLabelText('Field name technicians see'), {
      target: { value: 'serial number' },
    })
    fireEvent.click(dialog().getByRole('button', { name: 'Add field' }))
    expect(
      await dialog().findByText('A field with this name already exists in this type.'),
    ).toBeInTheDocument()
    expect(calls.addField).not.toHaveBeenCalled()
  })

  it('GIVEN New type as a copy THEN contract 2.11 gets created_via copy and the source', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: '+ New type' }))
    fireEvent.change(dialog().getByLabelText('Name technicians will see'), {
      target: { value: 'Motor v2' },
    })
    fireEvent.click(dialog().getByLabelText(/Copy of Motor Nameplate/))
    fireEvent.click(dialog().getByRole('button', { name: 'Create type' }))
    await waitFor(() =>
      expect(calls.create).toHaveBeenCalledWith({
        body: { name: 'Motor v2', created_via: 'copy', copied_from_type_id: 'motor' },
        idempotencyKey: expect.any(String),
      }),
    )
  })

  it('GIVEN AI-assist THEN suggestions are ticked and the type is created with them', async () => {
    calls.suggest.mockResolvedValue([
      { label: 'Manufacturer', data_type: 'text' },
      { label: 'Voltage', data_type: 'number' },
    ])
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'AI-assist from a photo' }))
    fireEvent.change(dialog().getByLabelText('New type name'), { target: { value: 'Generator' } })
    const photo = new File(['x'], 'label.jpg', { type: 'image/jpeg' })
    fireEvent.change(dialog().getByLabelText('Photo of the label'), { target: { files: [photo] } })
    fireEvent.click(dialog().getByRole('button', { name: 'Read from photo' }))

    fireEvent.click(await dialog().findByRole('checkbox', { name: /Voltage/ }))
    fireEvent.click(dialog().getByRole('button', { name: 'Create type with 1 fields' }))
    await waitFor(() => expect(calls.create).toHaveBeenCalled())
    expect(calls.suggest).toHaveBeenCalledWith({ name: 'Generator', image: photo })
    expect(calls.create.mock.calls[0]?.[0].body).toMatchObject({
      name: 'Generator',
      created_via: 'ai_assist',
      fields: [{ label: 'Manufacturer', data_type: 'text' }],
    })
  })

  it('GIVEN Publish THEN contract 2.19 is called after confirming', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Publish' }))
    fireEvent.click(dialog().getByRole('button', { name: 'Publish and lock' }))
    await waitFor(() => expect(calls.publish).toHaveBeenCalled())
  })
})
