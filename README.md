# Cloud ex Machina - AWS Integration using CloudFormation

This project provides CloudFormation templates to integrate your AWS Organization with the CXM platform. It grants CXM the access it needs to optimize your cloud infrastructure, and sets up EventBridge notifications that drive CXM's platform.

## Templates Overview

| Template | Type | Purpose |
|----------|------|---------|
| `cxm-integration-aws-root.yaml` | Stack | Deploys to the management account: organization crawler role, CUR reader role, and EventBridge notification rules |
| `cxm-integration-aws-sub-account.yaml` | StackSet | Deploys to member accounts: asset crawler role and EventBridge CloudFormation notifier |
| `cxm-integration-aws-eks.yaml` | Stack | Optional — Grants CXM read-only access to an EKS cluster via Access Entries (deploy once per cluster) |

## Manual Deployment

If you prefer to deploy manually via the AWS Console or CLI without using the provided scripts, follow these steps.

### Prerequisites

1. Copy and customize the parameter files:
   ```bash
   cp params-cxm-root-example.json params-cxm-root.json
   cp params-cxm-sub-accounts-example.json params-cxm-sub-accounts.json
   ```
2. Update both files with the values provided by CXM and your AWS configuration.

### Step 1: Deploy the Root Stack (Management Account)

Deploy `cxm-integration-aws-root.yaml` as a CloudFormation **Stack** in your management account.

**Via AWS Console:**
1. Navigate to CloudFormation > Stacks > Create stack
2. Upload `cxm-integration-aws-root.yaml`
3. Enter the parameters from `params-cxm-root.json`
4. Name the stack (e.g., `CxmIntegrationStack-Main`)
5. Acknowledge IAM resource creation and create the stack

**Via AWS CLI:**
```bash
aws cloudformation create-stack \
  --stack-name CxmIntegrationStack-Main \
  --template-body file://cxm-integration-aws-root.yaml \
  --parameters file://params-cxm-root.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

### Step 2: Deploy the Sub-Accounts StackSet

Deploy `cxm-integration-aws-sub-account.yaml` as a CloudFormation **StackSet** to your organization's member accounts.

**Via AWS Console:**
1. Navigate to CloudFormation > StackSets > Create StackSet
2. Choose "Service-managed permissions" (recommended for Organizations)
3. Upload `cxm-integration-aws-sub-account.yaml`
4. Enter the parameters from `params-cxm-sub-accounts.json`
5. Name the StackSet (e.g., `CxmIntegrationStack-SubAccounts`)
6. Select deployment targets:
   - Choose "Deploy to organizational units (OUs)" or specific accounts
   - Select target regions (all regions where you have resources)
7. Configure deployment options (concurrent accounts, failure tolerance)
8. Acknowledge IAM resource creation and create the StackSet

**Via AWS CLI:**
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

# Create stack instances in target OUs and regions
aws cloudformation create-stack-instances \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --deployment-targets OrganizationalUnitIds=ou-xxxx-xxxxxxxx \
  --regions us-east-1 us-east-2 eu-west-1 \
  --operation-preferences FailureTolerancePercentage=100,MaxConcurrentPercentage=50 \
  --region us-east-1
```

### Step 3: Deploy EKS Access (Optional)

If you run EKS clusters and want CXM to have read-only Kubernetes visibility, deploy the `cxm-integration-aws-eks.yaml` template **once per cluster**.

This template uses the EKS Access Entry API (available on clusters running Platform version `eks.14+` or created after October 2023). For older clusters using the `aws-auth` ConfigMap, you must first upgrade the cluster's authentication mode:

```bash
aws eks update-cluster-config \
  --name <CLUSTER_NAME> \
  --access-config authenticationMode=API_AND_CONFIG_MAP
```

**Via AWS CLI:**
```bash
aws cloudformation create-stack \
  --stack-name CxmEksAccess-<CLUSTER_NAME> \
  --template-body file://cxm-integration-aws-eks.yaml \
  --parameters \
    ParameterKey=ClusterName,ParameterValue=<CLUSTER_NAME> \
    ParameterKey=PrincipalArn,ParameterValue=<CXM_ROLE_ARN> \
  --region <CLUSTER_REGION>
```

Where `<CXM_ROLE_ARN>` is the `CxmOrganizationCrawlerRoleArn` or `CxmAssetCrawlerRoleArn` from the stack outputs.

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

### Step 4: Verify and Share Outputs

1. Check the root stack outputs in the CloudFormation console
2. Verify StackSet instances are deployed successfully across accounts
3. Share the stack outputs with CXM to complete the integration

---

## Scripted Deployment

For automated deployment using the provided scripts, follow these steps.

1. Copy and customize the parameter files:
   ```bash
   cp params-cxm-root-example.json params-cxm-root.json
   cp params-cxm-sub-accounts-example.json params-cxm-sub-accounts.json
   ```
2. Update both files with the values provided by CXM and your AWS configuration.
3. Select the target OUs and regions in your AWS organizations. If you don't select any, the script will default to the root OU and all currently active regions in your root account.
4. Login as an admin user of the management account of the organization.
   ```bash
   AWS_PROFILE=my-root aws sso login
   ```
5. Connect to AWS in your terminal, then launch the following command:
   ```
   AWS_PROFILE=my-root AWS_REGION=us-east-1 ./create_stack.sh --target-organizational-units "unit-1 unit-2" --target-regions "us-east-1 us-east-2"
   ```
   Alternatively you can use the script without any arguments to use default values:
   ```
   AWS_PROFILE=my-root AWS_REGION=us-east-1 ./create_stack.sh
   ```
6. Check the status of the `CxmIntegrationStack-Main` CloudFormation Stack on AWS console.
7. Check the status of the `CxmIntegrationStack-SubAccounts` CloudFormation StackSet on AWS console.
8. Confirm with CXM by dropping us a line.
9. If needed, you can update the stack with
   ```
   AWS_PROFILE=my-root AWS_REGION=us-east-1 ./update_stack.sh --target-organizational-units "unit-1 unit-2" --target-regions "us-east-1 us-east-2"
   ```
10. Send CXM the JSON outputs displayed on your terminal.
