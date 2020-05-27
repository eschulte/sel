;;; lisp.lisp --- software representation of lisp code
;;;
;;; Eclector, see @url{https://github.com/robert-strandh/Eclector},
;;; is used to parse lisp source into concrete ASTs.
;;;
;;; @texi{lisp}
(defpackage :software-evolution-library/software/lisp
  (:nicknames :sel/software/lisp :sel/sw/lisp)
  (:use :gt/full
        :software-evolution-library
        :software-evolution-library/software/parseable
        :eclector.parse-result)
  (:import-from :eclector.reader
                :evaluate-expression
                :interpret-symbol)
  (:shadowing-import-from :eclector.readtable
                          :copy-readtable
                          :set-dispatch-macro-character)
  (:shadowing-import-from :eclector.parse-result
                          :read
                          :read-from-string
                          :read-preserving-whitespace)
  (:export :lisp :lisp-ast
           :expression :expression-result
           :reader-conditional
           :feature-expression
           :reader-quote
           :reader-quasiquote
           :reader-unquote
           :reader-unquote-splicing
           :*string*
           :transform-reader-conditional
           :walk-feature-expressions
           :walk-reader-conditionals
           :map-reader-conditionals
           :map-feature-expressions
           :transform-feature-expression
           :featurep-with
           :remove-expression-features
           :remove-feature-support
           :compound-form-p
           :get-compound-form-args
           :quote-p
           :quasiquote-p
           :quoted-p
           :find-in-defining-form
           :find-local-function
           :enclosing-find-if))
(in-package :software-evolution-library/software/lisp)
(in-readtable :curry-compose-reader-macros)


(defvar *string* nil)

(defmacro define-matchable-class (class-name super-classes slots &rest options)
  "Define a new class that is wrapped in an eval-when form. This is to work
around an issue in SBCL--https://bugs.launchpad.net/sbcl/+bug/310120--that
prevents trivia:match from working correctly when classes are defined in the
same file as the match form its being used in."
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (defclass ,class-name ,super-classes
       ,slots
       ,@options)))

