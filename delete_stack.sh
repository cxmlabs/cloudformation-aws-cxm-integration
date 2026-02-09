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
  info "Deleting from OUs: $TARGET_ORGANIZATIONAL_UNITS"
fi

if [[ -z "$TARGET_REGIONS" ]]; then
  TARGET_REGIONS=$(aws ec2 describe-regions \
    --filters Name=opt-in-status,Values=opted-in,opt-in-not-required \
    --query "Regions[*].RegionName" \
    --output text) || error_exit "Failed to retrieve active AWS regions."
  info "--target-regions not provided. Using all available regions: $TARGET_REGIONS"
else
  info "Deleting from regions: $TARGET_REGIONS"
fi

# --------- Delete Stack Instances ---------
info "Deleting StackSet instances for OUs: $TARGET_ORGANIZATIONAL_UNITS in regions: $TARGET_REGIONS..."

aws cloudformation delete-stack-instances \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --deployment-targets "OrganizationalUnitIds=${TARGET_ORGANIZATIONAL_UNITS}" \
  --regions ${TARGET_REGIONS} \
  --no-retain-stacks \
  --operation-preferences "FailureToleranceCount=0,MaxConcurrentCount=5,RegionConcurrencyType=PARALLEL" || error_exit "Failed to delete StackSet instances."

info "Waiting for StackSet instances to be deleted (this may take several minutes)..."
sleep 60

# --------- Delete Stack Set ---------
info "Deleting StackSet..."

aws cloudformation delete-stack-set \
  --stack-set-name CxmIntegrationStack-SubAccounts || error_exit "Failed to delete StackSet."

success "StackSet deleted successfully."

# --------- Delete Root Stack ---------
info "Deleting root CloudFormation stack..."

aws cloudformation delete-stack \
  --stack-name CxmIntegrationStack-Main || error_exit "Failed to delete root stack."

info "Waiting for root stack deletion to complete..."
aws cloudformation wait stack-delete-complete \
  --stack-name CxmIntegrationStack-Main || error_exit "Root stack deletion did not complete successfully."

success "All CloudFormation resources deleted successfully."
