import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const takeOption = (name) => {
  const index = args.indexOf(name);
  if (index === -1) return undefined;
  const value = args[index + 1];
  if (!value) throw new Error(`${name} requires a directory`);
  args.splice(index, 2);
  return value;
};
const baseStorageOut = takeOption("--base-storage-out");
const baseNoMetadataOut = takeOption("--base-no-metadata-out");

let standardOut;
let noMetadataOut;
if (args.length === 1) {
  standardOut = join(root, "source-snapshot/contracts/out");
  [noMetadataOut] = args;
} else if (args.length === 2) {
  [standardOut, noMetadataOut] = args;
} else {
  throw new Error(
    "usage: node scripts/verify-final-artifacts.mjs [FINAL_STANDARD_OUT] FINAL_NO_METADATA_OUT " +
      "[--base-storage-out BASE_STANDARD_OUT] [--base-no-metadata-out BASE_NO_METADATA_OUT]",
  );
}

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const keccak = (value) => execFileSync("cast", ["keccak", value], { encoding: "utf8" }).trim();
const canonicalFlatObject = (value) => JSON.stringify(value, Object.keys(value ?? {}).sort());
const artifactKey = ({ source, contract }) => `${source}:${contract}`;

function readTsv(name) {
  const [header, ...lines] = readFileSync(join(root, name), "utf8").trim().split("\n");
  const fields = header.split("\t");
  return lines.map((line) => {
    const values = line.split("\t");
    return Object.fromEntries(fields.map((field, index) => [field, values[index]]));
  });
}

function canonicalStorageLayout({ storage, types }) {
  const memo = new Map();
  const resolveType = (id) => {
    if (memo.has(id)) return memo.get(id);
    const raw = types[id];
    if (!raw) throw new Error(`storage layout references missing type ${id}`);
    const resolved = {
      encoding: raw.encoding,
      label: raw.label,
      numberOfBytes: String(raw.numberOfBytes),
    };
    memo.set(id, resolved);
    for (const field of ["base", "key", "value"]) {
      if (raw[field]) resolved[field] = resolveType(raw[field]);
    }
    if (raw.members) {
      resolved.members = raw.members.map((member) => ({
        label: member.label,
        slot: String(member.slot),
        offset: Number(member.offset),
        type: resolveType(member.type),
      }));
    }
    return resolved;
  };

  return storage.map((entry) => ({
    label: entry.label,
    slot: String(entry.slot),
    offset: Number(entry.offset),
    type: resolveType(entry.type),
  }));
}

function readStorageLayout(outDir, expected) {
  const relative = join(expected.source, `${expected.contract}.json`);
  const artifact = JSON.parse(readFileSync(join(outDir, relative), "utf8"));
  if (!artifact.storageLayout) {
    throw new Error(`${expected.contract}: storageLayout missing from ${join(outDir, relative)}`);
  }
  return canonicalStorageLayout(artifact.storageLayout);
}

function readDeployableSourceArtifacts(outDir) {
  const result = new Map();
  for (const sourceDir of readdirSync(outDir, { withFileTypes: true })) {
    if (!sourceDir.isDirectory() || !sourceDir.name.endsWith(".sol")) continue;
    for (const artifactFile of readdirSync(join(outDir, sourceDir.name), { withFileTypes: true })) {
      if (!artifactFile.isFile() || !artifactFile.name.endsWith(".json")) continue;
      const artifact = JSON.parse(readFileSync(join(outDir, sourceDir.name, artifactFile.name), "utf8"));
      const targets = Object.entries(artifact.metadata?.settings?.compilationTarget ?? {});
      if (targets.length !== 1 || !targets[0][0].startsWith("src/")) continue;
      const contract = targets[0][1];
      const creation = artifact.bytecode?.object;
      const runtime = artifact.deployedBytecode?.object;
      if ((!creation || creation === "0x") && (!runtime || runtime === "0x")) continue;
      result.set(artifactKey({ source: sourceDir.name, contract }), { creation, runtime });
    }
  }
  return result;
}