(define-matchable-class lisp-ast (functional-tree-ast)
  ((expression :initarg :expression :initform nil :reader expression)
   (children :type list
             :initarg :children
             :initform nil
             :documentation "The list of children of the node,
which may be more nodes, or other values.")
   (child-slots :initform '(children) :allocation :class)
   (data-slot :initform 'expression :allocation :class))
  (:documentation "Class of Common Lisp ASTs."))

(defmethod fset-default-node-accessor ((node-type (eql 'lisp-ast)))
  'expression)

(define-matchable-class result (lisp-ast)
  ((start :initarg :start :initform (when *string* 0)
          :reader start :type (or null (integer 0 *)))
   (end :initarg :end :initform (when *string* (length *string*))
        :reader end :type (or null (integer 0 *)))
   (string-pointer :initarg :string-pointer :initform *string*
                   :reader string-pointer :type (or null string))))

(define-matchable-class expression-result (result) ())

(defmethod print-object ((obj expression-result) stream)
  (with-slots (start end string-pointer expression children) obj
    (if *print-readably*
        (format stream "~S" `(make-instance ',(class-name (class-of obj))
                               :start ,start
                               :end ,end
                               :string-pointer *string*
                               :expression ,expression
                               :children (list ,@children)))
        (print-unreadable-object (obj stream :type t)
          (format stream ":EXPRESSION ~a" expression)))))

(define-matchable-class reader-conditional (expression-result)
  ((feature-expression :initarg :feature-expression
                       :reader feature-expression)))

(defmethod initialize-instance :after ((obj reader-conditional) &key)
  (with-slots (feature-expression) obj
    (when (typep feature-expression 'expression-result)
      (callf #'expression feature-expression))
    (assert (typep feature-expression '(or symbol list)))))

(defmethod copy ((obj reader-conditional) &rest args &key &allow-other-keys)
  (apply #'call-next-method
         obj
         :feature-expression (feature-expression obj)
         args))

(defmethod print-object ((obj reader-conditional) stream)
  (nest
   (with-slots (feature-expression expression) obj)
   (if *print-readably* (call-next-method))
   (print-unreadable-object (obj stream :type t))
   (format stream "#~a~a :EXPRESSION ~a"
           (reader-conditional-sign obj)
           feature-expression expression)))

(define-matchable-class skipped-input-result (result)
  ((reason :initarg :reason :reader  reason)))

(defmethod print-object ((obj skipped-input-result) stream &aux (max-length 8))
  (nest (with-slots (start end string-pointer reason) obj)
        (if *print-readably*
            (format stream "~S" `(make-instance ',(class-name (class-of obj))
                                   :start ,start
                                   :end ,end
                                   :string-pointer *string*
                                   :reason ,reason)))
        (print-unreadable-object (obj stream :type t))
        (format stream ":REASON ~a :TEXT ~S" reason)
        (if (> (- end start) (- max-length 3))
            (concatenate
             'string
             (subseq string-pointer start (+ start (- max-length 3)))
             "...")
            (subseq string-pointer start end))))

(define-matchable-class reader-token (skipped-input-result)
  ())

(defmethod source-text ((obj reader-token) &optional stream)
  (write-string (string-pointer obj) stream))

(defmethod print-object ((obj reader-token) stream)
  (if *print-readably*
      (call-next-method)
      (print-unreadable-object (obj stream :type t))))

(define-matchable-class sharpsign-dot (reader-token)
  ((reason :initform :read-eval)
   (string-pointer :initform "#.")
   (start :initform 0)
   (end :initform 2)))

(define-matchable-class reader-conditional-token (reader-token)
  ((reason :initform :reader-conditional)
   (start :initform 0)
   (end :initform 2)))

(define-matchable-class sharpsign-plus (reader-conditional-token)
  ((string-pointer :initform "#+")))

(define-matchable-class sharpsign-minus (reader-conditional-token)
  ((string-pointer :initform "#-")))

(define-matchable-class reader-quote (expression-result) ())

(define-matchable-class reader-quasiquote (expression-result) ())

(define-matchable-class reader-unquote (expression-result) ())

(define-matchable-class reader-unquote-splicing (expression-result) ())

(defmethod convert ((to-type (eql 'lisp-ast)) (sequence list)
                    &key (spaces nil) (expression sequence)
                      (keyword-prefix ":")
                      &allow-other-keys)
  (labels ((m/space (&optional string)
             (or (and (not string) spaces (pop spaces))
                 (let ((*string* (or string " ")))
                   (make-instance 'skipped-input-result :reason :whitespace))))
           (m/keyword (symbol)
             (let ((*string* (concatenate 'string
                                          keyword-prefix
                                          (string-downcase
                                           (symbol-name symbol)))))
               (make-instance 'expression-result :expression symbol)))
           (m/symbol (symbol)
             (let ((*string* (string-downcase (symbol-name symbol))))
               (make-instance 'expression-result :expression symbol)))
           (m/other (other)
             (let ((*string* (format nil "~S" other)))
               (make-instance 'expression-result :expression other)))
           (intersperse-spaces (list)
             (let ((ult (length list))
                   (last nil))
               (iter (for el in list)
                     (for i upfrom 0)
                     (if (and (< i ult)
                              (> i 0)
                              (not (string= "(" (source-text last)))
                              (not (string= ")" (source-text el))))
                         (appending (list (m/space) el))
                         (collecting el))
                     (setf last el))))
           (convert (node)
             (when node
               (typecase node
                 (lisp-ast node)
                 (keyword (m/keyword node))
                 (symbol (m/symbol node))
                 (list
                  (let ((*string* ""))
                    (make-instance 'expression-result :expression expression
                                   :children
                                   (intersperse-spaces
                                    (append (list (m/space "("))
                                            (mapcar #'convert node)
                                            (list (m/space ")")))))))
                 (t (m/other node))))))
    (populate-fingers (convert sequence))))

;;; Trivial Eclector client used to customize parsing for SEL.
(define-matchable-class client (parse-result-client) ())

(defun sharpsign-sign-reader (stream char n)
  ;; TODO: back up according to digits in n
  (assert (not n))
  (nest
   (let* ((client (make-instance 'client))
          (start (- (file-position stream) 2))
          (feature-expression
           (let ((*package* (find-package :keyword)))
             (read client stream)))
          (expression (read client stream))
          (end (file-position stream))))
   (make 'reader-conditional
         :start start
         :end end
         :feature-expression feature-expression
         :expression expression
         :children (append
                    (list
                     (make (ecase char
                             (#\+ 'sharpsign-plus)
                             (#\- 'sharpsign-minus))
                           ;; These are for the benefit of read+, so
                           ;; it doesn't insert needless whitespace.
                           :start start
                           :end (+ start 2)))
                    (list feature-expression)
                    (list expression)))))

(defgeneric transform-reader-conditional (reader-conditional fn)
  (:documentation "Build a new reader condition by calling FN on READER-CONDITIONAL.

FN is called with three arguments: the sign, as a character \(+ or -);
the feature expresion \(as a list); and the guarded expression.

FN should return three values - a new sign, a new test, and a new
expression - which are used to build a new reader conditional.

If the sign, the test, and the expression are unchanged,
READER-CONDITIONAL is returned unchanged and a second value of t is
returned."))

(defmethod transform-reader-conditional ((result reader-conditional) fn)
  (mvlet* ((children (children result))
           (token (find-if (of-type 'reader-token) children))
           (sign
            (etypecase token
              (sharpsign-plus #\+)
              (sharpsign-minus #\-)))
           (test ex
                 (nest
                  (values-list)
                  (remove-if-not (of-type 'expression-result))
                  children))
           (new-sign new-test new-ex
                     (funcall fn sign (expression test) ex))
           (*string* nil))
    (assert (typep new-test '(or symbol list)))
    (if (and (eql new-sign sign)
             (equal new-test test)
             (eql ex new-ex))
        ;; Nothing has changed.
        (values result t)
        (make 'reader-conditional
              :start (start result)
              :end (end result)
              :feature-expression new-test
              :expression ex
              :children
              (mapcar (lambda (child)
                        (typecase child
                          (reader-token
                           (ecase new-sign
                             (#\+ (make 'sharpsign-plus))
                             (#\- (make 'sharpsign-minus))))
                          (expression-result
                           (econd ((eql child test)
                                   (if (equal new-test (expression test))
                                       test
                                       (convert 'lisp-ast new-test :keyword-prefix "")))
                                  ((eql child ex) new-ex)))
                          (t child)))
                      children)))))

(defmethod reader-conditional-sign ((ex reader-conditional))
  (let ((token (find-if (of-type 'reader-token) (children ex))))
    (etypecase token
      (sharpsign-plus #\+)
      (sharpsign-minus #\-))))

(defparameter *lisp-ast-readtable*
  (let ((readtable (copy-readtable eclector.readtable:*readtable*)))
    (set-dispatch-macro-character readtable #\# #\+ 'sharpsign-sign-reader)
    (set-dispatch-macro-character readtable #\# #\- 'sharpsign-sign-reader)
    readtable))

(defmethod make-expression-result
    ((client client) (result expression-result) (children t) (source t))
  result)

(defmethod make-expression-result
    ((client client) (result t) (children t) (source cons))
  (destructuring-bind (start . end) source
    (match result
           ((list '|#.| result)
            (make-instance 'expression-result
              :expression result
              :children (cons (make 'sharpsign-dot) children)
              :start start
              :end end))
           (otherwise
            (make-instance 'expression-result
              :expression result
              :children children
              :start start
              :end end)))))

(defmethod make-skipped-input-result
    ((client client) stream reason source)
  (declare (ignorable client stream))
  (make-instance 'skipped-input-result
    :reason reason :start (car source) :end (cdr source)))

(defmethod interpret-symbol
    ((client client) input-stream package-indicator symbol-name internp)
  (declare (ignorable input-stream))
  (let ((package (case package-indicator
                   (:current *package*)
                   (:keyword (find-package "KEYWORD"))
                   (t        (or (find-package package-indicator)
                                 ;; Return a fake package for missing packages.
                                 (find-package :missing)
                                 (make-package :missing))))))
    (if internp
        (intern symbol-name package)
        (multiple-value-bind (symbol status)
            (find-symbol symbol-name package)
          (cond ((null status) ; Ignore `symbol-does-not-exist' errors.
                 ;; (eclector.base::%reader-error
                 ;;  input-stream 'eclector.reader::symbol-does-not-exist
                 ;;  :package package
                 ;;  :symbol-name symbol-name)
                 symbol)
                ((eq status :internal) ; Ignore `symbol-is-not-external' errors.
                 ;; (eclector.base::%reader-error
                 ;;  input-stream 'eclector.reader::symbol-is-not-external
                 ;;  :package package
                 ;;  :symbol-name symbol-name)
                 symbol)
                (t
                 symbol))))))

;;; The next two forms are used to avoid throwing errors when a
;;; #. reader macro attempts to execute code during parsing.  We want
;;; to avoid this as we will typically not have the requisite
;;; variables defined.
(defgeneric wrap-in-sharpsign-dot (client material)
  (:method (client material)
    (declare (ignorable client))
    (list '|#.| material)))

(defmethod evaluate-expression ((client client) expression)
  (wrap-in-sharpsign-dot client expression))

(defun read-forms+ (string &key count)
  (check-type count (or null integer))
  (let ((*string* string)
        (client (make-instance 'client))
        (eclector.readtable:*readtable* *lisp-ast-readtable*))
    (labels
        ((process-skipped-input (start end)
           (when (< start end)
              (string-case (subseq string start end)
                ("'"
                 (list (make-instance 'reader-quote
                         :start start :end end)))
                ("`"
                 (list (make-instance 'reader-quasiquote
                         :start start :end end)))
                (","
                 (list (make-instance 'reader-unquote
                         :start start :end end)))
                (",@"
                 (list (make-instance 'reader-unquote-splicing
                                      :start start :end end)))
                (t
                 (list (make-instance 'skipped-input-result
                         :start start :end end :reason 'whitespace))))))
         (w/space (tree from to)
           (let ((result
                   (etypecase tree
                     (list
                      (append
                       (iter (for subtree in tree)
                         (appending (process-skipped-input from (start subtree)))
                         (appending (w/space subtree
                                             (start subtree) (end subtree)))
                         (setf from (end subtree)))
                       (process-skipped-input from to)))
                     (result
                      (when (subtypep (type-of tree) 'expression-result)
                        (when (children tree)
                          ;; Use (sef slot-value) because this is now a
                          ;; functional tree node so the default setf would
                          ;; have no effect (it would create a copy).
                          (setf (slot-value tree 'children)
                                (w/space
                                 (children tree) (start tree) (end tree)))))
                      (append
                       (process-skipped-input from (start tree))
                       (list tree)
                       (process-skipped-input (end tree) to))))))
             result)))
      (let ((end (length string)))
        (w/space
         (with-input-from-string (input string)
           (loop :with eof = '#:eof
              :for n :from 0
              :for form = (if (and count (>= n count))
                              eof
                              (read client input nil eof))
              :until (eq form eof) :collect form
              :finally (when count
                         (setf end (file-position input)))))
         0 end)))))

(defun walk-skipped-forms (function forms)
  (mapcar
   (lambda (form)
     (etypecase form
       (skipped-input-result (funcall function form))
       (expression-result (walk-skipped-forms function (children form)))))
   forms))

(defun walk-forms (function forms)
  (mapcar (lambda (form)
            (etypecase form
              (skipped-input-result (funcall function form))
              (expression-result (funcall function form)
                                 (walk-forms function (children form)))))
          forms))

(defun write-stream-forms+ (forms stream)
  "Write the original source text of FORMS to STREAM."
  (walk-skipped-forms  {source-text _ stream} forms))

(defun write-string-forms+ (forms)
  "Write the original source text of FORMS to a string."
  (with-output-to-string (s) (write-stream-forms+ forms s)))


;;; Lisp software object
(define-software lisp (parseable)
  ()
  (:documentation "Common Lisp source represented naturally as lists of code."))

(defmethod convert ((to-type (eql 'lisp-ast)) (string string)
                    &key &allow-other-keys)
  (make-instance 'lisp-ast :children (read-forms+ string)))

(defmethod parse-asts ((lisp lisp))
  (convert 'lisp-ast (genome-string lisp)))

(defmethod source-text ((obj result) &optional stream)
  (if (children obj)
      (mapc {source-text _ stream} (children obj))
      (write-string (string-pointer obj) stream
                    :start (start obj) :end (end obj))))

(defmethod convert ((to-type (eql 'expression-result)) (symbol symbol)
                    &key &allow-other-keys)
  (let ((*string*
         (string-invert-case
          (symbol-name symbol))))
    (make-instance 'expression-result
      :expression symbol
      :start 0
      :end (length *string*))))

(defmethod convert ((to-type (eql 'lisp-ast)) (symbol symbol)
                    &key &allow-other-keys)
  (make-instance 'lisp-ast
    :children (list (convert 'expression-result symbol))))

(defun walk-feature-expressions (fn ast)
  "Call FN, a function, on each feature expression in AST."
  (fbind (fn)
         (walk-reader-conditionals (lambda (sign featurex ex)
                                     (declare (ignore sign ex))
                                     (fn featurex))
                                   ast)))

(defun walk-reader-conditionals (fn ast)
  "Call FN, a function, on each reader conditional in AST.

FN is called with three arguments: the sign of the reader conditional
\(+ or -), the feature expression \(as a list), and the guarded
expression."
  (fbind (fn)
    (mapc (lambda (node)
            (when (typep node 'reader-conditional)
              (fn (reader-conditional-sign node)
                (feature-expression node)
                (expression node))))
          ast)
    (values)))

(defun featurex-empty? (featurex)
  (or (null featurex)
      (equal featurex '(:or))))

(defun map-feature-expressions (fn ast
                                &key remove-empty
                                  (remove-newly-empty remove-empty))
  "Build a new ast by calling FUN, a function, on each feature
expression in AST, substituting the old feature expression with the
return value of FN.

REMOVE-EMPTY and REMOVE-NOT-EMPTY have the same meaning as for
`map-reader-conditionals'."
  (fbind (fn)
         (map-reader-conditionals (lambda (sign featurex ex)
                                    (values sign (fn featurex) ex))
                                  ast
                                  :remove-empty remove-empty
                                  :remove-newly-empty remove-newly-empty)))

(defun map-reader-conditionals (fn ast
                                 &key remove-empty
                                 (remove-newly-empty remove-empty))
  "Build a new ast by calling FN, an function, on each reader
conditional in AST (as if by `transform-reader-conditional') and
substituting the old reader conditional with the new one.

If :REMOVE-EMPTY is true, remove any reader conditionals where the
feature expression is empty. If the sign is +, the entire reader
conditional is removed. If the sign is -, then only the guarded
expression is retained.

If :REMOVE-NEWLY-EMPTY is true, reader conditionals are removed if the
new feature expression is empty, but reader conditionals that were
already empty are retained."
  (assert (if remove-empty remove-newly-empty t))
  (nest
   (fbind (fn))
   (mapcar
    (lambda (node)
      (if (typep node 'reader-conditional)
          (block replace
            (flet ((remove (sign node)
                     (return-from replace
                       (ecase sign
                         (#\+ nil)
                         (#\- (expression node))))))
              (transform-reader-conditional
               node
               (lambda (sign featurex ex)
                 (if (and (featurex-empty? featurex) remove-empty)
                     (remove sign node)
                     (receive (sign featurex ex)
                         (fn sign featurex ex)
                       (if (and (featurex-empty? featurex)
                                remove-newly-empty)
                           (remove sign node)
                           (values sign featurex ex))))))))
          node))
    ast)))

(defun transform-feature-expression (feature-expression fn)
  "Call FN, a function, on each feature in FEATURE-EXPRESSION.
Substitute the return value of FN for the existing feature.

If FN returns nil, the feature is removed.

FN may return any feature expression, not just a symbol."
  (match feature-expression
         ((or nil (list :or)) nil)
         ((and symbol (type symbol))
          (funcall fn symbol))
         ((list (or :and :or :not))
          nil)
         ((list :and feature)
          (transform-feature-expression feature fn))
         ((list :or feature)
          (transform-feature-expression feature fn))
         ((list* (and prefix (or :and :or :not)) features)
          (let ((new
                 (cons prefix
                       (remove nil
                               (remove-duplicates
                                (mappend (lambda (feature-expression)
                                           (match (transform-feature-expression feature-expression fn)
                                                  ((list* (and subprefix (or :and :or))
                                                          features)
                                                   (if (eql subprefix prefix)
                                                       features
                                                       (list features)))
                                                  (x (list x))))
                                         features)
                                :test #'equal)))))
            (if (equal new feature-expression) new
                (transform-feature-expression new fn))))))

(defun featurep-with (feature-expression *features*)
  "Test FEATURE-EXPRESSION against the features in *FEATURES*.

The global value of `*features*` is ignored."
  (featurep feature-expression))

(defun remove-expression-features (feature-expression features)
  "Remove FEATURES from FEATURE-EXPRESSION.
If there are no features left, `nil' is returned."
  (transform-feature-expression feature-expression
                                (lambda (feature)
                                  (unless (member feature features)
                                    feature))))

(defun remove-feature-support (ast features)
  "Remove support for FEATURES from AST.
Each feature in FEATURES will be removed from all feature expressions,
and if any of the resulting expressions are empty their guards (and
possibly expressions) will be omitted according to the sign of the guard."
  (map-reader-conditionals (lambda (sign featurex ex)
                             (let ((featurex (remove-expression-features featurex features)))
                               (values sign featurex ex)))
                           ast
                           :remove-newly-empty t))


;;; Utility
(-> compound-form-p (lisp-ast &key (:name symbol)) t)
(defun compound-form-p (ast &key name)
  "If the AST is a compound form, return the car of the form. If NAME is
provided, return T if the car of the form is eq to NAME."
  (match ast
    ((lisp-ast
      (ast-children (list* _ (expression-result (expression form-name)) _)))
     (cond
       (name (eq name form-name))
       ((symbolp form-name) form-name)))))

(-> get-compound-form-args (lisp-ast) list)
(defun get-compound-form-args (ast)
  "Return the args to the compound form represented by AST."
  (match ast
    ((lisp-ast
      (ast-children (list* _ _ args)))
     (remove-if-not {typep _ 'expression-result} args))))

(-> quote-p (lisp-ast) (or null lisp-ast))
(defun quote-p (ast)
  "Return the quoted form if AST represents a quote ast."
  (match ast
    ((lisp-ast
      (ast-children
       (list (reader-quote) form)))
     form)
    ((lisp-ast
      (ast-children
       (list _ (expression-result (expression 'quote)) _ form _)))
     form)))

(-> quasiquote-p (lisp-ast) (or null lisp-ast))
(defun quasiquote-p (ast)
  "Return the quoted form if AST represents a quasiquote ast."
  #-sbcl
  (declare (ignorable ast))
  #-sbcl
  (error "~a currently only supports SBCL." #'quasiquote-p)
  #+sbcl
  (match ast
    ((lisp-ast
      (ast-children
       (list (reader-quasiquote) form)))
     form)
    ((lisp-ast
      (ast-children
       (list _ (expression-result (expression 'sb-int:quasiquote))
             _ form _)))
     form)))

(-> quoted-p (lisp lisp-ast) (or null lisp-ast))
(defun quoted-p (obj ast)
  "Return the quoted form if the AST is quoted."
  ;; TODO: This does not currently handle unquotes;
  ;;       it only checks if there is a quote or
  ;;       quasiquote somewhere above.
  (enclosing-find-if «or #'quote-p #'quasiquote-p» obj ast))

(->  find-in-defining-form (lisp lisp-ast symbol
                                 &key (:referencing-ast lisp-ast))
     (or null lisp-ast))
(defun find-in-defining-form (obj defining-form name &key referencing-ast)
  "Returns the ast in DEFINING-FORM that defines NAME.
If REFERENCING-AST is supplied, the returned ast must
occur before it."
  (let ((targeter (if referencing-ast
                      (lambda (target)
                        (and (path-later-p (ast-path obj referencing-ast)
                                           (ast-path obj target))
                             (compound-form-p target :name name)))
                      {compound-form-p _ :name name})))
    (match defining-form
      ((lisp-ast
        (ast-children (list* (@@ 3 _) definition-list _)))
       (cl:find-if targeter
                   (reverse
                    (remove-if-not {typep _ 'expression-result}
                                   (ast-children definition-list))))))))

(-> find-local-function (lisp lisp-ast symbol &key (:referencing-ast lisp-ast))
    (or null lisp-ast))
(defun find-local-function (obj enclosed-form function-name
                            &key (referencing-ast enclosed-form))
  "Return the ast of the local function named FUNCTION-NAME
which is in scope of ENCLOSED-FORM."
  (when-let ((defining-form (enclosing-find-if [«or {eq 'flet} {eq 'labels}»
                                                #'compound-form-p]
                                               obj enclosed-form)))
    (if-let (local-function
             (find-in-defining-form obj defining-form function-name
                                    :referencing-ast referencing-ast))
      local-function
      (find-local-function obj defining-form function-name
                           :referencing-ast referencing-ast))))

(-> enclosing-find-if (function lisp lisp-ast) (or null lisp-ast))
(defun enclosing-find-if (predicate obj ast)
  "Walk up OBJ's genome starting at the parent of AST.
If a node if found that satiisfies PREDICATE, return
that node. Otherwise, nil is returned."
  (when-let* ((enclosing-form-path (enclosing-scope obj ast))
              (enclosing-ast (lookup (genome obj) enclosing-form-path)))
    (if (funcall predicate enclosing-ast)
        enclosing-ast
        (enclosing-find-if predicate obj enclosing-ast))))

(defmethod enclosing-scope ((obj lisp) (ast lisp-ast))
  ;; Returns nil if already at the top level.
  (butlast (ast-path obj ast)))


;;; Example
#+example
(progn

;;; Rewrite ->> to use nest instead.
  (defun fix-double-arrow (node)
    (flet ((children (node)
             (let* ((*string* "nest")
                    (nest (make-instance 'expression-result
                            :expression 'nest :start 0 :end (length *string*)))
                    (space (remove-if-not
                            {typep _ 'skipped-input-result} (children node)))
                    (exprs (cons nest (reverse (cdr (remove-if-not
                                                     {typep _ 'expression-result}
                                                     (children node)))))))
               (mapcar ‹etypecase (skipped-input-result (pop space))
                        (expression-result (pop exprs))›
                        (children node)))))
      (let* ((*string* nil)
             (expression (cons 'nest (reverse (cdr (expression node)))))
             (children (children node)))
        (make-instance 'expression-result
          :expression expression
          :children children))))

  (defun rewrite-double-arrow (software)
    (setf (genome software)
          (mapcar (lambda (node)
                    (if (and (typep node 'expression-result)
                             (listp (expression node))
                             (equal '->> (first (expression node))))
                        (fix-double-arrow node)
                        node))
                    (genome software))))

  (defun rewrite-double-arrow-in-place (file)
    (string-to-file (source-text (rewrite-double-arrow
                                  (from-file (make-instance 'lisp) file))) file)))
