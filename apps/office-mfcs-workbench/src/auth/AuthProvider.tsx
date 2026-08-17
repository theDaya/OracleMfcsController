import { createContext, useContext, useMemo, useState, type ReactNode } from 'react'
import type { UserReference } from '../models/officeRequest'

const users: UserReference[] = [
  { id: 'jane.buyer@office.example', name: 'Jane Buyer', role: 'BUYER' },
  { id: 'michael.manager@office.example', name: 'Michael Manager', role: 'MANAGER' },
]

interface AuthContextValue {
  currentUser: UserReference
  users: UserReference[]
  selectUser: (userId: string) => void
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [currentUserId, setCurrentUserId] = useState(users[0].id)
  const value = useMemo<AuthContextValue>(() => ({
    currentUser: users.find((user) => user.id === currentUserId) ?? users[0],
    users,
    selectUser: setCurrentUserId,
  }), [currentUserId])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used inside AuthProvider')
  return context
}
