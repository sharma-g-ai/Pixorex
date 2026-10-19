import createClient from 'openapi-fetch'
import { getAccessToken, handleAccountRemoved, handleUnauthorized } from '../auth/session'
import { getDeviceId } from '../lib/deviceId'
import type { components as CommonComponents } from './generated/common'
import type { paths as S2Paths } from './generated/s2'
import type { paths as S3Paths } from './generated/s3'
import type { paths as S4Paths } from './generated/s4'
import type { paths as S5Paths } from './generated/s5'

/** Every endpoint in the contracts, typed from contracts/*.yaml. */
export type ApiPaths = S2Paths & S3Paths & S4Paths & S5Paths

/** RFC 9457 error body returned by every endpoint (contracts/common.yaml). */
export type Problem = CommonComponents['schemas']['Problem']

export const API_BASE_URL = '/api/v1'

/**
 * The one API client for the web app. Every call carries X-Device-Id and, once signed in,
 * the Keycloak access token (D-11). In mock mode the dev proxy adds a placeholder token.
 */
export const api = createClient<ApiPaths>({ baseUrl: API_BASE_URL })

api.use({
  async onRequest({ request }) {
    request.headers.set('X-Device-Id', getDeviceId())
    const token = await getAccessToken()
    if (token) request.headers.set('Authorization', `Bearer ${token}`)
    return request
  },
  async onResponse({ response }) {
    // Expired or revoked session: sign in again and come back here (loop-guarded).
    if (response.status === 401) {
      await handleUnauthorized(`${window.location.pathname}${window.location.search}`)
      return response
    }
    // Removed from every unit: end IdP session; do not try to sign in again.
    if (response.status === 403) {
      try {
        const problem = (await response.clone().json()) as Pick<Problem, 'type'>
        if (problemCode(problem) === 'account-removed') await handleAccountRemoved()
      } catch {
        // Non-problem body: leave the 403 for the caller.
      }
    }
    return response
  },
})

/** Stable error code of a problem, e.g. "locked-after-publish" from "/problems/locked-after-publish". */
export function problemCode(problem: Pick<Problem, 'type'>): string {
  return problem.type.split('/').pop() ?? problem.type
}

/** A message for the user from any error a call can throw. */
export function errorMessage(err: unknown): string {
  if (err instanceof ApiError) return err.problem.detail ?? err.problem.title
  return 'Something went wrong. Please try again.'
}

/** The response body of a call, or throws ApiError with the problem body. Use in every hook. */
export function unwrap<T>(result: { data?: T; error?: unknown }): T {
  if (result.error !== undefined) throw new ApiError(result.error as Problem)
  return result.data as T
}

/** Thrown by the API hooks so screens get the problem body, not a bare status. */
export class ApiError extends Error {
  readonly problem: Problem

  constructor(problem: Problem) {
    super(problem.title)
    this.name = 'ApiError'
    this.problem = problem
  }
}
