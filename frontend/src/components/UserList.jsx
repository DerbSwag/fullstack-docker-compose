function UserList({ users, editingId, editName, editEmail, onStartEdit, onNameChange, onEmailChange, onUpdate, onDelete }) {
  return users.map((user) => (
    <div key={user.id}>
      {editingId === user.id ? (
        <>
          <input
            type="text"
            value={editName}
            onChange={(event) => onNameChange(event.target.value)}
          />
          <input
            type="email"
            value={editEmail}
            onChange={(event) => onEmailChange(event.target.value)}
          />
          <button type="button" onClick={() => onUpdate(user.id)}>
            Save
          </button>
        </>
      ) : (
        <>
          <h2>{user.name}</h2>
          <p>{user.email}</p>
          <button type="button" onClick={() => onStartEdit(user)}>
            Edit
          </button>
          <button type="button" onClick={() => onDelete(user.id)}>
            Delete
          </button>
        </>
      )}
    </div>
  ));
}

export default UserList;
