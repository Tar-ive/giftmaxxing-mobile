# Minimal App Store Connect API client: mints an ES256 JWT from the team key
# and calls the given path. Used to check build/TestFlight state and manage
# tester-build assignments.
# Usage: python3 scripts/asc-api.py '/v1/builds?filter[app]=6788124639'
#        python3 scripts/asc-api.py '/v1/...' POST '{"data": ...}'

import base64
import json
import sys
import time
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

KEY_ID = "254ZRKZ2HP"
ISSUER_ID = "77c91aba-1d1e-431d-b9a3-a4dadd970467"
KEY_PATH = f"{__import__('os').path.expanduser('~')}/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"


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


path = sys.argv[1]
method = sys.argv[2] if len(sys.argv) > 2 else "GET"
body = sys.argv[3].encode() if len(sys.argv) > 3 else None
headers = {"Authorization": f"Bearer {make_token()}"}
if body:
    headers["Content-Type"] = "application/json"
req = urllib.request.Request(
    f"https://api.appstoreconnect.apple.com{path}",
    headers=headers,
    data=body,
    method=method,
)
try:
    with urllib.request.urlopen(req) as resp:
        out = resp.read()
        print(json.dumps(json.loads(out), indent=2) if out else f"OK {resp.status}")
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code}: {e.read().decode()}")
