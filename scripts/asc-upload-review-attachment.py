# Upload an App Review attachment (e.g. the account-deletion screen recording
# Apple asked for under 5.1.1(v)) to a version's appStoreReviewDetail.
# Same reserve → PUT chunks → commit dance as asc-upload-screenshots.py.
# Usage: python3 scripts/asc-upload-review-attachment.py <reviewDetailId> <file> [file ...]

import base64
import hashlib
import json
import sys
import time
import urllib.request
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

KEY_ID = "254ZRKZ2HP"
ISSUER_ID = "77c91aba-1d1e-431d-b9a3-a4dadd970467"
KEY_PATH = f"{Path.home()}/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"
BASE = "https://api.appstoreconnect.apple.com"


def b64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def make_token() -> str:
    with open(KEY_PATH, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    header = b64url(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = b64url(json.dumps({
        "iss": ISSUER_ID, "iat": now, "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }).encode())
    signing_input = header + b"." + payload
    der_sig = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der_sig)
    raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return (signing_input + b"." + b64url(raw)).decode()


def api(path: str, method: str = "GET", body: dict | None = None) -> dict:
    req = urllib.request.Request(
        f"{BASE}{path}",
        headers={
            "Authorization": f"Bearer {make_token()}",
            **({"Content-Type": "application/json"} if body is not None else {}),
        },
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
    )
    with urllib.request.urlopen(req) as resp:
        out = resp.read()
        return json.loads(out) if out else {}


def put_chunk(url: str, headers: list, data: bytes) -> None:
    req = urllib.request.Request(url, data=data, method="PUT")
    for h in headers:
        req.add_header(h["name"], h["value"])
    with urllib.request.urlopen(req) as resp:
        resp.read()


def main() -> None:
    detail_id, *files = sys.argv[1:]
    for f in files:
        path = Path(f)
        blob = path.read_bytes()
        att = api("/v1/appStoreReviewAttachments", "POST", {
            "data": {
                "type": "appStoreReviewAttachments",
                "attributes": {"fileName": path.name, "fileSize": len(blob)},
                "relationships": {"appStoreReviewDetail": {
                    "data": {"type": "appStoreReviewDetails", "id": detail_id}}},
            }})["data"]
        for op in att["attributes"]["uploadOperations"]:
            put_chunk(op["url"], op["requestHeaders"],
                      blob[op["offset"]:op["offset"] + op["length"]])
        api(f"/v1/appStoreReviewAttachments/{att['id']}", "PATCH", {
            "data": {
                "type": "appStoreReviewAttachments",
                "id": att["id"],
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
                },
            }})
        print(f"uploaded {path.name} ({len(blob)} bytes) -> attachment {att['id']}")

    time.sleep(5)
    for a in api(f"/v1/appStoreReviewDetails/{detail_id}/appStoreReviewAttachments"
                 "?fields[appStoreReviewAttachments]=fileName,assetDeliveryState")["data"]:
        at = a["attributes"]
        print(f"{at['fileName']}: {at['assetDeliveryState']['state']}")


if __name__ == "__main__":
    main()
