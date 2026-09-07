function UserForm({ name, email, submitting, onNameChange, onEmailChange, onSubmit }) {
  return (
    <form onSubmit={onSubmit}>
      <div>
        <label>
          Name:
          <input
            type="text"
            value={name}
            onChange={(event) => onNameChange(event.target.value)}
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
            onChange={(event) => onEmailChange(event.target.value)}
            required
          />
        </label>
      </div>

      <button type="submit" disabled={submitting}>
        {submitting ? "Adding..." : "Add User"}
      </button>
    </form>
  );
}

export default UserForm;
