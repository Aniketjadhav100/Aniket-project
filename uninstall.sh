#!/bin/bash

set -e

# Load configuration
source config.env

echo "=== Searching for EC2 Instances with tag Name = $INSTANCE_NAME ==="

INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" \
              "Name=instance-state-name,Values=running,stopped" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text --region "$AWS_REGION")

if [ -z "$INSTANCE_IDS" ]; then
    echo "No EC2 instances found."
else
    echo "Terminating EC2 instances: $INSTANCE_IDS"
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region "$AWS_REGION"
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region "$AWS_REGION"
    echo "EC2 termination complete."
fi

echo "=== Deleting Security Group: $SECURITY_GROUP_NAME ==="

SG_ID=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values="$SECURITY_GROUP_NAME" \
    --query "SecurityGroups[0].GroupId" --output text --region "$AWS_REGION" 2>/dev/null)

if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
    echo "Deleting Security Group: $SG_ID"
    aws ec2 delete-security-group --group-id "$SG_ID" --region "$AWS_REGION"
else
    echo "Security group not found."
fi

echo "=== Deleting Key Pair: $KEY_NAME ==="
aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$AWS_REGION" || true

if [ -f "${KEY_NAME}.pem" ]; then
    rm -f "${KEY_NAME}.pem"
    echo "Deleted local key file: ${KEY_NAME}.pem"
else
    echo "Local key file not found, skipping."
fi

echo "=== Deleting all S3 Buckets starting with prefix: $BUCKET_PREFIX ==="

BUCKETS=$(aws s3api list-buckets \
    --query "Buckets[*].Name" --output text | tr '\t' '\n' | grep "^$BUCKET_PREFIX" || true)

if [ -z "$BUCKETS" ]; then
    echo "No S3 buckets found with prefix $BUCKET_PREFIX."
else
    for BUCKET in $BUCKETS; do
        echo "Deleting bucket: $BUCKET"
        aws s3 rm "s3://$BUCKET" --recursive --region "$AWS_REGION"
        aws s3api delete-bucket --bucket "$BUCKET" --region "$AWS_REGION"
    done
fi

echo "=== Cleanup Summary ==="
echo "EC2 Instances Deleted: $INSTANCE_IDS"
echo "Security Group Deleted: $SG_ID"
echo "Key Pair Deleted: $KEY_NAME"
echo "Buckets Deleted:"
echo "$BUCKETS"

echo "Cleanup completed successfully."
