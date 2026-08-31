# Cloud ex Machina — AWS Integration (CloudFormation)

This project deploys CloudFormation stacks that grant CXM cross-account read access to your AWS Organization and set up EventBridge notifications that drive CXM's optimization platform.

## Templates

| Template | Type | Purpose |
|----------|------|---------|
| `cxm-integration-aws-root.yaml` | Stack | Deploys to the management account: organization crawler role, CUR reader role, and EventBridge notification rules |
| `cxm-integration-aws-sub-account.yaml` | StackSet | Deploys to member accounts: asset crawler role and EventBridge CloudFormation notifier |
| `cxm-integration-aws-eks.yaml` | Stack | Optional — Grants CXM read-only access to an EKS cluster via Access Entries (deploy once per cluster) |
| `cxm-integration-aws-log-source.yaml` | Stack | Optional — Deploys to the account/region hosting a centralized log bucket (VPC Flow Logs or CloudTrail): reader role and EventBridge notifications. **One stack per bucket** |
| `cxm-integration-aws-s3-inplace-query.yaml` | Stack | Optional — Renders (or applies) the bucket resource-policy statements that let CXM query a CloudTrail or VPC Flow Logs bucket in place with Athena (deploy once per bucket) |

## Prerequisites

- **AWS CLI v2** installed and configured
- **Admin access** to the AWS Organizations management account
- **Values provided by CXM**: External ID, CXM Account ID, and CUR S3 bucket name

## Parameters

