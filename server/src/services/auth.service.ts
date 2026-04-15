import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import { createHash } from "node:crypto";
import { z } from "zod";
import { config } from "../config.js";

const BCRYPT_ROUNDS = 12;
const ACCESS_TOKEN_EXPIRY = "15m";
const REFRESH_TOKEN_EXPIRY = "30d";
const JWT_ALGORITHM: jwt.Algorithm = "HS256";

const tokenPayloadSchema = z.object({
  userId: z.string().uuid(),
});

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, BCRYPT_ROUNDS);
}

export async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash);
}

export interface TokenPayload {
  userId: string;
}

export function generateAccessToken(userId: string): string {
  return jwt.sign({ userId } satisfies TokenPayload, config.JWT_SECRET, {
    algorithm: JWT_ALGORITHM,
    expiresIn: ACCESS_TOKEN_EXPIRY,
  });
}

export function generateRefreshToken(userId: string): string {
  return jwt.sign({ userId } satisfies TokenPayload, config.JWT_REFRESH_SECRET, {
    algorithm: JWT_ALGORITHM,
    expiresIn: REFRESH_TOKEN_EXPIRY,
  });
}

export function verifyAccessToken(token: string): TokenPayload {
  const decoded = jwt.verify(token, config.JWT_SECRET, { algorithms: [JWT_ALGORITHM] });
  const parsed = tokenPayloadSchema.safeParse(decoded);
  if (!parsed.success) throw new jwt.JsonWebTokenError("Invalid token payload");
  return parsed.data;
}

export function verifyRefreshToken(token: string): TokenPayload {
  const decoded = jwt.verify(token, config.JWT_REFRESH_SECRET, { algorithms: [JWT_ALGORITHM] });
  const parsed = tokenPayloadSchema.safeParse(decoded);
  if (!parsed.success) throw new jwt.JsonWebTokenError("Invalid token payload");
  return parsed.data;
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}
