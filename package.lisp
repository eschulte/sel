;; Copyright (C) 2011-2013  Eric Schulte
(defpackage :software-evolution
  (:nicknames :se)
  (:use
   :common-lisp
   :alexandria
   :metabang-bind
   :curry-compose-reader-macros
   :cl-arrows
   :iterate
   :split-sequence
   :cl-ppcre
   :cl-mongo
   :mongo-middle-man
   :usocket
   :diff
   :elf
   :memoize
   :software-evolution-utility)
  (:shadow :elf :size :type :magic-number :diff :insert)
  (:shadowing-import-from :iterate :iter :for :until :collecting :in)
  (:export
   ;; software objects
   :software
   :define-software
   :edits
   :fitness
   :fitness-extra-data
   :mutation-stats
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
   :types
   :globals
   :ancestral
   :ancestors
   :pick
   :pick-good
   :pick-bad
   :pick-snippet
   :mutate
   :mutation-types-clang
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
   :*analyze-mutation-verbose-stream*
   :analyze-mutation
   :mutation-key
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
   :genome-string-without-separator
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
   :random-point-in-function
   :select-intraprocedural-pair
   :clang-tidy
   :clang-format
   :clang-mutate
   :update-headers-from-snippet
   :to-file
   :apply-path
   :expression
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
   :stmts
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
   :header-asts
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
   :*cross-chance*
   :*mut-rate*
   :*fitness-evals*
   :*running*
   :*start-time*
   :elapsed-time
   ;; clang / clang-w-fodder global variables
   :fodder-database
   :mongo-database
   :db :host :port
   :mongo-middle-database
   :source-collection :cache-collection :middle-host :middle-port
   :json-database
   :find-snippets
   :weighted-pick
   :find-types
   :sorted-snippets
   :*clang-max-json-size*
   :*clang-full-stmt-bias*
   :*clang-same-class-bias*
   :*decl-mutation-bias*
   :*crossover-function-probability*
   :*fodder-selection-bias*
   :*clang-mutation-cdf*
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
   :*asm-linker*
   :elf
   :elf-cisc
   :elf-csurf
   :elf-x86
   :elf-arm
   :elf-risc
   :elf-mips
   :genome-bytes
   :pad
   :nop-p
   :forth
   :lisp
   :clang
   :clang-w-fodder
   :clang-w-binary
   :clang-w-fodder-and-binary
   :bytes
   :diff-data
   :do-not-filter
   :with-class-filter
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
   :ignore-failed-mutation
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
   :*lexicase-predicate*
   :*lexicase-key*
   :mutation
   :targets
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
   :clang-nop
   :clang-instrument
   :cut-decl
   :swap-decls
   :rename-variable
   :replace-fodder-same
   :replace-fodder-full
   :insert-fodder
   :insert-fodder-full
   :pick-bad-good
   :pick-bad-bad
   :pick-bad-only
   ))
