import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { renderHook, waitFor } from '@testing-library/react'
import type { ReactNode } from 'react'
import { describe, expect, it } from 'vitest'
import { usePagedList } from './paging'

function wrapper({ children }: { children: ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>
}

describe('usePagedList', () => {
  it('GIVEN new filters THEN the rows already shown stay until the new ones arrive (no loading flash)', async () => {
    let release: (v: { items: string[]; page: { next_cursor: null } }) => void = () => {}
    const fetchFor = (filter: string) => (cursor: string | undefined) =>
      filter === 'a'
        ? Promise.resolve({ items: ['a1', 'a2'], page: { next_cursor: null } })
        : new Promise<{ items: string[]; page: { next_cursor: null } }>((resolve) => {
            void cursor
            release = resolve
          })
    const { result, rerender } = renderHook(
      ({ filter }: { filter: string }) => usePagedList(['list', filter], fetchFor(filter)),
      { wrapper, initialProps: { filter: 'a' } },
    )
    await waitFor(() => expect(result.current.items).toEqual(['a1', 'a2']))

    rerender({ filter: 'b' })
    // While "b" is loading, the page is not "pending": the old rows are still there.
    expect(result.current.isPending).toBe(false)
    expect(result.current.items).toEqual(['a1', 'a2'])
    expect(result.current.isPlaceholderData).toBe(true)

    release({ items: ['b1'], page: { next_cursor: null } })
    await waitFor(() => expect(result.current.items).toEqual(['b1']))
    expect(result.current.isPlaceholderData).toBe(false)
  })
})
