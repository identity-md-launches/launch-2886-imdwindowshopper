# Vendored dependencies

These are ordinary source files, not submodules or generated package directories.
No downloads take place during builds. Production code imports only the listed
OpenZeppelin dependency closure. Forge Std is used only by tests.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | `v5.0.2` | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol`, `LICENSE` | MIT |
| [Forge Std](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | Upstream `src/` and both license files | MIT or Apache-2.0 |

The worker selected these versions; the requester did not specify library
versions. Sources are unmodified. OpenZeppelin files were retrieved from
`https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v5.0.2/`.
Forge Std was retrieved from
`https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7`; that
archive's SHA-256 is
`45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.
The archive itself is not needed and is not included.

`lib/checksums.sha256` records SHA-256 hashes of every vendored source and license
file. Run `sha256sum -c lib/checksums.sha256` from the project root to check them.
This is an integrity inventory of the vendored files, not a claim of an audit.
