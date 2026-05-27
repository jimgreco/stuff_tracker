import { pool } from '../db/pool';

export type Role = 'owner' | 'admin' | 'editor' | 'viewer';

type MemberRoleRow = {
  role: Role;
  owner_is_paid: boolean;
};

/** Returns the user's role in a home, or null if no access. */
export async function getHomeRole(homeId: string, userId: string): Promise<Role | null> {
  // Check if owner
  const ownerRes = await pool.query(
    'SELECT id FROM homes WHERE id = $1 AND owner_id = $2',
    [homeId, userId]
  );
  if (ownerRes.rows[0]) return 'owner';

  const memberRes = await pool.query<MemberRoleRow>(
    `SELECT hm.role,
            EXISTS (
              SELECT 1
              FROM user_entitlements ue
              WHERE ue.user_id = h.owner_id
                AND ue.status = 'active'
                AND ue.revoked_at IS NULL
                AND (ue.expires_at IS NULL OR ue.expires_at > NOW())
            ) AS owner_is_paid
     FROM home_members hm
     JOIN homes h ON h.id = hm.home_id
     WHERE hm.home_id = $1 AND hm.user_id = $2`,
    [homeId, userId]
  );
  const member = memberRes.rows[0];
  return member?.owner_is_paid ? member.role : null;
}

export function canEdit(role: Role | null): boolean {
  return role === 'owner' || role === 'admin' || role === 'editor';
}

export function canAdmin(role: Role | null): boolean {
  return role === 'owner' || role === 'admin';
}
