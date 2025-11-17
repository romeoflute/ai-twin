#!/bin/bash
set -e

echo "🔥 Starting AWS Cleanup (Everything except IAM)..."

##############################################
# 1️⃣ Delete ALL Lambda functions
##############################################
echo "🧹 Deleting Lambda functions..."
LAMBDA_LIST=$(aws lambda list-functions --query "Functions[].FunctionName" --output text)
for fn in $LAMBDA_LIST; do
    echo "  - Deleting Lambda: $fn"
    aws lambda delete-function --function-name "$fn"
done


##############################################
# 2️⃣ Delete ALL API Gateway REST APIs
##############################################
echo "🧹 Deleting API Gateway REST APIs..."
REST_APIS=$(aws apigateway get-rest-apis --query "items[].id" --output text)
for api in $REST_APIS; do
    echo "  - Deleting REST API: $api"
    aws apigateway delete-rest-api --rest-api-id "$api"
done

##############################################
# 3️⃣ Delete ALL API Gateway HTTP APIs (v2)
##############################################
echo "🧹 Deleting API Gateway HTTP/WebSocket APIs..."
HTTP_APIS=$(aws apigatewayv2 get-apis --query "Items[].ApiId" --output text)
for api in $HTTP_APIS; do
    echo "  - Deleting HTTP/WebSocket API: $api"
    aws apigatewayv2 delete-api --api-id "$api"
done


##############################################
# 4️⃣ Delete ALL CloudFront Distributions
##############################################
echo "🧹 Deleting CloudFront distributions..."
DISTROS=$(aws cloudfront list-distributions --query "DistributionList.Items[].Id" --output text)
for d in $DISTROS; do
    echo "  - Disabling distribution: $d"
    E_ID=$d
    CF_CONFIG=$(aws cloudfront get-distribution-config --id $E_ID)

    # Extract ETag
    ETAG=$(echo "$CF_CONFIG" | jq -r '.ETag')

    # Disable distribution
    DIST_CONFIG=$(echo "$CF_CONFIG" | jq '.DistributionConfig.Enabled = false')
    aws cloudfront update-distribution \
        --id $E_ID \
        --if-match $ETAG \
        --distribution-config "$DIST_CONFIG" > /dev/null

    echo "    Waiting for disable to propagate..."
    aws cloudfront wait distribution-deployed --id $E_ID

    echo "  - Deleting distribution: $E_ID (may take time)"
    aws cloudfront delete-distribution --id $E_ID --if-match $ETAG || true
done


##############################################
# 5️⃣ Delete ALL S3 buckets
##############################################
echo "🧹 Deleting S3 buckets..."
BUCKETS=$(aws s3api list-buckets --query "Buckets[].Name" --output text)
for b in $BUCKETS; do
    echo "  - Emptying and deleting bucket: $b"
    aws s3 rm "s3://$b" --recursive || true
    aws s3 rb "s3://$b" --force || true
done


##############################################
# 6️⃣ Delete CloudWatch Log Groups
##############################################
echo "🧹 Deleting CloudWatch Log Groups..."
LOGS=$(aws logs describe-log-groups --query "logGroups[].logGroupName" --output text)
for lg in $LOGS; do
    echo "  - Deleting log group: $lg"
    aws logs delete-log-group --log-group-name "$lg" || true
done


##############################################
# 7️⃣ Delete ECR Repositories (optional)
##############################################
echo "🧹 Deleting ECR Repositories..."
ECRS=$(aws ecr describe-repositories --query "repositories[].repositoryName" --output text)
for repo in $ECRS; do
    echo "  - Deleting ECR repo: $repo"
    aws ecr delete-repository --repository-name "$repo" --force || true
done


##############################################
# OPTIONAL: Delete custom IAM roles like twin-*
##############################################
echo "🧹 Deleting IAM custom project roles (twin-*)..."
ROLES=$(aws iam list-roles --query "Roles[].RoleName" --output text)
for role in $ROLES; do
    if [[ "$role" == twin-* ]]; then
        echo "  - Deleting IAM role: $role"
        aws iam delete-role --role-name "$role" || true
    fi
done

echo "🎉 AWS Cleanup COMPLETE! Account reset except IAM."
