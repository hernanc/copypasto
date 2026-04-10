import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { randomBytes } from "node:crypto";
import {
  hashPassword,
  verifyPassword,
  generateAccessToken,
  generateRefreshToken,
  verifyRefreshToken,
  hashToken,
} from "../services/auth.service.js";
import {
  createUser,
  getUserByEmail,
  getUserById,
  updateRefreshTokenHash,
} from "../services/user.service.js";

const signupSchema = z.object({
  email: z.string().email().max(255),
  password: z.string().min(8).max(128),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

export async function authRoutes(app: FastifyInstance): Promise<void> {
  app.post("/auth/signup", async (request, reply) => {
    const parsed = signupSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid input", details: parsed.error.flatten().fieldErrors });
    }

    const { email, password } = parsed.data;

    // Check if email already exists
    const existing = await getUserByEmail(email);
    if (existing) {
      return reply.code(409).send({ error: "Email already registered" });
    }

    const passwordHash = await hashPassword(password);
    const encryptionSalt = randomBytes(32).toString("base64");

    const { userId } = await createUser(email, passwordHash, encryptionSalt);

    const accessToken = generateAccessToken(userId);
    const refreshToken = generateRefreshToken(userId);

    await updateRefreshTokenHash(userId, hashToken(refreshToken));

    return reply.code(201).send({
      userId,
      accessToken,
      refreshToken,
      encryptionSalt,
    });
  });

  app.post("/auth/login", async (request, reply) => {
    const parsed = loginSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid input" });
    }

    const { email, password } = parsed.data;
    const user = await getUserByEmail(email);

    if (!user) {
      return reply.code(401).send({ error: "Invalid email or password" });
    }

    const valid = await verifyPassword(password, user.passwordHash);
    if (!valid) {
      return reply.code(401).send({ error: "Invalid email or password" });
    }

    const accessToken = generateAccessToken(user.userId);
    const refreshToken = generateRefreshToken(user.userId);

    await updateRefreshTokenHash(user.userId, hashToken(refreshToken));

    return reply.send({
      userId: user.userId,
      accessToken,
      refreshToken,
      encryptionSalt: user.encryptionSalt,
    });
  });

  app.post("/auth/refresh", async (request, reply) => {
    const parsed = refreshSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid input" });
    }

    const { refreshToken } = parsed.data;

    let payload;
    try {
      payload = verifyRefreshToken(refreshToken);
    } catch {
      return reply.code(401).send({ error: "Invalid or expired refresh token" });
    }

    const user = await getUserById(payload.userId);
    if (!user) {
      return reply.code(401).send({ error: "User not found" });
    }

    // Verify refresh token hash matches (single-use rotation)
    const tokenHash = hashToken(refreshToken);
    if (user.refreshTokenHash !== tokenHash) {
      return reply.code(401).send({ error: "Refresh token has been revoked" });
    }

    const newAccessToken = generateAccessToken(payload.userId);
    const newRefreshToken = generateRefreshToken(payload.userId);

    await updateRefreshTokenHash(payload.userId, hashToken(newRefreshToken));

    return reply.send({
      accessToken: newAccessToken,
      refreshToken: newRefreshToken,
    });
  });
}
