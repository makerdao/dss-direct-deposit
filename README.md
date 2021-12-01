# Direct Deposit Module for Maker
![Build Status](https://github.com/makerdao/dss-direct-deposit/actions/workflows/.github/workflows/tests.yaml/badge.svg?branch=master)

The Direct Deposit Module interfaces with third party lending protocols to enable a maximum variable borrow rate for selected assets. Maker Governance is able to pick a target variable borrow rate, and the module will automatically deposit/remove liquidity to ensure that target rate is hit.

## DssDirectDepositAaveDai

### Configuration

Below are the configurable parameters for the Aave DAI D3M:

- `tau` [seconds] - The expiry for when bad debt is sent to the vow debt queue. This must be set during initialization to enforce a deadline for when this module is considered to be in a failure mode where no more liquidity is available in the pool to unwind. Unwinding can still occur after this period elapses.
- `bar` [ray] - The target borrow rate on Aave for the DAI market. This module will aim to enforce that borrow limit.

### Operation

A permissionless `exec()` function exists which will perform all necessary steps to enforce the maximum borrow rate to within the available liquidity and debt ceiling constraints. `exec()` will need to be called on a somewhat regular basis to keep the system running properly. Upon unwinding interest will automatically be collected, but you can also permissionlessly call `reap()` to pull in all collected interest as well.

Any stkAave that is accured can be permissionlessly collected into the pause proxy by calling `collect(address[], uint256)`.
