import { UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { hashForLoginUpgrade } from "./password-service.mjs";

// Invoke this from the legacy account login path. It deliberately accepts only
// the authenticated user's key, so a migration cannot scan or rewrite accounts.
export async function migratePasswordOnLogin({ ddb, tableName, userId, password, storedHash }) {
  const replacement = await hashForLoginUpgrade(password, storedHash);
  if (!replacement) return false;

  await ddb.send(new UpdateCommand({
    TableName: tableName,
    Key: { userId },
    UpdateExpression: "SET passwordHash = :hash, passwordHashVersion = :version",
    ConditionExpression: "passwordHash = :oldHash",
    ExpressionAttributeValues: { ":hash": replacement, ":version": 1, ":oldHash": storedHash },
  }));
  return true;
}