const artifacts = readTsv("FINAL_PRODUCTION_ARTIFACTS.tsv");
for (const expected of artifacts) {
  const relative = join(expected.source, `${expected.contract}.json`);
  const standard = JSON.parse(readFileSync(join(standardOut, relative), "utf8"));
  const noMetadata = JSON.parse(readFileSync(join(noMetadataOut, relative), "utf8"));
  const actual = {
    creation_bytes: String((standard.bytecode.object.length - 2) / 2),
    runtime_bytes: String((standard.deployedBytecode.object.length - 2) / 2),
    creation_keccak: keccak(standard.bytecode.object),
    runtime_keccak: keccak(standard.deployedBytecode.object),
    no_metadata_creation_bytes: String((noMetadata.bytecode.object.length - 2) / 2),
    no_metadata_runtime_bytes: String((noMetadata.deployedBytecode.object.length - 2) / 2),
    no_metadata_creation_keccak: keccak(noMetadata.bytecode.object),
    no_metadata_runtime_keccak: keccak(noMetadata.deployedBytecode.object),
    abi_sha256: sha256(JSON.stringify(standard.abi)),
    method_identifiers_sha256: sha256(canonicalFlatObject(standard.methodIdentifiers)),
  };
  for (const [field, value] of Object.entries(actual)) {
    if (value !== expected[field]) {
      throw new Error(`${expected.contract} ${field}: expected ${expected[field]}, got ${value}`);
    }
  }
}

console.log(`final production artifact verification: PASS (${artifacts.length} artifacts)`);

const artifactScopes = new Map(artifacts.map((artifact) => [artifactKey(artifact), artifact.scope]));

function verifyChangedArtifactCoverage(label, baseOut, finalOut, allowedScopes) {
  const base = readDeployableSourceArtifacts(baseOut);
  const final = readDeployableSourceArtifacts(finalOut);
  for (const key of base.keys()) {
    if (!final.has(key)) throw new Error(`${label} deployable src artifact removed without manifest identity: ${key}`);
  }
  let changedCount = 0;
  for (const [key, value] of final) {
    const previous = base.get(key);
    if (previous && previous.creation === value.creation && previous.runtime === value.runtime) continue;
    changedCount++;
    const scope = artifactScopes.get(key);
    if (!scope || (allowedScopes && !allowedScopes.has(scope))) {
      throw new Error(`${label} changed deployable src artifact missing from manifest: ${key}`);
    }
  }
  console.log(`${label} changed deployable src artifact coverage: PASS (${changedCount} artifacts)`);
}

if (baseStorageOut) {
  verifyChangedArtifactCoverage("standard", baseStorageOut, standardOut);
}

if (baseNoMetadataOut) {
  verifyChangedArtifactCoverage(
    "metadata-free executable",
    baseNoMetadataOut,
    noMetadataOut,
    new Set(["priced", "included-legacy-context", "included-archive-context"]),
  );
}

if (baseStorageOut) {
  const layouts = readTsv("FINAL_PRODUCTION_STORAGE_LAYOUTS.tsv");
  const layoutKeys = new Set();

  for (const expected of layouts) {
    const key = artifactKey(expected);
    if (layoutKeys.has(key)) throw new Error(`duplicate storage layout row: ${key}`);
    if (artifactScopes.get(key) !== expected.scope) {
      throw new Error(`storage layout scope mismatch or unknown artifact: ${key}`);
    }
    layoutKeys.add(key);

    const base = readStorageLayout(baseStorageOut, expected);
    const final = readStorageLayout(standardOut, expected);
    const baseJson = JSON.stringify(base);
    const finalJson = JSON.stringify(final);
    const isAppended =
      final.length > base.length &&
      base.every((entry, index) => JSON.stringify(entry) === JSON.stringify(final[index]));
    const actual = {
      base_entries: String(base.length),
      final_entries: String(final.length),
      base_semantic_sha256: sha256(baseJson),
      final_semantic_sha256: sha256(finalJson),
      status: baseJson === finalJson ? "unchanged" : isAppended ? "appended" : "changed",
    };
    for (const [field, value] of Object.entries(actual)) {
      if (value !== expected[field]) {
        throw new Error(`${expected.contract} ${field}: expected ${expected[field]}, got ${value}`);
      }
    }
  }

  const statefulArtifactKeys = new Set();
  for (const expected of artifacts) {
    const relative = join(expected.source, `${expected.contract}.json`);
    const artifact = JSON.parse(readFileSync(join(standardOut, relative), "utf8"));
    if (artifact.storageLayout?.storage.length) statefulArtifactKeys.add(artifactKey(expected));
  }
  for (const key of statefulArtifactKeys) {
    if (!layoutKeys.has(key)) throw new Error(`stateful artifact missing from storage manifest: ${key}`);
  }
  for (const key of layoutKeys) {
    if (!statefulArtifactKeys.has(key)) throw new Error(`non-stateful or unknown storage manifest row: ${key}`);
  }

  console.log(`final production storage layout verification: PASS (${layouts.length} layouts)`);
}
