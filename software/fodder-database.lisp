;;;  Interface for all fodder database implementations.

(in-package :software-evolution)

(defclass fodder-database () ())

(defgeneric size (database)
  (:documentation "Return the number of elements in the database."))

(defgeneric find-snippets (database &key classes full-stmt limit)
  (:documentation "Find snippets in the fodder database DATABASE.

:CLASSES --- AST class all snippets should match
:FULL-STMT - Limit results to full statements if non-nil.
:LIMIT ----- Limit to N randomly drawn snippets"))

(defgeneric find-types (type-database &key hash)
  (:documentation "Find the types in the type database (optionally)
matching the keyword parameter HASH"))

(defgeneric weighted-pick
    (database predicate weight
     &key target key limit classes filter limit-considered)
  ;; NOTE: This function is largely only present so that classes like
  ;;       MONGO-MIDDLE-FODDER-DATABASE can provide optimized access
  ;;       to single results for sorted queries without having to
  ;;       retrieve and return all of the documents in the sorted
  ;;       results.
  (:documentation
   "Perform a random pick weighted by weight from `sorted-snippets'.
All other arguments are passed through to sorted snippets."))

(defmethod weighted-pick ((obj fodder-database) predicate weight
                          &key target key limit classes filter
                            (limit-considered infinity))
  (random-elt-with-decay
   (sorted-snippets obj predicate
                    :target target :key key :limit limit :classes classes
                    :filter filter :limit-considered limit-considered)
   weight))

(defgeneric sorted-snippets
    (database predicate
     &key target key limit classes limit-considered filter)
  (:documentation
   "Return snippets from DATABASE sorted by PREDICATE.

:TARGET ----------- specify the TARGET for a comparison based predicate
                    (this may be used to identify cached comparison results)
:KEY -------------- a function called on each snippet before predicate
:LIMIT ------------ only return the MANY most similar snippets
:CLASSES ---------- only consider snippets matching these AST classes
:LIMIT-CONSIDERED - limit search to MANY-CONSIDERED random snippets
:FILTER ----------- limit search to snippets for which FILTER returns false"))

(defmethod sorted-snippets ((db fodder-database) predicate
                            &key target key classes limit filter
                              (limit-considered infinity))
  (declare (ignorable target))
  (let ((fodder (find-snippets
                 db :classes classes :full-stmt (not classes) :limit limit)))
    (if (< limit-considered (length fodder))
        (let ((start (random (- (length fodder) limit-considered))))
          (sorted-snippets-unmemoized
           (subseq fodder start (+ start limit-considered))
           predicate :limit limit :key key :filter filter))
        (sorted-snippets-memoized fodder predicate
                                  :limit limit :key key :filter filter))))

(defun-memoized sorted-snippets-memoized
    (fodder predicate &key limit key filter)
  (let ((base (apply #'sort 
                     (if filter (remove-if filter fodder) fodder)
                     predicate
                     (if key (list :key key) '()))))
    (if limit (take limit base) base)))

(defun sorted-snippets-unmemoized (fodder predicate &key limit key filter)
  (let ((base (apply #'sort
                     (if filter (remove-if filter fodder) fodder)
                     predicate
                     (if key (list :key key) '()))))
    (if limit (take limit base) base)))
