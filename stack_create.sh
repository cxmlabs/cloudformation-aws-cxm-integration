#!/bin/bash

ORG_UNIT="r-abcd"

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
  --deployment-targets "OrganizationalUnitIds=${ORG_UNIT}" \
  --operation-preferences "FailureToleranceCount=0,MaxConcurrentCount=5" \
  --regions "us-east-1" "us-east-2" "us-west-1" "us-west-2" "eu-west-1" "eu-west-2" "eu-west-3"
