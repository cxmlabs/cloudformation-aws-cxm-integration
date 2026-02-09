# CloudFormation AWS CXM Integration — Feature Description & Terraform Comparison

## Overview

This repo provides CloudFormation templates that grant the CXM SaaS platform cross-account access to a customer's AWS Organization. It uses a **root stack** (management account) + **StackSet** (member accounts) pattern, with an optional **EKS access entry** template.

---

## Architecture: Role Trust Chain

```
CXM Account (external)
  |
  +- AssumeRole --> Organization Crawler Role  (mgmt account)
  |                    |
  |                    +- chain AssumeRole --> Asset Crawler Role  (each member account)
  |
  +- AssumeRole --> CUR Reader Role  (mgmt account, CUR bucket region)

EventBridge (AWS service)
  +- AssumeRole --> Notification Role (mgmt) --> CXM data-plane + control-plane buses
  +- AssumeRole --> Notification Role (members) --> CXM control-plane bus

EKS Access Entry (optional, per-cluster)
  +- CXM Role --> EKS AccessEntry (AmazonEKSAdminViewPolicy, read-only)
```

All cross-account AssumeRole calls are protected by an **External ID** condition.

---

## Feature 1: Organization-Level Crawling (root template)

**Role**: `{prefix}-organization-crawler{suffix}`
**Deployed to**: Management account, management region only

| Capability | Details |
|---|---|
| **Org read-only** | `AWSOrganizationsReadOnlyAccess` managed policy |
| **General read-only** | `ReadOnlyAccess` managed policy |
| **SSO read-only** | Inline: `sso-directory:*`, `sso:List/Get*`, `identitystore:Describe/List*` |
| **Cost Explorer** | Inline: `ce:Describe*`, `ce:Get*`, `ce:List*` |
| **CUR report definitions** | Inline: `cur:DescribeReportDefinitions`, `cur:ModifyReportDefinition`, `cur:PutReportDefinition` |
| **BCM Data Exports** | Inline: `bcm-data-exports:List*`, `bcm-data-exports:Get*` |
| **Cost Optimization Hub** | Inline: `cost-optimization-hub:List*`, `cost-optimization-hub:Get*` |
| **Service Quotas** | `ServiceQuotasFullAccess` managed policy |
| **Commitment management** | Full reservation management: Purchase/Modify/Cancel/Exchange RIs for EC2, RDS, Redshift, ElastiCache, OpenSearch, MemoryDB, DynamoDB |
| **Savings Plans** | `AWSSavingsPlansFullAccess` managed policy + `savingsplans:*` inline |
| **Chain assume** | Can assume any `{prefix}*` role in any member account |
| **Data plane deny** | Explicit deny on data-plane APIs |

---

## Feature 2: Cost and Usage Report Reading (root template)

**Role**: `{prefix}-cur-reader{suffix}`
**Deployed to**: Management account, CUR bucket region

| Capability | Details |
|---|---|
| **S3 bucket list** | `s3:ListBucket` on the specific CUR bucket |
| **S3 object read** | `s3:GetObject` on all objects in the CUR bucket |
| **KMS decrypt** | Conditional: `kms:Decrypt` + `kms:GenerateDataKey` scoped to the specific KMS key ARN (only if KMS ARN parameter is provided) |

---

## Feature 3: Asset Crawling per Member Account (sub-account template)

**Role**: `{prefix}-asset-crawler{suffix}`
**Deployed to**: Every member account, management region (one role per account, IAM is global)

| Capability | Details |
|---|---|
| **General read-only** | `ReadOnlyAccess` managed policy |
| **Service Quotas** | `ServiceQuotasFullAccess` managed policy |
| **Savings Plans** | `AWSSavingsPlansFullAccess` managed policy |
| **Commitment management** | Same RI purchase/modify/cancel/exchange permissions as org crawler |
| **Data plane deny** | Same explicit deny list as org crawler |

**Trust**: Can be assumed by the organization crawler role from the management account (chain assumption). Also allows Lambda/ECS/CodeBuild service principals with External ID.

---

## Feature 4: EKS Cluster Enablement (standalone template, optional)

**Resource**: `AWS::EKS::AccessEntry`
**Deployed to**: Per EKS cluster, in the cluster's region

| Capability | Details |
|---|---|
| **EKS read-only** | `AmazonEKSAdminViewPolicy` access policy (view-only for all Kubernetes resources) |
| **Scope control** | Cluster-wide or namespace-scoped access |

Requires clusters with Access Entry API support (Platform version `eks.14+` or created after October 2023). Legacy clusters using `aws-auth` ConfigMap must upgrade their authentication mode first.

