#!/usr/bin/env bash
set -e

BLOCK=$(cast block-number)
START=$((BLOCK-50))
echo "Checking from $START to $BLOCK"

for i in $( eval echo {$START..$BLOCK} )
do
    echo "==================== RUNNING TESTS AT BLOCK $i ===================="
    forge test --fork-url "$ETH_RPC_URL" --fork-block-number "$i" -v --force
done
