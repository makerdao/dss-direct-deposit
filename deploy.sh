#!/bin/bash
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
            *)
    esac
done

[[ -n "$FOUNDRY_SCRIPT_CONFIG" ]] || {
    echo "Please specify the D3M configration JSON. Example: ./deploy.sh config=aave";
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

[[ "$FOUNDRY_ROOT_CHAINID" == "1" ]] && echo "Deploying '$FOUNDRY_SCRIPT_CONFIG' D3M on Mainnet"
[[ "$FOUNDRY_ROOT_CHAINID" == "5" ]] && echo "Deploying '$FOUNDRY_SCRIPT_CONFIG' D3M on Goerli"

mkdir -p "script/output/$FOUNDRY_ROOT_CHAINID"

export FOUNDRY_ROOT_CHAINID
export FOUNDRY_EXPORTS_NAME="$FOUNDRY_SCRIPT_CONFIG"
forge script script/D3MDeploy.s.sol:D3MDeployScript --use solc:0.8.14 --rpc-url "$ETH_RPC_URL" --sender "$ETH_FROM" --broadcast --verify
