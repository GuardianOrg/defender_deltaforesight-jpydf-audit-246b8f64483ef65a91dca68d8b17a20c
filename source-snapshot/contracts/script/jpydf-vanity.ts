import assert from "assert";

import {
  type ByteArray,
  bytesToHex,
  concatBytes,
  getAddress,
  hexToBytes,
  keccak256,
  padBytes,
  stringToBytes,
} from "viem";

import JpydfToken from "../out/JpydfToken.sol/JpydfToken.json";

const requiredAddress = (name: string): `0x${string}` => {
  const value = process.env[name];
  assert(value, `${name} is required`);
  return getAddress(value) as `0x${string}`;
};

const DEPLOYER = requiredAddress("DEPLOYER");
const BRIDGE_ADMIN = requiredAddress("DF_BRIDGE_ADMIN");
const SALT_PREFIX = "beJPYDF";
const CREATE2_DEPLOYER = "0x4e59b44847b379578588920cA78FbF26c0B4956C";
const CREATE2_PREFIX = concatBytes([hexToBytes("0xFF"), hexToBytes(CREATE2_DEPLOYER)]);

const computeCreate2Address = (salt: ByteArray, initCodeHash: ByteArray): ByteArray =>
  keccak256(concatBytes([CREATE2_PREFIX, salt, initCodeHash]), "bytes").slice(12);

const startsWith = <T extends string>(str: string, prefix: T): str is `${T}${string}` => str.startsWith(prefix);
assert(startsWith(JpydfToken.bytecode.object, "0x"));

const jpydfInitCodeHash = keccak256(
  concatBytes([
    hexToBytes(JpydfToken.bytecode.object),
    padBytes(hexToBytes(DEPLOYER)),
    padBytes(hexToBytes(BRIDGE_ADMIN)),
  ]),
  "bytes",
);

for (let i = 0;; ++i) {
  const saltStr = `${SALT_PREFIX}${i}`;
  const salt = keccak256(stringToBytes(saltStr), "bytes");
  const jpydfAddress = computeCreate2Address(salt, jpydfInitCodeHash);

  if (jpydfAddress[0] === 0xb0 && jpydfAddress[1] === 0x1d /*&& jpydfAddress[18] === 0xb0 && jpydfAddress[19] === 0x1d*/) {
    console.log("Salt found:", saltStr);
    console.log("JPYDF address:", getAddress(bytesToHex(jpydfAddress)));
    break;
  }
}
