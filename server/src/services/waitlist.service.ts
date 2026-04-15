import { PutCommand, GetCommand } from "@aws-sdk/lib-dynamodb";
import { SESClient, SendEmailCommand } from "@aws-sdk/client-ses";
import { docClient } from "../db/dynamodb.js";
import { config } from "../config.js";

const ses = new SESClient({ region: config.AWS_REGION });

export async function saveWaitlistEntry(email: string): Promise<boolean> {
  try {
    await docClient.send(
      new PutCommand({
        TableName: config.DYNAMODB_WAITLIST_TABLE,
        Item: {
          email,
          createdAt: new Date().toISOString(),
        },
        ConditionExpression: "attribute_not_exists(email)",
      })
    );
    return true;
  } catch (err: unknown) {
    if (
      typeof err === "object" &&
      err !== null &&
      "name" in err &&
      err.name === "ConditionalCheckFailedException"
    ) {
      return false; // already exists
    }
    throw err;
  }
}

export async function sendNotificationEmail(signupEmail: string): Promise<void> {
  await ses.send(
    new SendEmailCommand({
      Source: config.NOTIFICATION_EMAIL,
      Destination: {
        ToAddresses: [config.NOTIFICATION_EMAIL],
      },
      Message: {
        Subject: {
          Data: `Copypasto waitlist: ${signupEmail}`,
        },
        Body: {
          Text: {
            Data: `New waitlist signup: ${signupEmail}\n\nTime: ${new Date().toISOString()}`,
          },
        },
      },
    })
  );
}
