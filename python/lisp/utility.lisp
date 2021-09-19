;;; utility.lisp - Utility functions shared by the python API cl applications
(defpackage :software-evolution-library/python/lisp/utility
  (:nicknames :sel/py/lisp/utility)
  (:use :gt/full)
  (:export :common-lisp-to-python-type))
(in-package :software-evolution-library/python/lisp/utility)
(in-readtable :curry-compose-reader-macros)

;; (-> common-lisp-to-python-type ((or clazz symbol string)) string)
(defgeneric common-lisp-to-python-type (type)
  (:documentation "Convert the given common lisp TYPE to the corresponding
python type identifier.")
  (:method ((clazz class))
    (common-lisp-to-python-type (class-name clazz)))
  (:method ((sym symbol))
    (common-lisp-to-python-type (symbol-name sym)))
  (:method ((typename string))
    (labels ((c/cpp-to-cxx (term)
               "Replace C/CPP TERMs with CXX, a valid python identifier."
               (if (string= term "C/CPP") "CXX" term))
             (pep8-camelcase (term)
               "Camelcase TERM in accordance to PEP-8 conventions."
               ;; Keep abbreviations uppercase, otherwise camelcase per PEP-8.
               (cond ((member term '("AST" "CPP" "CXX") :test #'string=) term)
                     (t (string-capitalize term)))))
      (nest (apply #'concatenate 'string)
            (mapcar [#'pep8-camelcase #'c/cpp-to-cxx])
            (split-sequence #\-)
            (terminal-replace typename)))))

(defmacro symname-find-replace$ (symname pairs)
  "Build cond clauses from PAIRS specifying find/replace for trailing
characters of the symbol string SYMNAME."
  `(cond ,@(mapcar
             (lambda (pair)
               (let ((regex (format nil "(.*[A-Za-z0-9]-)(?i)(~a)$"
                                        (if (equal (car pair) "\\n")
                                            (car pair)
                                            (quote-meta-chars (car pair)))))
                     (replacement (format nil "\\1~a" (cdr pair))))
                 `((scan ,regex ,symname)
                   (regex-replace ,regex ,symname ,replacement
                                  :preserve-case t))))
             (stable-sort pairs #'> :key [#'length #'car]))
         (t ,symname)))

(-> terminal-replace (string) string)
(defun terminal-replace (typename)
  "Replace chars in terminal AST TYPENAMEs not valid in python identifiers."
  (symname-find-replace$ typename
                         (;; Logical operators
                          ("||" . "logical-or")
                          ("&&" . "logical-and")
                          ("!" . "logical-not")
                          ("&&=" . "logical-and-assign")
                          ("||=" . "logical-or-assign")
                          ;; Comparison operators
                          ("<" . "less-than")
                          ("<=" . "less-than-or-equal")
                          (">" . "greater-than")
                          (">=" . "greater-than-or-equal")
                          ("==" . "equal")
                          ("!=" . "not-equal")
                          ;; Bitwise operators
                          ("<<" . "bitshift-left")
                          (">>" . "bitshift-right")
                          ("&" . "bitwise-and")
                          ("|" . "bitwise-or")
                          ("^" . "bitwise-xor")
                          ("~" . "bitwise-not")
                          ("<<=" . "bitshift-left-assign")
                          (">>=" . "bitshift-right-assign")
                          ("&=" . "bitwise-and-assign")
                          ("|=" . "bitwise-or-assign")
                          ("^=" . "bitwise-xor-assign")
                          ;; Arithmatic operators
                          ("+" . "add")
                          ("-" . "subtract")
                          ("*" . "multiply")
                          ("/" . "divide")
                          ("%" . "modulo")
                          ("+=" . "add-assign")
                          ("-=" . "subtract-assign")
                          ("*=" . "multiply-assign")
                          ("/=" . "divide-assign")
                          ("%=" . "module-assign")
                          ("++" . "increment")
                          ("--" . "decrement")
                          ;; Miscellaneous operators
                          ("=" . "assign")
                          ("[" . "open-bracket")
                          ("]" . "close-bracket")
                          ("{" . "open-brace")
                          ("}" . "close-brace")
                          ("(" . "open-parenthesis")
                          (")" . "close-parenthesis")
                          ("," . "comma")
                          ("." . "dot")
                          ("?" . "question")
                          (":" . "colon")
                          (";" . "semicolon")
                          ("->" . "arrow")
                          ("..." . "ellipsis")
                          ("\\n" . "newline")
                          ;; Quote terminals
                          ("'" . "single-quote")
                          ("\"" . "double-quote")
                          ("`" . "back-quote")
                          ("u'" . "unicode-single-quote")
                          ("u\"" . "unicode-double-quote")
                          ;; Python terminals
                          (":=" . "walrus")
                          ("<>" . "not-equal-flufl")
                          ("@" . "matrix-multiply")
                          ("**" . "pow")
                          ("//" . "floor-divide")
                          ("@=" . "matrix-multiply-assign")
                          ("**=" . "pow-assign")
                          ("//=" . "floor-divide-assign")
                          ;; Javascript terminals
                          ("=>" . "arrow")
                          ("?." . "chaining")
                          ("${" . "open-template-literal")
                          ("??" . "nullish-coalescing")
                          ("??=" . "nullish-coalescing-assign")
                          ("===" . "strictly-equal")
                          ("!==" . "strictly-not-equal")
                          ("<<<" . "unsigned-bitshift-left")
                          (">>>" . "unsigned-bitshift-right")
                          ("<<<=" . "unsigned-bitshift-left-assign")
                          (">>>=" . "unsigned-bitshift-right-assign")
                          ;; C/C++ terminals
                          ("[[" . "open-attribute")
                          ("]]" . "close-attribute")
                          ("::" . "scope-resolution")
                          ("l'" . "wchar-single-quote")
                          ("l\"" . "wchar-double-quote")
                          ("u\'-terminal" . "unsigned-terminal-single-quote")
                          ("u\"-terminal" . "unsigned-terminal-double-quote")
                          ("u8'" . "unsigned-8bit-terminal-single-quote")
                          ("u8\"" . "unsigned-8bit-terminal-double-quote")
                          ("--unaligned" . "underscore-unaligned")
                          ("#define" . "macro-define")
                          ("#include" . "macro-include")
                          ("#ifdef" . "macro-if-defined")
                          ("#ifndef" . "macro-if-not-defined")
                          ("#if" . "macro-if")
                          ("#elif" . "macro-elif")
                          ("#else" . "macro-else")
                          ("#endif" . "macro-end-if")
                          ("#end" . "macro-end"))))
