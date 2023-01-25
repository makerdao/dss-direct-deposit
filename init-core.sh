#!/bin/bash
# NOTE: This can only be run against an anvil-node. Production initialization needs to be done in the spell.
set -e

[[ -n "$FOUNDRY_ROOT_CHAINID" ]] || {
    [[ -n $ETH_RPC_URL ]] || {
        echo "Please set FOUNDRY_ROOT_CHAINID (1 or 5) or ETH_RPC_URL";
        exit 1;
    }
    FOUNDRY_ROOT_CHAINID="$(cast chain-id)"
}
[[ "$FOUNDRY_ROOT_CHAINID" == "1" ]] || [[ "$FOUNDRY_ROOT_CHAINID" == "5" ]] || {
    echo "Invalid chainid of $FOUNDRY_ROOT_CHAINID. Please set your forking environment via ETH_RPC_URL or manually by defining FOUNDRY_ROOT_CHAINID (1 or 5)."
    exit 1;
}

[[ "$FOUNDRY_ROOT_CHAINID" == "1" ]] && echo "Initializing D3M Core on Mainnet"
[[ "$FOUNDRY_ROOT_CHAINID" == "5" ]] && echo "Initializing D3M Core on Goerli"

export FOUNDRY_ROOT_CHAINID
unset ETH_FROM
cast rpc anvil_setBalance $MCD_PAUSE_PROXY 0x10000000000000000 > /dev/null
cast rpc anvil_impersonateAccount $MCD_PAUSE_PROXY > /dev/null

forge script script/D3MCoreInit.s.sol:D3MCoreInitScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --broadcast --unlocked --sender $MCD_PAUSE_PROXY

cast rpc anvil_stopImpersonatingAccount $MCD_PAUSE_PROXY > /dev/null
