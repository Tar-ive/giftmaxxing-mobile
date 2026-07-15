#!/usr/bin/env python3
"""Deploy (or refresh) the MTL value model as a SageMaker SERVERLESS endpoint.

Raw boto3 — no sagemaker SDK needed (it fights local venvs; the notebook uses
it instead on a real SageMaker instance). Script-managed like
s3vectors-setup.mjs: the endpoint scales to zero, so it carries no idle cost
and lives outside Terraform. Idempotent: re-running with a retrained ./model
rolls the endpoint to the new weights via a fresh Model + EndpointConfig
(SageMaker UpdateEndpoint = managed blue/green).

model.tar.gz layout for the PyTorch inference toolkit:
  model.pt, config.json          — weights + architecture (train.py output)
  code/inference.py, code/mtl_model.py — handlers (SAGEMAKER_PROGRAM)

Usage:
  python deploy_endpoint.py [--model-dir model] [--endpoint giftmaxxing-dev-mtl]
                            [--memory 2048] [--concurrency 5] [--delete]
"""
import argparse
import os
import tarfile
import tempfile
import time

import boto3

REGION = "us-east-1"
ML_BUCKET = "giftmaxxing-dev-ml"
ROLE = "arn:aws:iam::445056752928:role/giftmaxxing-dev-sagemaker-exec"
# AWS Deep Learning Container — PyTorch inference, CPU. Public DLC account.
IMAGE = "763104351884.dkr.ecr.us-east-1.amazonaws.com/pytorch-inference:2.3.0-cpu-py311-ubuntu20.04-sagemaker"


def wait_endpoint(sm, name):
    while True:
        st = sm.describe_endpoint(EndpointName=name)["EndpointStatus"]
        if st not in ("Creating", "Updating"):
            return st
        print(f"  {st}…")
        time.sleep(20)


def main():
    ap = argparse.ArgumentParser()
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--model-dir", default=os.path.join(here, "model"))
    ap.add_argument("--endpoint", default="giftmaxxing-dev-mtl")
    ap.add_argument("--memory", type=int, default=2048)
    ap.add_argument("--concurrency", type=int, default=5)
    ap.add_argument("--profile", default=os.environ.get("AWS_PROFILE"))
    ap.add_argument("--delete", action="store_true", help="tear the endpoint down instead")
    args = ap.parse_args()

    sess = boto3.Session(profile_name=args.profile, region_name=REGION) if args.profile else boto3.Session(region_name=REGION)
    sm = sess.client("sagemaker")

    if args.delete:
        sm.delete_endpoint(EndpointName=args.endpoint)
        print(f"deleting endpoint {args.endpoint}")
        return

    stamp = time.strftime("%Y-%m-%d-%H-%M-%S")
    key = f"models/mtl/{stamp}/model.tar.gz"
    with tempfile.TemporaryDirectory() as td:
        tar_path = os.path.join(td, "model.tar.gz")
        with tarfile.open(tar_path, "w:gz") as tar:
            for fn in ["model.pt", "config.json"]:
                tar.add(os.path.join(args.model_dir, fn), arcname=fn)
            for fn in ["inference.py", "mtl_model.py"]:
                tar.add(os.path.join(here, fn), arcname=f"code/{fn}")
        sess.client("s3").upload_file(tar_path, ML_BUCKET, key)
    model_data = f"s3://{ML_BUCKET}/{key}"
    print("model artifact:", model_data)

    model_name = f"{args.endpoint}-{stamp}"
    sm.create_model(
        ModelName=model_name,
        ExecutionRoleArn=ROLE,
        PrimaryContainer={
            "Image": IMAGE,
            "ModelDataUrl": model_data,
            "Environment": {
                "SAGEMAKER_PROGRAM": "inference.py",
                "SAGEMAKER_SUBMIT_DIRECTORY": "/opt/ml/model/code",
                "SAGEMAKER_REGION": REGION,
                "SAGEMAKER_CONTAINER_LOG_LEVEL": "20",
            },
        },
    )
    cfg_name = model_name
    sm.create_endpoint_config(
        EndpointConfigName=cfg_name,
        ProductionVariants=[{
            "VariantName": "AllTraffic",
            "ModelName": model_name,
            "ServerlessConfig": {"MemorySizeInMB": args.memory, "MaxConcurrency": args.concurrency},
        }],
    )
    try:
        sm.describe_endpoint(EndpointName=args.endpoint)
        sm.update_endpoint(EndpointName=args.endpoint, EndpointConfigName=cfg_name)
        print(f"updating endpoint {args.endpoint} -> {cfg_name}")
    except sm.exceptions.ClientError:
        sm.create_endpoint(EndpointName=args.endpoint, EndpointConfigName=cfg_name)
        print(f"creating endpoint {args.endpoint}")
    status = wait_endpoint(sm, args.endpoint)
    print(f"endpoint {args.endpoint}: {status}")
    if status != "InService":
        raise SystemExit(f"endpoint ended in {status} — check CloudWatch /aws/sagemaker/Endpoints/{args.endpoint}")


if __name__ == "__main__":
    main()
