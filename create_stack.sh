#!/bin/bash

get_root_ou() {
  ROOT_OU=$(aws organizations list-roots --query "Roots[0].Id" --output text)
  echo "$ROOT_OU"
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --target-organizational-units)
      if [[ -n "$2" && "$2" != --* ]]; then
        TARGET_ORGANIZATIONAL_UNITS=$2
        shift 2
      else
        echo "Error: --target-organizational-units requires a value."
        exit 1
      fi
      ;;
    --target-regions)
      if [[ -n "$2" && "$2" != --* ]]; then
        TARGET_REGIONS=$2
        shift 2
      else
        echo "Error: --target-regions requires a value."
        exit 1
      fi
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$TARGET_ORGANIZATIONAL_UNITS" ]]; then
  TARGET_ORGANIZATIONAL_UNITS=$(get_root_ou)
  echo "Info: --target-organizational-units not provided. Using Root OU ${TARGET_ORGANIZATIONAL_UNITS} instead."
else
  echo "Info: deploying to OUs ${TARGET_ORGANIZATIONAL_UNITS}"
fi

if [[ -z "$TARGET_REGIONS" ]]; then
  TARGET_REGIONS=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text)
  echo "Info: --target-regions not provided. Using default ${TARGET_REGIONS} instead."
else
  echo "Info: deploying to regions ${TARGET_REGIONS}"
fi

# root stack
aws cloudformation create-stack \
  --stack-name CxmIntegrationStack-Main \
  --template-body file://cxm-integration-aws-root.yaml \
  --parameters file://params-cxm-root-example.json \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete \
  --stack-name CxmIntegrationStack-Main

# sub accounts stack-set
aws cloudformation create-stack-set \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --template-body file://cxm-integration-aws-sub-account.yaml \
  --parameters file://params-cxm-sub-accounts-example.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment "Enabled=true,RetainStacksOnAccountRemoval=false"

aws cloudformation create-stack-instances \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --deployment-targets "OrganizationalUnitIds=${TARGET_ORGANIZATIONAL_UNITS}" \
  --operation-preferences "FailureToleranceCount=0,MaxConcurrentCount=5" \
  --regions ${TARGET_REGIONS}


# Display CloudFormation stack outputs
STACK_OUTPUT=$(aws cloudformation describe-stacks \
  --stack-name CxmIntegrationStack-Main \
  --query "Stacks[0].Outputs" \
  --output json)

echo "CloudFormation Stack Outputs:"
echo "$STACK_OUTPUT"

# Display StackSet outputs
STACKSET_OUTPUT=$(aws cloudformation describe-stack-set \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --query "StackSet" \
  --output json)

echo "CloudFormation StackSet Outputs:"
echo "$STACKSET_OUTPUT"
