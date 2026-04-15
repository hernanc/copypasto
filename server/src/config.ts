import { z } from "zod";

const envSchema = z.object({
  PORT: z.coerce.number().default(3000),
  JWT_SECRET: z.string().min(16),
  JWT_REFRESH_SECRET: z.string().min(16),
  AWS_REGION: z.string().default("us-east-1"),
  DYNAMODB_USERS_TABLE: z.string().default("copypasto-users"),
  DYNAMODB_CLIPBOARD_TABLE: z.string().default("copypasto-clipboard"),
  DYNAMODB_WAITLIST_TABLE: z.string().default("copypasto-waitlist"),
  NOTIFICATION_EMAIL: z.string().email().default("hernan@avantasoftware.com"),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error("Invalid environment variables:", parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const config = parsed.data;
