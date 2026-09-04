import { useEffect, useState } from 'react'
import './App.css'

function App() {
  const [users, setUsers] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [submitting, setSubmitting] = useState(false)

  const [editingId, setEditingId] = useState(null)
  const [editName, setEditName] = useState('')
  const [editEmail, setEditEmail] = useState('')

  useEffect(() => {
    fetch('/api/users')
      .then((response) => {
        if (!response.ok) {
          throw new Error(`HTTP error: ${response.status}`)
        }

        return response.json()
      })
      .then((data) => {
        setUsers(data)
      })
      .catch((err) => {
        setError(err.message)
      })
      .finally(() => {
        setLoading(false)
      })
  }, [])

  const handleSubmit = async (event) => {
    event.preventDefault()

    setSubmitting(true)
    setError(null)

    try {
      const response = await fetch('/api/users', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name,
          email,
        }),
      })

      if (!response.ok) {
        throw new Error(`HTTP error: ${response.status}`)
      }

      const newUser = await response.json()

      setUsers((currentUsers) => [...currentUsers, newUser])
      setName('')
      setEmail('')
    } catch (err) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  const startEdit = (user) => {
    setEditingId(user.id)
    setEditName(user.name)
    setEditEmail(user.email)
  }

  const handleUpdate = async (id) => {
    setError(null)

    try {
      const response = await fetch(`/api/users/${id}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: editName,
          email: editEmail,
        }),
      })

      if (!response.ok) {
        throw new Error(`HTTP error: ${response.status}`)
      }

      const updatedUser = await response.json()

      setUsers((currentUsers) =>
        currentUsers.map((user) =>
          user.id === id ? updatedUser : user
        )
      )

      setEditingId(null)
      setEditName('')
      setEditEmail('')
    } catch (err) {
      setError(err.message)
    }
  }

  const handleDelete = async (id) => {
    setError(null)

    try {
      const response = await fetch(`/api/users/${id}`, {
        method: 'DELETE',
      })

      if (!response.ok) {
        throw new Error(`HTTP error: ${response.status}`)
      }

      setUsers((currentUsers) =>
        currentUsers.filter((user) => user.id !== id)
      )
    } catch (err) {
      setError(err.message)
    }
  }

  if (loading) {
    return <h1>Loading users...</h1>
  }

  if (error) {
    return <h1>Error: {error}</h1>
  }

  return (
    <main>
      <h1>Users</h1>

      <form onSubmit={handleSubmit}>
        <div>
          <label>
            Name:
            <input
              type="text"
              value={name}
              onChange={(event) => setName(event.target.value)}
              required
            />
          </label>
        </div>

        <div>
          <label>
            Email:
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
            />
          </label>
        </div>

        <button type="submit" disabled={submitting}>
          {submitting ? 'Adding...' : 'Add User'}
        </button>
      </form>

      {users.map((user) => (
        <div key={user.id}>
          {editingId === user.id ? (
            <>
              <input
                type="text"
                value={editName}
                onChange={(event) => setEditName(event.target.value)}
              />

              <input
                type="email"
                value={editEmail}
                onChange={(event) => setEditEmail(event.target.value)}
              />

              <button
                type="button"
                onClick={() => handleUpdate(user.id)}
              >
                Save
              </button>
            </>
          ) : (
            <>
              <h2>{user.name}</h2>
              <p>{user.email}</p>

              <button
                type="button"
                onClick={() => startEdit(user)}
              >
                Edit
              </button>

              <button
                type="button"
                onClick={() => handleDelete(user.id)}
              >
                Delete
              </button>
            </>
          )}
        </div>
      ))}
    </main>
  )
}

export default App
