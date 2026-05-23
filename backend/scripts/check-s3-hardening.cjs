const {
  GetBucketEncryptionCommand,
  GetBucketLifecycleConfigurationCommand,
  GetBucketPolicyStatusCommand,
  GetPublicAccessBlockCommand,
  S3Client,
} = require('@aws-sdk/client-s3');

require('dotenv').config();

const bucket = process.env.S3_BUCKET || process.env.AWS_S3_BUCKET;
if (!bucket) {
  console.error('S3_BUCKET is required');
  process.exit(1);
}

const region = process.env.S3_REGION || process.env.AWS_REGION || 'us-east-1';
const s3 = new S3Client({ region });

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

async function main() {
  const failures = [];
  const warnings = [];

  await checkPublicAccessBlock(failures);
  await checkPolicyStatus(failures, warnings);
  await checkEncryption(failures);
  await checkLifecycle(warnings);

  for (const warning of warnings) {
    console.warn(`WARN ${warning}`);
  }

  if (failures.length > 0) {
    for (const failure of failures) {
      console.error(`FAIL ${failure}`);
    }
    process.exit(1);
  }

  console.log(`S3 hardening check passed for ${bucket}`);
}

async function checkPublicAccessBlock(failures) {
  try {
    const response = await s3.send(new GetPublicAccessBlockCommand({ Bucket: bucket }));
    const config = response.PublicAccessBlockConfiguration || {};
    const required = [
      'BlockPublicAcls',
      'IgnorePublicAcls',
      'BlockPublicPolicy',
      'RestrictPublicBuckets',
    ];

    for (const key of required) {
      if (config[key] !== true) {
        failures.push(`Public access block ${key} is not enabled`);
      }
    }
  } catch (err) {
    failures.push(`Could not read public access block: ${describeAwsError(err)}`);
  }
}

async function checkPolicyStatus(failures, warnings) {
  try {
    const response = await s3.send(new GetBucketPolicyStatusCommand({ Bucket: bucket }));
    if (response.PolicyStatus?.IsPublic === true) {
      failures.push('Bucket policy is public');
    }
  } catch (err) {
    if (err.name === 'NoSuchBucketPolicy') {
      warnings.push('Bucket has no policy; verify app access is granted through least-privilege IAM instead');
      return;
    }
    failures.push(`Could not read bucket policy status: ${describeAwsError(err)}`);
  }
}

async function checkEncryption(failures) {
  try {
    const response = await s3.send(new GetBucketEncryptionCommand({ Bucket: bucket }));
    const rules = response.ServerSideEncryptionConfiguration?.Rules || [];
    if (rules.length === 0) {
      failures.push('Bucket has no default server-side encryption rules');
      return;
    }

    const hasSupportedEncryption = rules.some((rule) => {
      const algorithm = rule.ApplyServerSideEncryptionByDefault?.SSEAlgorithm;
      return algorithm === 'AES256' || algorithm === 'aws:kms';
    });

    if (!hasSupportedEncryption) {
      failures.push('Bucket default encryption is not AES256 or aws:kms');
    }
  } catch (err) {
    failures.push(`Could not read bucket encryption: ${describeAwsError(err)}`);
  }
}

async function checkLifecycle(warnings) {
  try {
    const response = await s3.send(new GetBucketLifecycleConfigurationCommand({ Bucket: bucket }));
    const rules = response.Rules || [];
    if (rules.length === 0) {
      warnings.push('Bucket lifecycle configuration has no rules');
    }
  } catch (err) {
    if (err.name === 'NoSuchLifecycleConfiguration') {
      warnings.push('Bucket has no lifecycle configuration');
      return;
    }
    warnings.push(`Could not read bucket lifecycle configuration: ${describeAwsError(err)}`);
  }
}

function describeAwsError(err) {
  return [err.name, err.message].filter(Boolean).join(': ') || String(err);
}
