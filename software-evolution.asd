(defsystem :software-evolution
  :description "programmatic modification and evaluation of extant software"
  :long-description "A common interface abstracts over multiple
types of software objects including abstract syntax trees parsed from
source code, LLVM IR, compiled assembler, and linked ELF binaries.
Mutation and evaluation methods are implemented on top of this
interface supporting Search Based Software Engineering (SBSE)
techniques."
  :version "0.0.0"
  :licence "GPL V3"
  ;; :homepage "http://eschulte.github.io/software-evolution/index.html"
  :depends-on (alexandria
               metabang-bind
               curry-compose-reader-macros
               split-sequence
               cl-json
               cl-ppcre
               cl-mongo
               diff
               elf
               memoize
               software-evolution-utility)
  :in-order-to ((test-op (test-op software-evolution-test)))
  :components
  ((:module base
            :pathname ""
            :components
            ((:file "package")
             (:file "software-evolution" :depends-on ("package"))))
   (:module software
            :depends-on (base)
            :pathname "software"
            :components
            ((:file "lisp")
             (:file "simple")
             (:file "diff" :depends-on ("simple"))
             (:file "asm"  :depends-on ("simple"))
             (:file "elf"  :depends-on ("diff"))
             (:file "elf-cisc" :depends-on ("elf"))
             (:file "elf-risc" :depends-on ("elf"))
             (:file "elf-mips" :depends-on ("elf-risc"))
             (:file "ast")
             (:file "cil" :depends-on ("ast"))
             (:file "clang" :depends-on ("ast"))
             (:file "clang-w-fodder" :depends-on ("clang"))
             (:file "clang-mito" :depends-on ("ast"))
             (:file "fodder-database")
             (:file "json-fodder-database" :depends-on ("fodder-database"))
             (:file "mongo-fodder-database" :depends-on ("fodder-database"))
             (:file "fix-compilation" :depends-on ("clang" "clang-w-fodder"))
             (:file "llvm" :depends-on ("ast"))))))
