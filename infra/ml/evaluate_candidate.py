"""Gate a registry candidate using training and synthetic-persona evidence."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import boto3


def load_json(s3, bucket: str, key: str, required: bool = True) -> dict:
    try:
        return json.loads(s3.get_object(Bucket=bucket, Key=key)["Body"].read())
    except s3.exceptions.NoSuchKey:
        if required:
            raise SystemExit(f"missing s3://{bucket}/{key}")
        return {}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True, help="Model package ARN or version")
    parser.add_argument("--evaluation", help="10-person report JSON; otherwise S3 evaluations/<version>.json")
    args = parser.parse_args()
    region = os.environ.get("AWS_REGION", "us-east-1")
    bucket = os.environ.get("RECOMMENDER_ML_BUCKET")
    group = os.environ.get("RECOMMENDER_MODEL_PACKAGE_GROUP", "giftmaxxing-dev-recommender")
    if not bucket:
        raise SystemExit("RECOMMENDER_ML_BUCKET is required")
    sm, s3 = boto3.client("sagemaker", region_name=region), boto3.client("s3", region_name=region)
    arn = args.candidate
    if not arn.startswith("arn:"):
        packages = sm.list_model_packages(ModelPackageGroupName=group, SortBy="CreationTime", SortOrder="Descending", MaxResults=100)["ModelPackageSummaryList"]
        match = next((p for p in packages if p["ModelPackageArn"].rsplit("/", 1)[-1] == arn), None)
        if not match:
            raise SystemExit(f"candidate {arn} not found")
        arn = match["ModelPackageArn"]
    package = sm.describe_model_package(ModelPackageName=arn)
    version = str(package["ModelPackageVersion"])
    run_id = package.get("CustomerMetadataProperties", {}).get("run_id")
    if not run_id:
        raise SystemExit("candidate has no run_id metadata")
    run = load_json(s3, bucket, f"runs/{run_id}/run.json")
    evaluation = json.loads(Path(args.evaluation).read_text()) if args.evaluation else load_json(s3, bucket, f"evaluations/{version}.json")
    report = run.get("report", {})
    ci_low = (report.get("ndcg10_ci95") or [None])[0]
    aggregate = evaluation.get("aggregate", {})
    regressions = {
        name: float(aggregate.get(f"{name}Regression", 0))
        for name in ("shoppability", "diversity", "coverage", "safety", "latency")
    }
    checks = {
        "positiveNdcgLowerBound": ci_low is not None and float(ci_low) > 0,
        "noQualityRegressionOver2Percent": all(value <= 0.02 for value in regressions.values()),
        "syntheticPersonasPassed": bool(evaluation.get("passed")),
        "shadowPassed": bool(evaluation.get("shadowPassed")),
    }
    decision = {
        "candidate": arn, "version": version, "runId": run_id, "artifact": run.get("artifact"),
        "passed": all(checks.values()), "checks": checks,
        "trainingReport": report, "evaluationSummary": aggregate,
    }
    key = f"evaluations/{version}-gate.json"
    s3.put_object(Bucket=bucket, Key=key, Body=json.dumps(decision, indent=2).encode(), ContentType="application/json")
    print(json.dumps(decision, indent=2))
    if not decision["passed"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
