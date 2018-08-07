;;; csurf-asm.lisp --- Support for csurf-generated assembler files
;;;
;;; DOCFIXME Need a page or so introduction to csurf-asm software objects.
;;;
;;; @texi{csurf-asm}
(in-package :software-evolution-library)
(in-readtable :curry-compose-reader-macros)

(define-software csurf-asm (asm-heap)
  ((assembler
    :initarg :assembler :accessor assembler :initform "nasm"
    :documentation "Assembler to use for assembling.")
   (linker
    :initarg :linker :accessor linker :initform "ld"
    :documentation "Linker to use for linking.")
   (flags
    :initarg :flags :accessor flags
    :initform
    '("-m" #+x86-64 "elf_x86_64" #-x86-64 "elf_x86" "-e" "_start" "-lc")
    :documentation "Flags to use for linking")
   (asm-flags
    :initarg :asm-flags :accessor asm-flags
    :initform '("-f" #+x86-64 "elf64" #-x86-64 "elf32" "-Ox")
    :documentation "Flags to pass to assembler.")
   (redirect-file
    :initarg :redirect-file :accessor redirect-file :initform nil
    :documentation "CodeSurfer redirect file to redirect elf copy relocations.")
   (linker-script
    :initarg :linker-script :accessor linker-script :initform nil
    :documentation "CodeSurfer linker script to pin section locations.")
   (weak-symbols
    :initarg :weak-symbols :accessor weak-symbols :initform nil
    :copier :direct
    :documentation "Symbols to weaken with `elf-weaken-gmon-start'.")
   (linked-files
    :initarg :linked-files :accessor linked-files :initform nil
    :documentation "List of additional libraries to link."))
  (:documentation "Software object for ASM generated by CodeSurfer."))

