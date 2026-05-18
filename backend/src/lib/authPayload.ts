export type AppleFullName = {
  givenName?: string;
  familyName?: string;
};

export function readAuthString(body: unknown, ...keys: string[]) {
  const record = asRecord(body);
  if (!record) return undefined;

  for (const key of keys) {
    const value = record[key];
    if (typeof value === 'string' && value.length > 0) {
      return value;
    }
  }

  return undefined;
}

export function readAppleFullName(body: unknown): AppleFullName | undefined {
  const rawFullName = readField(body, 'fullName', 'full_name');
  const fullName = asRecord(rawFullName);
  if (!fullName) return undefined;

  const givenName = readAuthString(fullName, 'givenName', 'given_name');
  const familyName = readAuthString(fullName, 'familyName', 'family_name');
  if (!givenName && !familyName) return undefined;

  return { givenName, familyName };
}

function readField(body: unknown, ...keys: string[]) {
  const record = asRecord(body);
  if (!record) return undefined;

  for (const key of keys) {
    const value = record[key];
    if (value !== undefined && value !== null) {
      return value;
    }
  }

  return undefined;
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return undefined;
  }

  return value as Record<string, unknown>;
}
