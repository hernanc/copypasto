import type { FastifyInstance } from "fastify";
import type { WebSocket } from "ws";
import { verifyAccessToken } from "../services/auth.service.js";
import { addEntry } from "../services/clipboard.service.js";
import { addConnection, removeConnection, broadcastToUser, sendToSocket } from "./connections.js";
import { parseClientMessage, validatePayloadSize } from "./messages.js";

const WS_RATE_LIMIT_WINDOW_MS = 60_000;
const WS_RATE_LIMIT_MAX = 60;

interface RateState {
  count: number;
  resetAt: number;
}

export async function websocketHandler(app: FastifyInstance): Promise<void> {
  app.get("/ws", { websocket: true, logLevel: "silent" }, (socket, request) => {
    const token = (request.query as Record<string, string>).token;
    if (!token) {
      sendToSocket(socket, { type: "error", code: "AUTH_MISSING", message: "Token required" });
      socket.close(4001, "Token required");
      return;
    }

    let userId: string;
    try {
      const payload = verifyAccessToken(token);
      userId = payload.userId;
    } catch {
      sendToSocket(socket, { type: "error", code: "AUTH_INVALID", message: "Invalid token" });
      socket.close(4001, "Invalid token");
      return;
    }

    addConnection(userId, socket);

    const rateState: RateState = { count: 0, resetAt: Date.now() + WS_RATE_LIMIT_WINDOW_MS };

    socket.on("message", async (rawData: Buffer | ArrayBuffer | Buffer[]) => {
      // Rate limiting
      const now = Date.now();
      if (now > rateState.resetAt) {
        rateState.count = 0;
        rateState.resetAt = now + WS_RATE_LIMIT_WINDOW_MS;
      }
      rateState.count++;
      if (rateState.count > WS_RATE_LIMIT_MAX) {
        sendToSocket(socket, { type: "error", code: "RATE_LIMIT", message: "Too many messages" });
        return;
      }

      const data = rawData.toString();
      const message = parseClientMessage(data);

      if (!message) {
        sendToSocket(socket, { type: "error", code: "INVALID_MESSAGE", message: "Invalid message format" });
        return;
      }

      if (message.type === "ping") {
        sendToSocket(socket, { type: "pong" });
        return;
      }

      if (message.type === "clipboard:push") {
        if (!validatePayloadSize(message.payload.ciphertext)) {
          sendToSocket(socket, {
            type: "clipboard:push:error",
            id: message.id,
            error: "Payload too large",
          });
          return;
        }

        try {
          const entry = await addEntry(
            userId,
            message.payload.ciphertext,
            message.payload.iv,
            message.payload.contentLength
          );

          app.log.info({ userId, entryId: entry.id, contentLength: entry.contentLength }, "Clipboard entry stored");

          // Ack the sender
          sendToSocket(socket, { type: "clipboard:push:ack", id: message.id });

          // Broadcast to other connections of the same user
          broadcastToUser(
            userId,
            {
              type: "clipboard:new",
              id: entry.id,
              payload: {
                ciphertext: entry.ciphertext,
                iv: entry.iv,
                contentLength: entry.contentLength,
              },
              createdAt: entry.createdAt,
            },
            socket // exclude sender
          );
        } catch (err) {
          app.log.error(err, "Failed to store clipboard entry");
          sendToSocket(socket, {
            type: "clipboard:push:error",
            id: message.id,
            error: "Internal error",
          });
        }
      }
    });

    socket.on("close", () => {
      removeConnection(userId, socket);
    });

    socket.on("error", (err: Error) => {
      app.log.error(err, "WebSocket error");
      removeConnection(userId, socket);
    });
  });
}