(defvar *dynamic-linker-path*
  ;; Find the dynamic linker by pulling it from an executable on the system.
  #+unix (->> (split-sequence #\Newline
                (shell "ldd ~a" (trim-whitespace (shell "which ls"))))
              (mappend {split-sequence #\space})
              (mapcar #'trim-whitespace)
              (find-if {search "ld-linux"} ))
  #-unix (error "No analog for dynamic linker when not on Linux.")
  "Path to the dynamic linker on this system.")

;;; NOTE: Add the following variables to your path with something like...
;;; (osicat-posix:setenv "PATH" (concatenate 'string (getenv "PATH")
;;;                                          ":/path/to/libswyx/bin"))

(defvar *elf-copy-redirect-path* "elf_copy_redirect"
  "Path to elf_copy_redirect (or just the name if it's on the path).")

(defvar *elf-edit-symtab-path*
  #+x86-64 "elf_edit_symtab64"
  #+(or i386 i686) "elf_edit_symtab32"
  #+(not (or x86-64 i386 i686))
  (warn "Unable to initialize `*elf-edit-symtab-path*'.")
  "Path to elf_edit_symtab64 or 32 (or just the name if it's on the path).")

(defun elf-weaken-gmon-start (elf-objfile symbols)
  "Run elf_edit_symtab on ELF-OBJFILE and each symbol in SYMBOLS.
Reimplementation of CSURF elf:weaken-gmon-start.
* ELF-OBJFILE - an object file
* SYMBOLS - a list of strings representing symbols to mark as weakly required
Return a list of pairs whose first element is a symbol and whose second element
is the error number after running `*elf-edit-symtab-path*' on that symbol.
"
  (let ((cmd-path (namestring *elf-edit-symtab-path*)))
    (iter (for sym in symbols)
          (multiple-value-bind (stdout stderr errno)
              (shell "~a ~a ~a 2" cmd-path elf-objfile sym)
            (declare (ignorable stdout stderr))
            (unless (zerop errno)
              (collect (cons sym errno)))))))

(defun elf-copy-redirect (elf-file redirect-file)
  "Reimplementation of CSURF elf:copy-redirect.
Redirect ELF COPY relocations and associated symbols, for entries
described in redirect-file.  Requires GT_HOME environment variable to be
set."
  (shell "~a -v -s ~a ~a"
         (namestring *elf-copy-redirect-path*)
         redirect-file elf-file))

(defmethod phenome ((asm csurf-asm) &key (bin (temp-file-name)))
  "Assemble and link ASM into binary BIN.
1. Run `assembler' with `asm-flags'. If unsuccessful, return early.
2. If ASM contains `weak-symbols', mark them as weakly required
   (see `elf-weaken-gmon-start').
3. Run `linker' with `flags'.
4. If `redirect-file' is specified, run `elf-copy-redirect'."
  ;; In CSURF-generated asm, mark some symbols, e.g.  __gmon_start__,
  ;; as weakly required.  The first value returned will be the name of
  ;; the binary on success, but may be the name of the object file if
  ;; there is a failure prior to linking.
  (flet ((build-linker-flags (file-ls)
           (iter (for file in file-ls)
                 (if (probe-file file)
                     ;; use file path if available
                     (collecting file)
                     ;; otherwise use -l
                     (progn
                       (collecting "-l")
                       (if (starts-with-subseq
                            "lib"
                            (pathname-name file))
                           ;; drop suffix and lib: libc -> -lc
                           (collecting
                            (subseq (pathname-file file) 3))
                           ;; non-standard name, use :name
                           (collecting (format nil ":~a"
                                               (file-namestring file)))))))))
    (with-temp-file-of (src "s") (genome-string asm)
      (with-temp-file (obj)
        ;; Assemble.
        (multiple-value-bind (stdout stderr errno)
            (shell "~a -o ~a ~a ~{~a~^ ~}"
                   (assembler asm) obj src (asm-flags asm))
          (if (not (zerop errno))
              (values obj errno stderr stdout src)
              ;; Mark __gmon_start__ et al. as weakly required.
              (if (elf-weaken-gmon-start obj (weak-symbols asm))
                  ;; Errors in `elf-weaken-gmon-start'.
                  (values obj (max errno 1) stderr stdout src)
                  ;; Link.
                  (multiple-value-bind (stdout stderr errno)
                      (shell
                       "~a -o ~a ~a ~{~a~^ ~}"
                       (or (linker asm) *asm-linker*)
                       bin obj
                       (append (flags asm)
                               (when (linker-script asm)
                                 (list "-T" (linker-script asm)))
                               (when (linked-files asm)
                                 (build-linker-flags (linked-files asm)))
                               (list "--dynamic-linker"
                                     *dynamic-linker-path*)))
                    (cond
                      ((not (zerop errno)) ; Errors linking
                       (values bin (max errno 1) stderr stdout src))
                      ((not (redirect-file asm)) ; Link success, no redirect
                       (values bin errno stderr stdout src))
                      (t (multiple-value-bind (stdout stderr errno)
                             ;; Link successful, handle redirect
                             (elf-copy-redirect bin (redirect-file asm))
                           (values bin errno stderr stdout src))))))))))))


;; Parsing csurf output (for asm/linker flags, weak symbols, redirects)
(defun parse-and-apply-command (csurf-asm bracket-cmd)
  "Parse BRACKET-CMD to update fields of CSURF-ASM software object.
Currently only populates the `weak-symbols' field from the log."
  ;; Trim brackets.
  (flet ((is-program-cmd (program cmd)
           ;; Check if the command CMD is invoking program PROGRAM.
           ;; CMD is a list of strings representing a command. Check
           ;; if the first element ends with the string PROGRAM (to
           ;; allow for qualified paths).
           (and program (ends-with-subseq program (first cmd) :test #'equal)))
         (extract-linker-flags
             (cmd &aux (linker-flags-to-keep
                        (cons "-z"
                              (when (linker-script csurf-asm)
                                '("-Ttext" "-Tbss" "-Tdata"
                                  "-Trodata-segment"
                                  "-Tldata-segment")))))
           ;; Return a list of the flags for a linker command from
           ;; CMD.  CMD is a list of strings representing a command.
           ;; Remove the first element which is the program name.
           ;; Keep only flags listed in `linker-flags-to-keep'.

           ;; Use cdr to remove linker program name.
           (iter (for str in (cdr cmd))
                 (for i upfrom 0)
                 (with prev-str = (car cmd))
                 ;; Keep if the element is in the whitelist of keep-able flags.
                 (when (or
                        ;; Space between flag and param.
                        (member prev-str linker-flags-to-keep :test #'equal)
                        ;; Flag with no space before param.
                        (some {starts-with-subseq _ str} linker-flags-to-keep))
                   (collect str into extract-flags))
                 (setf prev-str str)
                 (finally (return extract-flags))))
         ;; Collect linked libraries
         (extract-linked-files (cmd)
           (iter (for str in (cdr cmd))
                 (for i upfrom 0)
                 (with prev-str = (car cmd))
                 ;; Current arg is a path: it starts with /, is a file, and
                 ;; isn't a flag param (i.e., prev-str isn't a single dash flag)
                 (when (and (starts-with-subseq "/" str)
                            (file-exists-p str)
                            (not (equal "--dynamic-linker" prev-str))
                            (or (starts-with-subseq "--" prev-str)
                                (not (starts-with-subseq "-" prev-str))))
                   (collect str into files-to-link))
                 (setf prev-str str)
                 (finally (return files-to-link)))))
    (let ((cmd (->> (subseq bracket-cmd 1 (1- (length bracket-cmd)))
                    (split "\\s+"))))
      (cond
        ;; NOTE: Disabled as the defaults above are generally better for now.
        ;; Assembler command.
        ;; ((is-program-cmd (assembler csurf-asm) cmd)
        ;;  (setf (asm-flags csurf-asm)
        ;;        ;; Remove first argument (program name) and last (file name).
        ;;        (butlast (cdr cmd))))
        ;; Mark symbols weakly required.
        ((is-program-cmd *elf-edit-symtab-path* cmd)
         (setf (weak-symbols csurf-asm)
               ;; Symbol is the second to last argument in elf_edit_symtab.
               (adjoin (lastcar (butlast cmd))
                       (weak-symbols csurf-asm)
                       :test #'equal)))
        ;; Linker cmd.
        ((is-program-cmd (linker csurf-asm) cmd)
         ;; keep defaults, append additional flags from log file
         (appendf (flags csurf-asm)
                  (extract-linker-flags cmd))
         (appendf (linked-files csurf-asm)
                  (extract-linked-files cmd)))
        ;; Elf copy redirect file.
        ;; ((is-program-cmd *elf-copy-redirect-path* cmd)
        ;;  (setf (redirect-file csurf-asm)
        ;;        (lastcar (butlast cmd))))
        ;; Some other command.
        (t nil)))))

(defmethod apply-config ((obj csurf-asm) log-file)
  "Parse LOG-FILE to update fields of CSURF-ASM software object."
  (when (probe-file log-file)
    (with-open-file (in (probe-file log-file))
      (iter (for line = (ignore-errors (read-line in)))
            (while line)
            (multiple-value-bind (is-cmd bracket-cmd)
                (starts-with-subseq "#[subr system]" line :return-suffix t)
              (when is-cmd
                (parse-and-apply-command obj bracket-cmd))))))
  obj)
