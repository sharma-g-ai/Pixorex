import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api, unwrap } from './client'
import type { components } from './generated/s2'

export type Technician = components['schemas']['Technician']

const techniciansKey = (buId: string) => ['technicians', buId] as const

/** Contract 1.18 GET /business-units/{buId}/technicians (BU Admin). */
export function useTechnicians(buId: string) {
  return useQuery({
    queryKey: techniciansKey(buId),
    queryFn: async () =>
      unwrap(await api.GET('/business-units/{buId}/technicians', { params: { path: { buId } } }))
        .items,
  })
}

/**
 * Contract 1.19: removes the technician from this unit. The API signs them out of
 * the unit and returns their open batch to the review queue.
 */
export function useRemoveTechnician(buId: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (userId: string) =>
      unwrap(
        await api.POST('/business-units/{buId}/technicians/{userId}/remove', {
          params: { path: { buId, userId } },
        }),
      ),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: techniciansKey(buId) }),
  })
}
