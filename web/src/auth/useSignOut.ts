import { useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { api } from '../api/client'
import { getDeviceId } from '../lib/deviceId'
import { authConfig } from './authConfig'
import { endKeycloakSession } from './session'

/**
 * Sign out (D-11): end this device's API session (contract 1.3), forget all cached data,
 * then end the Keycloak session. A failed 1.3 call still signs out locally.
 */
export function useSignOut() {
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  return async () => {
    try {
      await api.POST('/me/sign-out', { params: { header: { 'X-Device-Id': getDeviceId() } } })
    } catch {
      // Offline or already revoked: carry on, the Keycloak session still ends below.
    }
    queryClient.clear()
    if (authConfig.mode === 'oidc') await endKeycloakSession()
    else await navigate('/signed-out', { replace: true })
  }
}
