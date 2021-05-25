(in-package #:cc-bir-to-bmir)

(defun replace-typeq (typeq)
  (let ((ts (bir:test-ctype typeq)))
    ;; Undo some parsing. KLUDGE.
    (cond
      ;; FIXNUM
      ((equal ts '(integer #.most-negative-fixnum #.most-positive-fixnum))
       (setf ts 'fixnum))
      ;; bignum
      ((equal ts '(or (integer * (#.most-negative-fixnum))
                   (integer (#.most-positive-fixnum) *)))
       (setf ts 'bignum))
      ;; simple-bit-array becomes (simple-array bit (*)), etc.
      ((and (consp ts) (eq (car ts) 'simple-array))
       (setf ts (core::simple-vector-type (second ts))))
      ;; simple-string
      ((or (equal ts '(or (simple-array base-char (*))
                       (simple-array character (*))))
           (equal ts '(or (simple-array character (*))
                       (simple-array base-char (*)))))
       (setf ts 'simple-string))
      ((and (consp ts) (eq (car ts) 'function))
       ;; We should check that this does not specialize, because
       ;; obviously we can't check that.
       (setf ts 'function)))
    (case ts
      ((fixnum) (change-class typeq 'cc-bmir:fixnump))
      ((cons) (change-class typeq 'cc-bmir:consp))
      ((character) (change-class typeq 'cc-bmir:characterp))
      ((single-float) (change-class typeq 'cc-bmir:single-float-p))
      ((core:general) (change-class typeq 'cc-bmir:generalp))
      (t (let ((header-info (gethash ts core:+type-header-value-map+)))
           (cond (header-info
                  (check-type header-info (or integer cons)) ; sanity check
                  (change-class typeq 'cc-bmir:headerq :info header-info))
                 (t (error "BUG: Typeq for unknown type: ~a" ts))))))))

(defun reduce-local-typeqs (function)
  (bir:map-iblocks
   (lambda (ib)
     (let ((term (bir:end ib)))
       (when (typep term 'bir:ifi)
         (let ((test-out (bir:input term)))
           (when (typep test-out 'bir:output)
             (let ((test (bir:definition test-out)))
               (when (typep test 'bir:typeq-test)
                 (replace-typeq test))))))))
   function))

(defun reduce-module-typeqs (module)
  (cleavir-bir:map-functions #'reduce-local-typeqs module))

(defun maybe-replace-primop (primop)
  (case (cleavir-primop-info:name (bir:info primop))
    ((cleavir-primop:car)
     (let ((in (bir:inputs primop))
           (nout (make-instance 'bir:output)))
       (change-class primop 'cc-bmir:load :inputs ())
       (let ((mr (make-instance 'cc-bmir:memref2
                   :inputs in :outputs (list nout)
                   :offset (- cmp:+cons-car-offset+ cmp:+cons-tag+))))
         (bir:insert-instruction-before mr primop)
         (setf (bir:inputs primop) (list nout)))))
    ((cleavir-primop:cdr)
     (let ((in (bir:inputs primop))
           (nout (make-instance 'bir:output)))
       (change-class primop 'cc-bmir:load :inputs ())
       (let ((mr (make-instance 'cc-bmir:memref2
                   :inputs in :outputs (list nout)
                   :offset (- cmp:+cons-cdr-offset+ cmp:+cons-tag+))))
         (bir:insert-instruction-before mr primop)
         (setf (bir:inputs primop) (list nout)))))
    ((cleavir-primop:rplaca)
     (let ((in (bir:inputs primop))
           (nout (make-instance 'bir:output)))
       (change-class primop 'cc-bmir:store :inputs ())
       (let ((mr (make-instance 'cc-bmir:memref2
                   :inputs (list (first in)) :outputs (list nout)
                   :offset (- cmp:+cons-car-offset+ cmp:+cons-tag+))))
         (bir:insert-instruction-before mr primop)
         (setf (bir:inputs primop) (list (second in) nout)))))
    ((cleavir-primop:rplacd)
     (let ((in (bir:inputs primop))
           (nout (make-instance 'bir:output)))
       (change-class primop 'cc-bmir:store :inputs ())
       (let ((mr (make-instance 'cc-bmir:memref2
                   :inputs (list (first in)) :outputs (list nout)
                   :offset (- cmp:+cons-cdr-offset+ cmp:+cons-tag+))))
         (bir:insert-instruction-before mr primop)
         (setf (bir:inputs primop) (list (second in) nout)))))))

(defun reduce-primops (function)
  (bir:map-local-instructions
   (lambda (i)
     (when (typep i 'bir:primop)
       (maybe-replace-primop i)))
   function))

(defun reduce-module-primops (module)
  (cleavir-set:mapset nil #'reduce-primops (bir:functions module)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Representation types ("rtypes")
;;;
;;; An rtype describes how a value or values is represented in the runtime.
;;; An rtype is either :multiple-values, meaning several T_O*s stored in the
;;; thread local multiple values vector, or a list of value rtypes; and a value
;;; rtype can only be :object meaning T_O*. So e.g. (:object :object) means a
;;; pair of T_O*. In the future there will probably be rtypes for unboxed
;;; values as well as fixed numbers of values.

;; Given an instruction, determine what rtype it outputs.
(defgeneric definition-rtype (instruction))
;; usually correct default
(defmethod definition-rtype ((inst bir:instruction)) '(:object))
(defmethod definition-rtype ((inst bir:abstract-call)) :multiple-values)
(defmethod definition-rtype ((inst bir:values-save))
  (let ((input (bir:input inst)))
    (maybe-assign-rtype input)
    (cc-bmir:rtype input)))
(defmethod definition-rtype ((inst bir:values-collect))
  (if (= (length (bir:inputs inst)) 1)
      (let ((input (first (bir:inputs inst))))
        (maybe-assign-rtype input)
        (cc-bmir:rtype input))
      :multiple-values))
(defmethod definition-rtype ((inst cc-bir:mv-foreign-call)) :multiple-values)
(defmethod definition-rtype ((inst cc-bmir:local-call-arguments))
  (make-list (multiple-value-bind (req opt rest)
                 (cmp::process-cleavir-lambda-list
                  (bir:lambda-list (bir:callee inst)))
               (+ (car req) (* 2 (car opt)) (if rest 1 0)))
             :initial-element :object))
(defmethod definition-rtype ((inst bir:thei))
  ;; THEI really throws a wrench in some stuff.
  (let ((input (first (bir:inputs inst))))
    (maybe-assign-rtype input)
    (cc-bmir:rtype input)))
(defmethod definition-rtype ((inst bir:fixed-to-multiple))
  (make-list (length (bir:inputs inst)) :initial-element :object))

;;; Given a datum, determine what rtype its use requires.
(defgeneric use-rtype (datum))
;; Given a user (instruction) and a datum, determine the rtype required.
(defgeneric %use-rtype (instruction datum))
(defmethod %use-rtype ((inst bir:instruction) (datum bir:datum))
  ;; Having this as a default is mildly dicey but should work: instructions
  ;; that need multiple value inputs are a definite minority.
  '(:object))
(defmethod %use-rtype ((inst bir:mv-call) (datum bir:datum))
  (if (member datum (rest (bir:inputs inst)))
      :multiple-values '(:object)))
(defmethod %use-rtype ((inst bir:mv-local-call) (datum bir:datum))
  (if (member datum (rest (bir:inputs inst)))
      :multiple-values '(:object)))
(defmethod %use-rtype ((inst cc-bmir:local-call-arguments) (datum bir:datum))
  :multiple-values)
(defmethod %use-rtype ((inst cc-bmir:real-mv-local-call) (datum bir:datum))
  (if (member datum (rest (bir:inputs inst)))
      (make-list (multiple-value-bind (req opt rest)
                     (cmp::process-cleavir-lambda-list
                      (bir:lambda-list (bir:callee inst)))
                   (+ (car req) (* 2 (car opt)) (if rest 1 0)))
                 :initial-element :object)
      '(:object)))
(defmethod %use-rtype ((inst cc-bmir:fake-mv-local-call) (datum bir:datum))
  (if (member datum (rest (bir:inputs inst)))
      :multiple-values '(:object)))
(defmethod %use-rtype ((inst bir:returni) (datum bir:datum)) :multiple-values)
(defmethod %use-rtype ((inst bir:values-save) (datum bir:datum))
  (use-rtype (bir:output inst)))
(defmethod %use-rtype ((inst bir:values-collect) (datum bir:datum))
  (if (= (length (bir:inputs inst)) 1)
      (use-rtype (bir:output inst))
      :multiple-values))
(defmethod %use-rtype ((inst bir:unwind) (datum bir:datum))
  (error "BUG: transitive-rtype should make this impossible!"))
(defmethod %use-rtype ((inst bir:jump) (datum bir:datum))
  (error "BUG: transitive-rtype should make this impossible!"))
(defmethod %use-rtype ((inst bir:thei) (datum bir:datum))
  ;; actual type tests, which need multiple values, should have been turned
  ;; into mv calls by this point. but out of an abundance of caution,
  (if (symbolp (bir:type-check-function inst))
      (use-rtype (first (bir:outputs inst)))
      :multiple-values))
             
;; Determine the rtype a datum needs to end up as by chasing transitive use.
(defun transitive-rtype (datum)
  (loop (let ((use (bir:use datum)))
          (etypecase use
            (null (return '())) ; don't need any value at all
            ((or bir:jump bir:unwind)
             (setf datum (nth (position datum (bir:inputs use))
                              (bir:outputs use))))
            (bir:instruction (return (%use-rtype use datum)))))))
(defmethod use-rtype ((datum bir:phi)) (transitive-rtype datum))
(defmethod use-rtype ((datum bir:output)) (transitive-rtype datum))
(defmethod use-rtype ((datum bir:argument)) (transitive-rtype datum))

;;; Given two value rtypes, return the most preferable.
;;; Only :object is valid right now, so this does nothing.
(defun min-vrtype (vrt1 vrt2)
  (declare (ignore vrt1 vrt2))
  :object)

(defun max-vrtype (vrt1 vrt2)
  (declare (ignore vrt1 vrt2))
  :object)

;;; Given two rtypes, return the most preferable rtype.
(defun min-rtype (rt1 rt2)
  (cond ((listp rt1)
         (cond ((listp rt2)
                ;; Shorten
                (mapcar #'min-vrtype rt1 rt2))
               (t
                (assert (member rt2 '(:multiple-values)))
                rt1)))
        ((eq rt1 :multiple-values) rt2)
        (t (error "Bad rtype: ~a" rt1))))

(defun assign-output-rtype (datum)
  (let* ((source (definition-rtype (bir:definition datum)))
         (dest (use-rtype datum))
         (rtype (min-rtype source dest)))
    (change-class datum 'cc-bmir:output :rtype rtype)
    rtype))

(defun phi-rtype (datum)
  ;; PHIs are trickier. If the destination is single-value, the phi can be too.
  ;; If not, then the phi could still be single-value, but only if EVERY
  ;; definition is, and otherwise we need to use multiple values.
  (let ((rt :any) (dest (use-rtype datum)))
    (if (eq dest :multiple-values)
        ;; If the phi definitions are all non-mv and agree on a number of
        ;; values, that works.
        (cleavir-set:doset (def (bir:definitions datum) rt)
          (etypecase def
            ((or bir:jump bir:unwind)
             (let ((in (nth (position datum (bir:outputs def))
                            (bir:inputs def))))
               (maybe-assign-rtype in)
               (let ((irt (cc-bmir:rtype in)))
                 (cond ((eq irt :multiple-values) (return irt)) ; nothing for it
                       ((eq rt :any) (setf rt irt))
                       ((= (length rt) (length irt))
                        (setf rt (mapcar #'max-vrtype rt irt)))
                       ;; different value counts
                       (t (return :multiple-values))))))))
        ;; Destination only needs some fixed thing - do that
        dest)))

(defun assign-phi-rtype (datum)
  (change-class datum 'cc-bmir:phi :rtype (phi-rtype datum)))

(defgeneric maybe-assign-rtype (datum))
(defmethod maybe-assign-rtype ((datum cc-bmir:output)))
(defmethod maybe-assign-rtype ((datum cc-bmir:phi)))
(defmethod maybe-assign-rtype ((datum bir:variable)))
(defmethod maybe-assign-rtype ((datum bir:argument)))
(defmethod maybe-assign-rtype ((datum bir:load-time-value)))
(defmethod maybe-assign-rtype ((datum bir:constant)))
(defmethod maybe-assign-rtype ((datum bir:output))
  (assign-output-rtype datum))
(defmethod maybe-assign-rtype ((datum bir:phi))
  (assign-phi-rtype datum))

(defun assign-instruction-rtypes (inst)
  (mapc #'maybe-assign-rtype (bir:outputs inst)))

(defun assign-function-rtypes (function)
  (bir:map-local-instructions #'assign-instruction-rtypes function))

(defun assign-module-rtypes (module)
  (bir:map-functions #'assign-function-rtypes module))

(defun insert-mtf (after datum)
  (let* ((fx (make-instance 'cc-bmir:output :rtype '(:object)
                            :derived-type (bir:ctype datum)))
         (mtf (make-instance 'cc-bmir:mtf :outputs (list fx))))
    (bir:insert-instruction-after mtf after)
    (bir:replace-uses fx datum)
    (setf (cc-bmir:rtype datum) :multiple-values)
    (setf (bir:inputs mtf) (list datum)))
  (values))

(defun maybe-insert-mtf (after datum)
  (let ((rt (cc-bmir:rtype datum)))
    (cond ((eq rt :multiple-values))
          ((null rt))
          ((equal rt '(:object)) (insert-mtf after datum))
          (t (error "BUG: Bad rtype ~a" rt)))))

(defun insert-ftm (before datum)
  (let* ((mv (make-instance 'cc-bmir:output :rtype :multiple-values
                            :derived-type (bir:ctype datum)))
         (ftm (make-instance 'cc-bmir:ftm :outputs (list mv))))
    (bir:insert-instruction-before ftm before)
    (bir:replace-uses mv datum)
    (setf (bir:inputs ftm) (list datum))
    ftm))

(defun maybe-insert-ftm (before datum)
  (let ((rt (cc-bmir:rtype datum)))
    (cond ((eq rt :multiple-values))
          ((and (listp rt) (every (lambda (x) (eq x :object)) rt))
           (insert-ftm before datum))
          (t (error "BUG: Bad rtype ~a" rt)))))

(defun maybe-insert-ftms (before data)
  (loop for dat in data do (maybe-insert-ftm before dat)))

(defun insert-pad-after (after ninputs datum)
  (let* ((new (make-instance 'cc-bmir:output
                :rtype (make-list ninputs :initial-element :object)
                :derived-type (bir:ctype datum)))
         (pad (make-instance 'cc-bmir:fixed-values-pad :inputs (list new))))
    (bir:insert-instruction-after pad after)
    (setf (bir:outputs after) (list new)
          (bir:outputs pad) (list datum))
    pad))

(defun maybe-insert-pad-after (after ninputs datum)
  (when (/= ninputs (length (cc-bmir:rtype datum)))
    (insert-pad-after after ninputs datum)))

;;; This is necessary for the situation where zero values are used as an input
;;; to something expecting values.
(defun insert-pad-before (before noutputs datum)
  (let* ((new (make-instance 'cc-bmir:output
                :rtype (make-list noutputs :initial-element :object)
                :derived-type (bir:ctype datum)))
         (pad (make-instance 'cc-bmir:fixed-values-pad :outputs (list new))))
    (bir:insert-instruction-before pad before)
    (bir:replace-uses new datum)
    (setf (bir:inputs pad) (list datum))
    pad))

(defgeneric insert-values-coercion (instruction))

(defun object-input (instruction input)
  (let ((rt (cc-bmir:rtype input)))
    (cond ((equal rt '(:object)))
          ((null rt) (insert-pad-before instruction 1 input))
          (t (error "BUG: Bad rtype ~a where ~a expected" rt '(:object))))))

(defun object-inputs (instruction
                            &optional (inputs (bir:inputs instruction)))
  (loop for inp in inputs do (object-input instruction inp)))

(defmethod insert-values-coercion ((instruction bir:instruction))
  ;; Default method: Assume we need all :objects and output (:object).
  (object-inputs instruction))

(defmethod insert-values-coercion ((instruction bir:fixed-to-multiple))
  (object-inputs instruction)
  (maybe-insert-pad-after instruction (length (bir:inputs instruction))
                          (bir:output instruction)))
;;; Make sure we don't insert things infinitely
(defmethod insert-values-coercion ((instruction cc-bmir:mtf)))
(defmethod insert-values-coercion ((instruction cc-bmir:ftm)))
(defmethod insert-values-coercion ((instruction cc-bmir:fixed-values-pad)))
;;; Doesn't need to do anything, and might not have all :object inputs
(defmethod insert-values-coercion ((instruction bir:thei)))

(defun insert-jump-coercion (instruction)
  (loop for inp in (bir:inputs instruction)
        for outp in (bir:outputs instruction)
        for inprt = (cc-bmir:rtype inp)
        for outprt = (cc-bmir:rtype outp)
        do (if (eq inprt :multiple-values)
               (unless (eq outprt :multiple-values)
                 (error "BUG: MV input into ~a jump output in ~a"
                        outprt instruction))
               (if (eq outprt :multiple-values)
                   (insert-ftm instruction inp)
                   (assert (equal inprt outprt))))))

(defmethod insert-values-coercion ((instruction bir:jump))
  (insert-jump-coercion instruction))
(defmethod insert-values-coercion ((instruction bir:unwind))
  (insert-jump-coercion instruction))

(defmethod insert-values-coercion ((instruction bir:call))
  (object-inputs instruction)
  (maybe-insert-mtf instruction (first (bir:outputs instruction))))
(defmethod insert-values-coercion ((instruction bir:mv-call))
  (object-input instruction (first (bir:inputs instruction)))
  (maybe-insert-ftms instruction (rest (bir:inputs instruction)))
  (maybe-insert-mtf instruction (first (bir:outputs instruction))))
(defmethod insert-values-coercion ((instruction bir:local-call))
  (object-inputs instruction (rest (bir:inputs instruction)))
  (maybe-insert-mtf instruction (first (bir:outputs instruction))))
(defmethod insert-values-coercion ((instruction bir:mv-local-call))
  (maybe-insert-ftms instruction (rest (bir:inputs instruction)))
  (maybe-insert-mtf instruction (first (bir:outputs instruction))))
(defmethod insert-values-coercion ((instruction cc-bmir:local-call-arguments)))
(defmethod insert-values-coercion ((instruction cc-bmir:real-mv-local-call))
  (maybe-insert-mtf instruction (first (bir:outputs instruction))))
(defmethod insert-values-coercion ((instruction cc-bmir:fake-mv-local-call))
  (maybe-insert-ftms instruction (rest (bir:inputs instruction)))
  (maybe-insert-mtf instruction (first (bir:outputs instruction))))
(defmethod insert-values-coercion ((instruction cc-bir:mv-foreign-call))
  (object-inputs instruction)
  (maybe-insert-mtf instruction (first (bir:outputs instruction))))
(defmethod insert-values-coercion ((instruction bir:values-save))
  (let* ((input (bir:input instruction)) (output (bir:output instruction))
         (inputrt (cc-bmir:rtype input)) (outputrt (cc-bmir:rtype output))
         (nde (bir:dynamic-environment instruction)))
    (cond ((eq outputrt :multiple-values)
           (maybe-insert-ftms instruction (bir:inputs instruction)))
          (t
           ;; The number of values is fixed, so this is a nop to delete.
           (assert (equal inputrt outputrt))
           (cleavir-set:doset (s (cleavir-bir:scope instruction))
             (setf (cleavir-bir:dynamic-environment s) nde))
           (cleavir-bir:replace-terminator
            (make-instance 'cleavir-bir:jump
              :inputs () :outputs () :next (bir:next instruction))
            instruction)
           ;; Don't need to recompute flow order since we haven't changed it.
           ;; We also don't merge iblocks because we're mostly done optimizing
           ;; at this point anyway.
           (bir:replace-uses input output)))))
(defmethod insert-values-coercion ((instruction bir:values-collect))
  (let* ((inputs (bir:inputs instruction)) (output (bir:output instruction))
         (outputrt (cc-bmir:rtype output)))
    (cond ((and (= (length inputs) 1) (not (eq outputrt :multiple-values)))
           ;; fixed values, so this is a nop to delete.
           (setf (bir:inputs instruction) nil)
           (bir:replace-uses (first inputs) output)
           (bir:delete-instruction instruction))
          (t
           (maybe-insert-mtf instruction output)))))
(defmethod insert-values-coercion ((instruction bir:returni))
  (maybe-insert-ftms instruction (bir:inputs instruction)))

(defun insert-values-coercion-into-function (function)
  (cleavir-bir:map-local-instructions #'insert-values-coercion function))

(defun insert-values-coercion-into-module (module)
  (bir:map-functions #'insert-values-coercion-into-function module))

;;;

(defgeneric lower-local-call (call hairyp))

(defmethod lower-local-call ((call bir:local-call) (hairyp null))
  (change-class call 'cc-bmir:real-local-call))
(defmethod lower-local-call ((call bir:local-call) hairyp)
  (declare (ignore hairyp))
  (change-class call 'cc-bmir:fake-local-call))
(defmethod lower-local-call ((call bir:mv-local-call) (hairyp null))
  (let ((callee (bir:callee call))
        (arginputs (rest (bir:inputs call))))
    (setf (bir:inputs call) (list callee))
    (let* ((parsed (make-instance 'bir:output))
           (parse (make-instance 'cc-bmir:local-call-arguments
                    :callee (bir:callee call) :inputs arginputs
                    :outputs (list parsed))))
      (bir:insert-instruction-before parse call)
      (setf (bir:inputs call) (list callee parsed))))
  (change-class call 'cc-bmir:real-mv-local-call))
(defmethod lower-local-call ((call bir:mv-local-call) hairyp)
  (declare (ignore hairyp))
  (change-class call 'cc-bmir:fake-mv-local-call))

;;; FIXME: duplicate code
(defun lambda-list-too-hairy-p (lambda-list)
  (multiple-value-bind (reqargs optargs rest-var
                        key-flag keyargs aok aux varest-p)
      (cmp::process-cleavir-lambda-list lambda-list)
    (declare (ignore reqargs optargs rest-var keyargs aok aux))
    (or key-flag varest-p)))

(defun lower-function-local-calls (function)
  (let ((hairyp (lambda-list-too-hairy-p (bir:lambda-list function))))
    (cleavir-set:doset (call (bir:local-calls function))
      (lower-local-call call hairyp))))

(defun lower-local-calls (module)
  (bir:map-functions #'lower-function-local-calls module))
