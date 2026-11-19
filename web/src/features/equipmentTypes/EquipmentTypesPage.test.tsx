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
  deleteField: vi.fn(),
  rename: vi.fn(),
  deleteType: vi.fn(),
  publish: vi.fn(),
  suggest: vi.fn(),
}
const motor: EquipmentType = {
  type_id: 'motor',
  name: 'Motor Nameplate',
  status: 'not_published',
  created_via: 'ai_assist',
  version_no: 1,
  field_count: 2,
  fields: [
    {
      field_id: 'sn',
      field_key: 'serial_number',
      label: 'Serial Number',
      data_type: 'text',
      is_required: true,
      description: 'The unique serial number, printed after S/N.',
      sort_order: 1,
      origin: 'manual',
      flag_below_confidence: 0.85,
    },
    {
      field_id: 'hz',
      field_key: 'hazard',
      label: 'Hazard Class',
      data_type: 'dropdown',
      options: ['Flammable', 'Toxic'],
      is_required: false,
      description: null,
      sort_order: 2,
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
// Lets a test say the AI is still reading the photo.
const reading = { on: false }
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
  useDeleteField: () => mutation(calls.deleteField),
  useReorderFields: () => mutation(vi.fn()),
  useRenameType: () => mutation(calls.rename),
  useDeleteType: () => mutation(calls.deleteType),
  usePublishType: () => mutation(calls.publish),
  useSuggestFields: () => ({ ...mutation(calls.suggest), isPending: reading.on }),
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
const fieldsTable = () => within(screen.getByRole('table', { name: 'Fields of Motor Nameplate' }))

beforeEach(() => {
  for (const fn of Object.values(calls))
    fn.mockReset().mockResolvedValue({ type_id: 'new', name: 'New' })
  types = [
    motor,
    { ...motor, type_id: 'valve', name: 'Control Valve', status: 'published', fields: [] },
  ]
})

describe('Equipment types page', () => {
  it('GIVEN types THEN the register lists them and the first is open with its fields', () => {
    renderPage()
    expect(screen.getByRole('button', { name: /Control Valve/ })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Motor Nameplate' })).toBeInTheDocument()
    expect(fieldsTable().getByText('Serial Number')).toBeInTheDocument()
  })

  it('GIVEN the header THEN there is one "+ New type" button and no separate AI-assist button', () => {
    renderPage()
    expect(screen.getByRole('button', { name: '+ New type' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /AI-assist/ })).not.toBeInTheDocument()
  })

  it('GIVEN a type in the register THEN its line says only the field count, and the badge the state', () => {
    renderPage()
    const row = screen.getByRole('button', { name: /Motor Nameplate/ })
    expect(within(row).getByText('2 fields')).toBeInTheDocument()
    expect(within(row).getByText('Draft')).toBeInTheDocument()
    expect(within(row).queryByText(/Not published/)).toBeNull()
    const published = screen.getByRole('button', { name: /Control Valve/ })
    expect(within(published).getByText('Published')).toBeInTheDocument()
    expect(within(published).queryByText(/· Published/)).toBeNull()
  })

  it('GIVEN a type THEN its header has only the name and a badge: no "Started with", no version, no blue box', () => {
    renderPage()
    expect(screen.queryByText(/Started with/)).toBeNull()
    expect(screen.queryByText(/version 1/)).toBeNull()
    expect(screen.queryByText(/Not published yet\./)).toBeNull()
    expect(screen.queryByText(/can't be edited or deleted/)).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: /Control Valve/ }))
    expect(screen.getByText('Published · locked')).toBeInTheDocument()
    expect(screen.queryByText(/Published and locked\./)).toBeNull()
  })

  it('GIVEN a published type THEN its fields cannot be changed', () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: /Control Valve/ }))
    expect(screen.queryByRole('button', { name: '+ Add field' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Publish' })).not.toBeInTheDocument()
  })

  it('GIVEN no types THEN says how to start, naming AI assisted schema discovery', () => {
    types = []
    renderPage()
    expect(screen.getByText(/AI assisted schema discovery/)).toBeInTheDocument()
  })
})

describe('Field table', () => {
  it('GIVEN fields THEN the columns are Order, Field, Required, Description, Flag, Actions', () => {
    renderPage()
    const headers = fieldsTable()
      .getAllByRole('columnheader')
      .map((h) => h.textContent)
    expect(headers).toEqual(['Order', 'Field', 'Required', 'Description', 'Flag', 'Actions'])
    expect(fieldsTable().queryByRole('columnheader', { name: 'Critical' })).toBeNull()
    expect(fieldsTable().queryByRole('columnheader', { name: 'Format check' })).toBeNull()
  })

  it('GIVEN descriptions THEN they are shown, and a dash where there is none', () => {
    renderPage()
    expect(
      fieldsTable().getByText('The unique serial number, printed after S/N.'),
    ).toBeInTheDocument()
    const hazard = within(
      fieldsTable().getByText('Hazard Class').closest('[role="row"]') as HTMLElement,
    )
    expect(hazard.getByText('—')).toBeInTheDocument()
  })

  it('GIVEN the footer line THEN it explains Required and Flag, not Critical', () => {
    renderPage()
    expect(screen.getByText(/the technician must fill it/)).toBeInTheDocument()
    expect(screen.getByText(/AI confidence under this number is flagged/)).toBeInTheDocument()
    expect(screen.queryByText(/Critical/)).toBeNull()
  })

  it('GIVEN no fields THEN says to add at least one to publish', () => {
    types = [{ ...motor, fields: [], field_count: 0 }]
    renderPage()
    expect(
      screen.getByText('No fields yet. Add at least one field to publish.'),
    ).toBeInTheDocument()
  })

  it('GIVEN Required is clicked THEN contract 2.16 flips it', () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Required', pressed: true }))
    expect(calls.updateField).toHaveBeenCalledWith({ fieldId: 'sn', is_required: false })
  })

  it('GIVEN a field is added, changed, or deleted THEN no result banner appears', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: '+ Add field' }))
    fireEvent.change(dialog().getByLabelText('Field name technicians see'), {
      target: { value: 'Voltage' },
    })
    fireEvent.click(dialog().getByRole('button', { name: 'Add field' }))
    await waitFor(() => expect(calls.addField).toHaveBeenCalled())
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
    expect(screen.queryByRole('status')).toBeNull()
    expect(screen.queryByText(/was added/)).toBeNull()
  })
})

