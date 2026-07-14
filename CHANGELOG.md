# Changelog

## 0.3.0.0 — 2026-07-08

- New `--sort` flag: stably sort transactions by date. Sorting is
  directive-bounded (directives and standalone comment blocks are barriers,
  so positional directives like `apply account`/`Y`/`alias` keep their
  scope) and stable (equal dates keep source order). A comment directly
  above a transaction travels with it. `--check --sort` verifies a file is
  both aligned and sorted. Default formatting is unchanged (whitespace-only);
  `hledger print` stays byte-identical either way.

## 0.2.1.0 — 2026-07-08

- An amount-less posting that carries only a balance assertion or cost
  (e.g. `Assets:Cash    = 0 RSD`) now reserves the number and commodity
  columns with blanks, so the `= …`/`@ …` tail lines up as if a zero amount
  stood in front of it, instead of sitting one commodity too far left.

## 0.2.0.0 — 2026-07-08

Changed alignment from per-transaction to file-wide.

- The account field is now padded past the longest account name in the whole
  file, and every first-amount number is right-aligned to a single shared
  column across all transactions (previously each transaction was aligned
  independently). `@`/`@@` costs and `=` assertions still trail the aligned
  amount with single-space separators.
- Output of multi-transaction files changes accordingly; single-transaction
  files are unaffected. Still whitespace-only: `hledger print` is unchanged.

## 0.1.0.2 — 2026-07-07

- Report a clean error and exit non-zero when a file cannot be read or
  written, instead of crashing with an uncaught `openFile` exception (e.g.
  `hledger fmt missing.ledger`). Remaining files are still processed.

## 0.1.0.1 — 2026-07-07

- Handle `--help`/`-h` and `--version` instead of treating them as file
  operands (which crashed with an `openFile` error, notably on
  `hledger fmt --help`). Unknown `-`-prefixed options now report an error
  and exit 2 rather than trying to open a file.
- `--check` with no file operands now checks stdin.

## 0.1.0.0 — 2026-07-07

Initial release.

- `hledger-fmt`: format-preserving hledger journal formatter. Reflows
  posting columns while touching only whitespace; directives, top-level
  comments, `include` lines, `P` price directives, and blank-line grouping
  pass through byte-for-byte, and numbers are never restyled.
- Line-oriented, no semantic parse: an indented run is reflowed as postings
  only when it follows a transaction header, so `account`/`commodity`
  sub-directives are left untouched.
- Amount alignment: the first amount's number is right-aligned to a common
  column per transaction; `@`/`@@` costs and `=` assertions follow with
  single-space separators and are not column-aligned.
- `--check`: writes nothing, exits non-zero on unformatted input (for CI
  and pre-commit); `-` or no operands stream stdin to stdout.
- `base`-only library and executable; no hledger-lib dependency.
- Tested with tasty golden fixtures (ragged widths, costs, assertions,
  amount-less legs, inline comments, single-space account names, trailing
  whitespace) plus an idempotence check, and a `hledger print`
  semantic-invariance harness.
