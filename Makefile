.PHONY: doc api python-check libcxx-src

# Set personal or machine-local flags in a file named local.mk
ifneq ("$(wildcard local.mk)","")
include local.mk
endif

ROOT_DIR = $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
PACKAGE_NAME = software-evolution-library
PACKAGE_NICKNAME = sel
API_TITLE = "Software Evolution Library Index"
API_NEXT = "ChangeLog"
API_PREV = "Python Library"
DOC_PACKAGES =								\
	software-evolution-library					\
	software-evolution-library/command-line-rest			\
	software-evolution-library/components/clang-tokens		\
	software-evolution-library/components/configuration		\
	software-evolution-library/components/file			\
	software-evolution-library/components/fix-compilation		\
	software-evolution-library/components/fodder-database		\
	software-evolution-library/components/formatting		\
	software-evolution-library/components/in-memory-fodder-database	\
	software-evolution-library/components/instrument		\
	software-evolution-library/components/json-fodder-database	\
	software-evolution-library/components/lexicase			\
	software-evolution-library/components/multi-objective		\
	software-evolution-library/components/pliny-fodder-database	\
	software-evolution-library/components/searchable		\
	software-evolution-library/components/serapi-io			\
	software-evolution-library/components/test-suite		\
	software-evolution-library/rest					\
	software-evolution-library/rest/async-jobs			\
	software-evolution-library/rest/define-command-endpoint		\
	software-evolution-library/rest/sessions			\
	software-evolution-library/rest/std-api				\
	software-evolution-library/rest/utility				\
	software-evolution-library/software/adaptive-mutation		\
	software-evolution-library/software/ancestral			\
	software-evolution-library/software/asm				\
	software-evolution-library/software/asm-heap			\
	software-evolution-library/software/asm-super-mutant		\
	software-evolution-library/software/cil				\
	software-evolution-library/software/clang			\
	software-evolution-library/software/clang-expression		\
	software-evolution-library/software/clang-project		\
	software-evolution-library/software/clang-w-fodder		\
	software-evolution-library/software/compilable			\
	software-evolution-library/software/coq				\
	software-evolution-library/software/coq-project			\
	software-evolution-library/software/diff			\
	software-evolution-library/software/elf				\
	software-evolution-library/software/elf-cisc			\
	software-evolution-library/software/elf-risc			\
	software-evolution-library/software/expression			\
	software-evolution-library/software/forth			\
	software-evolution-library/software/ir				\
	software-evolution-library/software/lisp			\
	software-evolution-library/software/llvm			\
	software-evolution-library/software/parseable			\
	software-evolution-library/software/parseable-project		\
	software-evolution-library/software/project			\
	software-evolution-library/software/sexp			\
	software-evolution-library/software/simple			\
	software-evolution-library/software/styleable			\
	software-evolution-library/software/super-mutant		\
	software-evolution-library/software/super-mutant-clang		\
	software-evolution-library/software/super-mutant-project	\
	software-evolution-library/software/tree-sitter			\
	software-evolution-library/software/c				\
	software-evolution-library/software/cpp				\
	software-evolution-library/software/python			\
	software-evolution-library/software/javascript			\
	software-evolution-library/software/json			\
	software-evolution-library/software/with-exe			\
	software-evolution-library/utility/debug			\
	software-evolution-library/utility/git				\
	software-evolution-library/utility/json				\
	software-evolution-library/utility/range			\
	software-evolution-library/utility/task				\
	software-evolution-library/view

DOC_DEPS = doc/software-evolution-library/GrammaTech-CLA-SEL.pdf

doc/software-evolution-library/GrammaTech-CLA-SEL.pdf: doc/GrammaTech-CLA-SEL.pdf
	mkdir -p doc/software-evolution-library/ && cp $< $@

LISP_DEPS =				\
	$(wildcard *.lisp) 		\
	$(wildcard components/*.lisp)	\
	$(wildcard software/*.lisp)	\
	$(wildcard python/lisp/*.lisp)

TEST_ARTIFACTS = \
	test/etc/gcd/gcd \
	test/etc/gcd/gcd.s

# FIXME: move test binaries into test/bin or bin/test/
# Extend cl.mk to have a separate build target for test binaries
BINS = rest-server dump-store tree-sitter-interface tree-sitter-py-generator test-parse \
       limit
BIN_TEST_DIR = test/bin
BIN_TESTS =			\
	example-001-mutate

LONG_BIN_TESTS =		\
	example-002-evaluation	\
	example-003-neutral	\
	example-004-evolve

include .cl-make/cl.mk

test/etc/gcd/gcd: test/etc/gcd/gcd.c
	$(CC) $< -o $@

test/etc/gcd/gcd.s: test/etc/gcd/gcd.c
	$(CC) $< -S -masm=intel -o $@

bin/limit: limit.c
	$(CC) $< -o $@

python-check: bin/tree-sitter-interface bin/tree-sitter-py-generator
	PATH=$(ROOT_DIR)/bin:$$PATH pytest python

libcxx-src: | utility/libcxx-src/LICENSE.TXT

utility/libcxx-src/LICENSE.TXT:
	mkdir -p utility/libcxx-src
	wget https://github.com/llvm/llvm-project/releases/download/llvmorg-13.0.0/libcxx-13.0.0.src.tar.xz -O - | tar Jxf - -C utility/libcxx-src --strip-components=1
