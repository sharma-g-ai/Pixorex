import { useInfiniteQuery } from '@tanstack/react-query'

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
) {
  const query = useInfiniteQuery({
    queryKey,
    queryFn: ({ pageParam }) => fetchPage(pageParam),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last) => last.page.next_cursor ?? undefined,
  })
  return { ...query, items: query.data?.pages.flatMap((p) => p.items) ?? [] }
}
