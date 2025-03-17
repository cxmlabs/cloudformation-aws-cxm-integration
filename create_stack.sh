#!/bin/bash

set -euo pipefail  # Exit on error, undefined variable, or pipeline failure

# --------- Utility Functions ---------
error_exit() {
  echo "❌ ERROR: $1" >&2
  exit 1
}

info() {
  echo "ℹ️ INFO: $1"
}

success() {
  echo "✅ SUCCESS: $1"
}

# --------- Get Root OU Function ---------
get_root_ou() {
  local ROOT_OU
  ROOT_OU=$(aws organizations list-roots --query "Roots[0].Id" --output text) || error_exit "Failed to retrieve Root OU."
  echo "$ROOT_OU"
}

# --------- Argument Parsing ---------
TARGET_ORGANIZATIONAL_UNITS=""
TARGET_REGIONS=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --target-organizational-units)
      if [[ -n "${2:-}" && "$2" != --* ]]; then
        TARGET_ORGANIZATIONAL_UNITS=$2
        shift 2
      else
        error_exit "--target-organizational-units requires a value."
      fi
      ;;
    --target-regions)
      if [[ -n "${2:-}" && "$2" != --* ]]; then
        TARGET_REGIONS=$2
        shift 2
      else
        error_exit "--target-regions requires a value."
      fi
      ;;
    *)
      error_exit "Unknown argument: $1"
      ;;
  esac
done

# --------- Set Defaults if Not Provided ---------
if [[ -z "$TARGET_ORGANIZATIONAL_UNITS" ]]; then
  TARGET_ORGANIZATIONAL_UNITS=$(get_root_ou)
  info "--target-organizational-units not provided. Using Root OU: $TARGET_ORGANIZATIONAL_UNITS"
else
  info "Deploying to OUs: $TARGET_ORGANIZATIONAL_UNITS"
fi

if [[ -z "$TARGET_REGIONS" ]]; then
  TARGET_REGIONS=$(aws ec2 describe-regions \
    --filters Name=opt-in-status,Values=opted-in,opt-in-not-required \
    --query "Regions[*].RegionName" \
    --output text) || error_exit "Failed to retrieve active AWS regions."
  info "--target-regions not provided. Using all available regions: $TARGET_REGIONS"
else
  info "Deploying to regions: $TARGET_REGIONS"
fi

# --------- Create Root Stack ---------
info "Creating root CloudFormation stack..."

aws cloudformation create-stack \
  --stack-name CxmIntegrationStack-Main \
  --template-body file://cxm-integration-aws-root.yaml \
  --parameters file://params-cxm-root-example.json \
  --capabilities CAPABILITY_NAMED_IAM || error_exit "Failed to create root stack."

info "Waiting for root stack creation to complete..."
aws cloudformation wait stack-create-complete \
  --stack-name CxmIntegrationStack-Main || error_exit "Root stack creation did not complete successfully."

success "Root stack created successfully."

# --------- Create Stack Set ---------
info "Creating StackSet for sub-accounts..."

aws cloudformation create-stack-set \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --template-body file://cxm-integration-aws-sub-account.yaml \
  --parameters file://params-cxm-sub-accounts-example.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment "Enabled=true,RetainStacksOnAccountRemoval=false" || error_exit "Failed to create StackSet."

success "StackSet created successfully."

# --------- Create Stack Instances ---------
info "Creating StackSet instances for OUs: $TARGET_ORGANIZATIONAL_UNITS in regions: $TARGET_REGIONS..."

aws cloudformation create-stack-instances \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --deployment-targets "OrganizationalUnitIds=${TARGET_ORGANIZATIONAL_UNITS}" \
  --operation-preferences "FailureToleranceCount=0,MaxConcurrentCount=5" \
  --regions ${TARGET_REGIONS} || error_exit "Failed to create StackSet instances."

success "StackSet instances created successfully."

# --------- Display Outputs ---------
info "Fetching root stack outputs..."
STACK_OUTPUT=$(aws cloudformation describe-stacks \
  --stack-name CxmIntegrationStack-Main \
  --query "Stacks[0].Outputs" \
  --output json) || error_exit "Failed to retrieve root stack outputs."

info "CloudFormation Stack Outputs:"
echo "$STACK_OUTPUT"

info "Fetching StackSet outputs..."
STACKSET_OUTPUT=$(aws cloudformation describe-stack-set \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --query "StackSet" \
  --output json) || error_exit "Failed to retrieve StackSet outputs."

info "CloudFormation StackSet Outputs:"
echo "$STACKSET_OUTPUT"

success "All CloudFormation resources created and configured successfully."