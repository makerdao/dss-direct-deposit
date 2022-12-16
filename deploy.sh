#!/bin/bash
set -e

for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)

    case "$KEY" in
            type)            export DEPLOY_D3M_TYPE="$VALUE" ;;
            admin)           export DEPLOY_ADMIN="$VALUE" ;;
            ilk)             export DEPLOY_ILK="$VALUE" ;;
            aave-pool)       export DEPLOY_AAVE_LENDING_POOL="$VALUE" ;;
            compound-cdai)   export DEPLOY_COMPOUND_CDAI="$VALUE" ;;
            *)
    esac
done

echo "Deploying contracts..."
forge script script/DeployD3M.s.sol:DeployD3M --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
