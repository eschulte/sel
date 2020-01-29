;;; file.lisp --- mixins for software in files
;;;
;;; file- This mixin should be utilized when preserving
;;;       the original path from which the software object
;;;       was created is required.
;;;
;;; file-w-attributes - This mixin should be utilized
;;;                     when preserving file attributes
;;;                     (e.g. permissions/modification time)
;;;                     in addition to the original path
;;;                     from which the software object was
;;;                     created is required.
;;;
;;; @texi{file}

(defpackage :software-evolution-library/software/file
  (:nicknames :sel/software/file :sel/sw/file)
  (:use :gt/full
        :software-evolution-library)
  #-windows (:import-from :osicat :file-permissions)
  (:export :file
           :file-w-attributes
           :original-path
           :original-directory))
(in-package :software-evolution-library/software/file)


(defclass file ()
  ((original-path
    :initarg :original-path
    :accessor original-path
    :initform nil))
  (:documentation "Mixin class for software where preserving the original
path from which the software was created is required."))

(defgeneric original-directory (obj)
  (:documentation "Return the original directory OBJ was populated from.")
  (:method ((obj file))
    (when (original-path obj)
      (namestring (pathname-directory-pathname (original-path obj))))))

(defmethod from-file :after ((obj file) path)
  "Reading from a file saves PATH."
  (setf (original-path obj) path))

(defmethod copy :around ((obj file) &key)
  "Wrap the copy method to ensure the OBJ's fields are copied."
  (let ((copy (call-next-method)))
    (setf (slot-value copy 'original-path)
          (original-path obj))
    copy))


(defclass file-w-attributes (file)
  ((permissions
    :initarg :permissions
    :accessor permissions
    :initform (list :user-read :user-write))
   (modification-time
    :initarg :modification-time
    :accessor modification-time
    :initform nil)
   (original-genome-string
    :initarg :original-genome-string
    :accessor original-genome-string
    :initform nil))
  (:documentation
   "Mixin class for software where preserving file attributes is required."))

(defun file-modification-time (file)
  "Return FILE's modification time in the form YYYYMMDDHHMM.SS"
  (multiple-value-bind (stdout stderr exit)
      (shell "date +%Y%m%d%H%M.%S -r ~a" file)
    (declare (ignorable stderr))
    (when (zerop exit) (trim-whitespace stdout))))

(defmethod copy :around ((obj file-w-attributes) &key)
  "Wrap the copy method to ensure the OBJ's fields are copied."
  (let ((copy (call-next-method)))
    (with-slots (permissions modification-time original-genome-string) copy
      (setf permissions (permissions obj)
            modification-time (modification-time obj)
            original-genome-string (original-genome-string obj)))
    copy))

(defmethod from-file :before ((obj file-w-attributes) path)
  "Wrapper around the `from-file` method to store the file at PATH's
permissions and modification time when creating OBJ."
  (setf (modification-time obj) (file-modification-time path)
        (permissions obj) (file-permissions path)))

(defmethod from-file :after ((obj file-w-attributes) path)
  "Reading from a file sets ORIGINAL-GENOME-STRING."
  (declare (ignorable path))
  (setf (original-genome-string obj) (genome-string obj)))

(defmethod to-file :after ((obj file-w-attributes) path)
  "Wrapper around the `to-file` method to preserve permissions and
modification time when writing OBJ to PATH."
  (when (modification-time obj)
    (shell "touch -t ~a ~a" (modification-time obj) path))
  (unless (permissions obj)
    (warn "No permissions set for file ~S, using u+rw" obj)
    (setf (permissions obj)
          (list :user-read :user-write)))
  (setf (file-permissions path) (permissions obj)))

(defmethod to-file :around ((obj file-w-attributes) path)
  ;; Copy from original-path unless obj is modified or original-path is invalid
  (if (or (not (equal (original-genome-string obj) (genome-string obj)))
          (not (original-path obj))
          (not (probe-file (original-path obj))))
      (call-next-method)
      (unless (equalp (canonical-pathname (original-path obj))
                      (canonical-pathname path))
        (shell "cp --preserve=all ~a ~a" (original-path obj) path))))
