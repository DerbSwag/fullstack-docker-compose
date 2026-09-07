import { useEffect, useState } from "react";
import { createUser, deleteUser, listUsers, updateUser } from "./api/users";
import UserForm from "./components/UserForm";
import UserList from "./components/UserList";
import "./App.css";

function App() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [editName, setEditName] = useState("");
  const [editEmail, setEditEmail] = useState("");

  useEffect(() => {
    listUsers()
      .then(setUsers)
      .catch((requestError) => setError(requestError.message))
      .finally(() => setLoading(false));
  }, []);

  const handleSubmit = async (event) => {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      const newUser = await createUser({ name, email });
      setUsers((currentUsers) => [...currentUsers, newUser]);
      setName("");
      setEmail("");
    } catch (requestError) {
      setError(requestError.message);
    } finally {
      setSubmitting(false);
    }
  };

  const startEdit = (user) => {
    setEditingId(user.id);
    setEditName(user.name);
    setEditEmail(user.email);
  };

  const handleUpdate = async (id) => {
    setError(null);

    try {
      const updatedUser = await updateUser(id, {
        name: editName,
        email: editEmail,
      });

      setUsers((currentUsers) =>
        currentUsers.map((user) => (user.id === id ? updatedUser : user))
      );
      setEditingId(null);
      setEditName("");
      setEditEmail("");
    } catch (requestError) {
      setError(requestError.message);
    }
  };

  const handleDelete = async (id) => {
    setError(null);

    try {
      await deleteUser(id);
      setUsers((currentUsers) =>
        currentUsers.filter((user) => user.id !== id)
      );
    } catch (requestError) {
      setError(requestError.message);
    }
  };

  if (loading) {
    return <h1>Loading users...</h1>;
  }

  if (error) {
    return <h1>Error: {error}</h1>;
  }

  return (
    <main>
      <h1>Users</h1>
      <UserForm
        name={name}
        email={email}
        submitting={submitting}
        onNameChange={setName}
        onEmailChange={setEmail}
        onSubmit={handleSubmit}
      />
      <UserList
        users={users}
        editingId={editingId}
        editName={editName}
        editEmail={editEmail}
        onStartEdit={startEdit}
        onNameChange={setEditName}
        onEmailChange={setEditEmail}
        onUpdate={handleUpdate}
        onDelete={handleDelete}
      />
    </main>
  );
}

export default App;
