#!/usr/bin/env bash
set -euo pipefail

cd ~/deploy

mode="${STUFF_DB_HARDENING_MODE:-validate}"
db_name="${STUFF_DB_NAME:-stuff}"
app_role="${STUFF_DB_APP_ROLE:-stuff_app}"
migration_role="${STUFF_DB_MIGRATION_ROLE:-stuff_migrator}"
app_connection_limit="${STUFF_DB_APP_CONNECTION_LIMIT:-10}"
migration_connection_limit="${STUFF_DB_MIGRATION_CONNECTION_LIMIT:-2}"
database_connection_limit="${STUFF_DB_CONNECTION_LIMIT:-16}"

read_env() {
  key="$1"
  line="$(grep -E "^${key}=" .env | tail -n 1 || true)"
  value="${line#*=}"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "$value"
}

write_env() {
  key="$1"
  value="$2"
  tmp=".env.tmp.$$"
  touch .env
  awk -v key="$key" -v line="${key}=${value}" '
    BEGIN { found = 0; prefix = key "=" }
    index($0, prefix) == 1 { print line; found = 1; next }
    { print }
    END { if (!found) print line }
  ' .env > "$tmp"
  mv "$tmp" .env
  chmod 600 .env
}

random_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 36 | tr -d '\n'
  else
    LC_ALL=C tr -dc 'A-Za-z0-9_+=' < /dev/urandom | head -c 48
  fi
}

urlencode_password() {
  node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$1"
}

psql_admin() {
  docker-compose exec -T -e PGPASSWORD="$db_password" db psql -U admin -d "$db_name" -v ON_ERROR_STOP=1 "$@"
}

validate_role_posture() {
  echo "Validating database role posture"
  psql_admin -Atc "SELECT rolname FROM pg_roles WHERE rolname IN ('${app_role}', '${migration_role}') ORDER BY rolname;"
  psql_admin -Atc "SELECT datname || ':' || datconnlimit FROM pg_database WHERE datname = '${db_name}';"
  psql_admin -Atc "SELECT rolname || ':' || rolconnlimit || ':' || rolsuper || ':' || rolcreatedb || ':' || rolcreaterole FROM pg_roles WHERE rolname IN ('${app_role}', '${migration_role}') ORDER BY rolname;"

  app_url="$(read_env STUFF_DATABASE_URL)"
  migration_url="$(read_env STUFF_MIGRATION_DATABASE_URL)"
  if [ -z "$app_url" ] || [ -z "$migration_url" ]; then
    echo "::error title=Database hardening failed::STUFF_DATABASE_URL and STUFF_MIGRATION_DATABASE_URL must be set in ~/deploy/.env"
    exit 1
  fi

  docker-compose exec -T -e DB_EXPECTED_APP_ROLE="$app_role" stuff npm run db:hardening:check
}

db_password="$(read_env DB_PASSWORD)"
if [ -z "$db_password" ]; then
  echo "::error title=Database hardening failed::DB_PASSWORD is missing from ~/deploy/.env"
  exit 1
fi

if [ "$mode" = "validate" ]; then
  validate_role_posture
  exit 0
fi

if [ "$mode" != "apply" ]; then
  echo "::error title=Database hardening failed::STUFF_DB_HARDENING_MODE must be validate or apply"
  exit 1
fi

app_password="$(random_password)"
migration_password="$(random_password)"

echo "Applying database role hardening for ${db_name}"
export APP_ROLE="$app_role"
export APP_PASSWORD="$app_password"
export MIGRATION_ROLE="$migration_role"
export MIGRATION_PASSWORD="$migration_password"
export APP_CONNECTION_LIMIT="$app_connection_limit"
export MIGRATION_CONNECTION_LIMIT="$migration_connection_limit"
export DATABASE_CONNECTION_LIMIT="$database_connection_limit"

psql_admin -v app_role="$app_role" -v migration_role="$migration_role" <<'SQL'
SELECT set_config('stuff.app_role', :'app_role', false);
SELECT set_config('stuff.migration_role', :'migration_role', false);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_setting('stuff.app_role')) THEN
    EXECUTE format('CREATE ROLE %I LOGIN', current_setting('stuff.app_role'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_setting('stuff.migration_role')) THEN
    EXECUTE format('CREATE ROLE %I LOGIN', current_setting('stuff.migration_role'));
  END IF;
END
$$;
SQL

psql_admin \
  -v db_name="$db_name" \
  -v app_role="$app_role" \
  -v app_password="$app_password" \
  -v migration_role="$migration_role" \
  -v migration_password="$migration_password" \
  -v app_connection_limit="$app_connection_limit" \
  -v migration_connection_limit="$migration_connection_limit" \
  -v database_connection_limit="$database_connection_limit" <<'SQL'
SELECT set_config('stuff.migration_role', :'migration_role', false);

ALTER ROLE :"app_role" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT CONNECTION LIMIT :app_connection_limit PASSWORD :'app_password';
ALTER ROLE :"migration_role" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT CONNECTION LIMIT :migration_connection_limit PASSWORD :'migration_password';
REVOKE ALL ON DATABASE :"db_name" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db_name" TO :"app_role", :"migration_role";
ALTER DATABASE :"db_name" CONNECTION LIMIT :database_connection_limit;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO :"app_role";
GRANT USAGE, CREATE ON SCHEMA public TO :"migration_role";
ALTER SCHEMA public OWNER TO :"migration_role";

DO $$
DECLARE
  row record;
BEGIN
  FOR row IN
    SELECT schemaname, tablename
    FROM pg_tables
    WHERE schemaname = 'public'
  LOOP
    EXECUTE format('ALTER TABLE %I.%I OWNER TO %I', row.schemaname, row.tablename, current_setting('stuff.migration_role'));
  END LOOP;

  FOR row IN
    SELECT sequence_schema, sequence_name
    FROM information_schema.sequences
    WHERE sequence_schema = 'public'
  LOOP
    EXECUTE format('ALTER SEQUENCE %I.%I OWNER TO %I', row.sequence_schema, row.sequence_name, current_setting('stuff.migration_role'));
  END LOOP;
END
$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :"app_role";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :"app_role";
ALTER DEFAULT PRIVILEGES FOR ROLE :"migration_role" IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"app_role";
ALTER DEFAULT PRIVILEGES FOR ROLE :"migration_role" IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO :"app_role";
SQL

encoded_app_password="$(urlencode_password "$app_password")"
encoded_migration_password="$(urlencode_password "$migration_password")"
write_env STUFF_DATABASE_URL "postgresql://${app_role}:${encoded_app_password}@db:5432/${db_name}?sslmode=disable"
write_env STUFF_MIGRATION_DATABASE_URL "postgresql://${migration_role}:${encoded_migration_password}@db:5432/${db_name}?sslmode=disable"

docker-compose up -d stuff

for attempt in $(seq 1 60); do
  if docker-compose exec -T stuff node -e 'fetch("http://127.0.0.1:" + (process.env.PORT || 3002) + "/health").then((response) => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1))' >/dev/null 2>&1; then
    echo "stuff service is healthy"
    break
  fi

  if [ "$attempt" = "60" ]; then
    docker-compose ps stuff || true
    docker-compose logs --tail=100 stuff || true
    echo "::error title=Database hardening failed::stuff service did not become healthy after DB role rotation"
    exit 1
  fi

  sleep 2
done

validate_role_posture
docker-compose exec -T stuff npm run smoke:deploy
echo "Database role hardening applied"
