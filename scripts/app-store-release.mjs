#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createPrivateKey, sign } from "node:crypto";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";

const apply = process.argv.includes("--release");
const appId = process.env.ASC_APP_ID ?? "6788124639";
const keyId = process.env.ASC_KEY_ID ?? "254ZRKZ2HP";
const issuerId = process.env.ASC_ISSUER_ID ?? "77c91aba-1d1e-431d-b9a3-a4dadd970467";
const keyPath = process.env.ASC_KEY_PATH
  ?? `${homedir()}/.appstoreconnect/private_keys/AuthKey_${keyId}.p8`;
const privateKey = process.env.ASC_KEY_P8 ?? readFileSync(keyPath, "utf8");

if (!privateKey) throw new Error("App Store Connect private key is required");

const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
const jwt = () => {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${encode({ alg: "ES256", kid: keyId, typ: "JWT" })}.${encode({
    iss: issuerId,
    iat: now,
    exp: now + 900,
    aud: "appstoreconnect-v1",
  })}`;
  const signature = sign("sha256", Buffer.from(unsigned), {
    key: createPrivateKey(privateKey),
    dsaEncoding: "ieee-p1363",
  });
  return `${unsigned}.${signature.toString("base64url")}`;
};

async function request(path, method = "GET", body) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${jwt()}`,
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${method} ${path}: ${response.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

const versions = await request(
  `/v1/apps/${appId}/appStoreVersions?filter%5Bplatform%5D=IOS&limit=20&fields%5BappStoreVersions%5D=versionString,appStoreState,createdDate`,
);
const version = versions.data.toSorted(
  (a, b) => new Date(b.attributes.createdDate) - new Date(a.attributes.createdDate),
).find(
  ({ attributes }) => attributes.appStoreState === "PENDING_DEVELOPER_RELEASE",
);

if (!version) {
  console.log("No approved iOS version is waiting for developer release.");
  process.exit(0);
}

console.log(`Release candidate ${version.attributes.versionString} (${version.id})`);
if (!apply) {
  console.log("Dry run only; pass --release to publish it.");
  process.exit(0);
}

const phased = await request(
  `/v1/appStoreVersions/${version.id}/appStoreVersionPhasedRelease`,
);
if (!phased.data) {
  await request("/v1/appStoreVersionPhasedReleases", "POST", {
    data: {
      type: "appStoreVersionPhasedReleases",
      attributes: { phasedReleaseState: "ACTIVE" },
      relationships: {
        appStoreVersion: { data: { type: "appStoreVersions", id: version.id } },
      },
    },
  });
}

await request("/v1/appStoreVersionReleaseRequests", "POST", {
  data: {
    type: "appStoreVersionReleaseRequests",
    relationships: {
      appStoreVersion: { data: { type: "appStoreVersions", id: version.id } },
    },
  },
});
console.log(`Released ${version.attributes.versionString} with phased rollout enabled.`);

// Tag the release. Until this existed, nothing in the repo recorded which
// commit a public version came from — reconstructing that for 1.1.2 took a dig
// through agent session logs. The tag is annotated with the build number and
// the ASC version id so the trail survives outside git too.
tagRelease(version);

function tagRelease({ id, attributes }) {
  const tag = `v${attributes.versionString}`;
  const git = (...args) => execFileSync("git", args, { encoding: "utf8" }).trim();
  try {
    if (git("tag", "--list", tag)) {
      console.log(`Tag ${tag} already exists; leaving it alone.`);
      return;
    }
    // The released binary is whatever this checkout is, which is what the
    // release workflow archived. GitCommit in the build's Info.plist is the
    // authoritative record; this ties it back to a name.
    const sha = git("rev-parse", "HEAD");
    git("tag", "-a", tag, sha, "-m",
      `App Store ${attributes.versionString} (ASC version ${id}), released ${new Date().toISOString().slice(0, 10)}.`);
    git("push", "origin", tag);
    console.log(`Tagged ${tag} at ${sha.slice(0, 8)} and pushed it.`);
  } catch (error) {
    // A failed tag must not read as a failed release — the release already
    // happened by this point.
    console.warn(`Released, but tagging ${tag} failed: ${error.message}`);
  }
}
