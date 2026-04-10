import type { FastifyInstance } from "fastify";
import { authMiddleware } from "../middleware/auth.js";
import { getEntries } from "../services/clipboard.service.js";

export async function clipboardRoutes(app: FastifyInstance): Promise<void> {
  app.get("/clipboard", { preHandler: authMiddleware }, async (request) => {
    const items = await getEntries(request.userId);
    return { items };
  });
}
