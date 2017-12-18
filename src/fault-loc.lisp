;;;; fault-loc.lisp -- fault localization
;;; These all operate on execution traces generated by the instrument method.

(in-package :software-evolution-library)
(in-readtable :curry-compose-reader-macros)

(defgeneric collect-fault-loc-traces (bin test-suite read-trace-fn
                                      &optional fl-neg-test)
  (:documentation "Run test cases and collect execution traces.

Returns a list of traces where the notion of \"good\" traces (from
passing tests) \"bad\" traces (from failing tests) are recorded in a
manner that the client can later digest.

BIN is the path to software object which has already been instrumented
and built.  READ-TRACE-FN is a function for reading the traces
generated by that instrumentation. fl-neg-test specifies a list of
tests to be considered the 'failing' tests (indicating a bug,
usually).

No assumptions are made about the format or contents of the traces."))

(defmethod collect-fault-loc-traces (bin test-suite read-trace-fn
                                     &optional fl-neg-test)
  (iter (for test in (test-cases test-suite))
        (note 3 "Begin running test ~a" test)
        (let* ((f (evaluate bin test :output :stream :error :stream))
               ;; Set is-good-trace based on actual outcome, or the
               ;; user-specified "bad test."
               (is-good-trace (cond
                                (fl-neg-test (if (member test fl-neg-test)
                                                 nil
                                                 t))
                                (t (>= f 1.0)))))
          (with accumulated-result = nil)
          (setf accumulated-result
                (funcall read-trace-fn accumulated-result is-good-trace test))
          (finally (return accumulated-result)))))

(defun stmts-in-file (trace file-id)
  (remove-if-not [{= file-id} {aget :f}] trace))

(defun error-funcs (software bad-traces good-traces)
  "Find statements which call error functions.

Error functions are defined as functions which are only called during
bad runs. Such functions often contain error-handling code which is
not itself faulty, so it's useful to identify their callers instead."
  (labels
      ((call-sites (obj neg-test-stmts error-funcs)
         (remove-if-not (lambda (x)
                          (remove-if-not
                           (lambda (y)
                             (let ((cur-node (ast-at-index obj x)))
                               (and (eq (ast-class cur-node)
                                        :CallExpr)
                                    (search y (source-text cur-node)))))
                           error-funcs))
                        neg-test-stmts))
       (functions (obj trace)
         (remove-duplicates
          (mapcar [{function-containing-ast obj} {ast-at-index obj}]
                  ;; Not necessary, but this is faster than doing
                  ;; duplicate function-containing-ast lookups.
                  (remove-duplicates trace))))
       (find-error-funcs (obj good-stmts bad-stmts)
         (mapcar #'ast-name
                 (set-difference (functions obj bad-stmts)
                                 (functions obj good-stmts)
                                 :test #'equalp))))

    ;; Find error functions in each file individually, then append them.
    (let ((good-stmts (apply #'append good-traces))
          (bad-stmts (apply #'append bad-traces)))
      (iter
        (for obj in (mapcar #'cdr (evolve-files software)))
        (for i upfrom 0)
        (let ((good (mapcar {aget :c} (stmts-in-file good-stmts i)))
              (bad (mapcar {aget :c} (stmts-in-file bad-stmts i))))
          (appending
           (mapcar (lambda (c) `((:c . ,c) (:f . ,i)))
                   (call-sites obj
                               (remove-duplicates bad)
                               (find-error-funcs obj good bad)))))))))

(defstruct stmt-counts
  "A struct for a single stmt-count entry.
This includes the test id, the number of positive and negative tests
that exercise the statement, and an alist for positions in traces,
which maps (test-casel: position)"
  (id "")
  (positive 0.0)
  (negative 0.0)
  ;; The `stmt-counts' "positions" field gets its own struct for
  ;; printing purposes.
  (positions '()))

(defun add-to-pos (k v sc)
  ;; acons "k: v" onto positions, double-unwrapping
  (setf (stmt-counts-positions sc)
        (acons k v (stmt-counts-positions sc))))

(defun pp-stmt-counts (sc)
  (format nil "~a : [pos: ~a, neg: ~a] -- [~a]"
          (stmt-counts-id sc)
          (stmt-counts-positive sc)
          (stmt-counts-negative sc)
          (pp-positions (stmt-counts-positions sc))))

(defun pp-positions (pos)
  (when pos
    (let ((pair_lst (loop :for key :in (mapcar 'car pos)
                       :for value :in (mapcar 'cdr pos)
                       :collecting (format nil "~a:~a" key value))))
      (format nil "~{~a~^,~}" pair_lst))))

(defun rinard-write-out (path data)
  "Write out fault localization to speed up subsequent trials (see docs)"
  (with-open-file (stream path :direction :output
                          :if-exists :supersede :if-does-not-exist :create)
    (format stream "~a~%" (hash-table-alist data))))

(defun rinard-read-in (path)
  "Read in previously-written fault localization info (see docs)"
  (with-open-file (stream path)
    (let ((alst (loop :for line = (read stream nil :done)
                   :while (not (eq line :done))
                   :collect line)))
      (alist-hash-table alst))))

(defun rinard-compare (a b)
  "Return non-nil if A is more suspicious than B."
  ;; A is more suspicious than B if any of the following are true:
  (cond
    ((> (stmt-counts-negative a) (stmt-counts-negative b)) t)
    ((< (stmt-counts-negative a) (stmt-counts-negative b)) nil)
    ;; Negative count is equal.
    ((< (stmt-counts-positive a) (stmt-counts-positive b)) t)
    ((> (stmt-counts-positive a) (stmt-counts-positive b)) nil)
    ;; Both counts are equal: which is executed later in more tests?
    (t (let* ((pos_a (stmt-counts-positions a))
              (pos_b (stmt-counts-positions b))
              ;; Pairs of positions for traces both a and b appear in.
              (shared_traces (remove nil
                               (loop :for key :in (mapcar 'car pos_a)
                                  :for val_a :in (mapcar 'cdr pos_a)
                                  :collect (let ((pair_b (assoc key pos_b)))
                                             (if pair_b
                                                 (cons val_a (cdr pair_b))
                                                 nil))))))
         (> (count t (mapcar (lambda (pair)
                               (> (or (car pair) -1) (or (cdr pair) -1)))
                             shared_traces))
            (/ (length shared_traces) 2))))))

(defun rinard (count obj stmt-counts)
  "Spectrum-based fault localization from SPR and Prophet."
  (note 2 "Start rinard")
  (let ((stmt-counts-vals (loop for key being the hash-keys of stmt-counts
                             using (hash-value val) collecting val)))
    (let ((sorted (sort stmt-counts-vals #'rinard-compare)))
      ;; Comment in to print out the actual fault loc list with counts.
      ;; (print-rinard sorted)
      (mapcar #'stmt-counts-id (take count sorted)))))

(defun print-rinard (sorted)
  (with-open-file (stream (merge-pathnames "/tmp/GP_fault_loc_sorted")
                          :direction :output :if-exists :supersede)
    (loop :for stmt :in sorted
       :do (format stream "~a~%" (pp-stmt-counts stmt)))))

(defun rinard-incremental (trace-stream stmt-counts is-good-trace cur_test)
  "Process a single trace's output, return the aggregated results"
  ;; find position of last occurrence of stmt in trace
  (note 3 "Start rinard-incremental")
  (unless stmt-counts
    (setf stmt-counts (make-hash-table)))

  (flet ((increment-counts (stmt-count is-good-trace)
           (setf (stmt-counts-positive stmt-count)
                 (+ (stmt-counts-positive stmt-count)
                    (if is-good-trace 1 0)))
           (setf (stmt-counts-negative stmt-count)
                 (+ (stmt-counts-negative stmt-count)
                    (if is-good-trace 0 1))))
         ;; we need actual stmt values, rather than strings for later comparisons
         (fix-string-fields (trace-results)
           (let ((rehash (make-hash-table :test #'equal)))
             (loop for key being the hash-keys of trace-results
                using (hash-value value)
                do (let ((k (if (stringp key)
				(read-from-string key)
				key)))
                     (setf (stmt-counts-id value) (stmt-counts-id value))
                     (setf (gethash k rehash) value)))
             rehash)))
    ;; use new-counts to trace stmts occurring in current trace
    (let ((new-counts (make-hash-table :test #'equal)))
      (iter (for stmt = (read-line trace-stream nil :done))
        (for i upfrom 0)
        (while (not (eq stmt :done)))
	  ;; convert to sexp
	  (setf stmt (read-from-string stmt))
          ;; we'll never store 'nil' as a key, so just inspecting returned val is fine
          (let ((stmt-count (gethash stmt new-counts)))
            (if stmt-count
                ;; stmt occurred earlier in this trace: update last position
                (unless is-good-trace
                  (rplacd (assoc cur_test (stmt-counts-positions stmt-count)) i))
                ;; stmt has not already occurred in this trace
                (let ((stmt-count (gethash stmt stmt-counts)))
                  (if stmt-count
                      ;; stmt occurred in a prior trace
                      (progn
                        ;; add to stmts seen in trace, add position, increment
                        ;; counts
                        (setf (gethash (stmt-counts-id stmt-count) new-counts) stmt-count)
                        (unless is-good-trace
                          (setf (stmt-counts-positions stmt-count) (acons cur_test i (stmt-counts-positions stmt-count))))
                        (increment-counts stmt-count is-good-trace))
                      ;; new stmt not yet seen in any trace
                      (let ((new-count (make-stmt-counts
                                        :id stmt
                                        :positive (if is-good-trace 1.0 0.0)
                                        :negative (if is-good-trace 0.0 1.0)
                                        :positions  (if is-good-trace
                                                        '()
                                                        (list (cons cur_test i))))))
                        (setf (gethash (stmt-counts-id new-count) new-counts) new-count)
                        (setf (gethash (stmt-counts-id new-count) stmt-counts) new-count))))))))
  (note 3 "End rinard-incremental")

  ;; debug -- use to compare fault loc info to other techniques
  ;; (let ((sorted_keys (sort (loop for key being the hash-keys of stmt-counts
  ;;                             collecting key)
  ;;                          #'string-lessp)))
  ;;   (loop for x in sorted_keys
  ;;      do
  ;;        (multiple-value-bind (val found) (gethash x stmt-counts)
  ;;          (format t "~S : ~S~%" x (pp-stmt-counts val)))))

  (fix-string-fields stmt-counts)))
