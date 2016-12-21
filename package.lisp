;; Copyright (C) 2011-2013  Eric Schulte
(defpackage :software-evolution
  (:nicknames :se)
  (:use
   :alexandria
   :bordeaux-threads
   :common-lisp
   :cl-arrows
   :cl-mongo
   :cl-ppcre
   :curry-compose-reader-macros
   :diff
   :elf
   :iterate
   :memoize
   :metabang-bind
   :split-sequence
   :software-evolution-utility
   :usocket)
  (:shadow :elf :size :type :magic-number :diff :insert)
  (:shadowing-import-from :iterate :iter :for :until :collecting :in)
  (:export
   :+software-evolution-version+
   ;; software objects
   :software
   :define-software
   :edits
   :fitness
   :fitness-extra-data
   :mutation-stats
   :*mutation-improvements*
   :genome
   :phenome
   :compile-p
   :evaluate
   :copy
   :size
   :lines
   :line-breaks
   :genome-string
   :headers
   :macros
   :includes
   :types
   :declarations
   :globals
   :ancestral
   :ancestors
   :pick
   :pick-good
   :pick-bad
   :pick-snippet
   :pick-guarded-compound
   :mutate
   :no-mutation-targets
   :pick-mutation-type
   :clang-mutation
   :build-op
   :apply-mutation
   :apply-all-mutations
   :apply-picked-mutations
   :text
   :obj
   :op
   :*mutation-stats*
   :*crossover-stats*
   :analyze-mutation
   :mutation-key
   :summarize-mutation-stats
   :classify
   :crossover
   :one-point-crossover
   :two-point-crossover
   :*edit-consolidation-size*
   :*consolidated-edits*
   :*edit-consolidation-function*
   :edit-distance
   :from-file
   :from-file-exactly
   :from-string
   :from-string-exactly
   :ext
   :get-vars-in-scope
   :bind-free-vars
   :prepare-sequence-snippet
   :prepare-inward-snippet
   :create-inward-snippet
   :apply-fun-body-substitutions
   :select-before
   :crossover-2pt-inward
   :crossover-2pt-outward
   :intraprocedural-2pt-crossover
   :select-crossover-points
   :function-containing-ast
   :function-body-p
   :adjust-stmt-range
   :random-point-in-function
   :select-intraprocedural-pair
   :clang-tidy
   :clang-format
   :clang-mutate
   :update-headers-from-snippet
   :to-file
   :apply-path
   :expression
   :expression-intern
   :expression-to-c
   :mutation
   :define-mutation
   :object
   :targeter
   :picker
   :targets
   :get-targets
   :at-targets
   :compiler
   :prototypes
   :functions
   :asts
   :stmt-asts
   :non-stmt-asts
   :good-stmts
   :bad-stmts
   :update-asts
   :source-location
   :line
   :column
   :asts-containing-source-location
   :asts-contained-in-source-range
   :asts-intersecting-source-range
   :ast-to-source-range
   :get-ast
   :get-parent-ast
   :get-parent-asts
   :parent-ast-p
   :get-parent-full-stmt
   :wrap-ast
   :wrap-child
   :can-be-made-full-p
   :get-make-parent-full-stmt
   :get-immediate-children
   :extend-to-enclosing
   :get-ast-info
   :+c-numeric-types+
   :+c-relational-operators+
   :+c-arithmetic-binary-operators+
   :+c-arithmetic-assignment-operators+
   :+c-bitwise-binary-operators+
   :+c-bitwise-assignment-operators+
   :+c-arithmetic-unary-operators+
   :+c-bitwise-unary-operators+
   :+c-sign-unary-operators+
   :+c-pointer-unary-operators+
   :all-use-of-var
   :ast-declares
   :declaration-of
   :declared-type
   :type-of-var
   :random-function-name
   :replace-fields-in-ast
   ;; global variables
   :*population*
   :*generations*
   :*max-population-size*
   :*tournament-size*
   :*tournament-eviction-size*
   :*fitness-predicate*
   :fitness-better-p
   :fitness-equal-p
   :*cross-chance*
   :*mut-rate*
   :*fitness-evals*
   :*running*
   :*start-time*
   :elapsed-time
   ;; simple / asm global variables
   :*simple-mutation-types*
   :*asm-linker*
   :*asm-mutation-types*
   ;; adaptive software
   :adaptive-mutation
   :*bias-toward-dynamic-mutation*
   :*better-bias*
   :*same-bias*
   :*worse-bias*
   :*dead-bias*
   :adaptive-analyze-mutation
   :update-mutation-types
   ;; clang / clang-w-fodder global variables
   :searchable
   :fodder-database
   :in-memory-database
   :json-database
   :mongo-database
   :pliny-database
   :db
   :host
   :port
   :database-emptyp
   :source-collection
   :cache-collection
   :middle-host
   :middle-port
   :find-snippets
   :weighted-pick
   :find-type
   :similar-snippets
   :*clang-max-json-size*
   :*crossover-function-probability*
   :*clang-mutation-types*
   :*clang-w-fodder-mutation-types*
   :*clang-w-fodder-new-mutation-types*
   :*free-var-decay-rate*
   :*matching-free-var-retains-name-bias*
   :*matching-free-function-retains-name-bias*
   :*allow-bindings-to-globals-bias*
   :*clang-json-required-fields*
   :*clang-json-required-aux*
   :*database*
   :*mmm-processing-seconds*
   ;; evolution functions
   :incorporate
   :evict
   :default-select-one
   :*tournament-selector*
   :tournament
   :mutant
   :crossed
   :new-individual
   :mcmc
   :evolve
   :generational-evolve
   ;; software backends
   :simple
   :light
   :sw-range
   :diff
   :original
   :asm
   :csurf-asm
   :*isa-nbits*
   :elf
   :elf-cisc
   :elf-csurf
   :elf-x86
   :elf-arm
   :elf-risc
   :elf-mips
   :genome-bytes
   :pad-nops
   :nop-p
   :forth
   :lisp
   :clang
   :clang-w-fodder
   :clang-w-binary
   :clang-w-fodder-and-binary
   :bytes
   :diff-data
   :recontextualize
   :rebind-uses
   :rebind-uses-in-snippet
   :delete-decl-stmts
   :rename-variable-near-use
   :run-cut-decl
   :run-swap-decls
   :run-rename-variable
   :common-ancestor
   :ancestor-of
   :get-fresh-ancestry-id
   :save-ancestry
   :scopes-between
   :nesting-depth
   :get-ast-text
   :full-stmt-p
   :enclosing-full-stmt
   :enclosing-block
   :nesting-relation
   :match-nesting
   :block-successor
   :show-full-stmt
   :full-stmt-text
   :full-stmt-info
   :full-stmt-successors
   :prepare-code-snippet
   :get-children-using
   :get-declared-variables
   :cil
   :llvm
   :linker
   :flags
   :assembler
   :asm-flags
   :redirect-file
   :weak-symbols
   :elf-risc-max-displacement
   :ops                      ; <- might want to fold this into `lines'
   ;; software backend specific methods
   :reference
   :base
   :disasm
   :addresses
   :instrument
   :var-instrument
   :add-include
   :add-type
   :add-macro
   :nullify-asts
   :ignore-failed-mutation
   :try-another-mutation
   :fix-compilation
   :generational-evolve
   :simple-reproduce
   :simple-evaluate
   :simple-select
   :*target-fitness-p*
   :*worst-fitness-p*
   :worst-numeric-fitness
   :worst-numeric-fitness-p
   :lexicase-select
   :lexicase-select-one
   :*lexicase-key*
   :mutation
   :targets
   :simple-cut
   :simple-insert
   :simple-swap
   :asm-replace-operand
   :asm-nth-instruction
   :asm-split-instruction
   :clang-cut
   :clang-cut-same
   :clang-cut-full
   :clang-cut-full-same
   :clang-insert
   :clang-insert-same
   :clang-insert-full
   :clang-insert-full-same
   :clang-swap
   :clang-swap-same
   :clang-swap-full
   :clang-swap-full-same
   :clang-replace
   :clang-replace-same
   :clang-replace-full
   :clang-replace-full-same
   :clang-set-range
   :clang-promote-guarded
   :clang-nop
   :clang-instrument
   :explode-for-loop
   :coalesce-while-loop
   :cut-decl
   :swap-decls
   :rename-variable
   :replace-fodder-same
   :replace-fodder-full
   :insert-fodder-decl
   :insert-fodder-decl-rep
   :insert-fodder
   :insert-fodder-full
   :pick-bad-good
   :pick-bad-bad
   :pick-bad-only
   :*lisp-mutation-types*
   :lisp-cut
   :lisp-replace
   :lisp-swap
   :change-operator
   :change-constant
   :clang-expression
   :scope
   :mult-divide
   :add-subtract
   :subtract-add
   :add-subtract-tree
   :subtract-add-tree
   :add-subtract-scope
   :evaluate-expression
   :demote-binop-left
   :demote-binop-right
   :eval-error
   :project
   :current-file
   :with-current-file
   :evolve-files
   :other-files
   :all-files
   :write-genome-to-files
   :with-build-dir
   :with-temp-build-dir
   :make-build-dir
   :full-path
   :*build-dir*
   :test-suite
   :test-cases
   :run-test
   :case-fitness
   :instrumentation-exprs
   :synthesize-condition
   :build
   :build-failed
   :add-condition
   :tighten-condition
   :loosen-condition
   :valid-targets
   :if-to-while
   :if-to-while-tighten-condition
   :insert-else-if
   :stmts-in-file
   :error-funcs
   :rinard
   :collect-fault-loc-traces
   :generate-helpers
   :type-of-scoped-var))
