CABAL ?= cabal

.PHONY: build test test-semantic lint fmt fmt-check clean

build:
	$(CABAL) build

test:
	$(CABAL) test --test-show-details=direct

# Semantic invariant (the safety net): `hledger print` must be byte-identical
# before and after formatting. Requires the hledger binary on PATH.
test-semantic: build
	./test/semantic.sh "$$($(CABAL) list-bin hledger-fmt)"

lint:
	hlint src app test

fmt:
	fourmolu --mode inplace src app test

fmt-check:
	fourmolu --mode check src app test

clean:
	$(CABAL) clean
