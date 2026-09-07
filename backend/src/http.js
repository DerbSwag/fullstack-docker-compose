function validateUserInput(body) {
  const { name, email } = body || {};

  if (!name || !email) {
    return "name and email are required";
  }

  return null;
}

function sendInternalError(res, message, error) {
  console.error(`${message}:`, error.message);
  return res.status(500).json({ error: "Unable to process request" });
}

module.exports = { validateUserInput, sendInternalError };
