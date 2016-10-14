;;; Concrete implementation of the database interface
;;; for an external Pliny fodder database.

(in-package :software-evolution)

;; Constants
(define-constant +pliny-default-host+ "localhost"
  :test #'equalp
  :documentation "Default Pliny database host")

(define-constant +pliny-default-port+ 10005
  :documentation "Default Pliny database port")

(define-constant +server-frontend-num-threads+ 4
  :documentation "Number of threads for the database front-end")

(define-constant +server-backend-num-threads+ 4
  :documentation "Number of threads for the database back-end")

(define-constant +server-memory-per-thread+ 436207616
  :documentation "Amount of memory to allocate for each thread")

;; Helpers
(defclass json-false ()
  ())

(defmethod cl-json:encode-json ((object json-false) &optional stream)
  (princ "false" stream)
  nil)

(defvar *json-false* (make-instance 'json-false))

(define-condition pliny-query-failed (error)
  ((command :initarg :command :initform nil :reader command)
   (stdout :initarg :stdout :initform nil :reader stdout)
   (stderr :initarg :stderr :initform nil :reader stderr)
   (exit-code :initarg :exit-code :initform nil :reader exit-code))
  (:report (lambda (condition stream)
             (format stream "Shell command failed with status ~a: \"~a\"~%~
                             stdout: ~a~%~
                             stderr: ~a~%"
                     (exit-code condition) (command condition)
                     (stdout condition) (stderr condition)))))

(defmethod features-to-weights (features)
  (mapcar (lambda (feature) (cons (car feature) (/ 1 (length features))))
          features))

;; Pliny Database
(defclass pliny-database (fodder-database)
  ((host :initarg :host
         :reader host
         :initform +pliny-default-host+
         :type simple-string)
   (port :initarg :port
         :reader port
         :initform +pliny-default-port+
         :type integer)
   (catalog       :initform (temp-file-name)
                  :reader catalog
                  :type simple-string)
   (storage       :initform (temp-file-name)
                  :reader storage
                  :type simple-string)
   (frontend-log  :initform (temp-file-name)
                  :reader frontend-log
                  :type simple-string)
   (backend-log   :initform (temp-file-name)
                  :reader backend-log
                  :type simple-string)
   (ipc-file      :initform (temp-file-name)
                  :reader ipc-file
                  :type simple-string)
   (server-thread :reader server-thread)))

(defmethod from-file ((obj pliny-database) db)
  (note 1 "Starting Pliny Database")
  (start-server obj)
  (sleep 2.5)

  (note 1 "Loading Pliny Database from ~a. ~
           This could take several minutes." db)
  (load-server obj db)

  #+sbcl
  (push {shutdown-server obj} sb-ext:*exit-hooks*)
  #+ccl
  (push {shutdown-server obj} ccl:*lisp-cleanup-functions*)
  #-(or sbcl ccl)
  (warning "Unsupported lisp; please cleanup Pliny ~
            server instance manually upon exit")

  (handler-case
    (when (null (find-snippets obj :limit 1))
      (shutdown-server obj)
      (error "Pliny database ~a does not contain fodder snippets." obj))
    (pliny-query-failed (e)
      (declare (ignorable e))
      (shutdown-server obj)
      (error "Pliny database ~a does not contain fodder snippets." obj)))

  obj)

(defmethod start-server ((obj pliny-database))
  (with-slots (host port catalog frontend-log backend-log ipc-file
               server-thread) obj
    (setf host "localhost")
    (setf server-thread
          (make-thread (lambda()
                        (shell "GTServer ~a ~d ~a ~d ~d ~d ~a ~a"
                               catalog
                               port
                               ipc-file
                               +server-frontend-num-threads+
                               +server-backend-num-threads+
                               +server-memory-per-thread+
                               frontend-log
                               backend-log))
                       :name (format nil "GTServerThread:~a" port)))))

(defmethod load-server ((obj pliny-database) db)
  (with-temp-file (logfile)
    (shell "GTLoader ~a ~d ~a --storage ~a --logfile ~a"
           (host obj) (port obj) db (storage obj) logfile)))

(defmethod shutdown-server ((obj pliny-database))
  (or (or (null (host obj)) (null (port obj)))
      (with-temp-file (logfile)
        (shell "GTServerShutdown ~a ~d --logfile ~a"
               (host obj) (port obj) logfile)))
  (or (null (server-thread obj)) (join-thread (server-thread obj)))
  (or (null (catalog obj)) (delete-file (catalog obj)))
  (or (null (storage obj)) (delete-file (storage obj)))
  (or (null (ipc-file obj)) (delete-file (ipc-file obj)))
  (or (null (frontend-log obj)) (delete-file (frontend-log obj)))
  (or (null (backend-log obj)) (delete-file (backend-log obj)))

  (with-slots (host port server-thread catalog storage ipc-file
               frontend-log backend-log) obj
    (setf host nil
          port nil
          server-thread nil
          catalog nil
          storage nil
          ipc-file nil
          frontend-log nil
          backend-log nil))

  nil)

(defmethod print-object ((obj pliny-database) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~a:~d" (host obj) (port obj))))

(defmethod find-snippets ((obj pliny-database)
                          &key ast-class full-stmt decls
                            (limit (- (expt 2 32) 1)))
  (let ((features (cond (ast-class
                         `((:ast--class  . ,ast-class)
                           (:random . ,(random 1.0))))
                        ((and full-stmt decls)
                         `((:full--stmt . t)
                           (:random . ,(random 1.0))))
                        (full-stmt
                         `((:full--stmt . t)
                           (:is--decl . ,*json-false*)
                           (:random . ,(random 1.0))))
                        ((not decls)
                         `((:is--decl . ,*json-false*)
                           (:random . ,(random 1.0))))
                        (t `((:random . ,(random 1.0)))))))
    (execute-query obj
                   `((:*features . ,features)
                     (:*weights  . ,(features-to-weights features)))
                   limit)))

(defmethod sorted-snippets ((obj pliny-database) predicate
                            &key target key ast-class limit-considered
                              (limit (- (expt 2 32) 1))
                              (filter #'null))
  (declare (ignorable predicate key limit-considered))
  (labels ((add-target-feature ()
             (if (every 'integerp target)
                 `((:binary--contents . ,(format nil "~{~2,'0x~^ ~}" target)))
                 `((:disasm . ,(format nil "~S" target)))))
           (add-ast-class-feature (features)
             (if ast-class
                 (append features `((:ast--class . ,ast-class)))
                 features)))
    (let ((features (-> (add-target-feature)
                        (add-ast-class-feature))))
      (remove-if filter
                 (execute-query obj
                                `((:*features . ,features)
                                  (:*weights . ,(features-to-weights features)))
                                limit)))))

(defmethod find-type ((obj pliny-database) hash)
  (first (execute-query obj
                        `((:*features (:hash . ,hash))
                          (:*weights (:hash . 1)))
                        1)))

(defgeneric execute-query (pliny-database query limit)
  (:documentation
   "Execute QUERY against PLINY-DATABASE with GTQuery."))

(defmethod execute-query ((obj pliny-database) query limit)
  (with-temp-file-of (query-file "json")
    (cl-json:encode-json-to-string query)
    (with-temp-file (log-file)
      (let ((query-command (format nil "GTQuery ~a ~D ~D ~a --logfile ~a"
                                   (host obj) (port obj) limit
                                   query-file log-file))
            (cl-json:*identifier-name-to-key* 'se-json-identifier-name-to-key))
        (multiple-value-bind (stdout stderr errno)
            (shell query-command)
          (if (zerop errno)
              (reverse (cl-json:decode-json-from-string stdout))
              (error (make-condition 'pliny-query-failed
                       :exit-code errno
                       :command query-command
                       :stdout stdout
                       :stderr stderr))))))))
