import type { FastifyInstance } from "fastify";

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  app.get("/health", { logLevel: "silent" }, async () => {
    return { status: "ok", timestamp: new Date().toISOString() };
  });
}
