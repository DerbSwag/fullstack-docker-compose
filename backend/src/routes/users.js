const express = require("express");
const { validateUserInput, sendInternalError } = require("../http");

function createUserRouter({ pool }) {
  const router = express.Router();

  router.get("/", async (req, res) => {
    try {
      const [users] = await pool.query(
        "SELECT id, name, email FROM users ORDER BY id"
      );

      res.json(users);
    } catch (error) {
      sendInternalError(res, "GET /users failed", error);
    }
  });

  router.post("/", async (req, res) => {
    const validationError = validateUserInput(req.body);

    if (validationError) {
      return res.status(400).json({ error: validationError });
    }

    const { name, email } = req.body;

    try {
      const [result] = await pool.query(
        "INSERT INTO users (name, email) VALUES (?, ?)",
        [name, email]
      );
      const [rows] = await pool.query(
        "SELECT id, name, email FROM users WHERE id = ?",
        [result.insertId]
      );

      res.status(201).json(rows[0]);
    } catch (error) {
      sendInternalError(res, "POST /users failed", error);
    }
  });

  router.put("/:id", async (req, res) => {
    const validationError = validateUserInput(req.body);

    if (validationError) {
      return res.status(400).json({ error: validationError });
    }

    const { id } = req.params;
    const { name, email } = req.body;

    try {
      const [result] = await pool.query(
        "UPDATE users SET name = ?, email = ? WHERE id = ?",
        [name, email, id]
      );

      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "User not found" });
      }

      const [rows] = await pool.query(
        "SELECT id, name, email FROM users WHERE id = ?",
        [id]
      );

      res.json(rows[0]);
    } catch (error) {
      sendInternalError(res, "PUT /users/:id failed", error);
    }
  });

  router.delete("/:id", async (req, res) => {
    const { id } = req.params;

    try {
      const [result] = await pool.query("DELETE FROM users WHERE id = ?", [id]);

      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "User not found" });
      }

      res.json({ message: "User deleted", id: Number(id) });
    } catch (error) {
      sendInternalError(res, "DELETE /users/:id failed", error);
    }
  });

  return router;
}

module.exports = { createUserRouter };
