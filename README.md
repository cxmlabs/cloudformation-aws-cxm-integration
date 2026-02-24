# Cloud ex Machina — AWS Integration (CloudFormation)

This project deploys CloudFormation stacks that grant CXM cross-account read access to your AWS Organization and set up EventBridge notifications that drive CXM's optimization platform.

## Templates

| Template | Type | Purpose |
|----------|------|---------|
| `cxm-integration-aws-root.yaml` | Stack | Deploys to the management account: organization crawler role, CUR reader role, and EventBridge notification rules |
| `cxm-integration-aws-sub-account.yaml` | StackSet | Deploys to member accounts: asset crawler role and EventBridge CloudFormation notifier |
| `cxm-integration-aws-eks.yaml` | Stack | Optional — Grants CXM read-only access to an EKS cluster via Access Entries (deploy once per cluster) |

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
| `ManagementAccountId` | Yes | — | Your 12-digit AWS Organizations management account ID (where CXM roles are created) |
| `CostAndUsageReportS3BucketName` | Yes | — | S3 bucket name storing your CUR data (bucket name only, not the ARN — e.g. `my-cur-bucket`) |
| `CostAndUsageReportS3BucketKmsKeyArn` | No | `""` | KMS key ARN if your CUR bucket is encrypted (e.g. `arn:aws:kms:us-east-1:123456789012:key/...`) |
| `CostAndUsageBucketRegion` | No | `us-east-1` | Region of the CUR S3 bucket |
| `ManagementRegion` | No | `us-east-1` | Region where IAM roles are created |
| `Prefix` | No | `cxm` | Namespace prefix for resource names |
| `RoleSuffix` | No | `""` | Optional suffix appended to IAM role names |

### Sub-Account StackSet (`params-cxm-sub-accounts.json`)

> **Important:** This StackSet must be deployed to all member accounts in your organization for CXM to have visibility into their resources. Without it, CXM can only see assets in the management account.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `CXMExternalId` | Yes | — | External ID provided by CXM (same as root) |
| `CXMCustomerAccountId` | Yes | — | 12-digit CXM AWS account ID provided by CXM (same as root) |
| `ManagementAccountId` | Yes | — | Your 12-digit AWS Organizations management account ID |
| `ManagementRegion` | No | `us-east-1` | Region where roles are created |
| `Prefix` | No | `cxm` | Namespace prefix for resource names |
| `RoleSuffix` | No | `""` | Optional suffix appended to IAM role names |

### EKS Stack (inline parameters)

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `ClusterName` | Yes | — | Name of the EKS cluster |
| `PrincipalArn` | Yes | — | IAM role ARN of the CXM role (from root stack outputs, e.g. `arn:aws:iam::123456789012:role/cxm-organization-crawler`) |
| `AccessScopeType` | No | `cluster` | `cluster` for full access, `namespace` to restrict |
| `AccessScopeNamespaces` | No | `""` | Comma-separated namespaces (only when type is `namespace`) |
| `KubernetesGroups` | No | `""` | Comma-separated Kubernetes groups for the access entry |
| `Prefix` | No | `cxm` | Namespace prefix for resource names |

## Deployment

### 1. Configure Parameters

```bash
cp params-cxm-root-example.json params-cxm-root.json
cp params-cxm-sub-accounts-example.json params-cxm-sub-accounts.json
```

Edit both files and fill in the values provided by CXM.

### 2. Deploy the Root Stack

```bash
aws cloudformation create-stack \
  --stack-name CxmIntegrationStack-Main \
  --template-body file://cxm-integration-aws-root.yaml \
  --parameters file://params-cxm-root.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

aws cloudformation wait stack-create-complete \
  --stack-name CxmIntegrationStack-Main \
  --region us-east-1
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
  --region us-east-1

# Deploy instances to your OUs and regions
aws cloudformation create-stack-instances \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --deployment-targets OrganizationalUnitIds='["ou-xxxx-xxxxxxxx"]' \
  --regions us-east-1 us-east-2 eu-west-1 \
  --operation-preferences FailureTolerancePercentage=100,MaxConcurrentPercentage=50 \
  --region us-east-1
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

### 5. Verify & Share Outputs

Retrieve the root stack outputs and share them with CXM to complete the integration:

```bash
aws cloudformation describe-stacks \
  --stack-name CxmIntegrationStack-Main \
  --query "Stacks[0].Outputs" \
  --output json \
  --region us-east-1
```

## Updating

When CXM provides updated templates or you need to change parameters:

```bash
# Update the root stack
aws cloudformation update-stack \
  --stack-name CxmIntegrationStack-Main \
  --template-body file://cxm-integration-aws-root.yaml \
  --parameters file://params-cxm-root.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

aws cloudformation wait stack-update-complete \
  --stack-name CxmIntegrationStack-Main \
  --region us-east-1

# Update the StackSet
aws cloudformation update-stack-set \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --template-body file://cxm-integration-aws-sub-account.yaml \
  --parameters file://params-cxm-sub-accounts.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
  --region us-east-1

# Update existing instances (after the StackSet update finishes)
aws cloudformation update-stack-instances \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --deployment-targets OrganizationalUnitIds='["ou-xxxx-xxxxxxxx"]' \
  --regions us-east-1 us-east-2 eu-west-1 \
  --operation-preferences FailureTolerancePercentage=100,MaxConcurrentPercentage=50 \
  --region us-east-1
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
  --region us-east-1

# Wait for instances to be deleted, then delete the StackSet
aws cloudformation delete-stack-set \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --region us-east-1

# Delete the root stack
aws cloudformation delete-stack \
  --stack-name CxmIntegrationStack-Main \
  --region us-east-1

aws cloudformation wait stack-delete-complete \
  --stack-name CxmIntegrationStack-Main \
  --region us-east-1
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
