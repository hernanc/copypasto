import { clientMessageSchema, type ClientMessage } from "../types/ws.js";

// Max base64-decoded ciphertext size: 1MB plaintext + 16 bytes AES-GCM tag
const MAX_CIPHERTEXT_BASE64_LENGTH = Math.ceil((1_048_576 + 16) * 4 / 3);

export function parseClientMessage(data: string): ClientMessage | null {
  try {
    const json = JSON.parse(data);
    const result = clientMessageSchema.safeParse(json);
    if (!result.success) return null;
    return result.data;
  } catch {
    return null;
  }
}

export function validatePayloadSize(ciphertext: string): boolean {
  return ciphertext.length <= MAX_CIPHERTEXT_BASE64_LENGTH;
}
