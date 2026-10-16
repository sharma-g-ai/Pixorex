import { Button } from './Button'

interface LoadMoreProps {
  hasNextPage: boolean
  isFetchingNextPage: boolean
  fetchNextPage: () => unknown
}

/** "Load more" under a cursor-paged list; hidden once the last page is in. */
export function LoadMore({ hasNextPage, isFetchingNextPage, fetchNextPage }: LoadMoreProps) {
  if (!hasNextPage) return null
  return (
    <div className="flex justify-center">
      <Button variant="secondary" disabled={isFetchingNextPage} onClick={() => fetchNextPage()}>
        {isFetchingNextPage ? 'Loading…' : 'Load more'}
      </Button>
    </div>
  )
}
