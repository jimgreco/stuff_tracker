FROM node:20-alpine AS builder
WORKDIR /app
COPY backend/package*.json ./
RUN npm ci
COPY backend/tsconfig.json ./
COPY backend/src ./src
RUN npm run build

FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
RUN apk add --no-cache gzip postgresql16-client
COPY backend/package*.json ./
RUN npm ci --omit=dev
COPY backend/scripts ./scripts
COPY --from=builder /app/dist ./dist
COPY backend/src/db/schema.sql ./dist/db/schema.sql
COPY backend/src/db/migrations ./dist/db/migrations
COPY web ./web
EXPOSE 3002
CMD ["sh", "-c", "if [ -n \"${MIGRATION_DATABASE_URL:-}\" ]; then DATABASE_URL=\"$MIGRATION_DATABASE_URL\" npm run db:migrate; else npm run db:migrate; fi && node dist/index.js"]
