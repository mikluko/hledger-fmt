# hledger-fmt

A format-preserving formatter for [hledger](https://hledger.org) journals. It
aligns posting columns while touching **only whitespace**: directives,
top-level comments, `include` lines, `P` price directives, and blank-line
grouping pass through byte-for-byte, and numbers are never restyled.

Unlike `hledger print`, which is lossy on structure (it emits transactions
only, drops directives and comments, and restyles amounts to each commodity's
display style), `hledger-fmt` is safe to run over a whole ledger tree,
including price-only and `include`-only files.

The library and executable depend on `base` only, so the tool builds with the
GHC toolchain already present wherever hledger is used, with no extra
runtime dependencies.

## Install

```sh
cabal install hledger-fmt
```

Or grab a prebuilt binary from the [releases page](https://github.com/mikluko/hledger-fmt/releases).

Naming the binary `hledger-fmt` lets hledger dispatch to it as an add-on, so
`hledger fmt ...` works the same as `hledger-fmt ...`.

## Usage

```
hledger-fmt [--check] [--sort] [FILE|-]...
```

- `hledger-fmt FILE...` — format each file in place.
- `hledger-fmt --check FILE...` — write nothing; exit non-zero if any file is
  not already formatted, listing offenders (for CI and pre-commit).
- `hledger-fmt --sort FILE...` — also sort transactions by date (see below).
- `hledger-fmt -` or no arguments — format stdin to stdout.

Format every tracked journal:

```sh
hledger-fmt $(git ls-files '*.ledger' '*.journal')
```

## What it does

Alignment is computed once over the whole file, so amounts line up in a
single column across every transaction:

1. Posting indent normalized to 4 spaces.
2. Account and amount are separated by a run of two or more spaces (hledger's
   rule; account names may contain single spaces).
3. The account field is padded past the longest account name in the file, then
   the first amount's number is right-aligned to one shared column, then one
   space, then the commodity. A trailing `@`/`@@` cost and `= assertion`
   follow with single-space separators and are not column-aligned:

   ```ledger
       A:B                          10.00 USD
       C:D                         -10.00 USD

       Expenses:Groceries:Weekly   100.00 EUR @ 1.20 USD
       Assets:Bank:Checking       -120.00 USD
   ```

4. Amount-less postings (the implicit balancing leg) get the account only,
   trailing whitespace trimmed. If such a posting carries only a balance
   assertion or cost (e.g. `= 0 RSD`), the amount column is reserved with
   blanks so the tail lines up as if a zero amount stood in front of it:

   ```ledger
       Expenses:Unknown
       Assets:Cash                = 0 RSD
   ```
5. Inline posting comments are preserved and normalized to 2 spaces before `;`.
6. Numbers are never restyled: digit grouping, decimal places, and sign
   spacing are copied through unchanged.

It is line-oriented and builds no semantic model. An indented run is reflowed
as postings only when it follows a transaction header, so `account` and
`commodity` sub-directives are left untouched.

Formatting is idempotent: `hledger-fmt` on already-formatted output is a no-op.

## Sorting (`--sort`)

`--sort` additionally reorders transactions by date. The sort is **stable**
(transactions with the same date keep their source order) and
**directive-bounded**: directives (`P`, `include`, `account`, `apply account`,
`Y`, `alias`, …) and standalone comment blocks act as barriers, and
transactions are only reordered within the runs between them. This keeps
positional directives (`apply account`, `Y`, `alias`) in scope. A comment line
directly above a transaction (no blank line between) travels with it.

Because `hledger print` sorts by date anyway, `--sort` still changes only what
`print` ignores: `hledger print` output is byte-identical before and after.

```sh
hledger-fmt --sort file.journal          # align + sort in place
hledger-fmt --check --sort file.journal  # is it aligned and sorted?
```

## Non-goals

- No number or commodity-style normalization (that is `print`'s lossy job).
- No `include` following: one file is formatted at a time, like a linter.
- No semantic parse, valuation, balancing, or assertion checking.
- No reordering of postings or transactions.

## Development

```sh
make build        # cabal build
make test         # tasty: golden fixtures, idempotence, --check
make test-semantic  # hledger print must be byte-identical before/after
make lint         # hlint
make fmt          # fourmolu --mode inplace
make fmt-check    # fourmolu --mode check
```

The **semantic invariant** is the safety net: for every self-contained
fixture, `hledger print` before and after formatting must be byte-identical.
If it differs, the tool changed meaning, not just whitespace, and the test
fails.

## License

MIT
