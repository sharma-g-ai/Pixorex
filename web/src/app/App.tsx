import { BrowserRouter, MemoryRouter, Navigate, Route, Routes } from 'react-router'
import { ActivityPage } from '../features/activity/ActivityPage'
import { CustomersVesselsPage } from '../features/admin/CustomersVesselsPage'
import { ProductsPage } from '../features/admin/ProductsPage'
import { UsersRolesPage } from '../features/admin/UsersRolesPage'
import { ConsumptionPage } from '../features/consumption/ConsumptionPage'
import { OverviewPage } from '../features/overview/OverviewPage'
import { SeaStockPage } from '../features/seaStock/SeaStockPage'
import { SignInPage } from '../features/signIn/SignInPage'
import { Layout } from './Layout'
import { homePath } from './navigation'
import { DEMO_USER, useViewer, SessionProvider } from './viewer'

// A role demo runs inside a page whose address cannot change, so it keeps its routes in memory.
const Router = DEMO_USER ? MemoryRouter : BrowserRouter

function Home() {
  const { user } = useViewer()
  return <Navigate to={homePath(user)} replace />
}

export function App() {
  return (
    <SessionProvider>
      <Router>
        <Routes>
          <Route path="/sign-in" element={<SignInPage />} />
          <Route element={<Layout />}>
            <Route index element={<Home />} />
            <Route path="/overview" element={<OverviewPage />} />
            <Route path="/sea-stock" element={<SeaStockPage />} />
            <Route path="/consumption" element={<ConsumptionPage />} />
            <Route path="/activity" element={<ActivityPage />} />
            <Route path="/admin/customers" element={<CustomersVesselsPage />} />
            <Route path="/admin/users" element={<UsersRolesPage />} />
            <Route path="/admin/products" element={<ProductsPage />} />
            <Route path="*" element={<Home />} />
          </Route>
        </Routes>
      </Router>
    </SessionProvider>
  )
}
