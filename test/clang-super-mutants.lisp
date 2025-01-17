;;;; clang-super-mutants.lisp --- Super mutants of clang objects.
(defpackage :software-evolution-library/test/clang-super-mutants
  (:nicknames :sel/test/clang-super-mutants)
  (:use
   :gt/full
   #+gt :testbot
   :software-evolution-library/test/util
   :software-evolution-library/test/util-clang
   :stefil+
   :software-evolution-library
   :software-evolution-library/software/parseable
   :software-evolution-library/software/clang
   :software-evolution-library/software/super-mutant
   :software-evolution-library/software/super-mutant-clang)
  (:import-from :arrow-macros :some->>) ; FIXME: Remove.
  (:export :test-clang-super-mutants))
(in-package :software-evolution-library/test/clang-super-mutants)
(in-readtable :curry-compose-reader-macros)
(defsuite test-clang-super-mutants "Clang representation." (clang-available-p))

(define-software mutation-failure-tester (clang) ())
(defvar *test-mutation-count* 0)
(defmethod mutate ((soft mutation-failure-tester))
  (incf *test-mutation-count*)
  ;; Every other mutation fails
  (when (zerop (mod *test-mutation-count* 2))
    (error (make-condition 'mutate)))
  soft)

(deftest (super-mutant-genome-works :long-running) ()
  (with-fixture fib-clang
    (let* ((mutant-a (copy *fib*))
           (mutant-b (copy *fib*))
           (*matching-free-var-retains-name-bias* 1.0))
      (apply-mutation mutant-a
                      `(clang-cut (:stmt1 . ,(stmt-with-text mutant-a
                                                             "x = x + y;"))))
      (apply-mutation mutant-b
                      `(clang-cut (:stmt1 . ,(stmt-with-text mutant-b
                                                             "y = t;"))))

      (let ((super (make-instance 'super-mutant
                     :mutants (list mutant-a mutant-b
                                    (copy mutant-b)))))
        (is (genome super))
        (is (phenome-p super))))))

(deftest (super-mutant-genome-preserves-unvarying-functions :long-running) ()
  "Switch should be omitted in functions which are the same across all mutants."
  (with-fixture huf-clang
    (let ((mutant-a (copy *huf*))
          (mutant-b (copy *huf*))
          (mutant-c (copy *huf*)))
      (apply-mutation mutant-a
                      `(clang-cut (:stmt1 . ,(stmt-with-text mutant-a
                                                             "h->n = 0;"))))
      (apply-mutation mutant-b
                      `(clang-cut (:stmt1 . ,(stmt-with-text mutant-b
                                                             "free(heap);"))))
      (apply-mutation mutant-c
                      `(clang-cut (:stmt1 . ,(stmt-with-text mutant-b
                                                             "heap->n--;"))))

      (let* ((super (make-instance 'super-mutant
                      :mutants (list mutant-a mutant-b
                                     mutant-c)))
             (obj (super-soft super)))
        (is (genome super))
        (is (phenome-p super))
        (mapcar (lambda (fun)
                  (is (eq (if (member (ast-name fun)
                                      '("_heap_create" "_heap_destroy"
                                        "_heap_remove")
                                      :test #'string=)
                              1
                              0)
                          (count-if [{eq :SwitchStmt} #'ast-class]
                                    (nest (child-asts)
                                          (function-body fun))))))
                (functions obj))))))

(deftest (super-mutant-genome-has-union-of-global-decls :long-running) ()
  (with-fixture gcd-clang
    (let* ((mutant-a (nest
                      (apply-mutation (copy *gcd*))
                      `(clang-insert (:stmt1 . ,(car (asts *gcd*)))
                                     (:stmt2 . ,(stmt-with-text *gcd*
                                                                "double a")))))
           (mutant-b (copy mutant-a))
           (mutant-c (copy mutant-b)))
      (apply-mutation mutant-b
                      `(clang-insert (:stmt1 . ,(second (roots mutant-b)))
                                     (:stmt2 . ,(stmt-with-text mutant-b
                                                                "double b"))))
      (apply-mutation mutant-c
                      `(clang-insert (:stmt1 . ,(second (roots mutant-c)))
                                     (:stmt2 . ,(stmt-with-text mutant-c
                                                                "double c"))))
      (apply-mutation mutant-c
                      `(clang-insert (:stmt1 . ,(second (roots mutant-c)))
                                     (:stmt2 . ,(stmt-with-text mutant-c
                                                                "double r1"))))
      (let* ((super (make-instance 'super-mutant
                      :mutants (list mutant-a mutant-b
                                     mutant-c)))
             (obj (super-soft super)))
        (is (genome super))
        (is (phenome-p super))
        (let ((decls (mapcar #'source-text
                             (remove-if #'function-decl-p (roots obj)))))
          ;; Ordering between b and (c r1) is arbitrary, but a must
          ;; come first.
          (is (or (equal decls
                         '("double a" "double c" "double r1" "double b"))
                  (equal decls
                         '("double a" "double b" "double c" "double r1")))))))))

(deftest (super-mutant-genome-has-union-of-functions :long-running) ()
  (with-fixture huf-clang
    (let* ((mutant-a (copy *huf*))
           (mutant-b (copy *huf*))
           (mutant-c (copy *huf*)))
      (nest (apply-mutation mutant-a)
            `(clang-cut (:stmt1 . ,(find-if [{string= "_heap_add"}
                                             #'ast-name]
                                            (functions mutant-a)))))
      (nest (apply-mutation mutant-a)
            `(clang-cut (:stmt1 . ,(find-if [{string= "_heap_remove"}
                                             #'ast-name]
                                            (functions mutant-a)))))
      (nest (apply-mutation mutant-b)
            `(clang-cut (:stmt1 . ,(find-if [{string= "_heap_add"}
                                             #'ast-name]
                                            (functions mutant-b)))))
      (nest (apply-mutation mutant-c)
            `(clang-cut (:stmt1 . ,(find-if [{string= "_heap_remove"}
                                             #'ast-name]
                                            (functions mutant-c)))))

      (let* ((super (make-instance 'super-mutant
                      :mutants (list mutant-a mutant-b
                                     mutant-c)))
             (obj (super-soft super)))
        (is (genome super))
        (is (phenome-p super))
        (let ((functions (nest (mapcar #'ast-name)
                               (take 5)
                               (functions obj))))
          ;; Ordering between _heap_sort and _heap_destroy is
          ;; arbitrary, but _heap_create must come first.
          (is (or (equal functions
                         '("_heap_create" "_heap_destroy" "_heap_sort"
                           "_heap_add" "_heap_remove"))
                  (equal functions
                         '("_heap_create" "_heap_destroy" "_heap_sort"
                           "_heap_remove" "_heap_add")))))))))

(deftest (super-mutant-genome-can-insert-merged-function :long-running) ()
  (with-fixture huf-clang
    (let* ((mutant-a (copy *huf*))
           (mutant-b (copy *huf*))
           (mutant-c (copy *huf*))
           (*matching-free-var-retains-name-bias* 1.0))
      (nest (apply-mutation mutant-a)
            `(clang-cut (:stmt1 . ,(find-if [{string= "_heap_add"}
                                             #'ast-name]
                                            (functions mutant-a)))))
      (nest (apply-mutation mutant-b)
            `(clang-insert (:stmt1 . ,(stmt-with-text mutant-b
                                                      "_heap_sort(heap);"))
                           (:value1 . ,(stmt-with-text mutant-b
                                                       "heap->n++;"))))
      (nest (apply-mutation mutant-c)
            `(clang-insert (:stmt1 . ,(stmt-with-text mutant-c
                                                      "_heap_sort(heap);"))
                           (:value1 . ,(stmt-with-text mutant-c
                                                       "heap->h[heap->n] = c;"))))



      (let* ((super (make-instance 'super-mutant
                      :mutants (list mutant-a mutant-b
                                     mutant-c)))
             (obj (super-soft super))
             (heap-add (find-if [{string= "_heap_add"} #'ast-name]
                                (functions obj)))
             (stmts (apply #'subseq (asts obj) (stmt-range obj heap-add))))
        (is (genome super))
        (is (phenome-p super))
        (is heap-add)
        (mapcar (lambda (fun)
                  (is (eq (if (eq heap-add fun)
                              1
                              0)
                          (count-if [{eq :SwitchStmt} #'ast-class]
                                    (nest (child-asts)
                                          (function-body fun))))))
                (functions obj))
        (is (eq 1 (count-if [{eq :DefaultStmt} #'ast-class] stmts))
            "Super-function contains default statement.")
        (is (eq 2 (count-if [{eq :CaseStmt} #'ast-class] stmts))
            "Super-function contains correct number of case statements.")))))

(deftest super-mutant-genome-handles-function-prototypes ()
  (let ((mutant (from-string (make-instance 'clang) "int foo();")))
    (is (genome (make-instance 'super-mutant
                  :mutants (list (copy mutant) (copy mutant)))))))

(deftest super-mutant-genome-detects-mismatched-globals ()
  (let* ((base (from-string (make-instance 'clang)
                            "int a; int b; int c;"))
         (variant (copy base)))
    (apply-mutation variant
                    `(clang-replace (:stmt1 . ,(stmt-with-text variant
                                                               "int b;"))
                                    (:value1 . ,(nest (make-var-decl "b")
                                                      (find-or-add-type variant
                                                                        "char")))))
    (signals mutate
             (genome (make-instance 'super-mutant
                       :mutants (list base variant))))))

(deftest super-mutant-genome-detects-delete-function-body ()
  (let* ((base (from-string (make-instance 'clang)
                            "void foo() {}"))
         (variant (copy base)))
    ;; This is a useless mutation but it happens sometimes. Ensure
    ;; that it leads to a mutation error.
    (apply-mutation variant
                    `(clang-cut (:stmt1 . ,(stmt-with-text variant "{}"))))
    (signals mutate
             (genome (make-instance 'super-mutant
                       :mutants (list base variant))))))

(deftest collate-ast-variants-test ()
  ;; This function is intended to be called on asts, but it only
  ;; relies on EQUAL comparison of the keys so we can test it with
  ;; artificial data.

  ;; Simple case: all top-level decls line up
  (is (equal (collate-ast-variants '(((1 . a1) (2 . a2) (3 . a3))
                                     ((1 . b1) (2 . b2) (3 . b3))))
             '((a1 b1) (a2 b2) (a3 b3))))

  ;; Deleted AST
  (is (equal (collate-ast-variants '(((1 . a1) (2 . a2) (3 . a3))
                                     ((1 . b1) (3 . b3))))
             '((a1 b1) (a2 nil) (a3 b3))))

  ;; Inserted AST
  (is (equal (collate-ast-variants '(((1 . a1) (3 . a3))
                                     ((1 . b1) (2 . b2) (3 . b3))))
             '((a1 b1) (nil b2) (a3 b3))))

  ;; Deleted at beginning
  (is (equal (collate-ast-variants '(((1 . a1) (2 . a2) (3 . a3))
                                     ((2 . b2) (3 . b3))))
             '((a1 nil) (a2 b2) (a3 b3))))

  ;; Deleted at end
  (is (equal (collate-ast-variants '(((1 . a1) (2 . a2) (3 . a3))
                                     ((1 . b1) (2 . b2))))
             '((a1 b1) (a2 b2) (a3 nil))))

  ;; Inserted at beginning
  (is (equal (collate-ast-variants '(((2 . a2) (3 . a3))
                                     ((1 . b1) (2 . b2) (3 . b3))))
             '((nil b1) (a2 b2) (a3 b3))))

  ;; Inserted at end
  (is (equal (collate-ast-variants '(((1 . a1) (2 . a2))
                                     ((1 . b1) (2 . b2) (3 . b3))))
             '((a1 b1) (a2 b2) (nil b3))))

  ;; Multiple inserted ASTs
  (is (equal (collate-ast-variants '(((1 . a1) (3 . a3))
                                     ((1 . b1) (2 . b2) (4 . b4)
                                      (5 . b5) (3 . b3))))
             '((a1 b1) (nil b2) (nil b4) (nil b5) (a3 b3))))

  ;; 3 variants
  (is (equal (collate-ast-variants '(((1 . a1) (2 . a2) (3 . a3))
                                     ((1 . b1) (2 . b2) (3 . b3))
                                     ((1 . c1) (2 . c2) (3 . c3))))
             '((a1 b1 c1) (a2 b2 c2) (a3 b3 c3))))

  ;; 3 variants with inserts and deletes
  (is (equal (collate-ast-variants '(((1 . a1) (2 . a2) (3 . a3))
                                     ((1 . b1) (3 . b3))
                                     ((1 . c1) (2 . c2) (4 . c4)
                                      (3 . c3))))
             '((a1 b1 c1) (a2 nil c2) (nil nil c4) (a3 b3 c3))))


  ;; Swapped ASTs are not merged correctly. This is a known
  ;; limitation.
  (is (equal (collate-ast-variants '(((1 . a1) (2 . a2) (3 . a3))
                                     ((2 . b2) (1 . b1) (3 . b3))))
             '((a1 nil) (a2 b2) (nil b1) (a3 b3)))))

(deftest super-evolve-handles-mutation-failure ()
  (let* ((obj (from-string (make-instance 'mutation-failure-tester)
                           "int main() { return 0; }"))
         (*population* (list obj))
         (*max-population-size* 10)
         (*fitness-evals* 0)
         (*cross-chance* 0)
         (*target-fitness-p* (lambda (fit) (declare (ignorable fit)) t)))
    (setf (fitness obj) 0)
    ;; Ensure the software objects raise mutation errors as expected
    (signals mutate
             (evolve (lambda (obj) (declare (ignorable obj)) 1)
                     :max-evals 10
                     :super-mutant-count 4))
    (handler-bind ((mutate (lambda (err)
                             (declare (ignorable err))
                             (invoke-restart 'ignore-failed-mutation))))
      ;; This should exit after evaluating the first super-mutant,
      ;; because *target-fitness-p* is trivially true.
      (evolve (lambda (obj) (declare (ignorable obj)) 1)
              :max-evals 10
              :super-mutant-count 4))
    ;; Despite errors, the first super-mutant should accumulate the
    ;; desired number of variants and evaluate all of them.
    (is (eq *fitness-evals* 4))))

(deftest (super-mutant-evaluate-works :long-running) ()
  (let* ((template "#include <stdio.h>
int main() { puts(\"~d\"); return 0; }
")
         (mutants (mapcar (lambda (i)
                            (from-string (make-instance 'clang)
                                         (format nil template i)))
                          '(1 2 3 4)))
         (super (make-instance 'super-mutant :mutants mutants)))
    (evaluate (lambda (obj)
                ;; Proxies are the same type as mutants
                (is (typep obj 'clang))
                (cons (some->> (phenome obj)
                               (shell)
                               (parse-integer))
                      (genome-string obj)))
              super)
    ;; Each variant printed the appropriate number
    (is (equal '(1 2 3 4) (mapcar [#'car #'fitness] mutants)))
    ;; Each proxy had genome string identical to the corresponding mutant
    (is (equal (mapcar #'genome-string mutants)
               (mapcar [#'cdr #'fitness] mutants)))))
