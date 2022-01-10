#!/usr/bin/env bash
set -e

[[ "$(seth chain --rpc-url="$ETH_RPC_URL")" == "ethlive" ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1; }

for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)

    case "$KEY" in
            match)      MATCH="$VALUE" ;;
            runs)       RUNS="$VALUE" ;;
            *)
    esac

done

export DAPP_BUILD_OPTIMIZE=1
export DAPP_BUILD_OPTIMIZE_RUNS=200

if [[ -z "$MATCH" && -z "$RUNS" ]]; then
    dapp --use solc:0.6.12 test --rpc-url="$ETH_RPC_URL" --fuzz-runs 1 -vv
elif [[ -z "$RUNS" ]]; then
    dapp --use solc:0.6.12 test --rpc-url="$ETH_RPC_URL" --match "$MATCH" --fuzz-runs 1 -vv
elif [[ -z "$MATCH" ]]; then
    dapp --use solc:0.6.12 test --rpc-url="$ETH_RPC_URL" --fuzz-runs "$RUNS" -vv
else
    dapp --use solc:0.6.12 test --rpc-url="$ETH_RPC_URL" --match "$MATCH" --fuzz-runs "$RUNS" -vv
fi
