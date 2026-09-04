const express = require("express");
const cors = require("cors");
const mysql = require("mysql2/promise");
require("dotenv").config();

const app = express();
const port = process.env.PORT || 3001;

app.use(cors());
app.use(express.json());

const pool = mysql.createPool({
  host: process.env.DB_HOST || "mysql",
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
});

app.get("/health", async (req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({
      status: "ok",
      database: "connected",
    });
  } catch (error) {
    res.status(500).json({
      status: "error",
      database: "disconnected",
      message: error.message,
    });
  }
});

app.post("/users", async (req, res) => {
  const { name, email } = req.body;

  if (!name || !email) {
    return res.status(400).json({
      error: "name and email are required",
    });
  }

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
    console.error("POST /users failed:", error.message);

    res.status(500).json({
      error: "Unable to create user",
    });
  }
});

app.put("/users/:id", async (req, res) => {
  const { id } = req.params;
  const { name, email } = req.body;

  if (!name || !email) {
    return res.status(400).json({
      error: "name and email are required",
    });
  }

  try {
    const [result] = await pool.query(
      "UPDATE users SET name = ?, email = ? WHERE id = ?",
      [name, email, id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({
        error: "User not found",
      });
    }

    const [rows] = await pool.query(
      "SELECT id, name, email FROM users WHERE id = ?",
      [id]
    );

    res.json(rows[0]);
  } catch (error) {
    console.error("PUT /users/:id failed:", error.message);

    res.status(500).json({
      error: "Unable to update user",
    });
  }
});

app.delete("/users/:id", async (req, res) => {
  const { id } = req.params;

  try {
    const [result] = await pool.query(
      "DELETE FROM users WHERE id = ?",
      [id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({
        error: "User not found",
      });
    }

    res.json({
      message: "User deleted",
      id: Number(id),
    });
  } catch (error) {
    console.error("DELETE /users/:id failed:", error.message);

    res.status(500).json({
      error: "Unable to delete user",
    });
  }
});

app.get("/users", async (req, res) => {
  try {
    const [users] = await pool.query(
      "SELECT id, name, email FROM users ORDER BY id"
    );

    res.json(users);
  } catch (error) {
    console.error("GET /users failed:", error.message);

    res.status(500).json({
      error: "Unable to load users",
    });
  }
});

app.listen(port, "0.0.0.0", () => {
  console.log(`API listening on port ${port}`);
});
