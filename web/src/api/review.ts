import { useQuery } from '@tanstack/react-query'
import { api, unwrap } from './client'
import type { components } from './generated/s4'
import { usePagedList } from './paging'
import { useRefreshingMutation } from './useRefreshingMutation'

export type QueueItem = components['schemas']['QueueItem']
/** What the Review queue's Status column and filter offer. */
export type QueueStatus = 'waiting' | 'approved' | 'rejected'
export type SortOrder = 'oldest_first' | 'newest_first'

/** The Review queue's header filters. An empty list means no filter on that column. */
export interface QueueFilters {
  status: QueueStatus[]
  /** Schema (equipment type) ids. */
  schemas: string[]
  /** Technician user ids. */
  capturedBy: string[]
  /** YYYY-MM-DD, Indian days, both ends included; '' = no limit. */
  from: string
  to: string
  /** Scan ID typed in the column's search box; '' = no search. */
  search: string
  /** Decided from this day (YYYY-MM-DD); only Home's "approved this week" link sets it. */
  decidedFrom: string
  /** '' = the default: oldest first, scans a technician holds last. */
  sort: SortOrder | ''
}
export type QueueCounts = components['schemas']['QueueCounts']
export type ScanReview = components['schemas']['ScanReview']
export type ReviewField = components['schemas']['ReviewField']
export type Decision = components['schemas']['Decision']
export type DecisionInput = components['schemas']['DecisionInput']
export type RejectCategory = components['schemas']['RejectCategory']
export type TechnicianDecision = components['schemas']['TechnicianDecision']
export type Delegate = components['schemas']['Delegate']
export type Batch = components['schemas']['Batch']
export type Assignment = components['schemas']['Assignment']
export type Excluded = components['schemas']['Excluded']
export type ScanHistory = components['schemas']['ScanHistory']
export type HistoryEvent = components['schemas']['HistoryEvent']

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

/** How often an open review queue asks again: new scans join, decided ones leave. */
export const QUEUE_REFRESH_MS = 30_000
const QUEUE_PAGE = 50

/** Contract 3.3: the unit's review queue with the filters of its column headers, 50 at a time. */
export function useReviewQueue(buId: string, filters: QueueFilters) {
  return usePagedList(
    ['review-queue', buId, 'list', filters],
    async (cursor) =>
      unwrap(
        await api.GET('/business-units/{buId}/review-queue', {
          params: {
            path: { buId },
            query: {
              status: filters.status.length ? filters.status : undefined,
              equipment_type_id: filters.schemas.length ? filters.schemas : undefined,
              captured_by: filters.capturedBy.length ? filters.capturedBy : undefined,
              from: filters.from || undefined,
              to: filters.to || undefined,
              decided_from: filters.decidedFrom || undefined,
              q: filters.search || undefined,
              sort: filters.sort || undefined,
              cursor,
              limit: QUEUE_PAGE,
            },
          },
        }),
      ),
    { refetchMs: QUEUE_REFRESH_MS },
  )
}

/** The numbers on BU Home's cards (contract 3.3 counts): no scans are listed. */
export function useQueueCounts(buId: string) {
  return useQuery({
    queryKey: ['review-queue', buId, 'counts'],
    refetchInterval: QUEUE_REFRESH_MS,
    refetchOnWindowFocus: true,
    queryFn: async () =>
      unwrap(
        await api.GET('/business-units/{buId}/review-queue', {
          params: { path: { buId }, query: { status: ['waiting'], limit: 1 } },
        }),
      ).counts,
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

/** Contract 3.28: what happened to a scan, oldest first, and where it is now. */
export function useScanHistory(scanId: string) {
  return useQuery({
    queryKey: ['scan-review', scanId, 'history'],
    queryFn: async () =>
      unwrap(await api.GET('/scans/{scanId}/history', { params: { path: { scanId } } })),
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

/** Contract 3.6: the latest decisions made by technicians in delegated batches (BU Home). */
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

/** The "All decisions" table's header filters. */
export interface DecisionFilters {
  decision: 'approved' | 'rejected' | ''
  /** Technician user ids. */
  decidedBy: string[]
  from: string
  to: string
  sort: SortOrder
}

/** Contract 3.6: every decision technicians made, filtered, 50 at a time. */
export function useDecisionList(buId: string, filters: DecisionFilters) {
  return usePagedList(['technician-decisions', buId, 'list', filters], async (cursor) =>
    unwrap(
      await api.GET('/business-units/{buId}/technician-decisions', {
        params: {
          path: { buId },
          query: {
            decision: filters.decision || undefined,
            decided_by: filters.decidedBy.length ? filters.decidedBy : undefined,
            from: filters.from || undefined,
            to: filters.to || undefined,
            sort: filters.sort,
            cursor,
            limit: 50,
          },
        },
      }),
    ),
  )
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
    enabled: scanIds.length > 0, // the API wants 1–50 scans
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

/** Contract 3.10: the unit's delegated batches (BU Home reads them all for what needs attention). */
export function useBatches(buId: string) {
  return useQuery({
    queryKey: ['review-batches', buId],
    queryFn: async () =>
      unwrap(await api.GET('/business-units/{buId}/review-batches', { params: { path: { buId } } }))
        .items,
  })
}

/** The batch list's header filters. Status is read from each batch, see batchState. */
export interface BatchFilters {
  /** Technician user ids. */
  assignedTo: string[]
  from: string
  to: string
  sort: SortOrder
}

/** Contract 3.10: the unit's batches with the filters of the list's column headers. */
export function useBatchList(buId: string, filters: BatchFilters) {
  return usePagedList(['review-batches', buId, 'list', filters], async (cursor) =>
    unwrap(
      await api.GET('/business-units/{buId}/review-batches', {
        params: {
          path: { buId },
          query: {
            assigned_to: filters.assignedTo.length ? filters.assignedTo : undefined,
            from: filters.from || undefined,
            to: filters.to || undefined,
            sort: filters.sort,
            cursor,
            limit: 100,
          },
        },
      }),
    ),
  )
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
