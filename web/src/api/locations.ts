import { useQuery } from '@tanstack/react-query'
import { businessUnitsQueryKey } from './businessUnits'
import { api, unwrap } from './client'
import type { components } from './generated/s3'
import { useRefreshingMutation } from './useRefreshingMutation'

export type LocationSetup = components['schemas']['LocationSetup']
export type Level = components['schemas']['Level']
export type LevelInput = components['schemas']['LevelInput']
export type LocationNode = components['schemas']['LocationNode']
export type Requirement = components['schemas']['Requirement']
export type PublishCheck = components['schemas']['PublishCheck']

const setupKey = (buId: string) => ['locations', buId] as const

/** Contract 2.1: a unit's levels and location tree (EA). */
export function useLocationSetup(buId: string) {
  return useQuery({
    queryKey: setupKey(buId),
    queryFn: async () =>
      unwrap(await api.GET('/business-units/{buId}/locations', { params: { path: { buId } } })),
  })
}

/** Every location change re-reads the tree, so counts and paths stay right. */
function useChange<Vars, Result>(buId: string, call: (vars: Vars) => Promise<Result>) {
  return useRefreshingMutation(call, [setupKey(buId)])
}

/** Contract 2.2: replaces the whole level list, top to bottom. */
export function useSetLevels(buId: string) {
  return useChange(buId, async (levels: LevelInput[]) =>
    unwrap(
      await api.PUT('/business-units/{buId}/locations/levels', {
        params: { path: { buId } },
        body: { levels },
      }),
    ),
  )
}

/** Contract 2.3: one placeholder per level, the top one named after the facility. */
export function useCreateSkeleton(buId: string) {
  return useChange(buId, async () =>
    unwrap(
      await api.POST('/business-units/{buId}/locations/skeleton', { params: { path: { buId } } }),
    ),
  )
}

/**
 * Contract 2.4: adds 1–50 locations inside a parent. The caller passes one
 * Idempotency-Key per dialog, so a retried add cannot create them twice.
 */
export function useAddNodes(buId: string) {
  return useChange(
    buId,
    async ({
      idempotencyKey,
      ...body
    }: {
      parent_id: string
      level_id: string
      names: string[]
      idempotencyKey: string
    }) =>
      unwrap(
        await api.POST('/business-units/{buId}/locations/nodes', {
          params: { path: { buId }, header: { 'Idempotency-Key': idempotencyKey } },
          body,
        }),
      ),
  )
}

/** Contract 2.5: rename ({name}) or move ({parent_id}) one location. */
export function useUpdateNode(buId: string) {
  return useChange(
    buId,
    async ({ nodeId, ...body }: { nodeId: string; name?: string; parent_id?: string }) =>
      unwrap(await api.PATCH('/location-nodes/{nodeId}', { params: { path: { nodeId } }, body })),
  )
}

/** Contract 2.6: deletes the location and everything inside it. */
export function useDeleteNode(buId: string) {
  return useChange(buId, async (nodeId: string) =>
    unwrap(await api.DELETE('/location-nodes/{nodeId}', { params: { path: { nodeId } } })),
  )
}

/** Contract 2.7: what Review & publish checks before publishing. */
export function usePublishCheck(buId: string, enabled: boolean) {
  return useQuery({
    queryKey: [...setupKey(buId), 'publish-check'],
    enabled,
    queryFn: async () =>
      unwrap(
        await api.GET('/business-units/{buId}/locations/publish-check', {
          params: { path: { buId } },
        }),
      ),
  })
}

/** Contract 2.8: publishes and locks the unit's levels and locations for good. */
export function usePublishLocations(buId: string) {
  return useRefreshingMutation(
    async () =>
      unwrap(
        await api.POST('/business-units/{buId}/locations/publish', { params: { path: { buId } } }),
      ),
    [setupKey(buId), businessUnitsQueryKey],
  )
}
