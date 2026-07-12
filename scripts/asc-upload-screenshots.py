# Upload App Store screenshots to a version localization's screenshot set.
# Reserves each asset, PUTs the binary in the chunks ASC dictates, then
# commits with the MD5 checksum — the raw-binary dance asc-api.py can't do.
# Usage: python3 scripts/asc-upload-screenshots.py <versionLocalizationId> \
#          <displayType e.g. APP_IPHONE_69> <file1.png> [file2.png ...]

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
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + 1200,
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
    loc_id, display_type, *files = sys.argv[1:]

    sets = api(
        f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets"
        f"?filter[screenshotDisplayType]={display_type}"
    )["data"]
    if sets:
        set_id = sets[0]["id"]
        print(f"using existing screenshot set {set_id}")
    else:
        set_id = api("/v1/appScreenshotSets", "POST", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {"appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}},
            }})["data"]["id"]
        print(f"created screenshot set {set_id}")

    for f in files:
        path = Path(f)
        blob = path.read_bytes()
        shot = api("/v1/appScreenshots", "POST", {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": path.name, "fileSize": len(blob)},
                "relationships": {"appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": set_id}}},
            }})["data"]
        for op in shot["attributes"]["uploadOperations"]:
            put_chunk(op["url"], op["requestHeaders"],
                      blob[op["offset"]:op["offset"] + op["length"]])
        api(f"/v1/appScreenshots/{shot['id']}", "PATCH", {
            "data": {
                "type": "appScreenshots",
                "id": shot["id"],
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
                },
            }})
        print(f"uploaded {path.name} ({len(blob)} bytes) -> {shot['id']}")

    time.sleep(5)
    for s in api(f"/v1/appScreenshotSets/{set_id}/appScreenshots"
                 "?fields[appScreenshots]=fileName,assetDeliveryState")["data"]:
        a = s["attributes"]
        print(f"{a['fileName']}: {a['assetDeliveryState']['state']}")


if __name__ == "__main__":
    main()