---

## Feature 5: EventBridge Notifications (both templates)

### Root template — 4 rules, management account only

| Rule | Trigger | Target Bus |
|---|---|---|
| **CUR bucket changes** | S3 Object Created/Deleted in CUR bucket | CXM `data-plane` |
| **Organization changes** | Any write CloudTrail call to Organizations API | CXM `control-plane` |
| **CXM role changes** | IAM CreateRole/DeleteRole where role name contains `*{prefix}*` | CXM `control-plane` |
| **StackSet status** | CloudFormation StackSet/StackInstance status changes | CXM `control-plane` |

### Sub-account template — 1 rule, deployed to ALL accounts and ALL regions

| Rule | Trigger | Target Bus |
|---|---|---|
| **CloudFormation notifier** | Stack/StackInstance status changes for resources matching `*{prefix}*` | CXM `control-plane` |

---

## Feature 6: Deployment Tooling

- `create_stack.sh` — Creates root stack + StackSet + instances. Auto-discovers root OU and all active regions if not specified.
- `update_stack.sh` — Updates existing stack + StackSet + instances.
- `delete_stack.sh` — Tears down instances, StackSet, and root stack.
- Auto-deployment enabled on StackSet: new accounts added to target OUs get the sub-account stack automatically.

---

## Comparison with Terraform Repo (`terraform-aws-cxm-integration`)

### Full Comparison Matrix

| Feature | CloudFormation | Terraform | Parity? |
|---|---|---|---|
| **Organization crawler role** | Yes | Yes | Yes |
| **Managed policies (Org, ReadOnly, SQ, SP)** | Yes | Yes | Yes |
| **Commitment management (RI/SP purchase)** | Yes | Yes | Yes |
| **SSO/Identity Store read** | Yes | Yes | Yes |
| **Cost Explorer read** | Yes | Yes | Yes |
| **Cost Optimization Hub read** | Yes | Yes | Yes |
| **BCM Data Exports read** | Yes | Yes | Yes |
| **CUR report definition read+write** | Yes | Yes | Yes |
| **Data plane explicit deny** | Yes | Yes | Yes |
| **Cross-account chain assume** | Yes | Yes | Yes |
| **CUR S3 bucket read** | Yes | Yes | Yes |
| **CUR KMS decrypt** | Yes | Yes | Yes |
| **EKS cluster enablement** | Yes | Yes | Yes (CFN uses Access Entries only; TF also supports aws-auth ConfigMap) |
| **Asset crawler (member accounts)** | Yes | Yes | Yes |
| **EventBridge: CUR changes** | Yes | Yes | Yes |
| **EventBridge: Org changes** | Yes | Yes | Yes |
| **EventBridge: IAM role changes** | Yes | Yes | Yes |
| **EventBridge: StackSet changes** | Yes | Yes | Yes |
| **EventBridge: CF stack changes (members)** | Yes | Yes | Yes |
| **External ID protection** | Yes | Yes | Yes |
| **Auto-deployment to new accounts** | Yes | Yes | Yes |
| **`sts:TagSession` on org crawler** | Yes | **NO** | Fix TF |
| **CloudTrail S3 bucket read** | **NO** | Yes | Add to CFN (future) |
| **S3 EventBridge notification enable** | **NO** | Yes | Add to CFN or document (future) |
| **Lone account mode** | **NO** | Yes | Add to CFN (future) |
| **Permission boundaries** | **NO** | Yes | Add to CFN (future) |
| **Resource tagging** | **NO** | Yes | Add to CFN (future) |
| **Dry-run / existing role** | **NO** | Yes | Low priority |
| **Lambda benchmarking** | Removed | Yes | Removed from CFN; consider removing from TF |

---

## Remaining Work (Future Iterations)

### Features to Add

1. **CloudTrail reader role** — mirror the CUR reader with `CloudTrailS3BucketName`, `CloudTrailS3BucketKmsKeyArn` parameters
2. **Lone account mode** — separate template or condition for single-account deployments
3. **Permission boundary support** — `PermissionBoundaryArn` parameter, conditionally applied to all roles
4. **Resource tagging** — `Tags` parameter applied to all IAM roles, policies, and EventBridge rules
5. **S3 EventBridge notification enablement** — document as prerequisite or add custom resource

### Terraform Fixes (other repo)

1. **Add `sts:TagSession`** to `terraform-aws-iam-role/main.tf` trust policy
2. **Add `ec2:DescribeAccountAttributes`** to `terraform-aws-account-enablement` CommitmentManagementPermissions
3. **Consider removing Lambda benchmarking** module to match CloudFormation simplification
