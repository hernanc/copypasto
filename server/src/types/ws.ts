import { z } from "zod";

export const clipboardPushSchema = z.object({
  type: z.literal("clipboard:push"),
  id: z.string().min(1),
  payload: z.object({
    ciphertext: z.string().min(1),
    iv: z.string().min(1),
    contentLength: z.number().int().min(0).max(1_048_576),
  }),
});

export const pingSchema = z.object({
  type: z.literal("ping"),
});

export const clientMessageSchema = z.discriminatedUnion("type", [
  clipboardPushSchema,
  pingSchema,
]);

export type ClientMessage = z.infer<typeof clientMessageSchema>;

export interface ClipboardNewMessage {
  type: "clipboard:new";
  id: string;
  payload: {
    ciphertext: string;
    iv: string;
    contentLength: number;
  };
  createdAt: string;
}

export interface PushAckMessage {
  type: "clipboard:push:ack";
  id: string;
}

export interface PushErrorMessage {
  type: "clipboard:push:error";
  id: string;
  error: string;
}

export interface PongMessage {
  type: "pong";
}

export interface ErrorMessage {
  type: "error";
  code: string;
  message: string;
}

export type ServerMessage =
  | ClipboardNewMessage
  | PushAckMessage
  | PushErrorMessage
  | PongMessage
  | ErrorMessage;
