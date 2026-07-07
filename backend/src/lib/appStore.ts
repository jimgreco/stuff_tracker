import * as fs from 'node:fs';
import * as path from 'node:path';
import {
  Environment,
  NotificationTypeV2,
  SignedDataVerifier,
  Type,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from '@apple/app-store-server-library';
import { pool } from '../db/pool';
import { getCsvEnv, getOptionalIntegerEnv, getOptionalStringEnv, isProduction } from './env';

const DEFAULT_PRODUCT_IDS = [
  'com.jimgreco.stufftracker.pro.monthly',
  'com.jimgreco.stufftracker.pro.yearly',
];
const DEFAULT_BUNDLE_ID = 'com.jimgreco.stufftracker';
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type AppStoreApplyResult = {
  applied: boolean;
  ignoredReason?: string;
  userId?: string;
  status?: 'active' | 'expired' | 'revoked';
  productId?: string;
  expiresAt?: string | null;
};

type AppleTransactionRow = {
  user_id: string | null;
};

export function appStoreProductIds(): string[] {
  const configured = getCsvEnv('APP_STORE_SUBSCRIPTION_PRODUCT_IDS');
  return configured.length ? configured : DEFAULT_PRODUCT_IDS;
}

export function appStoreBundleId(): string {
  return getOptionalStringEnv('APP_STORE_BUNDLE_ID')
    ?? getOptionalStringEnv('APPLE_BUNDLE_ID')
    ?? DEFAULT_BUNDLE_ID;
}

export async function applySignedAppStoreTransaction(
  signedTransactionInfo: string,
  expectedUserId?: string
): Promise<AppStoreApplyResult> {
  const transaction = await verifyAppStoreTransaction(signedTransactionInfo);
  return applyAppStoreTransaction(transaction, signedTransactionInfo, expectedUserId);
}

export async function applyAppStoreNotification(signedPayload: string): Promise<AppStoreApplyResult> {
  const notification = await verifyAppStoreNotification(signedPayload);
  const signedTransactionInfo = notification.data?.signedTransactionInfo;
  if (!signedTransactionInfo) {
    return { applied: false, ignoredReason: 'notification_missing_transaction' };
  }

  const transaction = await verifyAppStoreTransaction(signedTransactionInfo, notification.data?.environment);
  return applyAppStoreTransaction(transaction, signedTransactionInfo, undefined, notification);
}

async function applyAppStoreTransaction(
  transaction: JWSTransactionDecodedPayload,
  signedTransactionInfo: string,
  expectedUserId?: string,
  notification?: ResponseBodyV2DecodedPayload
): Promise<AppStoreApplyResult> {
  const productId = transaction.productId;
  const transactionId = transaction.transactionId;
  const originalTransactionId = transaction.originalTransactionId;
  if (!productId || !transactionId || !originalTransactionId) {
    return { applied: false, ignoredReason: 'transaction_missing_required_fields' };
  }

  if (!appStoreProductIds().includes(productId)) {
    return { applied: false, ignoredReason: 'unknown_product_id', productId };
  }

  if (transaction.type && transaction.type !== Type.AUTO_RENEWABLE_SUBSCRIPTION) {
    return { applied: false, ignoredReason: 'unsupported_product_type', productId };
  }

  const userId = await targetUserId(transaction, originalTransactionId, expectedUserId);
  if (!userId) {
    return { applied: false, ignoredReason: 'transaction_missing_user', productId };
  }
  if (expectedUserId && userId !== expectedUserId) {
    return { applied: false, ignoredReason: 'transaction_belongs_to_different_user', productId };
  }

  const status = entitlementStatus(transaction, notification);
  const expiresAt = dateFromMs(transaction.expiresDate);
  const revocationDate = dateFromMs(transaction.revocationDate);
  const purchaseDate = dateFromMs(transaction.purchaseDate);
  const environment = String(transaction.environment ?? notification?.data?.environment ?? '');

  await pool.query(
    `INSERT INTO app_store_transactions (
       transaction_id, original_transaction_id, user_id, product_id, environment,
       purchase_date, expires_at, revocation_date, signed_transaction_info, payload
     )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
     ON CONFLICT (transaction_id) DO UPDATE SET
       original_transaction_id = EXCLUDED.original_transaction_id,
       user_id = EXCLUDED.user_id,
       product_id = EXCLUDED.product_id,
       environment = EXCLUDED.environment,
       purchase_date = EXCLUDED.purchase_date,
       expires_at = EXCLUDED.expires_at,
       revocation_date = EXCLUDED.revocation_date,
       signed_transaction_info = EXCLUDED.signed_transaction_info,
       payload = EXCLUDED.payload,
       updated_at = NOW()`,
    [
      transactionId,
      originalTransactionId,
      userId,
      productId,
      environment,
      purchaseDate,
      expiresAt,
      revocationDate,
      signedTransactionInfo,
      JSON.stringify({ transaction, notification: notification ?? null }),
    ]
  );

  await pool.query(
    `INSERT INTO user_entitlements (
       user_id, source, status, product_id, transaction_id, original_transaction_id,
       app_store_environment, expires_at, revoked_at, metadata
     )
     VALUES ($1, 'app_store', $2, $3, $4, $5, $6, $7, $8, $9)
     ON CONFLICT (source, original_transaction_id)
     WHERE source = 'app_store' AND original_transaction_id IS NOT NULL
     DO UPDATE SET
       user_id = EXCLUDED.user_id,
       status = EXCLUDED.status,
       product_id = EXCLUDED.product_id,
       transaction_id = EXCLUDED.transaction_id,
       app_store_environment = EXCLUDED.app_store_environment,
       expires_at = EXCLUDED.expires_at,
       revoked_at = EXCLUDED.revoked_at,
       metadata = EXCLUDED.metadata,
       updated_at = NOW()`,
    [
      userId,
      status,
      productId,
      transactionId,
      originalTransactionId,
      environment,
      expiresAt,
      revocationDate,
      JSON.stringify({
        webOrderLineItemId: transaction.webOrderLineItemId ?? null,
        notificationType: notification?.notificationType ?? null,
        notificationSubtype: notification?.subtype ?? null,
      }),
    ]
  );

  return {
    applied: true,
    userId,
    status,
    productId,
    expiresAt: expiresAt?.toISOString() ?? null,
  };
}

async function targetUserId(
  transaction: JWSTransactionDecodedPayload,
  originalTransactionId: string,
  expectedUserId?: string
): Promise<string | null> {
  const appAccountToken = transaction.appAccountToken;
  if (appAccountToken && UUID_PATTERN.test(appAccountToken)) {
    return appAccountToken;
  }

  if (expectedUserId) {
    return expectedUserId;
  }

  const { rows } = await pool.query<AppleTransactionRow>(
    `SELECT user_id
     FROM app_store_transactions
     WHERE original_transaction_id = $1 AND user_id IS NOT NULL
     ORDER BY updated_at DESC
     LIMIT 1`,
    [originalTransactionId]
  );
  return rows[0]?.user_id ?? null;
}

function entitlementStatus(
  transaction: JWSTransactionDecodedPayload,
  notification?: ResponseBodyV2DecodedPayload
): 'active' | 'expired' | 'revoked' {
  if (transaction.revocationDate || notification?.notificationType === NotificationTypeV2.REFUND || notification?.notificationType === NotificationTypeV2.REVOKE) {
    return 'revoked';
  }

  if (transaction.expiresDate !== undefined && transaction.expiresDate <= Date.now()) {
    return 'expired';
  }

  return 'active';
}

async function verifyAppStoreTransaction(
  signedTransactionInfo: string,
  expectedEnvironment?: string
): Promise<JWSTransactionDecodedPayload> {
  const unverified = decodeJwtPayload(signedTransactionInfo);
  const environment = appStoreEnvironment(expectedEnvironment ?? unverified.environment);
  const verifier = verifierFor(environment);
  return verifier.verifyAndDecodeTransaction(signedTransactionInfo);
}

async function verifyAppStoreNotification(signedPayload: string): Promise<ResponseBodyV2DecodedPayload> {
  const unverified = decodeJwtPayload(signedPayload);
  const environment = appStoreEnvironment(unverified.data?.environment);
  const verifier = verifierFor(environment, unverified.data?.appAppleId);
  return verifier.verifyAndDecodeNotification(signedPayload);
}

function verifierFor(environment: Environment, appAppleIdFromPayload?: number): SignedDataVerifier {
  const appAppleId = environment === Environment.PRODUCTION
    ? appStoreAppAppleId(appAppleIdFromPayload)
    : undefined;

  return new SignedDataVerifier(
    rootCertificatesFor(environment),
    appStoreOnlineChecksEnabled(),
    environment,
    appStoreBundleId(),
    appAppleId
  );
}

function rootCertificatesFor(environment: Environment): Buffer[] {
  if (environment === Environment.XCODE || environment === Environment.LOCAL_TESTING) {
    return [];
  }

  const certs = loadRootCertificates();
  if (!certs.length) {
    throw new Error('APP_STORE_ROOT_CERTIFICATE_PATHS or APP_STORE_ROOT_CERTIFICATES_DIR is required to verify App Store transactions');
  }
  return certs;
}

function loadRootCertificates(): Buffer[] {
  const explicitPaths = getCsvEnv('APP_STORE_ROOT_CERTIFICATE_PATHS');
  const dir = getOptionalStringEnv('APP_STORE_ROOT_CERTIFICATES_DIR');
  const dirPaths = dir && fs.existsSync(dir)
    ? fs.readdirSync(dir)
        .filter((file) => /\.(cer|der|pem)$/i.test(file))
        .map((file) => path.join(dir, file))
    : [];

  return [...explicitPaths, ...dirPaths].map((filePath) => fs.readFileSync(filePath));
}

function appStoreAppAppleId(appAppleIdFromPayload?: number): number {
  const configured = getOptionalIntegerEnv('APP_STORE_APP_APPLE_ID');
  if (configured !== undefined) {
    return configured;
  }
  if (appAppleIdFromPayload !== undefined && !isProduction()) {
    return appAppleIdFromPayload;
  }
  throw new Error('APP_STORE_APP_APPLE_ID is required to verify production App Store transactions');
}

function appStoreOnlineChecksEnabled(): boolean {
  const raw = process.env.APP_STORE_ENABLE_ONLINE_CHECKS?.trim().toLowerCase();
  if (raw === 'false' || raw === '0' || raw === 'no') {
    return false;
  }
  return true;
}

function appStoreEnvironment(value: unknown): Environment {
  switch (value) {
    case Environment.PRODUCTION:
    case 'Production':
      return Environment.PRODUCTION;
    case Environment.XCODE:
    case 'Xcode':
      return Environment.XCODE;
    case Environment.LOCAL_TESTING:
    case 'LocalTesting':
      return Environment.LOCAL_TESTING;
    case Environment.SANDBOX:
    case 'Sandbox':
    case undefined:
    case null:
      return Environment.SANDBOX;
    default:
      throw new Error(`Unsupported App Store environment: ${String(value)}`);
  }
}

function decodeJwtPayload(token: string): any {
  const parts = token.split('.');
  if (parts.length < 2) {
    throw new Error('Invalid signed App Store payload');
  }

  const payload = parts[1].replace(/-/g, '+').replace(/_/g, '/');
  const decoded = Buffer.from(payload, 'base64').toString('utf8');
  return JSON.parse(decoded);
}

function dateFromMs(value: number | undefined): Date | null {
  return value === undefined ? null : new Date(value);
}
