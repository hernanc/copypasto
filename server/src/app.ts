import Fastify from "fastify";
import cors from "@fastify/cors";
import rateLimit from "@fastify/rate-limit";
import websocket from "@fastify/websocket";
import { healthRoutes } from "./routes/health.js";
import { authRoutes } from "./routes/auth.js";
import { clipboardRoutes } from "./routes/clipboard.js";
import { waitlistRoutes } from "./routes/waitlist.js";
import { websocketHandler } from "./websocket/handler.js";

export async function buildApp() {
  const app = Fastify({
    logger: true,
    trustProxy: true,
    bodyLimit: 2 * 1024 * 1024, // 2MB for base64-encoded clipboard content
  });

  app.addHook("onRequest", async (_request, reply) => {
    reply.header("X-Content-Type-Options", "nosniff");
    reply.header("X-Frame-Options", "DENY");
    reply.header("X-XSS-Protection", "0");
    reply.header("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
    reply.header("Referrer-Policy", "no-referrer");
    reply.header("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
    reply.header("Content-Security-Policy", "default-src 'none'");
    reply.header("Cache-Control", "no-store");
  });

  await app.register(cors, { origin: true });

  await app.register(rateLimit, {
    global: false,
  });

  await app.register(websocket, {
    options: {
      maxPayload: 2 * 1024 * 1024, // 2MB
    },
  });

  // REST routes under /api prefix
  await app.register(
    async (api) => {
      await api.register(healthRoutes);

      await api.register(authRoutes, {
        config: {
          rateLimit: {
            max: 5,
            timeWindow: "1 minute",
          },
        },
      });

      await api.register(clipboardRoutes, {
        config: {
          rateLimit: {
            max: 30,
            timeWindow: "1 minute",
          },
        },
      });

      await api.register(waitlistRoutes, {
        config: {
          rateLimit: {
            max: 3,
            timeWindow: "1 minute",
          },
        },
      });
    },
    { prefix: "/api" }
  );

  // WebSocket endpoint (no prefix — /ws is at the root)
  await app.register(websocketHandler);

  return app;
}
