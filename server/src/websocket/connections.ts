import type { WebSocket } from "ws";
import type { ServerMessage } from "../types/ws.js";

const connections = new Map<string, Set<WebSocket>>();

export function addConnection(userId: string, ws: WebSocket): void {
  let userConnections = connections.get(userId);
  if (!userConnections) {
    userConnections = new Set();
    connections.set(userId, userConnections);
  }
  userConnections.add(ws);
}

export function removeConnection(userId: string, ws: WebSocket): void {
  const userConnections = connections.get(userId);
  if (!userConnections) return;

  userConnections.delete(ws);
  if (userConnections.size === 0) {
    connections.delete(userId);
  }
}

export function broadcastToUser(userId: string, message: ServerMessage, excludeWs?: WebSocket): void {
  const userConnections = connections.get(userId);
  if (!userConnections) return;

  const data = JSON.stringify(message);
  for (const ws of userConnections) {
    if (ws !== excludeWs && ws.readyState === ws.OPEN) {
      ws.send(data);
    }
  }
}

export function sendToSocket(ws: WebSocket, message: ServerMessage): void {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(message));
  }
}
