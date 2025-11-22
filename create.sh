#!/bin/bash

set -e

# Load configuration
source config.env

echo "=== Validating AWS CLI installation ==="
if ! command -v aws &> /dev/null; then
    echo "AWS CLI not installed! Install it first."
    exit 1
fi

echo "=== Validating AWS Credentials ==="
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Invalid AWS credentials! Configure using: aws configure"
    exit 1
fi

echo "=== Creating Key Pair ==="
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &> /dev/null; then
    echo "Key pair already exists: $KEY_NAME"
else
    aws ec2 create-key-pair --key-name "$KEY_NAME" --region "$AWS_REGION" \
    --query "KeyMaterial" --output text > "${KEY_NAME}.pem"
    chmod 400 "${KEY_NAME}.pem"
    echo "Created key pair: $KEY_NAME"
fi

echo "=== Creating Security Group ==="
SG_ID=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values="$SECURITY_GROUP_NAME" \
    --query "SecurityGroups[0].GroupId" --output text --region "$AWS_REGION" 2>/dev/null)

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then

    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "Auto SG" \
        --region "$AWS_REGION" \
        --query "GroupId" --output text)

    echo "Created security group: $SG_ID"

    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp --port 22 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"

else
    echo "Security group already exists: $SG_ID"
fi

echo "=== Creating EC2 Instance ==="
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" --output text)

echo "Instance created: $INSTANCE_ID"
echo "Waiting for Public IP..."

sleep 15

PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text --region "$AWS_REGION")

echo "Public IP: $PUBLIC_IP"

echo "=== Creating S3 Bucket ==="
RAND=$(date +%s)
BUCKET_NAME="${BUCKET_PREFIX}-${RAND}"

aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
echo "Bucket created: $BUCKET_NAME"

echo "=== Summary ==="
echo "Instance ID: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo "Security Group: $SG_ID"
echo "Key Pair Pem: ${KEY_NAME}.pem"
echo "S3 Bucket: $BUCKET_NAME"

echo "$INSTANCE_ID" > last_instance.txt
echo "$BUCKET_NAME" > last_bucket.txt
