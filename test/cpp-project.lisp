;;;; cpp-project.lisp --- Project tests.
(defpackage :software-evolution-library/test/cpp-project
  (:nicknames :sel/test/cpp-project)
  (:use
   :gt/full
   #+gt :testbot
   :software-evolution-library/test/util
   :stefil+
   :functional-trees/attrs
   :software-evolution-library
   :software-evolution-library/software/simple
   :software-evolution-library/software/compilable
   :software-evolution-library/software/tree-sitter
   :software-evolution-library/software/parseable
   :software-evolution-library/software/project
   :software-evolution-library/software/c-cpp-project
   :software-evolution-library/software/cpp-project)
  #-windows (:shadowing-import-from :osicat
                                    :file-permissions :pathname-as-directory)
  (:export :test-cpp-project))
(in-package :software-evolution-library/test/cpp-project)
(in-readtable :curry-compose-reader-macros)

(defun cpp-available-p ()
  "Returns true if the c tree-sitter parser is loaded."
  (let* ((p (find-package :sel/sw/tree-sitter))
         (s (and p (find-symbol "CPP" p))))
    (and s (find-class s))))

(defsuite test-cpp-project
    "CPP project representation."
  (cpp-available-p))

(defvar *s1*)
(defvar *s2*)
(defixture cpp-project
  (:setup
   (setf *s1* (make-instance 'simple))
   (setf (lines *s1*) (list "s1-genome"))
   (setf *s2* (make-instance 'simple))
   (setf (lines *s2*) (list "s2-genome"))
   (setf *project* (make-instance 'cpp-project
                     :evolve-files `(("s1" . ,*s1*)
                                     ("s2" . ,*s2*)))))
  (:teardown (setf *project* nil)))

(defixture multiple-artifacts-project
  (:setup
   (setf *project*
         (from-file
          (make-instance 'cpp-project
            :build-command "make"
            :artifacts (list "run_shared"
                             "shared.so.link"
                             "nested-dir/helper"))
          (make-pathname :directory +multiple-artifact-dir+))))
  (:teardown (setf *project* nil)))

(defixture cpp-sample-project
  (:setup
   (setf *project*
         (from-file
          (make-instance 'cpp-project
            :build-command "make"
            :artifacts '("sample")
            :compiler "g++"
            :flags "-v")
          (make-pathname :directory +cpp-sample-dir+))
         *mutation-stats* (make-hash-table :test 'equal)))
  (:teardown (setf *project* nil
                   *mutation-stats* nil)))

(defixture cpp-symbol-table-project
  (:setup
   (setf *project*
         (from-file 'cpp-project
                    (make-pathname
                     :directory (append1 +etc-dir+
                                         "cpp-symbol-table-project")))))
  (:teardown (setf *project* nil)))

(defixture cpp-relative-include-symbol-table-project
    (:setup
     (setf *project*
           (from-file 'cpp-project
                      (make-pathname
                       :directory (append1 +etc-dir+
                                           "cpp-symbol-table-project2")))))
  (:teardown (setf *project* nil)))

(defixture cpp-symbol-table-project3
    (:setup
     (setf *project*
           (from-file 'cpp-project
                      (make-pathname
                       :directory (append1 +etc-dir+
                                           "cpp-symbol-table-project3")))))
  (:teardown (setf *project* nil)))

(defmethod test-method ((obj simple) value)
  value)

(deftest to-file-fails-with-nil-path ()
  (with-fixture cpp-project
    (signals error (to-file *project* nil))))

(deftest simple-to-from-file-without-project-dir-works ()
  (with-fixture cpp-project
    (setf (project-dir *project*) nil)
    (with-temporary-directory (:pathname dir)
      (progn
        (to-file *project* dir)
        (is (member :user-read (file-permissions dir)))
        (is (member :user-write (file-permissions dir)))
        (let ((s1-2 (from-file (make-instance 'simple)
                               (make-pathname :name "s1"
                                              :directory dir)))
              (s2-2 (from-file (make-instance 'simple)
                               (make-pathname :name "s2"
                                              :directory dir))))
          (is (equalp (genome *s1*) (genome s1-2)))
          (is (equalp (genome *s2*) (genome s2-2))))))))

(deftest cpp-project-test ()
  (with-fixture cpp-sample-project
    (is (equal "make" (build-command *project*)))
    (is (equalp '("sample") (artifacts *project*)))
    (is (equal 3 (length (evolve-files *project*))))
    (is (member "src/sample.cc" (evolve-files *project*)
                :test 'equal :key 'car))
    (is (equal "g++"
               (compiler (cdar (member "src/sample.cc" (evolve-files *project*)
                                       :test 'equal :key 'car)))))
    (is (equal "-v"
               (flags (cdar (member "src/sample.cc" (evolve-files *project*)
                                       :test 'equal :key 'car)))))
    (is (equal (namestring (make-pathname :directory +cpp-sample-dir+))
               (namestring (project-dir *project*))))
    (is (equal (compiler *project*) "g++"))
    (is (equal (flags *project*) "-v"))))

(deftest cpp-project-can-build ()
  (with-fixture cpp-sample-project
    (is (phenome *project*))))

(deftest test-cpp-function-declaration-enclosing ()
  (let ((cpp (from-string 'cpp-project (fmt "~
boost::property_tree::ptree
make_config(const std::string& path_prefix,
            const std::unordered_map<std::string, std::string>& overrides = {},
            const std::unordered_set<std::string>& removes = {});~%"))))
    (with-attr-table cpp
      (find-enclosing-declaration 'function-declaration-ast
                                  cpp
                                  (stmt-with-text cpp "make_config")))))


;;; Symbol Table
(deftest cpp-project-symbol-table-1 ()
  "Every included system file has its namespace qualified symbols
imported into the symbol table of the file including it."
  (labels ((lookup-variable (symbol-table name)
             (lookup (lookup symbol-table :variable) name))
           (test-main.cc ()
             "Test that a symbol from stdio.h is in the symbol table in main.c."
             (let* ((software (aget "main.cc" (evolve-files *project*)
                                    :test #'equal))
                    (target-ast (find-if (of-type 'cpp-preproc-include)
                                         (genome software)))
                    (return-ast (find-if (of-type 'cpp-return-statement)
                                         (genome software)))
                    (system-header
                      (find-if (op (equal (header-name _) "iostream"))
                               (system-headers (genome *project*))))
                    (target-symbol-table (symbol-table target-ast))
                    (return-symbol-table (symbol-table return-ast)))
               (is (lookup-variable target-symbol-table "std::cout"))
               (is (lookup-variable return-symbol-table "std::cout"))
               (is (find-if (op (eq (car (lookup-variable target-symbol-table
                                                          "std::cout"))
                                    _))
                            system-header)))))
    (with-fixture cpp-symbol-table-project
      (with-attr-table *project*
        (test-main.cc)))))

(deftest cpp-project-symbol-table-2 ()
  "Locally included header files have their symbols imported into the
symbol table of the file including it."
  (labels ((lookup-type (symbol-table name)
             (lookup (lookup symbol-table :type) name)))
    (with-fixture cpp-relative-include-symbol-table-project
      (with-attr-table *project*
        (let* ((software (aget "my_program.cc" (evolve-files *project*)
                               :test #'equal))
               (target-ast (find-if (of-type 'cpp-preproc-include)
                                    (genome software)))
               (return-ast (find-if (of-type 'cpp-return-statement)
                                    (genome software)))
               (target-symbol-table (symbol-table target-ast))
               (return-symbol-table (symbol-table return-ast)))
          (is (lookup-type target-symbol-table "N::my_class"))
          (is (lookup-type return-symbol-table "N::my_class")))))))

(deftest cpp-project-symbol-table-3 ()
  "Check that we handle the case where a header is added that was not
present when the project was created."
  (with-fixture cpp-symbol-table-project3
    (let* ((main (aget "main.cc" (evolve-files *project*)
                       :test #'equal))
           (genome (genome main))
           (include (is (find-if (of-type 'cpp-system-lib-string) genome)))
           (new-genome
            (with genome include (copy include :text "<vector>")))
           (new-genome
            (mapcar (hash-table-function
                     (maphash-into
                      (make-hash-table)
                      (lambda (ast)
                        (if (source-text= ast "list")
                            (values ast (copy ast :text "vector"))
                            (values ast ast)))
                      (convert 'list genome)))
                    new-genome))
           (new-project
            (with *project* genome new-genome)))
      (with-attr-table new-project
        (get-declaration-ids
         :function
         (find-if (of-type 'cpp-field-expression)
                  new-genome))))))
