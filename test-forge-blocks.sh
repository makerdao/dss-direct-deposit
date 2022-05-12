#!/usr/bin/env bash
set -e

for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)

    case "$KEY" in
            url) URL="$VALUE" ;;
            *)
    esac
done

BLOCK=$(cast block-number)
START=$((BLOCK-50))
echo "Checking from $START to $BLOCK"

for i in $( eval echo {$START..$BLOCK} )
do
    echo "================================ $i ================================"
    forge test --fork-url "$URL" --fork-block-number "$i" -v --force
done
