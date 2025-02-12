# Cloud ex Machina - AWS Integration using Cloudformation

This project consists in one cloudformation stack and one stackset to apply to your AWS cloud organization.
It will allow CXM to access only the data it needs, and setup key notifications (CUR file creation, changes in organization) that drive CxM's platform.

## How to

1. Update the `params-cxm-root-example.json` & `params-cxm-root-sub-accounts-example.json` file with the parameter values CXM provided and your data
2. Select the target OUs and regions in your AWS organizations. If you don't select any, the script will default to the root OU and all currently active regions in your root account.
3. Login as an admin user of the management account of the organization.
   ```bash
   AWS_PROFILE=my-root aws sso login
   ```
4. Connect to AWS in your terminal, then launch the following command :
   ```
   AWS_PROFILE=my-root AWS_REGION=us-east-1 ./create_stack.sh --target-organizational-units "unit-1 unit-2" --target-regions "us-east-1 us-east-2"
   ```
   Alternatively you can use the script without any arguments to use default values:
   ```
   AWS_PROFILE=my-root AWS_REGION=us-east-1 ./create_stack.sh
   ```
5. Check the status of the `CxmIntegrationStack-Main` Cloudformation Stack on AWS console.
6. Check the status of the `CxmIntegrationStack-SubAccounts` Cloudformation Stack-SET on AWS console.
7. Confirm with CXM by dropping us a line.
8. If needed, you can update the stack with
   ```
   AWS_PROFILE=my-root AWS_REGION=us-east-1 ./update_stack.sh --target-organizational-units "unit-1 unit-2" --target-regions "us-east-1 us-east-2"
   ```
9. Send CxM the JSON outputs displayed on your terminal
