#!/usr/bin/env bash
set -e

[[ "$ETH_RPC_URL" && "$(cast chain)" == "ethlive" ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1; }

for ARGUMENT in "$@"
do
    KEY=$(echo "$ARGUMENT" | cut -f1 -d=)
    VALUE=$(echo "$ARGUMENT" | cut -f2 -d=)

    case "$KEY" in
            match)           MATCH="$VALUE" ;;
            match-test)      MATCH_TEST="$VALUE" ;;
            match-contract)  MATCH_CONTRACT="$VALUE" ;;
            block)           BLOCK="$VALUE" ;;
            *)
    esac
done

if [[ -z "$MATCH" && -z "$BLOCK" && -z "$MATCH_TEST" && -z "$MATCH_CONTRACT" ]]; then
    forge test --fork-url "$ETH_RPC_URL" -vv --force
elif [[ -z "$MATCH" && -z "$MATCH_TEST" && -z "$MATCH_CONTRACT" ]]; then
    forge test --fork-url "$ETH_RPC_URL" --fork-block-number "$BLOCK" -vv --force
else
    if [[ -n "$BLOCK" ]]; then
        if [[ -n "$MATCH" ]]; then
            forge test --fork-url "$ETH_RPC_URL" --match "$MATCH" --fork-block-number "$BLOCK" -vvv --force
        elif [[ -n "$MATCH_TEST" ]]; then
            forge test --fork-url "$ETH_RPC_URL" --match-test "$MATCH_TEST" --fork-block-number "$BLOCK" -vvv --force
        else
            forge test --fork-url "$ETH_RPC_URL" --match-contract "$MATCH_CONTRACT" --fork-block-number "$BLOCK" -vvv --force
        fi
    else
        if [[ -n "$MATCH" ]]; then
            forge test --fork-url "$ETH_RPC_URL" --match "$MATCH" -vvv --force
        elif [[ -n "$MATCH_TEST" ]]; then
            forge test --fork-url "$ETH_RPC_URL" --match-test "$MATCH_TEST" -vvv --force
        else
            forge test --fork-url "$ETH_RPC_URL" --match-contract "$MATCH_CONTRACT" -vvv --force
        fi
    fi
fi
