import assert from "node:assert/strict";

import { assertProductionNativeEthRouteEnvironment, DAY1_NATIVE_ETH_ROUTE } from "./day1-native-eth-route.js";

const exactEnvironment = {
  DF_ZAPPER_EXPECTED_STETH_0: DAY1_NATIVE_ETH_ROUTE.expectedStEth,
  DF_ZAPPER_LIDO_REFERRAL_0: DAY1_NATIVE_ETH_ROUTE.lidoReferral,
};

function validate(
  env: NodeJS.ProcessEnv,
  overrides: Partial<Parameters<typeof assertProductionNativeEthRouteEnvironment>[0]> = {},
) {
  assertProductionNativeEthRouteEnvironment({
    chainId: 1,
    mainnetTestDeployment: false,
    deploymentMode: "complete",
    env,
    ...overrides,
  });
}

assert.equal(DAY1_NATIVE_ETH_ROUTE.lidoReferral, "0x57af3a60314cD24032a4435b715f4dC8eb5967F0");
assert.doesNotThrow(() => validate(exactEnvironment));

for (const name of ["DF_ZAPPER_EXPECTED_STETH_0", "DF_ZAPPER_LIDO_REFERRAL_0"] as const) {
  for (const invalid of [undefined, "", "0x0000000000000000000000000000000000000000", "not-an-address"]) {
    assert.throws(
      () => validate({ ...exactEnvironment, [name]: invalid }),
      new RegExp(`${name} must match the Day-1 owner manifest value`),
    );
  }
}

assert.throws(
  () =>
    validate({
      ...exactEnvironment,
      DF_ZAPPER_LIDO_REFERRAL_0: "0x1111111111111111111111111111111111111111",
    }),
  /DF_ZAPPER_LIDO_REFERRAL_0 must match the Day-1 owner manifest value/,
);

assert.doesNotThrow(() => validate({}, { chainId: 11_155_111 }));
assert.doesNotThrow(() => validate({}, { chainId: 31_337 }));
assert.doesNotThrow(() => validate({}, { mainnetTestDeployment: true }));
assert.doesNotThrow(() => validate({}, { deploymentMode: "jpydf-only" }));

console.log("Day-1 native-ETH route environment tests passed");
