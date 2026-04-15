import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { saveWaitlistEntry, sendNotificationEmail } from "../services/waitlist.service.js";

const waitlistSchema = z.object({
  email: z.string().email().max(255).transform((e) => e.toLowerCase().trim()),
});

export async function waitlistRoutes(app: FastifyInstance): Promise<void> {
  app.post("/waitlist", async (request, reply) => {
    const parsed = waitlistSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid email address" });
    }

    const { email } = parsed.data;
    const isNew = await saveWaitlistEntry(email);

    if (isNew) {
      try {
        await sendNotificationEmail(email);
      } catch (err) {
        app.log.error({ err, email }, "Failed to send waitlist notification email");
      }
    }

    return reply.code(200).send({ ok: true });
  });
}
