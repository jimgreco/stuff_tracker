import { pool } from '../db/pool';

export type Role = 'owner' | 'admin' | 'editor' | 'viewer';

/** Returns the user's role in a home, or null if no access. */
export async function getHomeRole(homeId: string, userId: string): Promise<Role | null> {
  // Check if owner
  const ownerRes = await pool.query(
    'SELECT id FROM homes WHERE id = $1 AND owner_id = $2',
    [homeId, userId]
  );
  if (ownerRes.rows[0]) return 'owner';

  const memberRes = await pool.query(
    'SELECT role FROM home_members WHERE home_id = $1 AND user_id = $2',
    [homeId, userId]
  );
  return memberRes.rows[0]?.role ?? null;
}

export function canEdit(role: Role | null): boolean {
  return role === 'owner' || role === 'admin' || role === 'editor';
}

export function canAdmin(role: Role | null): boolean {
  return role === 'owner' || role === 'admin';
}
