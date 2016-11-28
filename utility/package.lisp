(defpackage :software-evolution-utility
  (:nicknames :se-utility)
  (:use
   :common-lisp
   :alexandria
   :metabang-bind
   :curry-compose-reader-macros
   :iterate
   :split-sequence
   :trivial-shell
   :cl-ppcre
   :cl-store
   :cl-dot
   :diff)
  (:shadowing-import-from :iterate :iter :for :until :collecting :in)
  (:export
   :infinity
   ;; OS
   :file-to-string
   :file-to-bytes
   :string-to-file
   :bytes-to-file
   :getenv
   :quit
   :current-git-commit
   :*temp-dir*
   :temp-file-name
   :with-temp-file
   :with-temp-file-of
   :with-temp-file-of-bytes
   :with-temp-files
   :ensure-path-is-string
   ;; :from-bytes
   ;; :to-bytes
   :*work-dir*
   :*shell-debug*
   :*shell-error-codes*
   :ignore-shell-error
   :shell-command-failed
   :shell
   :shell-with-input
   :shell-with-env
   :shell-check
   :cp-file
   :write-shell-file
   :read-shell-file
   :*bash-shell*
   :read-shell
   :xz-pipe
   :parse-number
   :parse-numbers
   ;; forensic
   :show-it
   :equal-it
   :count-cons
   ;; simple utility
   :repeatedly
   :indexed
   :different-it
   :plist-get
   :plist-keys
   :plist-drop-if
   :plist-drop
   :plist-merge
   :counts
   :proportional-pick
   :random-bool
   :random-elt-with-decay
   :random-hash-table-key
   :uniform-probability
   :normalize-probabilities
   :cumulative-distribution
   :un-cumulative-distribution
   :random-pick
   :random-subseq
   :apply-replacements
   :peel-bananas
   :replace-all
   :aget
   :alist
   :alist-merge
   :alist-filter
   :getter
   :transpose
   :interleave
   :mapconcat
   :drop
   :drop-while
   :drop-until
   :take
   :take-while
   :take-until
   :pad
   :chunks
   :binary-search
   :<and>
   :<or>
   ;;; Source and binary locations and ranges
   :source-location
   :line
   :column
   :source-range
   :range
   :begin
   :end
   :source-<
   :source-<=
   :source->
   :source->=
   :contains
   :intersects
   :levenshtein-distance
   :unlines
   :keep-lines-after-matching
   :resolve-function-includes
   ;; debugging
   :*note-level*
   :*note-out*
   :replace-stdout-in-note-targets
   :note
   :trace-memory
   :*shell-count*
   ;; diff computing
   :diff-scalar
   ;; gdb functions
   :gdb-disassemble
   :addrs
   :function-lines
   :calculate-addr-map
   ;; oprofile
   :samples-from-oprofile-file
   :samples-from-tracer-file
   ;; iterate helpers
   :concatenating
   ;; Profiling helpers
   :*profile-dot-min-ratio*
   :profile-to-dot-graph
   :profile-to-flame-graph
   ))

#+allegro
(set-dispatch-macro-character #\# #\_
                              #'(lambda (s c n) (declare (ignore s c n)) nil))
