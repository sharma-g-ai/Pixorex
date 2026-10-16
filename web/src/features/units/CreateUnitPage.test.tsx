import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useBuAdmins } from '../../api/buAdmins'
import { ApiError } from '../../api/client'
import { CreateUnitPage } from './CreateUnitPage'

const mutateAsync = vi.fn()

vi.mock('../../api/businessUnits', () => ({
  useCreateBusinessUnit: () => ({ mutateAsync, isPending: false }),
}))
vi.mock('../../api/buAdmins', () => ({ useBuAdmins: vi.fn() }))

function renderPage() {
  vi.mocked(useBuAdmins).mockReturnValue({
    isPending: false,
    data: [
      {
        user_id: 'rk',
        full_name: 'R. Kowalski',
        email: 'rk@ppg.test',
        status: 'active',
        last_active_at: null,
        units: [{ bu_id: 'p04', name: 'Plant 04' }],
      },
    ],
  } as never)
  return render(
    <MemoryRouter initialEntries={['/overview/new-unit']}>
      <Routes>
        <Route path="/overview/new-unit" element={<CreateUnitPage />} />
        <Route path="/locations" element={<h1>Locations page</h1>} />
      </Routes>
    </MemoryRouter>,
  )
}

const type = (label: string, value: string) =>
  fireEvent.change(screen.getByLabelText(label), { target: { value } })
const submit = () =>
  fireEvent.click(screen.getByRole('button', { name: 'Create unit & set up locations' }))

beforeEach(() => mutateAsync.mockReset())

describe('CreateUnitPage', () => {
  it('GIVEN an empty form WHEN submitted THEN shows what is missing and sends nothing', async () => {
    renderPage()
    submit()
    expect(await screen.findByText('Enter the unit name.')).toBeInTheDocument()
    expect(screen.getByText('Enter the facility name.')).toBeInTheDocument()
    expect(screen.getByText('Enter a valid email address.')).toBeInTheDocument()
    expect(mutateAsync).not.toHaveBeenCalled()
  })

  it('GIVEN a new unit with an invite WHEN submitted THEN sends contract 1.13 and returns to Overview', async () => {
    mutateAsync.mockResolvedValue({ bu_id: 'p12', name: 'PPG Plant 12' })
    renderPage()
    type('Unit name', 'PPG Plant 12')
    type('Facility (top location level)', 'Plant 12 — Akron, OH')
    type('Email', 'd.okafor@ppg.com')
    submit()

    await screen.findByRole('heading', { name: 'Locations page' })
    expect(mutateAsync).toHaveBeenCalledWith({
      body: {
        name: 'PPG Plant 12',
        facility_name: 'Plant 12 — Akron, OH',
        bu_admin: { invite_email: 'd.okafor@ppg.com' },
      },
      idempotencyKey: expect.any(String),
    })
  })

  it('GIVEN an existing BU Admin picked WHEN submitted THEN sends their user_id', async () => {
    mutateAsync.mockResolvedValue({ bu_id: 'p12', name: 'PPG Plant 12' })
    renderPage()
    type('Unit name', 'PPG Plant 12')
    type('Facility (top location level)', 'Plant 12')
    fireEvent.click(screen.getByLabelText(/Use an existing BU Admin/))
    fireEvent.click(screen.getByLabelText(/R\. Kowalski/))
    submit()

    await waitFor(() =>
      expect(mutateAsync).toHaveBeenCalledWith(
        expect.objectContaining({ body: expect.objectContaining({ bu_admin: { user_id: 'rk' } }) }),
      ),
    )
  })

  it('GIVEN the name is taken WHEN the API answers 409 duplicate-name THEN the name field shows it', async () => {
    const conflict = new ApiError({
      type: '/problems/duplicate-name',
      title: 'Conflict',
      status: 409,
    })
    mutateAsync.mockRejectedValueOnce(conflict)
    renderPage()
    type('Unit name', 'PPG Plant 04')
    type('Facility (top location level)', 'Plant 04')
    type('Email', 'a@ppg.com')
    submit()

    expect(await screen.findByText('A unit with this name already exists.')).toBeInTheDocument()
    expect(screen.getByLabelText('Unit name')).toHaveAttribute('aria-invalid', 'true')
  })

  it('GIVEN a retry after an error THEN the same Idempotency-Key is sent', async () => {
    mutateAsync.mockRejectedValueOnce(new Error('network')).mockResolvedValueOnce({ name: 'X' })
    renderPage()
    type('Unit name', 'X')
    type('Facility (top location level)', 'Y')
    type('Email', 'a@ppg.com')
    submit()
    await screen.findByText('Something went wrong. Please try again.')
    submit()

    await waitFor(() => expect(mutateAsync).toHaveBeenCalledTimes(2))
    const keys = mutateAsync.mock.calls.map(
      ([arg]) => (arg as { idempotencyKey: string }).idempotencyKey,
    )
    expect(new Set(keys).size).toBe(1)
  })
})
