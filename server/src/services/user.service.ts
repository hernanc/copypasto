import { GetCommand, PutCommand, QueryCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { docClient } from "../db/dynamodb.js";
import { config } from "../config.js";
import { randomUUID } from "node:crypto";

export interface UserRecord {
  pk: string;
  sk: string;
  email: string;
  passwordHash: string;
  encryptionSalt: string;
  refreshTokenHash: string | null;
  createdAt: string;
  updatedAt: string;
}

function userIdFromPk(pk: string): string {
  return pk.replace("USER#", "");
}

export async function createUser(
  email: string,
  passwordHash: string,
  encryptionSalt: string
): Promise<{ userId: string; user: UserRecord }> {
  const userId = randomUUID();
  const now = new Date().toISOString();

  const user: UserRecord = {
    pk: `USER#${userId}`,
    sk: "PROFILE",
    email: email.toLowerCase().trim(),
    passwordHash,
    encryptionSalt,
    refreshTokenHash: null,
    createdAt: now,
    updatedAt: now,
  };

  await docClient.send(
    new PutCommand({
      TableName: config.DYNAMODB_USERS_TABLE,
      Item: user,
      ConditionExpression: "attribute_not_exists(pk)",
    })
  );

  return { userId, user };
}

export async function getUserByEmail(email: string): Promise<(UserRecord & { userId: string }) | null> {
  const result = await docClient.send(
    new QueryCommand({
      TableName: config.DYNAMODB_USERS_TABLE,
      IndexName: "email-index",
      KeyConditionExpression: "email = :email",
      ExpressionAttributeValues: {
        ":email": email.toLowerCase().trim(),
      },
      Limit: 1,
    })
  );

  if (!result.Items || result.Items.length === 0) return null;

  const user = result.Items[0] as UserRecord;
  return { ...user, userId: userIdFromPk(user.pk) };
}

export async function getUserById(userId: string): Promise<UserRecord | null> {
  const result = await docClient.send(
    new GetCommand({
      TableName: config.DYNAMODB_USERS_TABLE,
      Key: { pk: `USER#${userId}`, sk: "PROFILE" },
    })
  );

  return (result.Item as UserRecord) ?? null;
}

export async function updateRefreshTokenHash(userId: string, hash: string): Promise<void> {
  await docClient.send(
    new UpdateCommand({
      TableName: config.DYNAMODB_USERS_TABLE,
      Key: { pk: `USER#${userId}`, sk: "PROFILE" },
      UpdateExpression: "SET refreshTokenHash = :hash, updatedAt = :now",
      ExpressionAttributeValues: {
        ":hash": hash,
        ":now": new Date().toISOString(),
      },
    })
  );
}
