import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useState } from 'react'
import { BrowserRouter, Route, Routes } from 'react-router'
import { AuthGate } from '../auth/AuthGate'
import { AuthCallbackPage, SignedOutPage } from '../auth/AuthPages'
import { ActivatePage } from '../features/activation/ActivatePage'
import { AppRoutes } from './AppRoutes'

export function App() {
  const [queryClient] = useState(
    () =>
      new QueryClient({ defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: false } } }),
  )
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Routes>
          {/* Public: Keycloak returns here, sign-out lands here, invite links open here. */}
          <Route path="/auth/callback" element={<AuthCallbackPage />} />
          <Route path="/signed-out" element={<SignedOutPage />} />
          <Route path="/activate" element={<ActivatePage />} />
          <Route
            path="*"
            element={
              <AuthGate>
                <AppRoutes />
              </AuthGate>
            }
          />
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  )
}
