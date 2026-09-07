const USERS_ENDPOINT = "/api/users";

async function request(endpoint = USERS_ENDPOINT, options) {
  const response = await fetch(endpoint, options);

  if (!response.ok) {
    throw new Error(`HTTP error: ${response.status}`);
  }

  return response.status === 204 ? null : response.json();
}

export function listUsers() {
  return request();
}

export function createUser(user) {
  return request(USERS_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(user),
  });
}

export function updateUser(id, user) {
  return request(`${USERS_ENDPOINT}/${id}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(user),
  });
}

export function deleteUser(id) {
  return request(`${USERS_ENDPOINT}/${id}`, { method: "DELETE" });
}