describe('Add a field', () => {
  const open = () => fireEvent.click(screen.getByRole('button', { name: '+ Add field' }))

  it('GIVEN the popup THEN type of value offers only Text, Number and Date', () => {
    renderPage()
    open()
    const options = within(dialog().getByLabelText('Type of value')).getAllByRole('option')
    expect(options.map((o) => o.textContent)).toEqual(['Text', 'Number', 'Date'])
  })

  it('GIVEN the popup THEN it has a Description box, and no Critical, Format check, or "Saved straight away" note', () => {
    renderPage()
    open()
    expect(dialog().getByLabelText('Description (optional)')).toBeInTheDocument()
    expect(dialog().getByLabelText('Flag below confidence (%)')).toBeInTheDocument()
    expect(dialog().queryByText(/Critical field/)).toBeNull()
    expect(dialog().queryByLabelText(/Format check/)).toBeNull()
    expect(dialog().queryByText(/Saved straight away/)).toBeNull()
    expect(dialog().queryByText(/Choices technicians pick from/)).toBeNull()
  })

  it('GIVEN a description WHEN added THEN contract 2.15 gets it, and no critical or format rule', async () => {
    renderPage()
    open()
    fireEvent.change(dialog().getByLabelText('Field name technicians see'), {
      target: { value: 'PO#' },
    })
    fireEvent.change(dialog().getByLabelText('Description (optional)'), {
      target: { value: '  Purchase order number printed on the label ' },
    })
    fireEvent.click(dialog().getByRole('button', { name: 'Add field' }))
    await waitFor(() => expect(calls.addField).toHaveBeenCalled())
    const body = calls.addField.mock.calls[0]?.[0].body
    expect(body).toMatchObject({
      label: 'PO#',
      data_type: 'text',
      description: 'Purchase order number printed on the label',
    })
    expect(body).not.toHaveProperty('is_critical')
    expect(body).not.toHaveProperty('format_rule')
  })

  it('GIVEN no description THEN null is sent', async () => {
    renderPage()
    open()
    fireEvent.change(dialog().getByLabelText('Field name technicians see'), {
      target: { value: 'Voltage' },
    })
    fireEvent.click(dialog().getByRole('button', { name: 'Add field' }))
    await waitFor(() => expect(calls.addField).toHaveBeenCalled())
    expect(calls.addField.mock.calls[0]?.[0].body.description).toBeNull()
  })

  it('GIVEN a field name already used THEN it is refused before sending', async () => {
    renderPage()
    open()
    fireEvent.change(dialog().getByLabelText('Field name technicians see'), {
      target: { value: 'serial number' },
    })
    fireEvent.click(dialog().getByRole('button', { name: 'Add field' }))
    expect(
      await dialog().findByText('A field with this name already exists in this type.'),
    ).toBeInTheDocument()
    expect(calls.addField).not.toHaveBeenCalled()
  })

  it('GIVEN a field saved earlier as a Dropdown WHEN edited THEN it keeps its type and choices', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Edit Hazard Class' }))
    const type = dialog().getByLabelText('Type of value') as HTMLSelectElement
    expect(type.value).toBe('dropdown')
    expect(
      within(type)
        .getAllByRole('option')
        .map((o) => o.textContent),
    ).toEqual(['Text', 'Number', 'Date', 'Dropdown'])
    expect((dialog().getByLabelText('Choice 1') as HTMLInputElement).value).toBe('Flammable')
    fireEvent.change(dialog().getByLabelText('Description (optional)'), {
      target: { value: 'The hazard class on the drum.' },
    })
    fireEvent.click(dialog().getByRole('button', { name: 'Save changes' }))
    await waitFor(() => expect(calls.updateField).toHaveBeenCalled())
    expect(calls.updateField.mock.calls[0]?.[0]).toMatchObject({
      fieldId: 'hz',
      data_type: 'dropdown',
      options: ['Flammable', 'Toxic'],
      description: 'The hazard class on the drum.',
    })
  })

  it('GIVEN an edit THEN the popup starts with the saved description', () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Edit Serial Number' }))
    expect((dialog().getByLabelText('Description (optional)') as HTMLTextAreaElement).value).toBe(
      'The unique serial number, printed after S/N.',
    )
  })
})

