const ADMIN_EMAIL_ENV_KEYS = ['STUFF_ADMIN_EMAILS', 'ADMIN_EMAILS'] as const;

export function isAdminEmail(email: string | null | undefined): boolean {
  const normalized = email?.trim().toLowerCase();
  if (!normalized) return false;
  return adminEmails().includes(normalized);
}

function adminEmails(): string[] {
  return ADMIN_EMAIL_ENV_KEYS
    .flatMap((key) => (process.env[key] || '').split(','))
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean);
}