### Root Stack (`params-cxm-root.json`)

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `CXMExternalId` | Yes | — | External ID provided by CXM |
| `CXMCustomerAccountId` | Yes | — | 12-digit CXM AWS account ID provided by CXM |
| `CostAndUsageReportS3BucketName` | Yes | — | S3 bucket name storing your CUR data (bucket name only, not the ARN — e.g. `my-cur-bucket`) |
| `CostAndUsageReportS3BucketKmsKeyArn` | No | `""` | KMS key ARN if your CUR bucket is encrypted (e.g. `arn:aws:kms:us-east-1:123456789012:key/...`) |
| `CostAndUsageBucketRegion` | No | `us-east-1` | Region of the CUR S3 bucket |
| `EnableInPlaceQueryGrant` | No | `false` | Set to `true` to render the in-place query statements as stack outputs. See [Querying logs in place](#querying-logs-in-place) |
| `InPlaceQueryObjectPrefix` | No | `AWSLogs` | Object key prefix the in-place grant is narrowed to, no trailing slash. Set to your report prefix for a CUR bucket |
| `InPlaceQueryKmsKeyArn` | No | `""` | KMS key CXM must decrypt for in-place queries (typically the Control Tower CloudTrail key, which lives in this management account). When set, this stack creates a KMS grant for the CXM account — no separate stack |
| `Prefix` | No | `cxm` | Namespace prefix for resource names |
| `EnableSavingsModifications` | No | `true` | `false` gives the crawler read-only commitment access — it reports on Savings Plans/RIs but cannot purchase, modify or cancel them, and cannot write CUR report definitions. Use for a read-only proof of concept |

### Sub-Account StackSet (`params-cxm-sub-accounts.json`)

> **Important:** This StackSet must be deployed to all member accounts in your organization for CXM to have visibility into their resources. Without it, CXM can only see assets in the management account.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `CXMExternalId` | Yes | — | External ID provided by CXM (same as root) |
| `CXMCustomerAccountId` | Yes | — | 12-digit CXM AWS account ID provided by CXM (same as root) |
| `ManagementAccountId` | Yes | — | Your 12-digit AWS Organizations management account ID |
| `ManagementRegion` | No | `us-east-1` | Single region in which the global IAM roles are created |
| `OrganizationId` | No | `""` | AWS Organizations root ID (`o-xxxxxxxxxx`). When set, the management account can only assume the asset crawler role from inside this organization (`aws:PrincipalOrgID`) |
| `EnableScheduling` | No | `false` | Grant scheduling/scaling permissions (stop/start, resize) for FinOps actions |
| `EnableSavingsModifications` | No | `true` | `false` gives the crawler read-only commitment access — it reports on Savings Plans/RIs but cannot purchase, modify or cancel them |
| `Prefix` | No | `cxm` | Namespace prefix for resource names |

### EKS Stack (inline parameters)

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `ClusterName` | Yes | — | Name of the EKS cluster |
| `PrincipalArn` | Yes | — | IAM role ARN of the CXM role **in the cluster's own account** — in an Organization deployment that is `CxmAssetCrawlerRoleArn` from the sub-account StackSet instance in that account, not the management account's organization crawler |
| `AccessScopeType` | No | `cluster` | `cluster` for full access, `namespace` to restrict |
| `AccessScopeNamespaces` | No | `""` | Comma-separated namespaces (only when type is `namespace`) |
| `KubernetesGroups` | No | `""` | Comma-separated Kubernetes groups for the access entry |
| `Prefix` | No | `cxm` | Namespace prefix for resource names |

### Log Source Stack (`params-cxm-log-source.json`) — one per bucket

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `CXMExternalId` | Yes | — | External ID provided by CXM (same as root) |
| `CXMCustomerAccountId` | Yes | — | 12-digit CXM AWS account ID provided by CXM (same as root) |
| `AdditionalCXMCustomerAccountId` | No | `""` | Second CXM account that also reads this bucket (e.g. staging alongside production). See [Several CXM environments reading one bucket](#several-cxm-environments-reading-one-bucket) |
| `AdditionalCXMExternalId` | No | `""` | External ID of that second account. Required whenever `AdditionalCXMCustomerAccountId` is set |
| `LogSource` | No | `flowlogs` | `flowlogs` or `cloudtrail`. Names every resource the stack creates — see [One stack per log bucket](#one-stack-per-log-bucket) |
| `LogSourceBucketName` | Yes | — | S3 bucket name storing the centralized logs |
| `LogSourceBucketKmsKeyArn` | No | `""` | KMS key ARN if the bucket is encrypted |
| `EnableInPlaceQueryGrant` | No | `false` | Set to `true` to render the in-place query statements as stack outputs. See [Querying logs in place](#querying-logs-in-place) |
| `InPlaceQueryObjectPrefix` | No | `AWSLogs` | Object key prefix the in-place grant is narrowed to, no trailing slash |
| `Prefix` | No | `cxm` | Namespace prefix for resource names |

### In-Place Query Stack (inline parameters, one per bucket)

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `CXMCustomerAccountId` | Yes | — | 12-digit CXM AWS account ID provided by CXM (same as root) |
| `AdditionalCXMCustomerAccountId` | No | `""` | Second CXM account that also queries this bucket. See [Several CXM environments reading one bucket](#several-cxm-environments-reading-one-bucket) |
| `BucketName` | Yes | — | Name of the CloudTrail or VPC Flow Logs bucket to grant query access to |
| `ObjectPrefix` | No | `AWSLogs` | Object key prefix the grant is narrowed to. No trailing `/` — one is added for you |
| `ManageBucketPolicy` | No | `false` | `true` makes the stack own the bucket policy, **replacing** whatever is attached. Only for a bucket dedicated to this integration |

If the bucket is KMS-encrypted, grant `kms:Decrypt` by setting `InPlaceQueryKmsKeyArn` on the **root stack** (it runs in the management account, where the Control Tower CloudTrail key lives) — no separate stack.

## Deployment

### Where to deploy

**Deploy the root stack to the region where your CUR S3 bucket lives** (e.g. `us-west-2` if your CUR bucket is in `us-west-2`). IAM roles are global, so they work regardless of region, but the CUR S3 event notification rule only captures events in the bucket's region.

After deployment, check the stack outputs:
- `CURReaderCreated` should show `YES`
- `ResourcesCreated` should show `All resources created`

If `CURReaderCreated` shows `NO`, you deployed to the wrong region — redeploy to the CUR bucket region.

### 1. Configure Parameters

```bash
cp params-cxm-root-example.json params-cxm-root.json
cp params-cxm-sub-accounts-example.json params-cxm-sub-accounts.json
```

Edit both files and fill in the values provided by CXM.

### 2. Deploy the Root Stack

```bash
# Deploy to the CUR bucket region (e.g. us-west-2)
CUR_REGION=us-east-1  # Change to your CUR bucket region

aws cloudformation create-stack \
  --stack-name CxmIntegrationStack-Main \
  --template-body file://cxm-integration-aws-root.yaml \
  --parameters file://params-cxm-root.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $CUR_REGION

aws cloudformation wait stack-create-complete \
  --stack-name CxmIntegrationStack-Main \
  --region $CUR_REGION
```

### 3. Deploy the Sub-Accounts StackSet

```bash
# Create the StackSet
aws cloudformation create-stack-set \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --template-body file://cxm-integration-aws-sub-account.yaml \
  --parameters file://params-cxm-sub-accounts.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
  --region $CUR_REGION

# Deploy instances to your OUs and regions
aws cloudformation create-stack-instances \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --deployment-targets OrganizationalUnitIds='["ou-xxxx-xxxxxxxx"]' \
  --regions us-east-1 us-east-2 eu-west-1 \
  --operation-preferences FailureTolerancePercentage=100,MaxConcurrentPercentage=50 \
  --region $CUR_REGION
```

Auto-deployment is enabled — new accounts joining the targeted OUs will receive the stack automatically.

### 4. Deploy EKS Access (Optional)

If you run EKS clusters and want CXM to have read-only Kubernetes visibility, deploy once per cluster:

```bash
aws cloudformation create-stack \
  --stack-name CxmEksAccess-<CLUSTER_NAME> \
  --template-body file://cxm-integration-aws-eks.yaml \
  --parameters \
    ParameterKey=ClusterName,ParameterValue=<CLUSTER_NAME> \
    ParameterKey=PrincipalArn,ParameterValue=<CXM_ROLE_ARN> \
  --region <CLUSTER_REGION>
```

Where `<CXM_ROLE_ARN>` is the `CxmOrganizationCrawlerRoleArn` or `CxmAssetCrawlerRoleArn` from the root stack outputs.

To restrict access to specific namespaces:

```bash
aws cloudformation create-stack \
  --stack-name CxmEksAccess-<CLUSTER_NAME> \
  --template-body file://cxm-integration-aws-eks.yaml \
  --parameters \
    ParameterKey=ClusterName,ParameterValue=<CLUSTER_NAME> \
    ParameterKey=PrincipalArn,ParameterValue=<CXM_ROLE_ARN> \
    ParameterKey=AccessScopeType,ParameterValue=namespace \
    ParameterKey=AccessScopeNamespaces,ParameterValue="ns1\,ns2" \
  --region <CLUSTER_REGION>
```

> **Legacy clusters:** Clusters created before October 2023 (platform version < `eks.14`) use the `aws-auth` ConfigMap. You must first enable the Access Entry API:
> ```bash
> aws eks update-cluster-config \
>   --name <CLUSTER_NAME> \
>   --access-config authenticationMode=API_AND_CONFIG_MAP
> ```

### 5. Deploy Log Sources (Optional)

#### One stack per log bucket

A log source stack grants read on **one** bucket and watches **one** bucket, so centralized VPC
Flow Logs and centralized CloudTrail get a stack each — even when both buckets live in the same
account. `LogSource` names everything the stack creates, so the two never collide and the role
name says which bucket it reads:

| `LogSource` | Reader role | Notification role | EventBridge rule |
|-------------|-------------|-------------------|------------------|
| `flowlogs` | `<Prefix>-flowlogs-reader` | `<Prefix>-flowlogs-notification` | `<Prefix>-flowlogs-bucket-change-notifier` |
| `cloudtrail` | `<Prefix>-cloudtrail-reader` | `<Prefix>-cloudtrail-notification` | `<Prefix>-cloudtrail-bucket-change-notifier` |

CXM is configured with these exact role names per log source, so deploying the wrong `LogSource`
against a bucket produces a role CXM will not look for. Name the stacks to match
(`CxmIntegrationStack-FlowLogs`, `CxmIntegrationStack-CloudTrail`).

Deploy **in the account and region where the bucket is located** — often neither is the
management account.

```bash
cp params-cxm-log-source-example.json params-cxm-log-source.json
# Edit params-cxm-log-source.json with your values, including LogSource

LOG_REGION=eu-west-1  # Change to your log bucket's region

aws cloudformation create-stack \
  --stack-name CxmIntegrationStack-FlowLogs \
  --template-body file://cxm-integration-aws-log-source.yaml \
  --parameters file://params-cxm-log-source.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $LOG_REGION \
  --profile org-network-logs  # Change to the log bucket account profile

aws cloudformation wait stack-create-complete \
  --stack-name CxmIntegrationStack-FlowLogs \
  --region $LOG_REGION \
  --profile org-network-logs
```

Repeat with `LogSource=cloudtrail`, the CloudTrail bucket name and
`--stack-name CxmIntegrationStack-CloudTrail` for the CloudTrail bucket.

> **The EventBridge rule needs notifications enabled on the bucket.** S3 emits nothing to
> EventBridge by default, so the rule this stack creates never fires until you turn it on:
>
> ```bash
> aws s3api put-bucket-notification-configuration \
>   --bucket <LOG_BUCKET> \
>   --notification-configuration '{"EventBridgeConfiguration":{}}' \
>   --region $LOG_REGION --profile org-network-logs
> ```

### 6. Grant In-Place Query Access (Optional)

The reader roles above let CXM *list and fetch* objects. Querying a log bucket in place
with Athena needs more: Athena reads S3 as the principal that submitted the query, not as
the assumed reader role, so the role's identity policy never applies to the scan. The only
grant that works is a policy on the bucket itself — and on the KMS key, if the bucket is
encrypted.

Deploy once per bucket (CloudTrail, VPC Flow Logs, …), **in the account and region that
owns the bucket**:

```bash
aws cloudformation create-stack \
  --stack-name CxmInPlaceQuery-<BUCKET_NAME> \
  --template-body file://cxm-integration-aws-s3-inplace-query.yaml \
  --parameters \
    ParameterKey=CXMCustomerAccountId,ParameterValue=<CXM_ACCOUNT_ID> \
    ParameterKey=BucketName,ParameterValue=<BUCKET_NAME> \
    ParameterKey=ObjectPrefix,ParameterValue=AWSLogs \
  --region <BUCKET_REGION>
```

By default the stack **creates nothing** — it renders the statements you need:

```bash
aws cloudformation describe-stacks \
  --stack-name CxmInPlaceQuery-<BUCKET_NAME> \
  --query "Stacks[0].Outputs[?OutputKey=='BucketPolicyStatementsJson'].OutputValue" \
  --output text \
  --region <BUCKET_REGION>
```

Merge those statements into the bucket's existing policy. If the bucket is KMS-encrypted,
set `InPlaceQueryKmsKeyArn` on the root stack to that key's ARN — no separate stack, no
key-policy edit.

> **Why merge instead of apply?** CloudFormation's `AWS::S3::BucketPolicy` replaces the
> entire bucket policy. CloudTrail and VPC Flow Logs buckets carry AWS log-delivery
> statements; replacing them silently stops log delivery. Set
> `ManageBucketPolicy=true` only for a bucket dedicated to this integration with no policy
> of its own.

For the KMS key, the root stack creates a **KMS grant** for the CXM account when
`InPlaceQueryKmsKeyArn` is set (a small inline Lambda custom resource does it) — additive,
it never touches the key policy, and deleting the stack revokes the grant. The root stack
runs in the management account, where the Control Tower CloudTrail key lives, so no extra
deployment is needed.

### 7. Verify Deployment

Retrieve the root stack outputs and confirm all resources were created:

```bash
aws cloudformation describe-stacks \
  --stack-name CxmIntegrationStack-Main \
  --query "Stacks[0].Outputs" \
  --output table \
  --region $CUR_REGION
```

Check that:
- `CxmOrganizationCrawlerRoleArn` is present (org crawler created)
- `CURReaderCreated` shows `YES` (CUR reader created in the right region)
- `ResourcesCreated` shows `All resources created (org crawler, CUR reader, notifications)`

Share the outputs with CXM to complete the integration.

## Querying logs in place

CXM can analyse your logs **in place** — reading the objects straight out of your bucket instead of copying them into ours. Nothing leaves your account and you pay no duplicate storage.

This needs a grant the reader roles above cannot provide. Athena reads S3 as the principal that submitted the query and cannot be handed an assumed-role session, so the cross-account role and its external ID never enter the read path. The bucket must grant access in its **own** policy — a resource policy — and, when the objects are encrypted with a customer managed key, that key must allow Decrypt for the CXM account.

### The bucket statements are rendered for you to merge; the KMS grant is applied by the root stack

Set `EnableInPlaceQueryGrant=true` and the stack outputs `InPlaceQueryBucketPolicyStatements`. **You merge those into your existing bucket policy yourself** — no bucket policy resource is created, so turning the parameter on changes nothing in your account.

That is deliberate. `AWS::S3::BucketPolicy` replaces the **whole** bucket policy and CloudFormation has no way to read the policy already on the bucket, so it cannot merge. CloudTrail and VPC Flow Logs buckets always carry AWS log-delivery statements (`cloudtrail.amazonaws.com`, `delivery.logs.amazonaws.com`); a managed bucket policy would silently delete them and stop your log delivery.

KMS is different: the root stack's `InPlaceQueryKmsKeyArn` param creates a **KMS grant** — an additive object that never reads or replaces the key policy — so it is applied directly, no separate stack. The root stack runs in the management account, where the Control Tower CloudTrail key lives.

Read the statements out of the stack outputs:

```bash
aws cloudformation describe-stacks \
  --stack-name CxmIntegrationStack-FlowLogs \
  --query "Stacks[0].Outputs[?starts_with(OutputKey, 'InPlaceQuery')]" \
  --output text \
  --region $LOG_REGION
```

The bucket grant looks like this, with your account ID, bucket name and prefix already filled in:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CxMInPlaceGetObject000000000000",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::000000000000:root" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::example-log-bucket/AWSLogs/*"
    },
    {
      "Sid": "CxMInPlaceListBucket000000000000",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::000000000000:root" },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-log-bucket",
      "Condition": { "StringLike": { "s3:prefix": "AWSLogs/*" } }
    },
    {
      "Sid": "CxMInPlaceGetBucketLocation000000000000",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::000000000000:root" },
      "Action": "s3:GetBucketLocation",
      "Resource": "arn:aws:s3:::example-log-bucket"
    }
  ]
}
```

For the KMS key, set `InPlaceQueryKmsKeyArn` on the root stack — it creates a KMS grant for the CXM account, no key-policy edit.

Points to keep when you merge the bucket statements:

- **Keep the three bucket statements separate.** `s3:GetBucketLocation` does not support the `s3:prefix` condition key, so folding it in with `s3:ListBucket` makes AWS reject the whole policy as `MalformedPolicy`. A rejected `put-bucket-policy` leaves the previous policy in place, which looks like success — always read the policy back afterwards.
- **Do not add an `aws:CalledVia` condition.** Athena does not populate `aws:CalledVia` on its scan requests, so the condition denies the very queries you are enabling.
- **The principal is the CXM account, not a role.** Access is narrowed by object prefix instead. Our submitting roles are named per tenant and per service, so naming them would break your policy every time one is renamed.
- **The KMS grant covers `Decrypt` only.** `GenerateDataKey` is write-side; in-place querying only ever decrypts.
- **Keep the account id in each `Sid`.** It is what lets a second CXM environment's statements sit alongside these. S3 does accept two statements sharing a `Sid`, but nothing can tell them apart afterwards, so revoking one reader would mean rewriting the other's grant.

### Several CXM environments reading one bucket

CXM may read the same bucket from more than one account — a staging environment alongside production, for example. Pass the second one:

```bash
    ParameterKey=AdditionalCXMCustomerAccountId,ParameterValue=<SECOND_CXM_ACCOUNT_ID> \
    ParameterKey=AdditionalCXMExternalId,ParameterValue=<SECOND_EXTERNAL_ID> \
```

The reader role then trusts both accounts — one trust statement each, because a single `StringEquals` holding two external IDs is an OR that would let either account in with either ID — and the rendered statements cover both readers, `Sid`-suffixed per account.

`AdditionalCXMExternalId` is mandatory once the account is set: the stack refuses to deploy without it rather than render a trust statement conditioned on an empty external ID, which nothing could satisfy. More than two readers needs the Terraform module, which takes a list.

The same statements are produced by the Terraform onboarding module, so the two routes grant identical access.

## Updating

When CXM provides updated templates or you need to change parameters:

```bash
# Update the root stack
aws cloudformation update-stack \
  --stack-name CxmIntegrationStack-Main \
  --template-body file://cxm-integration-aws-root.yaml \
  --parameters file://params-cxm-root.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $CUR_REGION

aws cloudformation wait stack-update-complete \
  --stack-name CxmIntegrationStack-Main \
  --region $CUR_REGION

# Update the StackSet
aws cloudformation update-stack-set \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --template-body file://cxm-integration-aws-sub-account.yaml \
  --parameters file://params-cxm-sub-accounts.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
  --region $CUR_REGION

# Update existing instances (after the StackSet update finishes)
aws cloudformation update-stack-instances \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --deployment-targets OrganizationalUnitIds='["ou-xxxx-xxxxxxxx"]' \
  --regions us-east-1 us-east-2 eu-west-1 \
  --operation-preferences FailureTolerancePercentage=100,MaxConcurrentPercentage=50 \
  --region $CUR_REGION
```

## Uninstalling

Remove resources in reverse order — instances first, then the StackSet, then the root stack:

```bash
# Delete all StackSet instances
aws cloudformation delete-stack-instances \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --deployment-targets OrganizationalUnitIds='["ou-xxxx-xxxxxxxx"]' \
  --regions us-east-1 us-east-2 eu-west-1 \
  --no-retain-stacks \
  --region $CUR_REGION

# Wait for instances to be deleted, then delete the StackSet
aws cloudformation delete-stack-set \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --region $CUR_REGION

# Delete the root stack
aws cloudformation delete-stack \
  --stack-name CxmIntegrationStack-Main \
  --region $CUR_REGION

aws cloudformation wait stack-delete-complete \
  --stack-name CxmIntegrationStack-Main \
  --region $CUR_REGION
```

If you deployed EKS stacks, delete those separately:

```bash
aws cloudformation delete-stack \
  --stack-name CxmEksAccess-<CLUSTER_NAME> \
  --region <CLUSTER_REGION>
```

## Helper Scripts

Wrapper scripts are provided for convenience. They accept `--target-organizational-units` and `--target-regions` flags, defaulting to the root OU and all active regions when omitted.

| Script | Action |
|--------|--------|
| `create_stack.sh` | Creates the root stack, StackSet, and instances |
| `update_stack.sh` | Updates the root stack, StackSet, and instances |
| `delete_stack.sh` | Deletes instances, StackSet, and root stack |

Usage:

```bash
# Login to your management account
AWS_PROFILE=my-root aws sso login

# Create (defaults to root OU + all regions)
AWS_PROFILE=my-root AWS_REGION=us-east-1 ./create_stack.sh

# Or specify targets explicitly
AWS_PROFILE=my-root AWS_REGION=us-east-1 ./create_stack.sh \
  --target-organizational-units "ou-xxxx-xxxxxxxx" \
  --target-regions "us-east-1 us-east-2 eu-west-1"

# Update
AWS_PROFILE=my-root AWS_REGION=us-east-1 ./update_stack.sh \
  --target-organizational-units "ou-xxxx-xxxxxxxx" \
  --target-regions "us-east-1 us-east-2 eu-west-1"

# Delete
AWS_PROFILE=my-root AWS_REGION=us-east-1 ./delete_stack.sh \
  --target-organizational-units "ou-xxxx-xxxxxxxx" \
  --target-regions "us-east-1 us-east-2 eu-west-1"
```
