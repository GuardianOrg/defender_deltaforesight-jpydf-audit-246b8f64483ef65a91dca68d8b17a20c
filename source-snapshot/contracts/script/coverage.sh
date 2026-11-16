#!/bin/bash
set -euo pipefail

forge coverage --report lcov --report-file lcov_foundry.info
cp lcov_foundry.info lcov_merged.info

lcov --remove lcov_merged.info -o lcov_merged.info \
     'test/*' \
     'script/*' \
     'src/Dependencies/Ownable.sol' \
     'src/NFTMetadata/*' \
     'src/MultiTroveGetter.sol' \
     'src/HintHelpers.sol'

genhtml lcov_merged.info --output-directory coverage
