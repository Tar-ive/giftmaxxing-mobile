#!/usr/bin/env bash
# Train the swipe model as a SageMaker Training Job (AWS CLI, no SDK).
#
# Runs the SAME code as the local path (sm_entry.py -> train_swipe.py ->
# swipe_model.py), so the job cannot silently diverge from what was validated
# locally. Costs ~2 minutes of ml.m5.large (~$0.005) per run.
#
#   export AWS_PROFILE=dev_sso_giftmaxxing
#   cd infra/ml && ./launch_training_job.sh
set -euo pipefail

REGION=${REGION:-us-east-1}
BUCKET=${BUCKET:-giftmaxxing-dev-ml}
ROLE=${ROLE:-arn:aws:iam::445056752928:role/service-role/AmazonSageMaker-ExecutionRole-20250201T001759}
IMAGE=${IMAGE:-683313688378.dkr.ecr.us-east-1.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3}
STAMP=$(date -u +%Y-%m-%d-%H%M%S)
JOB="giftmaxxing-swipe-$STAMP"
BASE="s3://$BUCKET/jobs/$STAMP"

[ -f data/swipes.npz ] || { echo "data/swipes.npz missing — run: python3 export_swipe_data.py"; exit 1; }

echo "packaging…"
tar -czf /tmp/sourcedir.tar.gz sm_entry.py swipe_model.py train_swipe.py export_swipe_data.py
aws s3 cp /tmp/sourcedir.tar.gz "$BASE/source/sourcedir.tar.gz" --quiet
aws s3 cp data/swipes.npz       "$BASE/input/swipes.npz"        --quiet

cat > /tmp/job.json <<JSON
{
  "TrainingJobName": "$JOB",
  "AlgorithmSpecification": {
    "TrainingImage": "$IMAGE",
    "TrainingInputMode": "File",
    "MetricDefinitions": [
      {"Name": "auc_cosine", "Regex": "auc_cosine=([0-9.]+);"},
      {"Name": "auc_model",  "Regex": "auc_model=([0-9.]+);"},
      {"Name": "lift",       "Regex": "lift=(-?[0-9.]+);"},
      {"Name": "auc_linear", "Regex": "auc_linear=([0-9.]+);"},
      {"Name": "ci_low",     "Regex": "ci_low=(-?[0-9.]+);"},
      {"Name": "ci_high",    "Regex": "ci_high=(-?[0-9.]+);"},
      {"Name": "p_better",   "Regex": "p_better=([0-9.]+);"}
    ]
  },
  "RoleArn": "$ROLE",
  "HyperParameters": {
    "sagemaker_program": "\"sm_entry.py\"",
    "sagemaker_submit_directory": "\"$BASE/source/sourcedir.tar.gz\""
  },
  "InputDataConfig": [{
    "ChannelName": "training",
    "DataSource": {"S3DataSource": {
      "S3DataType": "S3Prefix", "S3Uri": "$BASE/input/",
      "S3DataDistributionType": "FullyReplicated"}}
  }],
  "OutputDataConfig": {"S3OutputPath": "$BASE/output/"},
  "ResourceConfig": {"InstanceType": "ml.m5.large", "InstanceCount": 1, "VolumeSizeInGB": 10},
  "StoppingCondition": {"MaxRuntimeInSeconds": 1800},
  "Tags": [{"Key":"project","Value":"giftmaxxing"},{"Key":"model","Value":"swipe-lr"}]
}
JSON

aws sagemaker create-training-job --region "$REGION" --cli-input-json file:///tmp/job.json >/dev/null
echo "launched $JOB"

while true; do
  S=$(aws sagemaker describe-training-job --region "$REGION" --training-job-name "$JOB" --query TrainingJobStatus --output text)
  echo "  $S"; case "$S" in Completed|Failed|Stopped) break;; esac; sleep 20
done

aws sagemaker describe-training-job --region "$REGION" --training-job-name "$JOB" \
  --query 'FinalMetricDataList[].{metric:MetricName,value:Value}' --output table
echo "artifact: $BASE/output/$JOB/output/model.tar.gz"
