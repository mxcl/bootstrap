# mxcl’s Bootstrap

A package manager *manager* and other mad shit for science.

* Python managed by `uv`
  * `/usr/local/bin/python3.9`—`python3.13` are little shims that delegate
    through to `uv`
  * `python3`, `python`, `pip3`, `pip` symlinks to Python 3.12
* Node from the vendor installed securely
* Git from Xcode Command Line Tools (if installed, else brew)
* Rust ecosystem managed with rustup
* Crates run via `cargox`
* Brew’d stuff run via `brewx`
* Most simple binaries download straight from the vendor (Github releases)
* Auto install shims for casks like `code` and `ollama`
* Custom built `aws` that is minimal AF and installed securely

> [!TIP]
>
> ## Ready for Agents
>
> Let your agents use whatever they need.
>
> Many things with bootstrap are stubs that zeroconf install things on demand.
> Using vendor provided solutions where possible.
>
> We install stubs for all common python versions and symlink `python` to 3.12

> [!TIP]
>
> ## Secure for Agents
>
> Everything important is installed *as root*.
>
> Agents are our friends. Probably. Still, let’s not give them more power
> than they need. Installing important things as root means agents can’t
> mess with them.

## Installation

```sh
curl -Ssf https://mxcl.dev/bootstrap/setup.sh |
  sudo bash -exo pipefail &&
  outdated --apply
```

Or if you hate `curl | sh` stuff then clone this repo and run `./install.sh`.
This route *does nothing*, it just outputs what it would do and tells you how
to then do it yourself.

## Outdated Script

Check for outdated installs and upgrade only what needs it by running:

```sh
$ outdated
```

- `outdated` has no side effects; it prints an apply script to stdout.
- Apply immediately with:
  ```sh
  outdated | sh
  ```
- Each managed item is checked for outdated status first.

## `/usr/local/bin`

Why? Because everything looks there. Not everything looks in
`/opt/homebrew/bin` or `~/.local/bin`.

We install a mix of stubs that delegate to `foox` tools and direct installs.

## Details

### Python

We use `uv` managed pythons. Because they do it properly. Unlike everyone
else.

### Rust

Your rust toolchain is managed via `rustup`. The stubs seemlessly delegate to
it and install it as required.

We do not mangle your shell environment with `source $HOME/.cargo/env`
instead the stubs dynamically inject that.
