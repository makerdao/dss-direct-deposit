#!/bin/bash
set -e

for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)
    [[ -z "${VALUE}" ]] && continue

    case "$KEY" in
            chainlog)        export D3M_CHAINLOG="$VALUE" ;;
            admin)           export D3M_ADMIN="$VALUE" ;;
            *)
    esac
done

echo "Deploying contracts..."
rm -f out/contract-exports.env
forge script script/D3MCoreDeploy.s.sol:D3MCoreDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
