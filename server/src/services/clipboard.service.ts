import { BatchWriteCommand, PutCommand, QueryCommand } from "@aws-sdk/lib-dynamodb";
import { docClient } from "../db/dynamodb.js";
import { config } from "../config.js";
import { ulid } from "ulid";

const MAX_ENTRIES = 5;
const TTL_DAYS = 30;

export interface ClipboardRecord {
  pk: string;
  sk: string;
  ciphertext: string;
  iv: string;
  contentLength: number;
  createdAt: string;
  ttl: number;
}

export interface ClipboardEntry {
  id: string;
  ciphertext: string;
  iv: string;
  contentLength: number;
  createdAt: string;
}

function recordToEntry(record: ClipboardRecord): ClipboardEntry {
  // sk format: CLIP#<timestamp>#<ulid>
  const parts = record.sk.split("#");
  const id = parts[parts.length - 1];
  return {
    id,
    ciphertext: record.ciphertext,
    iv: record.iv,
    contentLength: record.contentLength,
    createdAt: record.createdAt,
  };
}

export async function addEntry(
  userId: string,
  ciphertext: string,
  iv: string,
  contentLength: number
): Promise<ClipboardEntry> {
  const now = new Date();
  const id = ulid();
  const ttl = Math.floor(now.getTime() / 1000) + TTL_DAYS * 24 * 60 * 60;

  const record: ClipboardRecord = {
    pk: `USER#${userId}`,
    sk: `CLIP#${now.toISOString()}#${id}`,
    ciphertext,
    iv,
    contentLength,
    createdAt: now.toISOString(),
    ttl,
  };

  await docClient.send(
    new PutCommand({
      TableName: config.DYNAMODB_CLIPBOARD_TABLE,
      Item: record,
    })
  );

  // Prune old entries beyond MAX_ENTRIES
  await pruneEntries(userId);

  return recordToEntry(record);
}

async function pruneEntries(userId: string): Promise<void> {
  const result = await docClient.send(
    new QueryCommand({
      TableName: config.DYNAMODB_CLIPBOARD_TABLE,
      KeyConditionExpression: "pk = :pk AND begins_with(sk, :prefix)",
      ExpressionAttributeValues: {
        ":pk": `USER#${userId}`,
        ":prefix": "CLIP#",
      },
      ScanIndexForward: false, // newest first
    })
  );

  const items = result.Items as ClipboardRecord[] | undefined;
  if (!items || items.length <= MAX_ENTRIES) return;

  const toDelete = items.slice(MAX_ENTRIES);

  // Batch delete in groups of 25 (DynamoDB limit)
  for (let i = 0; i < toDelete.length; i += 25) {
    const batch = toDelete.slice(i, i + 25);
    await docClient.send(
      new BatchWriteCommand({
        RequestItems: {
          [config.DYNAMODB_CLIPBOARD_TABLE]: batch.map((item) => ({
            DeleteRequest: {
              Key: { pk: item.pk, sk: item.sk },
            },
          })),
        },
      })
    );
  }
}

export async function getEntries(userId: string): Promise<ClipboardEntry[]> {
  const result = await docClient.send(
    new QueryCommand({
      TableName: config.DYNAMODB_CLIPBOARD_TABLE,
      KeyConditionExpression: "pk = :pk AND begins_with(sk, :prefix)",
      ExpressionAttributeValues: {
        ":pk": `USER#${userId}`,
        ":prefix": "CLIP#",
      },
      ScanIndexForward: false, // newest first
      Limit: MAX_ENTRIES,
    })
  );

  return (result.Items as ClipboardRecord[] | undefined)?.map(recordToEntry) ?? [];
}

export async function deleteAllEntries(userId: string): Promise<void> {
  const result = await docClient.send(
    new QueryCommand({
      TableName: config.DYNAMODB_CLIPBOARD_TABLE,
      KeyConditionExpression: "pk = :pk AND begins_with(sk, :prefix)",
      ExpressionAttributeValues: {
        ":pk": `USER#${userId}`,
        ":prefix": "CLIP#",
      },
      ProjectionExpression: "pk, sk",
    })
  );

  const items = result.Items as Array<{ pk: string; sk: string }> | undefined;
  if (!items || items.length === 0) return;

  for (let i = 0; i < items.length; i += 25) {
    const batch = items.slice(i, i + 25);
    await docClient.send(
      new BatchWriteCommand({
        RequestItems: {
          [config.DYNAMODB_CLIPBOARD_TABLE]: batch.map((item) => ({
            DeleteRequest: {
              Key: { pk: item.pk, sk: item.sk },
            },
          })),
        },
      })
    );
  }
}
