#
# Configurations
#
CABAL ?= cabal
DEV_TARGETS ?= test
TEST_SHOW_DETAILS_MODE ?= direct # alternatively: always | failure | never
TEST_PROP_NUM_RUNS ?= 1000
TEST_BUILDDIR ?= dist-test
TEST_COVERAGE_BUILDDIR ?= dist-coverage
DOCS_BUILDDIR ?= dist-docs

CABAL_TEST = $(CABAL) --builddir=$(TEST_BUILDDIR)
CABAL_COVERAGE = $(CABAL) --builddir=$(TEST_COVERAGE_BUILDDIR) --project-file=cabal.project.coverage
CABAL_DOCS = $(CABAL) --builddir=$(DOCS_BUILDDIR)
TEST_OPTIONS = \
	--test-show-details=$(TEST_SHOW_DETAILS_MODE) \
	--test-options="--maximum-generated-tests=$(TEST_PROP_NUM_RUNS)"

default: build

#
# Build
#
prepare:
	$(CABAL_TEST) v2-update

build:
	$(CABAL_TEST) v2-build all

clean: clean-dist

clean-docs:
	rm -rf dist-docs

clean-test:
	rm -rf dist-docs

clean-coverage:
	rm -rf dist-coverage

clean: clean-docs clean-test clean-coverage
	rm -rf dist-newstyle

.PHONY: default prepare build clean clean-*

#
# Testing
#
test:
	$(CABAL_TEST) \
		v2-test --enable-tests \
		$(TEST_OPTIONS) \
		all

test-coverage:
	$(CABAL_COVERAGE) \
		v2-test --enable-tests --enable-coverage \
		$(TEST_OPTIONS) \
		all

#
# Demos
#
demo-expo: build
	$(CABAL_TEST) v2-exec superfluid-validator -- --demo expo

demo-dfa: build
	$(CABAL_TEST) v2-exec superfluid-validator -- --demo dfa > dfa.ignore.dat
	gnuplot -p -e " \
		plot 'dfa.ignore.dat' using 1:2 with lines title 'alice', \
			 '' using 1:3 with lines title 'bob', \
			 '' using 1:4 with lines title 'carol', \
			 '' using 1:5 with lines title 'dan' \
		"
	rm -f dfa.ignore.dat

#
# Docs
#
docs-haddock:
	$(CABAL_DOCS) haddock all

YELLOWPAPER_ROOT=$(DOCS_BUILDDIR)/yellowpaper

$(YELLOWPAPER_ROOT)/tex:
	mkdir -p "$@"
$(YELLOWPAPER_ROOT)/tex/Paper.tex: yellowpaper/Paper.tex
	cp "$<" "$@"
$(YELLOWPAPER_ROOT)/tex/Biblio.bib: yellowpaper/Biblio.bib
	cp "$<" "$@"
$(YELLOWPAPER_ROOT)/tex/MoneyDistributionConcepts.tex: packages/core/src/Money/Distribution/Concepts.lhs
	./tasks/lhs2tex.sh "$<" > "$@"
$(YELLOWPAPER_ROOT)/tex/Communism.tex: packages/core/src/Money/Distribution/Communism.lhs
	./tasks/lhs2tex.sh "$<" > "$@"

$(YELLOWPAPER_ROOT)/tex/lhsfmt.tex:
	echo '%include lhs2TeX.fmt' | lhs2TeX > "$@"

YELLOWPAPER_INPUTS=$(YELLOWPAPER_ROOT)/tex \
	$(YELLOWPAPER_ROOT)/tex/MoneyDistributionConcepts.tex \
	$(YELLOWPAPER_ROOT)/tex/Communism.tex \
	$(YELLOWPAPER_ROOT)/tex/lhsfmt.tex \
	$(YELLOWPAPER_ROOT)/tex/lhsfmt.tex \
	$(YELLOWPAPER_ROOT)/tex/Biblio.bib \
	$(YELLOWPAPER_ROOT)/tex/Paper.tex
$(YELLOWPAPER_ROOT)/pdflatex/superfluid-yellowpaper.pdf: $(YELLOWPAPER_INPUTS)
	ls $(YELLOWPAPER_ROOT)/tex
	rm -rf $(YELLOWPAPER_ROOT)/pdflatex
	mkdir -p $(YELLOWPAPER_ROOT)/pdflatex
	cd $(YELLOWPAPER_ROOT)/pdflatex; { \
		pdflatex -shell-escape -jobname=superfluid-yellowpaper ../tex/Paper.tex; \
		biber superfluid-yellowpaper.bcf; \
		pdflatex -shell-escape -jobname=superfluid-yellowpaper ../tex/Paper.tex; \
	}

docs-yellowpaper: $(YELLOWPAPER_ROOT)/pdflatex/superfluid-yellowpaper.pdf

docs: docs-haddock docs-yellowpaper

.PHONY: docs-haddock docs

#
# Dev Environment
#
dev:
	nodemon -e hs,cabal -i dist -x "make $(DEV_TARGETS) || exit 1"

repl-simple:
	$(CABAL_TEST) repl superfluid-protocol-system-simple

cloc:
	@echo '**** Core Source Files ****'
	cloc packages/core/src
	@echo

	@echo '**** Simple System Source Files ****'
	cloc packages/simple/src
	@echo

	@echo '**** Validator Source Files ****'
	cloc packages/validator/src
	@echo

	@echo '**** Test Files ****'
	cloc packages/*/test
	@echo

.PHONY: demo-* test test-* dev repl-* cloc
