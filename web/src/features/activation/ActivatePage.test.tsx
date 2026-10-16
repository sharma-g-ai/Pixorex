import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../../api/client'
import { ActivatePage } from './ActivatePage'
import { readInviteToken } from './inviteLink'

const accept = vi.fn()
let preview: { isPending: boolean; isError: boolean; data?: unknown; error?: unknown }
vi.mock('../../api/activation', () => ({
  useInvitePreview: () => preview,
  useAcceptInvite: () => ({ mutateAsync: accept }),
}))

const invite = {
  role: 'bu_admin',
  email: 'm.lopez@ppg.com',
  units: [{ bu_id: 'p11', name: 'PPG Plant 11 — Resins' }],
  invited_by_name: 'A. Mehta',
  expires_at: '2026-10-06T06:00:00Z',
}
const conflict = (code: string) =>
  new ApiError({ type: `/problems/${code}`, title: 'Conflict', status: 409 })

function openLink(url: string) {
  window.history.replaceState(null, '', url)
  return render(
    <MemoryRouter initialEntries={['/activate']}>
      <Routes>
        <Route path="/activate" element={<ActivatePage />} />
        <Route path="/" element={<h1>Dashboard home</h1>} />
      </Routes>
    </MemoryRouter>,
  )
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date('2026-10-05T12:00:00Z'))
  accept.mockReset().mockResolvedValue({ user_id: 'u1', next_step: 'verify_email' })
  preview = { isPending: false, isError: false, data: invite }
})
afterEach(() => {
  vi.useRealTimers()
  window.history.replaceState(null, '', '/')
})

describe('invite link (D-11)', () => {
  it('reads the token from the fragment, or the query for older links', () => {
    expect(readInviteToken('#token=abc123', '')).toBe('abc123')
    expect(readInviteToken('', '?token=old')).toBe('old')
    expect(readInviteToken('#token=new', '?token=old')).toBe('new')
    expect(readInviteToken('', '')).toBe('')
  })

  it('GIVEN the link is opened THEN the token is removed from the address bar', () => {
    openLink('/activate#token=secret-token')
    expect(window.location.hash).toBe('')
    expect(window.location.href).not.toContain('secret-token')
  })
})

describe('Activate your account (canvas BU 01; contracts 1.6, 1.7)', () => {
  it('GIVEN a valid invite THEN shows the email (read-only), units and who assigned them', () => {
    openLink('/activate#token=t1')
    expect(screen.getByRole('heading', { name: 'Activate your account' })).toBeInTheDocument()
    expect(screen.getByLabelText('Work email')).toHaveValue('m.lopez@ppg.com')
    expect(screen.getByLabelText('Work email')).toBeDisabled()
    expect(screen.getByText('PPG Plant 11 — Resins')).toBeInTheDocument()
    expect(screen.getByText('Assigned by A. Mehta (Enterprise Admin)')).toBeInTheDocument()
    expect(screen.getByText(/This invite link expires in 18 h\./)).toBeInTheDocument()
  })

  it('GIVEN no name THEN asks for it and sends nothing', async () => {
    openLink('/activate#token=t1')
    fireEvent.click(screen.getByRole('button', { name: 'Activate account' }))
    expect(await screen.findByText('Enter your full name.')).toBeInTheDocument()
    expect(accept).not.toHaveBeenCalled()
  })

  it('GIVEN a name WHEN activating THEN accepts with the token and goes on (mock mode)', async () => {
    openLink('/activate#token=t1')
    fireEvent.change(screen.getByLabelText('Full name'), { target: { value: '  Maria Lopez ' } })
    fireEvent.click(screen.getByRole('button', { name: 'Activate account' }))
    expect(await screen.findByRole('heading', { name: 'Dashboard home' })).toBeInTheDocument()
    expect(accept).toHaveBeenCalledWith({ token: 't1', full_name: 'Maria Lopez' })
  })

  it('GIVEN the link expired while the page was open THEN the form is replaced by the reason', async () => {
    accept.mockRejectedValueOnce(conflict('invite-expired'))
    openLink('/activate#token=t1')
    fireEvent.change(screen.getByLabelText('Full name'), { target: { value: 'Maria Lopez' } })
    fireEvent.click(screen.getByRole('button', { name: 'Activate account' }))
    expect(
      await screen.findByRole('heading', { name: 'This invite has expired' }),
    ).toBeInTheDocument()
  })

  it('GIVEN another error THEN keeps the form and shows the message', async () => {
    accept.mockRejectedValueOnce(
      new ApiError({
        type: '/problems/validation',
        title: 'Bad',
        status: 400,
        detail: 'Name too long.',
      }),
    )
    openLink('/activate#token=t1')
    fireEvent.change(screen.getByLabelText('Full name'), { target: { value: 'Maria Lopez' } })
    fireEvent.click(screen.getByRole('button', { name: 'Activate account' }))
    expect(await screen.findByText('Name too long.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Activate account' })).toBeInTheDocument()
  })

  it.each([
    ['invite-used', 'This invite was already used', true],
    ['invite-cancelled', 'This invite was cancelled', false],
    ['invite-expired', 'This invite has expired', false],
  ])('GIVEN %s THEN says "%s"', (code, title, canSignIn) => {
    preview = { isPending: false, isError: true, error: conflict(code) }
    openLink('/activate#token=t1')
    expect(screen.getByRole('heading', { name: title })).toBeInTheDocument()
    expect(!!screen.queryByRole('button', { name: 'Sign in' })).toBe(canSignIn)
  })

  it('GIVEN a link without a token THEN explains, without calling the API', () => {
    openLink('/activate')
    expect(
      screen.getByRole('heading', { name: 'This invite link is incomplete' }),
    ).toBeInTheDocument()
  })

  it('GIVEN a technician invite THEN sends them to the mobile app (no dashboard access)', () => {
    preview = { isPending: false, isError: false, data: { ...invite, role: 'field_technician' } }
    openLink('/activate#token=t1')
    expect(screen.getByRole('heading', { name: 'Activate in the mobile app' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Activate account' })).not.toBeInTheDocument()
  })
})

describe('accept sends no token in a URL', () => {
  it('GIVEN activation THEN the token only travels in the request body', async () => {
    openLink('/activate#token=t9')
    fireEvent.change(screen.getByLabelText('Full name'), { target: { value: 'Maria Lopez' } })
    fireEvent.click(screen.getByRole('button', { name: 'Activate account' }))
    await waitFor(() => expect(accept).toHaveBeenCalled())
    expect(window.location.href).not.toContain('t9')
  })
})
