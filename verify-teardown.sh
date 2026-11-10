#!/usr/bin/env bash
# Proves the AWS resources of this lab are gone. Run with: ./verify-teardown.sh
set -u
NAME=pollie-flashvote
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || { echo "No working AWS credentials." >&2; exit 1; }
REGION=$(aws configure get region 2>/dev/null); REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-${REGION:-us-east-1}}}
echo "Checking account $ACCOUNT, region $REGION"
pass=0; failn=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS  $d"; pass=$((pass+1)); else echo "FAIL  $d"; failn=$((failn+1)); fi; }
empty() { [ -z "$(eval "$1")" ] || [ "$(eval "$1")" = None ]; }
check "no HTTP API named $NAME" empty "aws apigatewayv2 get-apis --query \"Items[?Name=='$NAME'].ApiId\" --output text"
check "no Lambda function $NAME" bash -c "! aws lambda get-function --function-name $NAME >/dev/null 2>&1"
check "no log group /aws/lambda/$NAME" empty "aws logs describe-log-groups --log-group-name-prefix /aws/lambda/$NAME --query 'logGroups[].logGroupName' --output text"
check "no IAM role starting with $NAME" empty "aws iam list-roles --query \"Roles[?starts_with(RoleName, '$NAME')].RoleName\" --output text"
check "no customer managed IAM policy starting with $NAME" empty "aws iam list-policies --scope Local --query \"Policies[?starts_with(PolicyName, '$NAME')].PolicyName\" --output text"
check "no DynamoDB table $NAME" bash -c "! aws dynamodb describe-table --table-name $NAME >/dev/null 2>&1"
echo
if [ "$failn" -eq 0 ]; then echo "TEARDOWN VERIFIED ($pass/$pass) in account $ACCOUNT"; else echo "NOT CLEAN: $failn leftover(s). Delete them (console or CLI) and run this again."; fi
exit "$failn"
