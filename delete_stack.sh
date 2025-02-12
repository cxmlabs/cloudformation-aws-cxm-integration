#!/bin/bash

ORG_UNIT="r-abcd"


aws cloudformation delete-stack-instances \
  --stack-set-name CxmIntegrationStack-SubAccounts \
  --deployment-targets "OrganizationalUnitIds=${ORG_UNIT}" \
  --operation-preferences "FailureToleranceCount=0,MaxConcurrentCount=5" \
  --regions "us-east-1" "us-east-2" "us-west-1" "us-west-2" "eu-west-1" "eu-west-2" "eu-west-3" \
  --no-retain-stacks


# sub accounts stack-set
aws cloudformation delete-stack-set \
  --stack-set-name CxmIntegrationStack-SubAccounts

# root stack
aws cloudformation delete-stack \
  --stack-name CxmIntegrationStack-Main