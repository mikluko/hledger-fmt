# Changelog

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
