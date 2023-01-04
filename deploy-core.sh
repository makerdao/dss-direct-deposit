#!/bin/bash
set -e

export FOUNDRY_SCRIPT_CONFIG="$1"

rm -f out/contract-exports.env
forge script script/D3MCoreDeploy.s.sol:D3MCoreDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
