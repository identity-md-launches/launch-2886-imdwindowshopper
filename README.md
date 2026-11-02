# IMDwindowshopper (WWW)

A fixed-supply ERC-20 for the requested custom-token launch. The entire supply is
minted once in the constructor to the immediate deployer (`msg.sender`).

| Property | Value |
| --- | --- |
| Solidity contract | `src/IMDwindowshopper.sol:IMDwindowshopper` |
| Name | `IMDwindowshopper` |
| Symbol | `WWW` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Base-unit supply | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None; ABI-encoded arguments are empty |
| Constructor payment | Zero; constructor is nonpayable |
| Initial recipient | Immediate deployer; the factory in the IMD launch |
| Application contracts | None |

## Design and assumptions

The worker selected OpenZeppelin Contracts **v5.0.2** ERC-20 as the implementation
base. The requested metadata and supply are fixed, and `INITIAL_SUPPLY` is a named
constant. The constructor calls `_mint` once. No externally callable method can
mint or burn, change metadata, pause transfers, blacklist holders, seize balances,
or upgrade the contract. There is no owner or administrative role.

Because no special transfer behavior was requested, the worker selected standard
ERC-20 behavior: exact transfers without tax, reflection, rebasing, hooks, or
external calls. Zero-value transfers and self-transfers are supported; transfers
to the zero address and approvals for the zero spender revert. Amounts are in base
units. Successful `transfer`, `approve`, and `transferFrom` calls return `true`;
invalid operations revert with OpenZeppelin's ERC-6093 custom errors.

Finite allowances decrease on `transferFrom`. An allowance of `uint256.max` keeps
the dependency's conventional unlimited-approval semantics. `approve` replaces
the previous allowance and emits `Approval`; this version does not emit an
additional `Approval` when `transferFrom` spends allowance. Transfers, including
the constructor mint and zero-value transfers, emit `Transfer`.

There are no oracle, signature, randomness, external-service, payable, or
maintenance dependencies. Plain ETH transfers and unknown selectors revert.
There is no asset-recovery function: tokens sent to this token contract, or assets
otherwise stranded there, cannot be retrieved by an administrator.

## Build and test offline

Use Foundry with Solidity **0.8.26** installed. All Solidity dependencies are
ordinary files under `lib/`; no package installation, submodule, RPC, environment
secret, or network access is required to build or execute tests. The compiler
binary is a toolchain prerequisite and is not part of the source deliverable.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x17f59ceee1debb6dc5a092ba99dce20b1d3e8411c9b0c8e079e9d53b42b1d1e4 forge test
forge fmt --check
sha256sum -c lib/checksums.sha256
```

`foundry.toml` pins compiler `0.8.26` and `bytecode_hash = "none"` as required.
Worker-selected build settings are the Cancun EVM target, optimization enabled
with 200 runs, 1,024 runs per fuzz test, and 256 invariant sequences of 64 calls.
Tests neither read nor change environment variables. The seed above is supplied
to Foundry by the shell; the project does not override it in configuration.
FFI and filesystem permissions are not enabled.

The unit/fuzz suite checks metadata, exact minting and its event, direct and
CREATE2 factory deployment, transfer events and edge cases, allowance lifecycle,
unauthorized spending, revert atomicity, and the absence of common mint, burn,
admin, and upgrade entry points. The invariant handler compares balances and
allowances to an independent ledger over repeated transfers, approvals, delegated
spending, and invalid actions, checking that all supply remains accounted for.

The local distribution test checks exact 10%/80%/10% token movements, a distributor
claim, and transfers into and out of a simulated pool balance holder. It does not
instantiate Uniswap or prove live swaps or liquidity pricing. The supplied
protected tests were read as acceptance definitions; their factory/Uniswap
integration and owner checks belong to the network's separate launch harness.
They are not copied into this project or represented as local test results.

Local verification passed: `forge build`, a forced `forge build --offline --force`,
`forge fmt --check`, and all dependency checksums. With the prescribed seed,
`forge test -vv` passed all 32 tests: 25 deterministic tests, six fuzz tests with
1,024 cases each, and one invariant with 256 sequences / 16,384 calls and no
unexpected handler reverts. Compiled-artifact inspection confirmed a no-argument,
nonpayable constructor, the expected ERC-20 ABI, no link references, and a
1,752-byte runtime. A scan matching the supplied protected test's opcode rules
found no reachable `DELEGATECALL`, `CALLCODE`, or `SELFDESTRUCT`.

## Deployment parameters and handoff

Deploy the compiled creation bytecode for `IMDwindowshopper` directly, with no
arguments or initialization transaction. `out/IMDwindowshopper.sol/IMDwindowshopper.json`
contains the compiler artifact after a build. There are no linked external
libraries or proxies. The Solidity name fits the launch's 32-character limit.

The immediate caller creating the contract receives all `10^27` base units. For
the assigned launch this must be the launch factory, which subsequently allocates
the supply. A different deploying wrapper would receive the tokens itself; the
constructor does not mint to `tx.origin` or an eventual end user. The factory's
initial balance is ordinary ownership of tokens, not a privileged contract role.

The brief supplies the following launch settings for the separate manifest step.
They are not constructor parameters and the token does not allocate these shares
or operate a pool itself.

| Launch field | Brief-supplied value |
| --- | --- |
| Chain | Ethereum, chain ID `1` |
| Paired currency (IMD, 18 decimals) | `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Manifest `pool.initialPrice` | `79228162514264337593543950336` |
| `economics.poolBps` | `8000` |
| `economics.initialMarketCapWei` | `2500000000000000000000` |
| `economics.remainderTo` | `0xee2aaa315cf7ed169f93148d30d24af9318dbb66` |

The factory sends 10% (100,000,000 WWW) to the launch distributor, allocates 80%
(800,000,000 WWW) to seed the pool, and sends the remaining 10% (100,000,000 WWW) to
the specified remainder recipient. Every such transfer delivers its exact amount.
The launch system derives the actual opening price from the supplied market cap,
supply, and currency ordering, as described in the brief. The manifest's supplied
price value is not an independent market quote. These launch values are copied
from the assignment, not worker-selected addresses or settings.

This implementation task does not produce `launch.json`; the later manifest step
owns it and must use the compiled token and the brief's exact economics. There is
no deployment script, key requirement, transaction broadcast, or claimed deployed
address in this deliverable.

## After launch

No owner setup, setters, keeper, or scheduled operation is required. The network's
deployer is responsible for manifest validation, independent review, launch
transactions, liquidity initialization and distribution, and source verification
using these compiler settings. At deployment, verify the metadata, total supply,
constructor mint event, and factory receipt before distribution. Check allocation
events and pool behavior in the launch harness and on the selected chain.

Holders are responsible for recipient addresses and spender approvals. Integrators
should read current allowances and handle standard ERC-20 reverts. Prefer bounded
allowances; when replacing an existing nonzero allowance, revoke it and confirm
that transaction before granting a new amount to reduce the usual ERC-20 approval
race exposure. The contract cannot undo transfers or recover lost keys.

The implementation uses the supplied security reference to check supply arithmetic,
authorization, zero-address behavior, rollback, and external-call exposure. Local
tests are not an independent security audit. Slither and Mythril are not run as
part of this implementation; independent adversarial review and launch integration
remain responsibilities of the release process.
