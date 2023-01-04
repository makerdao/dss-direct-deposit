#!/bin/bash
set -e

for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)

    if [ "$VALUE" = "" ]; then
        continue
    fi

    case "$KEY" in
            config)         export FOUNDRY_SCRIPT_CONFIG="$VALUE" ;;
            config-ext)     export FOUNDRY_SCRIPT_CONFIG_TEXT=$(jq -c < $VALUE) ;;
            *)
    esac
done

rm -f out/contract-exports.env
forge script script/D3MDeploy.s.sol:D3MDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
