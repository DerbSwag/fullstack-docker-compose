const { createApp } = require("./src/app");
const { createPool } = require("./src/db");

const port = Number(process.env.PORT || 3001);
const pool = createPool();
const app = createApp({ pool });
const server = app.listen(port, "0.0.0.0", () => {
  console.log(`API listening on port ${port}`);
});

const shutdown = async (signal) => {
  console.log(`${signal} received; shutting down`);

  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
};

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
