import { useMutation, useQuery } from '@tanstack/react-query'
import { api, ApiError, type Problem } from './client'
import type { components } from './generated/s5'

export type ExportInput = components['schemas']['ExportInput']
export type ExportJob = components['schemas']['ExportJob']
/** Optional column groups of a scans export (contract 4.1 options.columns). */
export type ExportColumn = NonNullable<components['schemas']['ExportOptions']['columns']>[number]

/** Small exports come back as the CSV itself; large ones as a background job. */
export type ExportResult = { kind: 'file'; csv: string } | { kind: 'job'; job: ExportJob }

/**
 * Contract 4.1 POST /exports. Up to 1,000 rows: 200 text/csv. More: 202 with a job that
 * becomes ready in the background (export_ready notice, link valid 1 hour).
 */
export function useCreateExport() {
  return useMutation({
    mutationFn: async ({
      body,
      idempotencyKey,
    }: {
      body: ExportInput
      idempotencyKey: string
    }): Promise<ExportResult> => {
      const { data, error, response } = await api.POST('/exports', {
        body,
        params: { header: { 'Idempotency-Key': idempotencyKey } },
        parseAs: 'text',
      })
      if (error !== undefined) throw new ApiError(parseProblem(error))
      const text = typeof data === 'string' ? data : ''
      return response.status === 202
        ? { kind: 'job', job: JSON.parse(text) as ExportJob }
        : { kind: 'file', csv: text }
    },
  })
}

/** Contract 4.2: the background export, re-checked every few seconds until it is ready or failed. */
export function useExportJob(exportId: string) {
  return useQuery({
    queryKey: ['exports', exportId],
    queryFn: async () => {
      const { data, error } = await api.GET('/exports/{exportId}', {
        params: { path: { exportId } },
      })
      if (error !== undefined) throw new ApiError(error as Problem)
      return data
    },
    refetchInterval: (query) => (query.state.data?.status === 'queued' ? 4000 : false),
  })
}

/** With parseAs 'text' the error body arrives as text too. */
function parseProblem(error: unknown): Problem {
  if (typeof error !== 'string') return error as Problem
  try {
    return JSON.parse(error) as Problem
  } catch {
    return { type: 'about:blank', title: error || 'Export failed', status: 500 }
  }
}
