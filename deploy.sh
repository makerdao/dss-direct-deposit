#!/bin/bash
set -e

for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)
    [[ -z "${VALUE}" ]] && continue

    case "$KEY" in
            chainlog)        export D3M_CHAINLOG="$VALUE" ;;
            type)            export D3M_TYPE="$VALUE" ;;
            plan-type)       export D3M_PLAN_TYPE="$VALUE" ;;
            admin)           export D3M_ADMIN="$VALUE" ;;
            ilk)             export D3M_ILK="$VALUE" ;;
            aave-pool)       export D3M_AAVE_LENDING_POOL="$VALUE" ;;
            compound-cdai)   export D3M_COMPOUND_CDAI="$VALUE" ;;
            *)
    esac
done

echo "Deploying contracts..."
rm -f out/contract-exports.env
forge script script/D3MDeploy.s.sol:D3MDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
