import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api, unwrap } from './client'
import type { components } from './generated/s2'

export type BusinessUnit = components['schemas']['BusinessUnit']

/** Body of contract 1.13: a new unit with a BU Admin invite or an existing BU Admin. */
export type CreateBusinessUnit = {
  name: string
  facility_name: string
  bu_admin: { invite_email: string } | { user_id: string }
}

export const businessUnitsQueryKey = ['business-units'] as const

/** Contract 1.12 GET /business-units: every unit for the EA, own units for a BU Admin. */
export function useBusinessUnits() {
  return useQuery({
    queryKey: businessUnitsQueryKey,
    queryFn: async () => unwrap(await api.GET('/business-units')).items,
  })
}

/**
 * Contract 1.13 POST /business-units (EA). The caller passes one Idempotency-Key
 * per form, so a retried submit cannot create the unit twice.
 */
export function useCreateBusinessUnit() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({
      body,
      idempotencyKey,
    }: {
      body: CreateBusinessUnit
      idempotencyKey: string
    }) =>
      unwrap(
        await api.POST('/business-units', {
          params: { header: { 'Idempotency-Key': idempotencyKey } },
          body,
        }),
      ),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: businessUnitsQueryKey }),
  })
}
