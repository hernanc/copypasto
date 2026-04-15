import { config } from "./config.js";
import { buildApp } from "./app.js";

async function main() {
  const app = await buildApp();

  const shutdown = async (signal: string) => {
    app.log.info({ signal }, "Shutting down gracefully");
    await app.close();
    process.exit(0);
  };

  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));

  try {
    await app.listen({ port: config.PORT, host: "0.0.0.0" });
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

main();
