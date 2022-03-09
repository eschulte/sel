;;; directory.lisp --- Functional Tree representation of a directory of software
(defpackage :software-evolution-library/software/directory
  (:nicknames :sel/software/directory :sel/sw/directory)
  (:use :gt/full
        :software-evolution-library
        :software-evolution-library/command-line
        :software-evolution-library/software/simple
        :software-evolution-library/software/tree-sitter
        :software-evolution-library/software/project
        :software-evolution-library/software/parseable)
  (:export :file-ast
           :directory-ast
           :directory-project
           :name
           :entries
           :contents
           :get-path
           :evolve-files
           :other-files
           :ignore-paths
           :only-paths
           :ignore-other-paths
           :only-other-paths
           :all-files
           :pick-file))
(in-package :software-evolution-library/software/directory)
(in-readtable :curry-compose-reader-macros)

(define-software directory-project (project parseable) ()
  (:documentation "A directory of files and software.
- Genome (from parseable) holds the directory structure.
  By inheriting from parseable we get support for the many common
  lisp sequence functions which map over the genomes of parseable
  objects.

- evolve-files and other-files (from project) hold software objects"))
(eval-always
 (defclass directory-or-file-ast (functional-tree-ast)
   ((name :accessor name :initarg :name :type string
          :documentation "Name of the directory"))
   (:documentation "Node to hold a directory or a file.")))

(define-node-class directory-ast (directory-or-file-ast)
  ((entries :accessor entries :initarg :entries :initform nil :type list
            :documentation "Entries (children) of the directory.")
   (child-slots :initform '(entries) :allocation :class))
  (:documentation "FT Node to hold a directory entry."))

(define-node-class file-ast (directory-or-file-ast)
  ((contents :accessor contents :initarg :contents :initform nil :type list
             :documentation "Contents of the file.")
   (child-slots :initform '(contents) :allocation :class))
  (:documentation "FT Node to hold a directory entry."))

(defmethod print-object ((obj directory-or-file-ast) stream)
  (if *print-readably*
      (call-next-method)
      (print-unreadable-object (obj stream :type t)
        (format stream "~a~@[ ~a~]"
                (serial-number obj)
                (name obj)))))

(defun pathname-to-list (path)
  (check-type path pathname)
  (let ((filename (when (pathname-name path)
                    (if (pathname-type path)
                        (string-join (list (pathname-name path) (pathname-type path)) ".")
                        (pathname-name path)))))
    (values (append (cdr (pathname-directory path)) (list filename))
            filename)))

(defgeneric ensure-path (directory path)
  (:documentation "Ensure that PATH exists under DIRECTORY.")
  (:method ((file file-ast) (path list))
    (assert (emptyp path)))
  (:method ((dir directory-ast) (path list))
    (when (emptyp path) (return-from ensure-path dir))
    (if-let ((subdir (find-if (op (string= (car path) (name _1))) (entries dir))))
      (ensure-path subdir (cdr path))
      (progn (push (make-instance 'directory-ast :name (car path)) (entries dir))
             (ensure-path dir path))))
  (:method (dir (path pathname))
    (multiple-value-bind (directory-list filename) (pathname-to-list path)
      (ensure-path dir (butlast directory-list))
      (pushnew (make-instance 'file-ast :name filename)
               (entries (@ dir (butlast directory-list))))
      dir))
  (:method (dir (path string))
    (ensure-path dir (pathname path))))

(defgeneric get-path (directory path)
  (:documentation "Return the contents of PATH under DIRECTORY.")
  (:method ((file file-ast) (path list))
    (when (emptyp path) file))
  (:method ((dir directory-ast) (path list))
    (when (emptyp path) (return-from get-path dir))
    (if-let ((subdir (find-if (op (string= (car path) (name _1))) dir)))
      (get-path subdir (cdr path))
      (error "path ~a not found in directory ~a" path (name dir))))
  (:method (dir (path pathname))
    (get-path dir (pathname-to-list path)))
  (:method (dir (path string))
    (get-path dir (pathname path))))

(defgeneric filepath-to-treepath (directory filepath)
  (:documentation "Ensure that PATH exists under DIRECTORY.")
  (:method ((dir directory-or-file-ast) (path list))
    (when (emptyp path) (return-from filepath-to-treepath nil))
    (if-let ((index (position-if (op (string= (car path) (name _1))) (entries dir))))
      (cons index (filepath-to-treepath (get-path dir (list (car path))) (cdr path)))
      (error "subdirectory ~a not found in directory ~a" path (name dir))))
  (:method (dir (path pathname))
    (filepath-to-treepath dir (pathname-to-list path)))
  (:method (dir (path string))
    (filepath-to-treepath dir (pathname path))))

(defgeneric (setf get-path) (new directory path)
  (:documentation "Save NEW into PATH under DIRECTORY.")
  (:method (new (obj directory-ast) (path list))
    (econd
     ((every #'stringp path)
      (setf (@ obj (filepath-to-treepath obj path)) new))
     ((every #'integerp path)
      (setf (@ obj path) new))))
  (:method (new (obj directory-ast) (path pathname))
    (setf (get-path obj (pathname-to-list path)) new))
  (:method (new (obj directory-ast) (path string))
    (setf (get-path obj (pathname path)) new)))

(defmethod (setf genome) (new (obj directory-project))
  (setf (slot-value obj 'genome) new))

(defmethod from-file ((obj directory-project) path)
  (assert (probe-file path) (path) "~a does not exist." path)
  (setf (project-dir obj) (canonical-pathname (truename path))
        (genome obj) (make-instance 'directory-ast
                                    :name (lastcar (pathname-directory (project-dir obj))))
        (evolve-files obj) (collect-evolve-files obj)
        (other-files obj) (collect-other-files obj))
  obj)

(defmethod collect-evolve-files :around ((obj directory-project))
  (let ((evolve-files (call-next-method)))
    (dolist (pair evolve-files evolve-files)
      (destructuring-bind (path . software-object) pair
        (ensure-path (genome obj) path)
        (setf (contents (get-path (genome obj) path))
              (list (genome software-object)))))))

(defmethod collect-evolve-files ((obj directory-project) &aux result)
  (walk-directory (project-dir obj)
                  (op (let ((language (guess-language _1)))
                        (push (cons (pathname-relativize (project-dir obj) _1)
                                    (from-file (make-instance (if (find-class-safe language)
                                                                  language
                                                                  'simple))
                                               _1))
                              result)))
                  :test (op (and (text-file-p _1)
                                 (not (nest
                                       (ignored-evolve-path-p obj)
                                       (pathname-relativize (project-dir obj) _1))))))
  result)

;;; Override project-specific defmethods that leverage evolve-files
;;; and instead implement these directly against the genome.

(defmethod lookup ((obj directory-project) key)
  ;; Enables the use of the `@' macro directly against projects.
  (lookup (genome obj) key))

(defmethod lookup ((obj directory-ast) (key string))
  ;; Enables the use of the `@' macro directly against projects.
  (find-if (op (string= key (name _))) (entries obj)))

(defmethod mapc (function (obj directory-project) &rest more)
  (apply 'mapc function (genome obj) more))

(defmethod mapcar (function (obj directory-project) &rest more)
  (apply 'mapcar function (genome obj) more))

(defmethod convert ((to-type (eql 'list)) (obj directory-project) &rest more)
  (apply 'convert to-type (genome obj) more))