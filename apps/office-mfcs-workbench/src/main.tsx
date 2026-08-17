import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { App } from './App'
import { AuthProvider } from './auth/AuthProvider'
import { WorkflowProvider } from './workflow/WorkflowProvider'
import './styles.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <WorkflowProvider>
          <App />
        </WorkflowProvider>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>,
)
