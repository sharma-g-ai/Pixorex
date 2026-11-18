import { keepPreviousData, useInfiniteQuery } from '@tanstack/react-query'

interface Page<T> {
  items: T[]
  page: { next_cursor: string | null }
}

/**
 * A cursor-paged list (contracts: `cursor` in, `page.next_cursor` out). `items` holds every
 * page loaded so far; `fetchNextPage` loads one more.
 */
export function usePagedList<T>(
  queryKey: readonly unknown[],
  fetchPage: (cursor: string | undefined) => Promise<Page<T>>,
  options: { refetchMs?: number } = {},
) {
  const query = useInfiniteQuery({
    queryKey,
    queryFn: ({ pageParam }) => fetchPage(pageParam),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last) => last.page.next_cursor ?? undefined,
    // A list that changes under the reader (the review queue) asks again from time to time.
    refetchInterval: options.refetchMs,
    refetchOnWindowFocus: options.refetchMs !== undefined,
    // When the filters change, the rows already shown stay until the new ones arrive, so the
    // table (and a filter popup open in its header) is not swapped for a loading message.
    placeholderData: keepPreviousData,
  })
  return { ...query, items: query.data?.pages.flatMap((p) => p.items) ?? [] }
}
