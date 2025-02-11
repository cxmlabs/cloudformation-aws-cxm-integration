
# Cloud ex Machina - AWS Integration using Cloudformation 

This project consists in one cloudformation stack and one stackset to apply to your AWS cloud organization.
It will allow CXM to access only the data it needs, and will setup basic events to notify CXM of some events (CUR file creation, changes in organization).


## How to

1. Update the `params-cxm-root-example.json` & `params-cxm-root-sub-accounts-example.json` file with the parameter values CXM provided and your data
2. Edit `create_stack.sh` & `update_stack` to replace the ORG_UNIT with the value of your root AWS Organization Unit
3. Connect to AWS in your terminal, then launch the following command :
    ```
    ./create_stack.sh
    ```
4. Check the status of the `CxmIntegrationStack-Main` Cloudformation Stack on AWS console.
5. Check the status of the `CxmIntegrationStack-SubAccounts` Cloudformation Stack-SET on AWS console.
6. Confirm with CXM by dropping us a line.
7. If needed, you can update the stack with
    ```
    ./update_stack.sh
    ```

Note : as you can see in the stack_create.sh script, the cloudformation root stack is to be executed prior the sub-account stack-set as the latter makes use of elements created by the root stack.