# IMDwindowshopper test properties

The suite tests the deployed `IMDwindowshopper` implementation through its public
interface. It uses the repository's existing Foundry and OpenZeppelin dependencies;
no fork, network, environment configuration, storage patching, or additional packages
are needed by the tests. All named actors are local test accounts.

`IMDwindowshopper.t.sol` retains the original deployment, metadata, mint event,
factory, ERC-20, unauthorized-call, and token distribution checks.
`IMDwindowshopper.properties.t.sol` adds boundary cases and algebraic properties.
`IMDwindowshopper.invariant.t.sol` extends the existing handler and independent ledger.

The five discovery passes suggested by the supplied Pashov fizz reference were
applied to this token, with the Trail of Bits property-testing reference used to
review input bounds, rollback assertions, and vacuous properties:

| Discovery pass | Property and evidence | Executable coverage |
| --- | --- | --- |
| Conservation | The constructor mints exactly `10**27` units once (`src/IMDwindowshopper.sol:11-14`). All tracked balances must sum to this fixed supply; every balance must match the independent transfer ledger. | Existing constructor tests and `invariant_balancesAllowancesAndSupplyMatchIndependentLedger`. |
| Round trips | Moving units out and back restores both balances; splitting a transfer delivers the same amount. There is no fee or unit conversion in inherited `ERC20._update` (`lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol:188`). | `fullBalanceRoundTrip`, partial round-trip fuzzing, and split delegated/direct transfer comparison. Each round-trip leg is checked. |
| State transitions | An approval replaces one owner's allowance for one spender. Finite spending reduces it; only `uint256.max` is infinite (`ERC20.sol:132,154,284,305`). Failure must preserve the allowance and balances. | Independent allowance matrix, `approveBoundary`, approved-failure handlers, idempotence/isolation tests, largest finite approval, revocation, and refill-after-exhaustion tests. |
| Adversarial inputs | Neither an outsider nor a spender approved by a different owner may move a holder's tokens. Even an approved self-transfer needs sufficient balance. A holder can move its full balance. | Unauthorized-spend handlers, cross-owner approval test, approved self-transfer fuzzing, maximum-input rejection, and full-balance round trips. |
| Token-specific properties | Zero amounts cannot bypass invalid-address checks. Self-transfers preserve balances but delegated self-transfers consume finite allowances. Tokens sent to the token contract are still part of the fixed supply. | `rejectZeroRecipient`, `rejectZeroSpender`, `selfSpend`, zero-amount unit/fuzz tests, and token-contract recipient test. |

The stateful campaign uses four holders and an outsider. Eleven explicitly selected
handler actions mutate or probe the token; inherited test utilities are not targets.
The ledger is initialized from the specified supply, updated from requested actions,
and never repaired from observed token balances. It checks all four balances and all
16 owner/spender allowances after each action, together with supply conservation
and zero balances at the zero address, test contract, and token contract.

Boundary approvals deliberately include zero, one, the entire supply, `uint256.max - 1`,
and `uint256.max`. The full-balance and self-spend actions select a funded holder to
guarantee positive amounts. Approved failure actions establish a sufficient allowance
before provoking the error, so they reach the balance/recipient checks. Expected
reverts are matched explicitly; any unexpected handler revert fails the campaign.

Inline settings select 1,024 runs for each new fuzz property and 256 invariant
sequences of 128 calls. Deterministic tests also pin one-unit, zero-address/zero-amount,
full-supply, and maximum-uint behavior. No new test discards fuzz inputs with `assume`.

Run from the repository root:

```sh
forge build --offline
FOUNDRY_FUZZ_SEED=0x17f59ceee1debb6dc5a092ba99dce20b1d3e8411c9b0c8e079e9d53b42b1d1e4 forge test --offline
```

To keep generated build artifacts inside disposable test storage, prefix both
commands with `FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache`.
Nothing under `test/scratch/` is part of the delivered suite.

The supplied launch-floor checks were reviewed as acceptance context. The local
factory/distribution tests cover exact token movements only; they do not substitute
for the verifier's separate PoolManager integration or deployment-manifest checks.
