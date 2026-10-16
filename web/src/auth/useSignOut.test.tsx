import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useSignOut } from './useSignOut'

const post = vi.fn()
vi.mock('../api/client', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  api: { POST: (...a: unknown[]) => post(...a) },
}))

function SignOutButton() {
  const signOut = useSignOut()
  return <button onClick={() => void signOut()}>Sign out</button>
}

const page = (client: QueryClient) =>
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={['/overview']}>
        <Routes>
          <Route path="/overview" element={<SignOutButton />} />
          <Route path="/signed-out" element={<h1>Signed out</h1>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )

beforeEach(() => post.mockReset().mockResolvedValue({ response: { status: 204 } }))

describe('sign out (contract 1.3, D-11)', () => {
  it('GIVEN sign out THEN ends the API session for this device and forgets cached data', async () => {
    const client = new QueryClient()
    client.setQueryData(['me'], { full_name: 'R. Kowalski' })
    page(client)
    fireEvent.click(screen.getByRole('button', { name: 'Sign out' }))
    expect(await screen.findByRole('heading', { name: 'Signed out' })).toBeInTheDocument()
    expect(post).toHaveBeenCalledWith('/me/sign-out', {
      params: { header: { 'X-Device-Id': expect.any(String) } },
    })
    expect(client.getQueryData(['me'])).toBeUndefined()
  })

  it('GIVEN the API call fails THEN still signs out locally', async () => {
    post.mockRejectedValueOnce(new Error('offline'))
    page(new QueryClient())
    fireEvent.click(screen.getByRole('button', { name: 'Sign out' }))
    expect(await screen.findByRole('heading', { name: 'Signed out' })).toBeInTheDocument()
  })
})
