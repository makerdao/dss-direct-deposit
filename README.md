# Direct Deposit Module for Maker
![Build Status](https://github.com/makerdao/dss-direct-deposit/actions/workflows/.github/workflows/tests.yaml/badge.svg?branch=master)

The Dai Direct Deposit Module (D3M) is a tool for directly injecting DAI into third party protocols.

![D3M](https://imgur.com/kiV7g2f.png)

As seen in the image above, external protocols are viewed under the simplified ERC-4626-like interface. Pool adapters are used to convert protocol complexity into simplified concepts of Excess Capacity + DAI liquidity + DAI outstanding. How DAI is converted between these states is completely protocol-specific and mostly irrelevant to the D3M.

The D3M is made of 3 components on the Maker side:

### D3MHub

The primary manager contract responsible for collecting all information and determining which action to take (if any). Each D3M instance is regsitered on the Hub using relevant `file(ilk, ...)` admin functions.

A permissionless `exec(ilk)` function exists which will perform all necessary steps to update the provided liquidity within the debt ceiling and external protocol constraints. `exec(ilk)` will need to be called on a somewhat regular basis to keep the system running properly. Upon unwinding, interest will automatically be collected, but you can also permissionlessly call `reap(ilk)` to pull in all collected interest as well.

### D3MPool

A "dumb" adapter which is responsible for depositing or withdrawing DAI from the target protocol based on instructions from the Hub. Also contains functions which provide information such as `maxDeposit()` and `maxWithdraw()`. These inform the hub the maximum room to deposit or withdraw respectively. Abstractly we view this `maxWithdraw()` value as the available DAI liquidity that can be immediately withdrawn. Different protocols have different mechanisms for making DAI liquidity available. For example, some protocols raise interest rates to encourage more 3rd party deposits (or repays from borrowers). In the other cases, there could be a function such as `intendToWithdraw()` which signals to the pool operator that they should begin liquidating some positions to free up DAI.

### D3MPlan

The D3MPlan can be viewed as the targeting logic for D3M instances. The plan is responsible for reading all relevant information from its state (i.e. the target rate) and possibly from the external protocol (i.e. current balance of supply and borrowing in the market) and condensing this down to a debt target. This desired target debt is forwarded to the Hub to take action to reach this target debt level asap.

# Specific Implementations

## Aave D3M

### Configuration

Below are the configurable parameters for the Aave DAI D3M:

- `tau` [seconds] - The expiry for when bad debt is sent to the vow debt queue. This must be set during initialization to enforce a deadline for when this module is considered to be in a failure mode where no more liquidity is available in the pool to unwind. Unwinding can still occur after this period elapses.
- `bar` [ray] - The target borrow rate on Aave for the DAI market. This module will aim to enforce that borrow limit.

Any stkAave that is accured can be permissionlessly collected into the pause proxy by calling `collect()`.
