#!/usr/bin/env bash
# Deletes everything this lab created in AWS. Run with: ./teardown.sh
set -u
NAME=pollie-flashvote
aws sts get-caller-identity >/dev/null 2>&1 || { echo "No working AWS credentials." >&2; exit 1; }
echo "Deleting the HTTP API..."
for id in $(aws apigatewayv2 get-apis --query "Items[?Name=='$NAME'].ApiId" --output text); do aws apigatewayv2 delete-api --api-id "$id" && echo "  deleted API $id"; done
echo "Deleting the Lambda function and its log group..."
aws lambda delete-function --function-name $NAME 2>/dev/null && echo "  deleted function"
aws logs delete-log-group --log-group-name /aws/lambda/$NAME 2>/dev/null && echo "  deleted log group"
echo "Deleting the IAM role(s)..."
for role in $(aws iam list-roles --query "Roles[?starts_with(RoleName, '$NAME')].RoleName" --output text); do
  for p in $(aws iam list-role-policies --role-name "$role" --query PolicyNames --output text); do aws iam delete-role-policy --role-name "$role" --policy-name "$p"; done
  for a in $(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$role" --policy-arn "$a"
    case "$a" in arn:aws:iam::aws:*) ;; *) aws iam delete-policy --policy-arn "$a" 2>/dev/null;; esac
  done
  aws iam delete-role --role-name "$role" && echo "  deleted role $role"
done
echo "Deleting the DynamoDB table..."
aws dynamodb delete-table --table-name $NAME >/dev/null 2>&1 && aws dynamodb wait table-not-exists --table-name $NAME && echo "  deleted table"
echo "Done. Now run ./verify-teardown.sh"
