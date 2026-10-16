import { useMutation, useQueryClient, type QueryKey } from '@tanstack/react-query'

/**
 * A change (create, update, delete, action) that re-reads the given lists once it
 * succeeds, so every screen shows the new state. Used by all API hooks that write.
 */
export function useRefreshingMutation<Vars, Result>(
  call: (vars: Vars) => Promise<Result>,
  refresh: QueryKey[],
) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: call,
    onSuccess: () =>
      Promise.all(refresh.map((queryKey) => queryClient.invalidateQueries({ queryKey }))),
  })
}
