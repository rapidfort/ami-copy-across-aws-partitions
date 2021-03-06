#!/bin/bash -e

source .env

#exec > >(ts "%.s" | tee build.log) 2>&1

status() {
    watch -n 1 "\
    AWS_REGION="${AWS_REGION_COMMERCIAL}" \
    AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID_COMMERCIAL}" \
    AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY_COMMERCIAL}" \
    aws ec2 describe-store-image-tasks"
}

import_ami() {
    AMI_ID="${2}"
    TARGET_AMI_NAME="${3:-my-cool-ami}"

    if test -n "${AMI_ID}"; then
        echo "Importing ${AMI_ID} @ ${AWS_REGION_COMMERCIAL} -> ${TARGET_AMI_NAME} @ ${AWS_REGION_GOV}"
    else
        echo "Usage: ./build.sh com_create_ami_bin ami-id"
        echo "missing source ami-id"
        echo "exiting..."
        exit 1
    fi

    # Copy AMI from aws commercial
    STS=$(AWS_REGION="${AWS_REGION_COMMERCIAL}" \
    AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID_COMMERCIAL}" \
    AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY_COMMERCIAL}" \
    aws ec2 create-store-image-task \
        --image-id "${AMI_ID}" \
        --bucket "${S3_BUCKET_COMMERCIAL}" | jq .OriginKey)

    # Check status of ami export
    STS=$(AWS_REGION="${AWS_REGION_COMMERCIAL}" \
    AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID_COMMERCIAL}" \
    AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY_COMMERCIAL}" \
    aws ec2 describe-store-image-tasks \
        |  jq -c ".StoreImageTaskResults | map(select(.AmiId == \"${AMI_ID}\"))[0].ProgressPercentage")

    i=1
    sp="/-\|"

    until [ $STS -eq 100 ]; do
        printf "\b${sp:i++%${#sp}:1} progress=$STS\r"
        sleep 1
        STS=$(AWS_REGION="${AWS_REGION_COMMERCIAL}" \
        AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID_COMMERCIAL}" \
        AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY_COMMERCIAL}" \
        aws ec2 describe-store-image-tasks \
            |  jq -c ".StoreImageTaskResults | map(select(.AmiId == \"${AMI_ID}\"))[0].ProgressPercentage")
    done

    AMI_ID_BIN="${2}".bin
    AMI_NAME=${3:-ami-from-aws-commercial}

    echo "AMI_ID=${2}, AMI_NAME="${TARGET_AMI_NAME}", S3_BUCKET_GOV="${S3_BUCKET_GOV}", AWS_REGION_GOV="${AWS_REGION_GOV}""
    echo "S3_BUCKET_COMMERCIAL="${S3_BUCKET_COMMERCIAL}", AWS_REGION_COMMERCIAL="${AWS_REGION_COMMERCIAL}""

    continue=n
    echo "continue [n/y]..."
    read continue
    if [ "$continue" != "y" ]; then
        echo "press y to continue. exiting..."
        exit 0
    fi
    # Get image from commercial aws
    AWS_REGION="${AWS_REGION_COMMERCIAL}" \
    AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID_COMMERCIAL}" \
    AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY_COMMERCIAL}" \
    aws s3 cp "s3://${S3_BUCKET_COMMERCIAL}"/${AMI_ID_BIN} ${AMI_ID_BIN}

    # Upload image to gov s3
    AWS_REGION="${AWS_REGION_GOV}" \
    AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID_GOV}" \
    AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY_GOV}" \
    aws s3 cp "${AMI_ID_BIN}" "s3://${S3_BUCKET_GOV}"

    # Load image to EC2
    AMI_ID_GOV=$(AWS_REGION=$AWS_REGION_GOV \
    AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID_GOV}" \
    AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY_GOV}" \
    aws ec2 create-restore-image-task \
        --object-key "${AMI_ID_BIN}" \
        --bucket "${S3_BUCKET_GOV}" \
        --name "${AMI_NAME}" | jq -r .ImageId)

    echo "Successfully copied ${AMI_ID} @ ${AWS_REGION_COMMERCIAL} --> ${AMI_ID_GOV} @ ${AMI_ID_GOV}"
}

usage() {
    echo "usage: $0 [ import_ami | status ]"
    exit 1
}

case "${1}"
in
    ("import_ami") import_ami ${@} ;;
    ("status") status ;;
    (*) usage ;;
esac

