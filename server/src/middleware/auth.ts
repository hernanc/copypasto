import type { FastifyRequest, FastifyReply } from "fastify";
import { verifyAccessToken } from "../services/auth.service.js";

declare module "fastify" {
  interface FastifyRequest {
    userId: string;
  }
}

export async function authMiddleware(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  const header = request.headers.authorization;
  if (!header?.startsWith("Bearer ")) {
    reply.code(401).send({ error: "Missing or invalid authorization header" });
    return;
  }

  const token = header.slice(7);
  try {
    const payload = verifyAccessToken(token);
    request.userId = payload.userId;
  } catch {
    reply.code(401).send({ error: "Invalid or expired token" });
  }
}
