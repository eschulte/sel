(in-package :software-evolution)

(define-condition unhandled-token-class (error)
  ((text :initarg :text :initform nil :reader text))
  (:report (lambda (condition stream)
             (format stream "Tokenization failed: ~a"
                     (text condition)))))

(defgeneric find-ast (asts ast-id)
  (:documentation "Find and return an ast node from the set of ASTS whose
id is AST-ID."))

(defmethod find-ast ((asts list) (ast-id integer))
  (find-if {eql ast-id} asts :key {aget :counter}))

(defmethod find-ast ((asts list) (ast-id (eql nil)))
  nil)

(defgeneric tokenize (root asts)
  (:documentation "Return a list of tokens representing the AST whose root
is ROOT and whose descendants are included in the set of ASTS."))

;; For reference, list of tokens:
;; :&& :identifier :l-brace :r-brace :l-paren :r-paren :l-square :r-square
;; (opcodes) := :break :continue :case :switch :default :comma :colon :question
;; :if :else :while :do :typedef :-> :. :va-arg :return :goto :for
;; :offset-of :generic :sizeof :alignof :struct :union
;; :char-literal :int-literal :string-literal :float-literal :i-literal
;; :...
(defmethod tokenize (root asts)
  (let ((children (aget :children root)))
    (flet ((tokenize-children (asts children)
             (mappend [{tokenize _ asts} {find-ast asts}] children))
           (tokenize-nth-child (asts children n)
             (let ((nth-child (nth n children)))
               (if nth-child
                   (tokenize (find-ast asts nth-child) asts)
                   (error (make-condition
                           'tokenization-failure
                           :text (format
                                  nil
                                  "Expected to find ~a children in AST ~a."
                                  (1+ n) root))))))
           (split-tokens (str &optional (start 0) (end (length str)))
             (remove-if #'emptyp
                        (split "\\s+|(\\W)" str
                               :with-registers-p t
                               :omit-unmatched-p t
                               :start start
                               :end end)))
           ;; in a list of lists, append a comma at the end of each list
           (comma-sep (ls)
             (cdr (mappend {cons :comma} ls)))
           (token-from-string (str)
             (switch (str :test #'equal)
               (">" :>) ("<" :<) ("<=" :<=) (">=" :>=) ("==" :==) ("!=" :!=)
               ("&&" :&&) ("||" :pipe-pipe) ("&" :&) ("|" :pipe) ("^" :^)
               ("<<" :<<) (">>" :>>) ("+" :+) ("-" :-) ("*" :*) ("/" :/)
               ("%" :%) ("+=" :+=) ("-=" :-=) ("*=" :*=) ("/=" :/=)
               ("%=" :%=) ("++" :++) ("--" :--) ("<<=" :<<=) (">>=" :>>=)
               ("&=" :&=) ("|=" :pipe=) ("^=" :^=) ("!" :!) ("~" :~) ("=" :=)
               ("," :comma) ("->" :->) ("." :.) ("(" :l-paren) (")" :r-paren)
               ("[" :l-square) ("]" :r-square) ("{" :l-brace) ("}" :r-brace)
               ("identifier" :identifier) ("..." :...)
               ("sizeof" :sizeof) ("alignof" :alignof)
               ("struct" :struct) ("union" :union)
               (t (intern str)))))
      (switch ((aget :ast-class root) :test #'equal)
        ("AddrLabelExpr"
         (assert (<= 2 (length (aget :src-text root))))
         (list :&& :identifier))
        ("ArraySubscriptExpr"
         (assert (= 2 (length children)))
         (append (tokenize-nth-child asts children 0)
                 (list :l-square)
                 (tokenize-nth-child asts children 1)
                 (list :r-square)))
        ;; no tokens, just proceed to children
        ("AttributedStmt" (tokenize-children asts children))
        ("BinaryOperator"
         (assert (= 2 (length children)))
         (append (tokenize-nth-child asts children 0)
                 (list (token-from-string (aget :opcode root)))
                 (tokenize-nth-child asts children 1)))
        ("BreakStmt" (list :break))
        ("CallExpr"
         (append (tokenize-nth-child asts children 0)
                 (list :l-paren)
                 ;; separate by commas then remove trailing comma
                 (comma-sep (mapcar {tokenize-nth-child asts children}
                                    (iota (1- (length children)) :start 1)))
                 ;; right paren
                 (list :r-paren)))
        ("CaseStmt" (append (list :case)
                            (tokenize-nth-child asts children 0)
                            (list :colon)
                            (tokenize-children asts (cdr children))))
        ("CharacterLiteral" (list :char-literal))
        ("CompoundAssignOperator"
         (assert (= 2 (length children)))
         (append (tokenize-nth-child asts children 0)
                 (list (token-from-string (aget :opcode root)))
                 (tokenize-nth-child asts children 1)))
        ;; TODO: need to pull out the cast part and tokenize the
        ;; children, but some children seem to be duplicated
        ("CompoundLiteralExpr"
         (let* ((l-paren (position #\( (aget :src-text root)))
                (r-paren (position #\) (aget :src-text root)))
                (cast-expr (split-tokens (aget :src-text root)
                                         (1+ l-paren)
                                         r-paren)))
           (append (list :l-paren)
                   ;; TODO: write string->token function
                   (mapcar #'token-from-string cast-expr)
                   (list :r-paren)
                   (tokenize-children asts children))))
        ("CompoundStmt" (append (list :l-brace)
                                (tokenize-children asts children)
                                (list :r-brace)))
        ("ConditionalOperator"
         (assert (= 3 (length children)))
         (append (tokenize-nth-child asts children 0)
                 (list :question)
                 (tokenize-nth-child asts children 1)
                 (list :colon)
                 (tokenize-nth-child asts children 2)))
        ("ContinueStmt" (list :continue))
        ("CStyleCastExpr"
         (let* ((l-paren (position #\( (aget :src-text root)))
                (r-paren (position #\) (aget :src-text root)))
                (cast-expr (split-tokens (aget :src-text root)
                                         (1+ l-paren)
                                         r-paren)))
           (append (list :l-paren)
                   ;; TODO: write string->token function
                   (mapcar #'token-from-string cast-expr)
                   (list :r-paren)
                   (tokenize-children asts children))))
        ("DeclRefExpr" (list :identifier))
        ("DeclStmt" (let ((src (aget :src-text root)))
                      (iter (for decl in (aget :declares root))
                            (setf src (regex-replace decl src "identifier")))
                      (let* ((eql-pos (position #\= src))
                             (left-tokens
                              (split-tokens src 0 (or eql-pos (length src)))))
                        (append (mapcar #'token-from-string  left-tokens)
                                (when eql-pos
                                  (cons :=
                                        (tokenize-children asts children)))))))
        ("DefaultStmt" (append (list :default :colon)
                               (tokenize-children asts children)))
        ;; TODO: This one is weird...
        ;; [const or range] = init , first child is init, rest are for array
        ;; .field-ident = init , child is init (none for field)
        ;; [const or range]*.field-ident = init
        ("DesignatedInitExpr"
         (let* ((src (aget :src-text root))
                (eq-index (position #\= src)))
           (append
            (iter (for i from 0 below eq-index)
                  (with child = 1)
                  (switch ((char src i))
                    (#\[ (appending (list :l-square) into tokens))
                    ;; #\] collect left child
                    (#\] (appending
                           (append (tokenize-nth-child asts children child)
                                   (list :r-square))
                           into tokens)
                         (incf child))
                    (#\. (if (and (< i (- eq-index 2))
                                  (eql #\. (char src (1+ i)))
                                  (eql #\. (char src (+ 2 i))))
                           ;; range: 0...1 collect left child
                           ;; (right child handled by #\] case)
                           (progn
                             (appending
                               (append (tokenize-nth-child asts children child)
                                       (list :...))
                               into tokens)
                             (incf child)
                             (setf i (+ i 2)))
                           ;; field: .identifier
                           (progn (appending (list :. :identifier)
                                    into tokens))))
                    (t nil))
                  (finally (return tokens)))
            (list :=)
            ;; seems backwards, but the initializer is always the first child
            (tokenize-nth-child asts children 0))))
        ("DoStmt"
         (assert (= 2 (length children)))
         (append (list :do)
                 (tokenize-nth-child asts children 0)
                 (list :while :l-paren)
                 (tokenize-nth-child asts children 1)
                 (list :r-paren)))
        ("Enum" (let ((has-ident (not (emptyp (first (aget :declares root))))))
                  (append (list :enum)
                          (when has-ident (list :identifier))
                          (list :l-brace)
                          (comma-sep (mapcar {tokenize-nth-child asts children}
                                             (iota (length children))))
                          (list :r-brace))))
        ("EnumConstant" (list :identifier))
        ("Field" (let* ((decl (first (aget :declares root)))
                        (src (regex-replace decl
                                            (aget :src-text root)
                                            "identifier"))
                        (src (remove #\; src)))
                   (mapcar #'token-from-string (split-tokens src))))
        ("FloatingLiteral" (list :float-literal))
        ("ForStmt"
         (append (list :for :l-paren)
                 (mappend {tokenize-nth-child asts children}
                          (iota (1- (length children))))
                 (list :r-paren)
                 (tokenize-nth-child asts children (1- (length children)))))

        ("Function"
         (let* ((f-name (first (aget :declares root)))
                (sig (take-until {string= "("}
                       (split-tokens
                        (regex-replace f-name
                                       (aget :src-text root)
                                       "identifier")))))
           (append (mapcar #'token-from-string sig)
                   (list :l-paren)
                   ;; comma-separated ParmVars (all but last child)
                   (comma-sep (mapcar {tokenize-nth-child asts children}
                                      (iota (1- (length children)))))
                   (list :r-paren)
                   (tokenize-nth-child asts children (1- (length children))))))
        ;; _Generic(child0, type: child1, type: child2, ...)
        ("GenericSelectionExpr"
         (let* ((comma (position #\, (aget :src-text root)))
                ;; split on commas to get each (type: child) pairs
                (a-ls (cdr (split "\\)|,\\s*" (aget :src-text root)
                                  :start comma)))
                ;; split a-ls on : to get types
                (types (mapcar [#'token-from-string #'first {split ":\\s*"}]
                               a-ls))
                ;; indices of children to tokenize
                (types-children (iota (length types) :start 1)))
           (assert (= (length types) (1- (length children))))
           (append (list :generic :l-paren)
                   (tokenize-nth-child asts children 0)
                   (mappend (lambda (type toks)
                              (append (list :comma type :colon)
                                      toks))
                            types
                            (mapcar {tokenize-nth-child asts children}
                                    types-children))
                   (list :r-paren))))
        ("GotoStmt" (list :goto :identifier))
        ("IfStmt" (append (list :if :l-paren)
                          (tokenize-nth-child asts children 0)
                          (list :r-paren)
                          (tokenize-nth-child asts children 1)
                          (when (= 3 (length children))
                            (cons :else
                                  (tokenize-nth-child asts children 2)))))
        ("ImaginaryLiteral" (list :i-literal))
        ;; Just tokenize children
        ("ImplicitCastExpr" (tokenize-children asts children))
        ("IndirectGotoStmt" (append (list :goto :*)
                                    (tokenize-children asts children)))
        ;; TODO might be broken: seems that some InitListExprs have a
        ;; child that duplicates the whole InitListExpr?
        ("InitListExpr"
         (append (list :l-brace)
                 (comma-sep (mapcar {tokenize-nth-child asts children}
                                    (iota (length children))))
                 (list :r-brace)))
        ("IntegerLiteral" (list :int-literal))
        ("LabelStmt" (append (list :identifier :colon)
                             (tokenize-children asts children)))
        ;; x.y or x->y (one child for leftof ->/.)
        ("MemberExpr"
         ;; find start of rightmost -> or .
         (let* ((dash (position #\- (aget :src-text root) :from-end t))
                (dot (position #\. (aget :src-text root) :from-end t))
                ;; identify (rightmost) -> or .
                (dash-dot (if (or (and dash dot (= dash (max dash dot)))
                                  (not dot))
                              (list :->)
                              (list :.))))
           (assert (= 1 (length children)))
           (append (tokenize-nth-child asts children 0)
                   dash-dot
                   (list :identifier))))
        ("NullStmt" nil)
        ("OffsetOfExpr" (list :offset-of
                              :l-paren
                              :identifier
                              :comma
                              :identifier
                              :r-paren))
        ("ParenExpr" (append (list :l-paren)
                             (tokenize-children asts children)
                             (list :r-paren)))
        ("ParmVar" (let ((decl (first (aget :declares root))))
                     (assert decl)
                     (let ((tokens (split-tokens
                                    (regex-replace decl (aget :src-text root)
                                                   "identifier"))))
                       (mapcar #'token-from-string tokens))))
        ("PredefinedExpr" (list (token-from-string (aget :src-text root))))
        ;; NOTE: struct, union. May include fields or just be a declaration
        ("Record"
         (let* ((decl (first (aget :declares root)))
                (src (if (emptyp decl)
                         (aget :src-text root)
                         (regex-replace decl
                                        (aget :src-text root)
                                        "identifier")))
                (end (position #\{ src)))
           (assert (or (starts-with-subseq "struct" src)
                       (starts-with-subseq "union" src)))
           (append (mapcar #'token-from-string
                           (split-tokens src 0 (or end (length src))))
                   (when end
                     (append (list :l-brace)
                             (tokenize-children asts children)
                             (list :r-brace)))))
         ;; (let ((tokens (split-tokens (aget :src-text root))))
         ;;            (mapcar #'token-from-string tokens))
         )
        ("ReturnStmt" (cons :return
                            (tokenize-children asts children)))
        ;; parenthesized CompoundStmt
        ("StmtExpr" (append (list :l-paren)
                            (tokenize-children asts children)
                            (list :r-paren)))
        ("StringLiteral" (list :string-literal))
        ("SwitchStmt"
         (assert (= 2 (length children)))
         (append (list :switch :l-paren)
                 (tokenize-nth-child asts children 0)
                 (list :r-paren)
                 (tokenize-nth-child asts children 1)))
        ;; NOTE: typedef always appears after struct, has no children in tree
        ("Typedef" (list :typedef))
        ("UnaryExprOrTypeTraitExpr"
         (assert (or (starts-with-subseq "sizeof" (aget :src-text root))
                     (starts-with-subseq "alignof" (aget :src-text root))))
         ;; split on whitespace or non-alpha chars., preserving non-whitespace
         (let ((tokens (split-tokens (aget :src-text root))))
           (mapcar #'token-from-string tokens)))
        ("UnaryOperator"
         (if (starts-with-subseq (aget :opcode root) (aget :src-text root))
             ;; prefix
             (cons (token-from-string (aget :opcode root))
                   (tokenize-children asts children))
             ;; postfix
             (append (tokenize-children asts children)
                     (list (token-from-string (aget :opcode root))))))
        ("VAArgExpr"
         (let* ((comma (position #\, (aget :src-text root)))
                (r-paren (position #\) (aget :src-text root)))
                (type (split-tokens (aget :src-text root)
                                    (1+ comma)
                                    r-paren)))
           (append (list :va-arg :l-paren :identifier)
                   (mapcar #'token-from-string type)
                   (list :r-paren))))
        ;; get all tokens from children
        ("Var" (tokenize-children asts children))
        ("WhileStmt"
         (assert (= 2 (length children)))
         (append (list :while :l-paren)
                 (tokenize-nth-child asts children 0)
                 (list :r-paren)
                 (tokenize-nth-child asts children 1)))
        (t (error
            (make-condition
             'unhandled-token-class
             :text (format nil "Unrecognized AST class ~a"
                           (aget :ast-class root)))))))))
