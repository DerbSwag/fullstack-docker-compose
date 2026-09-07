const express = require("express");
const cors = require("cors");
const { createUserRouter } = require("./routes/users");

function createApp({ pool }) {
  const app = express();

  app.use(cors());
  app.use(express.json());

  app.get("/health", async (req, res) => {
    try {
      await pool.query("SELECT 1");
      res.json({ status: "ok", database: "connected" });
    } catch (error) {
      res.status(500).json({
        status: "error",
        database: "disconnected",
        message: error.message,
      });
    }
  });

  app.use("/users", createUserRouter({ pool }));

  return app;
}

module.exports = { createApp };
