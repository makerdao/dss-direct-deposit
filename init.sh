#!/bin/bash
# NOTE: This can only be run against an anvil-node. Production initialization needs to be done in the spell.
set -e

for ARGUMENT in "$@"
do
    KEY=$(echo "$ARGUMENT" | cut -f1 -d=)
    VALUE=$(echo "$ARGUMENT" | cut -f2 -d=)

    if [ "$VALUE" = "" ]; then
        continue
    fi

    case "$KEY" in
            config)         export FOUNDRY_SCRIPT_CONFIG="$VALUE" ;;
            d3m)            D3M="$VALUE" ;;
            *)
    esac
done

[[ -n "$FOUNDRY_SCRIPT_CONFIG" ]] || {
    echo "Please specify the D3M configration JSON. Example: ./init.sh config=aave";
    exit 1;
}

[[ -n "$MCD_PAUSE_PROXY" ]] || {
    echo "Please set MCD_PAUSE_PROXY";
    exit 1;
}

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

[[ "$FOUNDRY_ROOT_CHAINID" == "1" ]] && echo "Initializing '$FOUNDRY_SCRIPT_CONFIG' D3M on Mainnet"
[[ "$FOUNDRY_ROOT_CHAINID" == "5" ]] && echo "Initializing '$FOUNDRY_SCRIPT_CONFIG' D3M on Goerli"

export FOUNDRY_ROOT_CHAINID
FOUNDRY_SCRIPT_DEPS_TEXT=$(jq -sc ".[0] * .[1]" script/output/"$FOUNDRY_ROOT_CHAINID"/core-latest.json script/output/"$FOUNDRY_ROOT_CHAINID"/"$D3M"-latest.json)
export FOUNDRY_SCRIPT_DEPS_TEXT
unset ETH_FROM
cast rpc anvil_setBalance "$MCD_PAUSE_PROXY" 0x10000000000000000 > /dev/null
cast rpc anvil_impersonateAccount "$MCD_PAUSE_PROXY" > /dev/null

forge script "script/init/D3MInit${D3M}.s.sol:D3MInit${D3M}Script" --use solc:0.8.14 --rpc-url "$ETH_RPC_URL" --broadcast --unlocked --sender "$MCD_PAUSE_PROXY"

cast rpc anvil_stopImpersonatingAccount "$MCD_PAUSE_PROXY" > /dev/null
