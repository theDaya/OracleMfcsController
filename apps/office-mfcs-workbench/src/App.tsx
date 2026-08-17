import { Box, ClipboardCheck, DatabaseSearch, FilePlus2, ListChecks, UserRound } from 'lucide-react'
import { NavLink, Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './auth/AuthProvider'
import { RequestListPage } from './pages/RequestListPage'
import { CreateRequestPage } from './pages/CreateRequestPage'
import { RequestDetailPage } from './pages/RequestDetailPage'
import { ApprovalQueuePage } from './pages/ApprovalQueuePage'
import { ApprovalReviewPage } from './pages/ApprovalReviewPage'
import { MfcsStateViewerPage } from './pages/MfcsStateViewerPage'

export function App() {
  const { currentUser, users, selectUser } = useAuth()
  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="brand"><span className="brand-mark"><Box size={22} /></span><div><strong>Office MFCS</strong><span>Merchandising workbench</span></div></div>
        <div className="header-controls">
          <label className="user-switcher"><UserRound size={17} /><span className="sr-only">Current user</span><select value={currentUser.id} onChange={(event) => selectUser(event.target.value)}>{users.map((user) => <option key={user.id} value={user.id}>{user.name} — {user.role === 'BUYER' ? 'Buyer' : 'Manager'}</option>)}</select></label>
        </div>
      </header>
      <aside className="app-sidebar">
        <nav aria-label="Primary navigation">
          <NavLink to="/requests"><ListChecks size={18} /> My requests</NavLink>
          <NavLink to="/mfcs-state"><DatabaseSearch size={18} /> MFCS state</NavLink>
          {currentUser.role === 'BUYER' && <NavLink to="/requests/new"><FilePlus2 size={18} /> New request</NavLink>}
          {currentUser.role === 'MANAGER' && <NavLink to="/approvals"><ClipboardCheck size={18} /> Approval queue</NavLink>}
        </nav>
        <div className="environment-note"><span className="live-dot" /> Oracle workflow database</div>
      </aside>
      <main className="app-main">
        <Routes>
          <Route path="/" element={<Navigate to="/requests" replace />} />
          <Route path="/requests" element={<RequestListPage />} />
          <Route path="/requests/new" element={<CreateRequestPage />} />
          <Route path="/requests/:id" element={<RequestDetailPage />} />
          <Route path="/requests/:id/edit" element={<CreateRequestPage />} />
          <Route path="/mfcs-state" element={<MfcsStateViewerPage />} />
          <Route path="/approvals" element={<ApprovalQueuePage />} />
          <Route path="/approvals/:id" element={<ApprovalReviewPage />} />
          <Route path="*" element={<Navigate to="/requests" replace />} />
        </Routes>
      </main>
    </div>
  )
}
