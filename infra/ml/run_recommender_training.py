"""Create one immutable Mixer v2 training run and a pending registry candidate."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

import boto3

REGION = os.environ.get("AWS_REGION", "us-east-1")
BUCKET = os.environ.get("RECOMMENDER_ML_BUCKET", "")
ROLE = os.environ.get("RECOMMENDER_SAGEMAKER_ROLE_ARN", "")
GROUP = os.environ.get("RECOMMENDER_MODEL_PACKAGE_GROUP", "")
IMAGE = os.environ.get("RECOMMENDER_TRAINING_IMAGE", "683313688378.dkr.ecr.us-east-1.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3")


def require(value: str, name: str) -> str:
    if not value:
        raise SystemExit(f"{name} is required")
    return value


def wait_for_job(sm, name: str) -> dict:
    while True:
        job = sm.describe_training_job(TrainingJobName=name)
        status = job["TrainingJobStatus"]
        print(f"training={status}", flush=True)
        if status in {"Completed", "Failed", "Stopped"}:
            if status != "Completed":
                raise RuntimeError(job.get("FailureReason", status))
            return job
        time.sleep(20)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reason", default="manual")
    parser.add_argument("--wait", action="store_true")
    args = parser.parse_args()
    bucket, role = require(BUCKET, "RECOMMENDER_ML_BUCKET"), require(ROLE, "RECOMMENDER_SAGEMAKER_ROLE_ARN")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    run_id, job_name = f"run-{stamp}", f"giftmaxxing-recommender-{stamp}"
    root = Path(__file__).resolve().parent
    s3, sm = boto3.client("s3", region_name=REGION), boto3.client("sagemaker", region_name=REGION)

    with tempfile.TemporaryDirectory() as raw:
        work = Path(raw)
        data = work / "swipes.npz"
        subprocess.run([sys.executable, str(root / "export_swipe_data.py"), "--out", str(data)], check=True)
        if not data.exists():
            raise RuntimeError("export completed without a dataset")
        source = work / "sourcedir.tar.gz"
        with tarfile.open(source, "w:gz") as archive:
            for name in ("sm_entry.py", "swipe_model.py", "train_swipe.py"):
                archive.add(root / name, arcname=name)
        prefix = f"runs/{run_id}"
        s3.upload_file(str(source), bucket, f"{prefix}/source/sourcedir.tar.gz")
        s3.upload_file(str(data), bucket, f"{prefix}/input/swipes.npz")
        meta = data.with_name("swipes_meta.json")
        if meta.exists():
            s3.upload_file(str(meta), bucket, f"{prefix}/input/swipes_meta.json")

    base = f"s3://{bucket}/{prefix}"
    sm.create_training_job(
        TrainingJobName=job_name,
        AlgorithmSpecification={
            "TrainingImage": IMAGE, "TrainingInputMode": "File",
            "MetricDefinitions": [
                {"Name": name, "Regex": f"{name}=(-?[0-9.]+);"}
                for name in ("auc_cosine", "auc_model", "lift", "auc_linear", "auc_classweight", "auc_pairwise", "ci_low", "ci_high", "p_better", "ndcg10_cosine", "ndcg10_model", "ndcg10_lift", "ndcg10_ci_low", "ndcg10_ci_high")
            ],
        },
        RoleArn=role,
        HyperParameters={"sagemaker_program": '"sm_entry.py"', "sagemaker_submit_directory": f'"{base}/source/sourcedir.tar.gz"'},
        InputDataConfig=[{"ChannelName": "training", "DataSource": {"S3DataSource": {"S3DataType": "S3Prefix", "S3Uri": f"{base}/input/", "S3DataDistributionType": "FullyReplicated"}}}],
        OutputDataConfig={"S3OutputPath": f"{base}/output/"},
        ResourceConfig={"InstanceType": "ml.m5.large", "InstanceCount": 1, "VolumeSizeInGB": 10},
        StoppingCondition={"MaxRuntimeInSeconds": 1800},
        Tags=[{"Key": "project", "Value": "giftmaxxing"}, {"Key": "reason", "Value": args.reason[:256]}],
    )
    manifest = {"runId": run_id, "jobName": job_name, "reason": args.reason, "status": "Training", "createdAt": stamp, "productionChanged": False}
    s3.put_object(Bucket=bucket, Key=f"{prefix}/run.json", Body=json.dumps(manifest, indent=2).encode(), ContentType="application/json")
    print(json.dumps(manifest))
    if not args.wait:
        return

    job = wait_for_job(sm, job_name)
    artifact = job["ModelArtifacts"]["S3ModelArtifacts"]
    with tempfile.TemporaryDirectory() as raw:
        model_tar = Path(raw) / "model.tar.gz"
        uri = artifact.removeprefix("s3://")
        artifact_bucket, artifact_key = uri.split("/", 1)
        s3.download_file(artifact_bucket, artifact_key, str(model_tar))
        with tarfile.open(model_tar) as archive:
            report_file = archive.extractfile("report.json")
            report = json.load(report_file) if report_file else {"viable": False}

    manifest.update(status="Completed", artifact=artifact, report=report)
    if report.get("viable") and GROUP:
        package = sm.create_model_package(
            ModelPackageGroupName=GROUP,
            ModelPackageDescription=f"{run_id}; reason={args.reason}",
            ModelApprovalStatus="PendingManualApproval",
            InferenceSpecification={"Containers": [{"Image": IMAGE, "ModelDataUrl": artifact}], "SupportedContentTypes": ["application/json"], "SupportedResponseMIMETypes": ["application/json"]},
            CustomerMetadataProperties={"run_id": run_id, "reason": args.reason[:256], "champion_unchanged": "true"},
        )
        manifest["candidateModelPackageArn"] = package["ModelPackageArn"]
        manifest["candidateStatus"] = "PendingManualApproval"
    else:
        manifest["candidateStatus"] = "CompletedWithoutViableCandidate"
    s3.put_object(Bucket=bucket, Key=f"{prefix}/run.json", Body=json.dumps(manifest, indent=2).encode(), ContentType="application/json")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