describe('Delete and rename', () => {
  it('GIVEN Delete type THEN it only asks "Are you sure? This can’t be undone."', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Delete type' }))
    expect(dialog().getByText('Delete Motor Nameplate?')).toBeInTheDocument()
    expect(dialog().getByText('Are you sure? This can’t be undone.')).toBeInTheDocument()
    expect(dialog().queryByText(/never published/)).toBeNull()
    fireEvent.click(dialog().getByRole('button', { name: 'Yes, delete type' }))
    await waitFor(() => expect(calls.deleteType).toHaveBeenCalled())
    expect(screen.queryByText(/was deleted/)).toBeNull() // the register shows it
  })

  it('GIVEN Delete on a field THEN it asks the same, and deletes it', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Delete Serial Number' }))
    expect(dialog().getByText('Are you sure? This can’t be undone.')).toBeInTheDocument()
    expect(dialog().queryByText(/isn't published yet/)).toBeNull()
    fireEvent.click(dialog().getByRole('button', { name: 'Yes, delete' }))
    await waitFor(() => expect(calls.deleteField).toHaveBeenCalledWith('sn'))
  })

  it('GIVEN Rename type THEN the box is called Equipment Name, with no explanation under it', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Rename type' }))
    expect(dialog().getByLabelText('Equipment Name')).toBeInTheDocument()
    expect(dialog().queryByText(/rename it until/)).toBeNull()
    fireEvent.change(dialog().getByLabelText('Equipment Name'), { target: { value: 'Motors' } })
    fireEvent.click(dialog().getByRole('button', { name: 'Save name' }))
    await waitFor(() => expect(calls.rename).toHaveBeenCalledWith('Motors'))
  })

  it('GIVEN Publish THEN contract 2.19 is called after confirming, with no result banner', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Publish' }))
    fireEvent.click(dialog().getByRole('button', { name: 'Publish and lock' }))
    await waitFor(() => expect(calls.publish).toHaveBeenCalled())
    expect(screen.queryByText(/is published\./)).toBeNull()
  })
})

