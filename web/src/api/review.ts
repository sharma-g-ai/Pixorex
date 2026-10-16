import { useQuery } from '@tanstack/react-query'
import { api, unwrap } from './client'
import type { components } from './generated/s4'
import { useRefreshingMutation } from './useRefreshingMutation'

export type QueueFilter = 'waiting' | 'over_1d' | 'over_1w' | 'delegated' | 'decided_by_technicians'
export type QueueItem = components['schemas']['QueueItem']
export type QueueCounts = components['schemas']['QueueCounts']
export type ScanReview = components['schemas']['ScanReview']
export type ReviewField = components['schemas']['ReviewField']
export type Decision = components['schemas']['Decision']
export type DecisionInput = components['schemas']['DecisionInput']
export type RejectCategory = components['schemas']['RejectCategory']
export type TechnicianDecision = components['schemas']['TechnicianDecision']
export type Delegate = components['schemas']['Delegate']
export type Batch = components['schemas']['Batch']
export type Excluded = components['schemas']['Excluded']

/** Everything that changes when a scan is decided or a batch moves. */
const reviewKeys = [
  'review-queue',
  'scan-review',
  'technician-decisions',
  'review-batches',
  'escalations',
  'scans',
  // Unit cards show waiting / escalated / delegated counts.
  'business-units',
]

/** Contract 3.3: the unit's review queue with the tab counts. */
export function useReviewQueue(buId: string, filter: QueueFilter) {
  return useQuery({
    queryKey: ['review-queue', buId, filter],
    queryFn: async () =>
      unwrap(
        await api.GET('/business-units/{buId}/review-queue', {
          params: { path: { buId }, query: { filter } },
        }),
      ),
  })
}

/** Contract 3.4: one scan for review (photos, AI vs technician values, decisions). */
export function useScanReview(scanId: string) {
  return useQuery({
    queryKey: ['scan-review', scanId],
    queryFn: async () =>
      unwrap(await api.GET('/scans/{scanId}/review', { params: { path: { scanId } } })),
  })
}

/** Contract 3.5: approve or reject the current revision. First decider wins (409). */
export function useDecide(scanId: string) {
  return useRefreshingMutation(
    async ({ body, idempotencyKey }: { body: DecisionInput; idempotencyKey: string }) =>
      unwrap(
        await api.POST('/scans/{scanId}/decisions', {
          params: { path: { scanId }, header: { 'Idempotency-Key': idempotencyKey } },
          body,
        }),
      ),
    reviewKeys.map((k) => [k]),
  )
}

/** Contract 3.6: decisions made by technicians in delegated batches. */
export function useTechnicianDecisions(buId: string, decision?: 'approved' | 'rejected') {
  return useQuery({
    queryKey: ['technician-decisions', buId, decision ?? 'all'],
    queryFn: async () =>
      unwrap(
        await api.GET('/business-units/{buId}/technician-decisions', {
          params: { path: { buId }, query: decision ? { decision } : {} },
        }),
      ).items,
  })
}

/** Contract 3.7: replaces a technician's decision with the admin's. */
export function useOverride(decisionId: string) {
  return useRefreshingMutation(
    async ({ body, idempotencyKey }: { body: DecisionInput; idempotencyKey: string }) =>
      unwrap(
        await api.POST('/decisions/{decisionId}/override', {
          params: { path: { decisionId }, header: { 'Idempotency-Key': idempotencyKey } },
          body,
        }),
      ),
    reviewKeys.map((k) => [k]),
  )
}

/** Contract 3.8: technicians who can take a batch, with how many of the scans are their own. */
export function useDelegates(buId: string, scanIds: string[]) {
  return useQuery({
    queryKey: ['delegates', buId, scanIds],
    queryFn: async () =>
      unwrap(
        await api.GET('/business-units/{buId}/delegates', {
          params: { path: { buId }, query: { scan_ids: scanIds } },
        }),
      ).items,
  })
}

/** Contract 3.9: delegates 1–50 waiting scans to one technician; their own scans are left out. */
export function useCreateBatch(buId: string) {
  return useRefreshingMutation(
    async ({
      assignedTo,
      scanIds,
      idempotencyKey,
    }: {
      assignedTo: string
      scanIds: string[]
      idempotencyKey: string
    }) =>
      unwrap(
        await api.POST('/business-units/{buId}/review-batches', {
          params: { path: { buId }, header: { 'Idempotency-Key': idempotencyKey } },
          body: { assigned_to: assignedTo, scan_ids: scanIds },
        }),
      ),
    reviewKeys.map((k) => [k]),
  )
}

/** Contract 3.10: the unit's delegated batches. */
export function useBatches(buId: string) {
  return useQuery({
    queryKey: ['review-batches', buId],
    queryFn: async () =>
      unwrap(await api.GET('/business-units/{buId}/review-batches', { params: { path: { buId } } }))
        .items,
  })
}

/** Contract 3.12: moves a batch's open scans to another technician. */
export function useReassignBatch(batchId: string) {
  return useRefreshingMutation(
    async (assignedTo: string) =>
      unwrap(
        await api.POST('/review-batches/{batchId}/reassign', {
          params: { path: { batchId } },
          body: { assigned_to: assignedTo },
        }),
      ),
    reviewKeys.map((k) => [k]),
  )
}

/** Contract 3.13: returns a batch's open scans to the queue, with an optional message. */
export function useTakeBackBatch(batchId: string) {
  return useRefreshingMutation(
    async (message: string) =>
      unwrap(
        await api.POST('/review-batches/{batchId}/take-back', {
          params: { path: { batchId } },
          body: message ? { message } : {},
        }),
      ),
    reviewKeys.map((k) => [k]),
  )
}

/** Contract 3.14: sends the technician a reminder about the batch. */
export function useRemindBatch(batchId: string) {
  return useRefreshingMutation(
    async () =>
      unwrap(await api.POST('/review-batches/{batchId}/remind', { params: { path: { batchId } } })),
    [['review-batches']],
  )
}

/** Contract 3.11: one batch with its scans. */
export function useBatch(batchId: string) {
  return useQuery({
    queryKey: ['review-batches', 'detail', batchId],
    queryFn: async () =>
      unwrap(await api.GET('/review-batches/{batchId}', { params: { path: { batchId } } })),
  })
}
