# A basic Makefile for building and installing Batteries Included
# It punts to ocamlbuild for all the heavy lifting.

NAME = batteries

VERSION := $(shell grep "^Version:" _oasis | cut -c 15-)
uname_S := $(shell sh -c 'uname -s 2>/dev/null || echo not')

# Define variables and export them for mkconf.ml
DOCROOT ?= /usr/share/doc/ocaml-batteries
export DOCROOT
BROWSER_COMMAND ?= x-www-browser
export BROWSER_COMMAND

OCAMLBUILD ?= ocamlbuild
OCAMLBUILDFLAGS ?= -no-links

ifeq ($(uname_S),Darwin)
  BATTERIES_NATIVE ?= yes
  BATTERIES_NATIVE_SHLIB ?= no
else
  BATTERIES_NATIVE ?= yes
  BATTERIES_NATIVE_SHLIB ?= $(BATTERIES_NATIVE)
endif

# Directory where to find qtest
QTESTDIR ?= qtest

INSTALL_FILES = _build/META _build/src/*.cma \
	battop.ml _build/src/*.cmi _build/src/*.mli \
	_build/src/batteriesHelp.cmo \
	_build/src/syntax/pa_comprehension/pa_comprehension.cmo \
	_build/src/syntax/pa_strings/pa_strings.cma \
	_build/src/syntax/pa_llist/pa_llist.cmo \
	_build/libs/*.cmi _build/libs/*.mli \
	_build/$(QTESTDIR)/qtest
OPT_INSTALL_FILES = _build/src/*.cmx _build/src/*.a _build/src/*.cmxa \
	_build/src/*.cmxs _build/src/*.lib _build/libs/*.cmx \

# What to build
TARGETS = syntax.otarget
TARGETS += src/batteries.cma
TARGETS += src/batteriesHelp.cmo
TARGETS += src/batteriesThread.cma
TARGETS += META
BENCH_TARGETS  = benchsuite/bench_int.native
BENCH_TARGETS += benchsuite/flip.native
BENCH_TARGETS += benchsuite/deque.native
BENCH_TARGETS += benchsuite/lines_of.native
BENCH_TARGETS += benchsuite/bitset.native
BENCH_TARGETS += benchsuite/bench_map.native
TEST_TARGET = test-byte

ifeq ($(BATTERIES_NATIVE_SHLIB), yes)
  EXT = native
  MODE = shared
  TARGETS += src/batteries.cmxs src/batteriesThread.cmxs
  TEST_TARGET = test-native
else
ifeq ($(BATTERIES_NATIVE), yes)
  EXT = native
  MODE = native
  TARGETS += src/batteries.cmxa src/batteriesThread.cmxa
  TEST-DEPS = test-native
else
  EXT = byte
  MODE = bytecode
endif
endif

.PHONY: all clean doc install uninstall reinstall test test-native test-byte qtest _build/$(QTESTDIR)/qtest camfail camfailunk coverage coverage/index.html man

all: _build/$(QTESTDIR)/qtest
	@echo "Build mode:" $(MODE)
	$(OCAMLBUILD) $(OCAMLBUILDFLAGS) $(TARGETS)

clean:
	@${RM} src/batteriesConfig.ml batteries.odocl bench.log
	@${RM} $(QTESTDIR)/all_tests.ml
	@${RM} -r man/
	@$(OCAMLBUILD) -clean
	@echo " Cleaned up working copy" # Note: ocamlbuild eats the first char!

batteries.odocl: src/batteries.mllib src/batteriesThread.mllib
	cat $^ > $@

doc: batteries.odocl
	$(OCAMLBUILD) batteries.docdir/index.html

man: all batteries.odocl
	-mkdir man
	ocamlfind ocamldoc -package threads.posix -sort -man -hide-warnings -d man -I _build/libs -I _build/src libs/ulib.mli src/*.mli

install: all uninstall_packages
	ocamlfind install estring \
		libs/estring/META \
		_build/libs/estring/*.cmo \
		_build/libs/estring/*.cmi \
		_build/libs/estring/*.mli
	ocamlfind install $(NAME) $(INSTALL_FILES) \
		-optional $(OPT_INSTALL_FILES)

uninstall_packages:
	ocamlfind remove estring
	ocamlfind remove $(NAME)

uninstall: uninstall_packages
	${RM} -r $(DOCROOT)

install-doc: doc
	mkdir -p $(DOCROOT)
	cp -r doc/batteries/* $(DOCROOT)
	# deal with symlink that will break
	${RM} $(DOCROOT)/html/batteries_large.png
	cp -f doc/batteries_large.png $(DOCROOT)/html
	mkdir -p $(DOCROOT)/html/api
	cp _build/batteries.docdir/* $(DOCROOT)/html/api
	cp LICENSE README.md FAQ $(DOCROOT)

install-man: man
	install man/* /usr/local/man/man3/

reinstall:
	$(MAKE) uninstall
	$(MAKE) install

###############################################################################
#	BUILDING AND RUNNING UNIT TESTS
###############################################################################
# to run the tests in testsuite: ocamlbuild testsuite/main.native --
# to run the tests in src/batSomething.ml: ocamlbuild src/batSomething_test.native --
# to run the tests in all the src/bat*.ml: make qtest or ocamlbuild src/all_tests.native --
# to run all the tests: make test-only-native


### qtest: "inline" unit tests
##############################################

# We want a version of qtest without extension to be installed
# why would we want to install the test framework?
_build/$(QTESTDIR)/qtest:
	$(OCAMLBUILD) $(OCAMLBUILDFLAGS) $(QTESTDIR)/qtest.$(EXT)
	cp $< $@

### qtest: quick run of inline unit tests
##############################################
qtest:
	@$(OCAMLBUILD) $(OCAMLBUILDFLAGS) src/all_tests.$(EXT) --

### run all unit tests
##############################################

test-byte:
	$(OCAMLBUILD) $(OCAMLBUILDFLAGS) testsuite/main.byte src/all_tests.byte
	@_build/testsuite/main.byte
	@_build/src/all_tests.byte

test-only-native:
	$(OCAMLBUILD) $(OCAMLBUILDFLAGS) testsuite/main.native src/all_tests.native
	@_build/testsuite/main.native
	@_build/src/all_tests.native

# why would test-native depend on test-byte???
test-native: test-byte test-only-native

test: $(TEST_TARGET)

###############################################################################
#	BENCHMARK SUITE
###############################################################################

bench:
	$(OCAMLBUILD) $(OCAMLBUILDFLAGS) $(TARGETS) $(BENCH_TARGETS)
	$(RM) bench.log
	$(foreach BENCH, $(BENCH_TARGETS), _build/$(BENCH) | tee -a bench.log; )
	@echo "Benchmarking results are written to bench.log"


###############################################################################
#	PREPARING RELEASE FILES
###############################################################################

release:
	$(MAKE) clean
	git stash save "stashing local modifications before release"
	$(MAKE) release-cleaned

# assumes irreproachably pristine working directory
release-cleaned: setup.ml doc test
	git archive --format=tar --prefix=batteries-$(VERSION)/ HEAD \
	  | gzip > batteries-$(VERSION).tar.gz

setup.ml: _oasis
	oasis setup
	git commit setup.ml -m"Update setup.ml based on _oasis"


###############################################################################
#	CODE COVERAGE REPORTS
###############################################################################

coverage/index.html:
	$(OCAMLBUILD) coverage/index.html

coverage: coverage/index.html