describe('New type', () => {
  const open = () => fireEvent.click(screen.getByRole('button', { name: '+ New type' }))

  it('GIVEN the popup THEN the name box is Equipment Name and there are only two ways to start', () => {
    renderPage()
    open()
    expect(dialog().getByLabelText('Equipment Name')).toBeInTheDocument()
    expect(dialog().queryByLabelText('Name technicians will see')).toBeNull()
    const choices = dialog().getAllByRole('radio')
    expect(choices.map((c) => c.closest('label')?.textContent)).toEqual([
      'Blank',
      'AI assisted schema discovery',
    ])
    expect(dialog().queryByLabelText(/Copy of/)).toBeNull()
  })

  it('GIVEN the popup THEN the "starts as Not published" note is gone', () => {
    renderPage()
    open()
    expect(dialog().queryByText(/starts as Not published/)).toBeNull()
    expect(dialog().queryByText(/use AI-assist/)).toBeNull()
  })

  it('GIVEN Blank THEN the photo picker is hidden and the button says Create type', async () => {
    renderPage()
    open()
    expect(dialog().queryByLabelText('Image of the label')).toBeNull()
    fireEvent.change(dialog().getByLabelText('Equipment Name'), { target: { value: 'Motor v2' } })
    fireEvent.click(dialog().getByRole('button', { name: 'Create type' }))
    await waitFor(() =>
      expect(calls.create).toHaveBeenCalledWith({
        body: { name: 'Motor v2', created_via: 'blank' },
        idempotencyKey: expect.any(String),
      }),
    )
    // The new type is open: no banner.
    expect(screen.queryByText(/was created as Not published/)).toBeNull()
  })

  it('GIVEN no name THEN it asks for one; a name already in the register is refused', async () => {
    renderPage()
    open()
    fireEvent.click(dialog().getByRole('button', { name: 'Create type' }))
    expect(await dialog().findByText('Enter a name.')).toBeInTheDocument()
    fireEvent.change(dialog().getByLabelText('Equipment Name'), {
      target: { value: 'motor nameplate' },
    })
    fireEvent.click(dialog().getByRole('button', { name: 'Create type' }))
    expect(
      await dialog().findByText('A type with this name is already in the register.'),
    ).toBeInTheDocument()
    expect(calls.create).not.toHaveBeenCalled()
  })

  it('GIVEN AI assisted schema discovery THEN the photo picker appears and the button reads Read from image', () => {
    renderPage()
    open()
    fireEvent.click(dialog().getByLabelText('AI assisted schema discovery'))
    expect(dialog().getByLabelText('Image of the label')).toBeInTheDocument()
    expect(dialog().getByRole('button', { name: 'Read from image' })).toBeInTheDocument()
    expect(dialog().queryByRole('button', { name: 'Create type' })).toBeNull()
  })

  it('GIVEN no photo THEN it asks for one', async () => {
    renderPage()
    open()
    fireEvent.change(dialog().getByLabelText('Equipment Name'), { target: { value: 'Generator' } })
    fireEvent.click(dialog().getByLabelText('AI assisted schema discovery'))
    fireEvent.click(dialog().getByRole('button', { name: 'Read from image' }))
    expect(await dialog().findByText('Choose an image of the label.')).toBeInTheDocument()
    expect(calls.suggest).not.toHaveBeenCalled()
  })

  it('GIVEN no photo yet THEN the picker offers Choose image, and a chosen file shows its name with Change and Remove', () => {
    renderPage()
    open()
    fireEvent.click(dialog().getByLabelText('AI assisted schema discovery'))
    expect(dialog().getByRole('button', { name: 'Choose image' })).toBeInTheDocument()
    expect(dialog().queryByText(/No file chosen/)).toBeNull()
    const photo = new File(['x'.repeat(2500)], 'nameplate.jpg', { type: 'image/jpeg' })
    fireEvent.change(dialog().getByLabelText('Image of the label'), { target: { files: [photo] } })
    expect(dialog().getByText('nameplate.jpg')).toBeInTheDocument()
    expect(dialog().getByText('3 KB')).toBeInTheDocument()
    fireEvent.click(dialog().getByRole('button', { name: 'Remove' }))
    expect(dialog().getByRole('button', { name: 'Choose image' })).toBeInTheDocument()
  })

  it('GIVEN a file that is not a JPEG or PNG THEN it is refused with a reason', () => {
    renderPage()
    open()
    fireEvent.click(dialog().getByLabelText('AI assisted schema discovery'))
    const pdf = new File(['x'], 'label.pdf', { type: 'application/pdf' })
    fireEvent.change(dialog().getByLabelText('Image of the label'), { target: { files: [pdf] } })
    expect(dialog().getByRole('alert')).toHaveTextContent("isn't a JPEG or PNG")
    expect(dialog().queryByText('label.pdf')).toBeNull()
  })

  it('GIVEN the AI is reading the photo THEN a clear busy message shows and nothing can be changed or closed', () => {
    reading.on = true
    try {
      renderPage()
      open()
      fireEvent.click(dialog().getByLabelText('AI assisted schema discovery'))
      expect(dialog().getByRole('status')).toHaveTextContent('Reading your image…')
      expect(dialog().getByRole('status')).toHaveTextContent('Please keep this window open')
      expect(dialog().getByRole('button', { name: /Reading the image/ })).toBeDisabled()
      expect(dialog().getByRole('button', { name: 'Cancel' })).toBeDisabled()
      expect(dialog().getByRole('button', { name: 'Choose image' })).toBeDisabled()
      expect(dialog().getByLabelText('Equipment Name')).toBeDisabled()
      expect(dialog().getByLabelText('Blank')).toBeDisabled()
      expect(dialog().getByLabelText('Image of the label')).toBeDisabled()
    } finally {
      reading.on = false
    }
  })

  const discover = async () => {
    calls.suggest.mockResolvedValue([
      { label: 'Manufacturer', data_type: 'text', description: 'The maker, usually the logo.' },
      { label: 'Voltage', data_type: 'number', description: 'Rated voltage in volts.' },
      { label: 'Notes', data_type: 'text', description: null },
    ])
    renderPage()
    open()
    fireEvent.change(dialog().getByLabelText('Equipment Name'), { target: { value: 'Generator' } })
    fireEvent.click(dialog().getByLabelText('AI assisted schema discovery'))
    const photo = new File(['x'], 'label.jpg', { type: 'image/jpeg' })
    fireEvent.change(dialog().getByLabelText('Image of the label'), { target: { files: [photo] } })
    fireEvent.click(dialog().getByRole('button', { name: 'Read from image' }))
    await dialog().findByRole('checkbox', { name: /Voltage/ })
    return photo
  }

  it('GIVEN the photo is read THEN every suggested field comes ticked, with its description to edit', async () => {
    const photo = await discover()
    expect(calls.suggest).toHaveBeenCalledWith({ name: 'Generator', image: photo })
    for (const name of [/Manufacturer/, /Voltage/, /Notes/]) {
      expect(dialog().getByRole('checkbox', { name })).toBeChecked()
    }
    expect(
      (dialog().getByLabelText('Description of Manufacturer') as HTMLTextAreaElement).value,
    ).toBe('The maker, usually the logo.')
    // The AI gave none for Notes: the box is empty, ready to fill.
    expect((dialog().getByLabelText('Description of Notes') as HTMLTextAreaElement).value).toBe('')
    expect(dialog().getByRole('button', { name: 'Create type with 3 fields' })).toBeInTheDocument()
  })

  it('GIVEN suggested fields WHEN one is unticked and a description changed THEN the type is created with exactly that', async () => {
    await discover()
    fireEvent.click(dialog().getByRole('checkbox', { name: /Notes/ }))
    fireEvent.change(dialog().getByLabelText('Description of Voltage'), {
      target: { value: '  Rated supply voltage in volts, no unit.  ' },
    })
    expect(dialog().getByRole('button', { name: 'Create type with 2 fields' })).toBeInTheDocument()
    fireEvent.click(dialog().getByRole('button', { name: 'Create type with 2 fields' }))
    await waitFor(() => expect(calls.create).toHaveBeenCalled())
    const body = calls.create.mock.calls[0]?.[0].body
    expect(body).toMatchObject({ name: 'Generator', created_via: 'ai_assist' })
    expect(body.fields).toEqual([
      {
        label: 'Manufacturer',
        data_type: 'text',
        is_required: false,
        description: 'The maker, usually the logo.',
        flag_below_confidence: 0.85,
      },
      {
        label: 'Voltage',
        data_type: 'number',
        is_required: false,
        description: 'Rated supply voltage in volts, no unit.',
        flag_below_confidence: 0.85,
      },
    ])
    expect(body.fields[0]).not.toHaveProperty('is_critical')
  })

  it('GIVEN one field ticked THEN the button says "1 field", not "1 fields"', async () => {
    await discover()
    fireEvent.click(dialog().getByRole('checkbox', { name: /Notes/ }))
    fireEvent.click(dialog().getByRole('checkbox', { name: /Voltage/ }))
    expect(dialog().getByRole('button', { name: 'Create type with 1 field' })).toBeInTheDocument()
  })

  it('GIVEN every field unticked THEN it asks for at least one', async () => {
    await discover()
    for (const name of [/Manufacturer/, /Voltage/, /Notes/]) {
      fireEvent.click(dialog().getByRole('checkbox', { name }))
    }
    fireEvent.click(dialog().getByRole('button', { name: 'Create type with 0 fields' }))
    expect(await dialog().findByText('Tick at least one field.')).toBeInTheDocument()
    expect(calls.create).not.toHaveBeenCalled()
  })

  it('GIVEN a blank description WHEN created THEN none is sent for that field', async () => {
    await discover()
    fireEvent.click(dialog().getByRole('button', { name: 'Create type with 3 fields' }))
    await waitFor(() => expect(calls.create).toHaveBeenCalled())
    const notes = calls.create.mock.calls[0]?.[0].body.fields.find(
      (f: { label: string }) => f.label === 'Notes',
    )
    expect(notes.description).toBeNull()
  })
})
