#!/usr/bin/env bash
set -e

[[ "$ETH_RPC_URL" && "$(seth chain)" == "ethlive" ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1; }

for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)

    case "$KEY" in
            match)  MATCH="$VALUE" ;;
            block)  BLOCK="$VALUE" ;;     
            *)   
    esac
done

if [[ -z "$MATCH" && -z "$BLOCK" ]]; then
    forge test --fork-url "$ETH_RPC_URL" -vv --force
elif [[ -z "$BLOCK" ]]; then
    forge test --fork-url "$ETH_RPC_URL" --match "$MATCH" -vvv --force
elif [[ -z "$MATCH" ]]; then
    forge test --fork-url "$ETH_RPC_URL" --fork-block-number "$BLOCK" -vv --force
else
    forge test --fork-url "$ETH_RPC_URL" --match "$MATCH" --fork-block-number "$BLOCK" -vvv --force
fi
