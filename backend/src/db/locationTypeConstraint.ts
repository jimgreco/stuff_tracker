export const LOCATION_TYPES = ['floor', 'room', 'container'] as const;

export function locationTypeConstraintSql() {
  const allowedTypes = LOCATION_TYPES.map((type) => `'${type}'`).join(', ');
  return `
    ALTER TABLE locations DROP CONSTRAINT IF EXISTS locations_type_check;
    ALTER TABLE locations
      ADD CONSTRAINT locations_type_check
      CHECK (type IN (${allowedTypes}));
  `;
}
