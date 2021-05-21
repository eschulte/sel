(defpackage :software-evolution-library/software/ql
  (:nicknames :sel/software/ql :sel/sw/ql)
  (:use :gt/full
        :software-evolution-library
        :software-evolution-library/software/tree-sitter))

(in-package :software-evolution-library/software/tree-sitter)
(in-readtable :curry-compose-reader-macros)

;;;===================================================
;;; Generate the language definitions
;;;===================================================
(create-tree-sitter-language "ql")
;;;===================================================