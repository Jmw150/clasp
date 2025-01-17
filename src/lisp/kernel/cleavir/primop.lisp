(in-package #:clasp-cleavir)

;;; A "primop" is something that can be "called" like a function (all its
;;; arguments are evaluated) but which is specially translated by the compiler.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; CORE:PRIMOP special operator
;;;
;;; This allows primops to be used directly in source code. Use with caution.
;;;

(defmethod cst-to-ast:convert-special ((symbol (eql 'core::primop)) cst env
                                       (system clasp-cleavir:clasp))
  (unless (cst:proper-list-p cst)
    (error 'cleavir-cst-to-ast:form-must-be-proper-list :cst cst))
  (let* ((name (cst:raw (cst:second cst)))
         (op (cleavir-primop-info:info name))
         (nargs (cleavir-primop-info:ninputs op)))
    (let ((count (- (length (cst:raw cst)) 2)))
      (unless (= count nargs) ; 2 for PRIMOP and the name
        (error 'cst-to-ast:incorrect-number-of-arguments-error
               :cst cst :expected-min nargs :expected-max nargs
               :observed count)))
    (make-instance 'cleavir-ast:primop-ast
      :info op
      :argument-asts (cst-to-ast::convert-sequence
                      (cst:rest (cst:rest cst))
                      env system)
      :origin cst)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Primop definition machinery
;;;

;;; Called by translate-simple-instruction. Return value irrelevant.
(defgeneric translate-primop (opname instruction))
;;; Called by translate-conditional-test
(defgeneric translate-conditional-primop (opname instruction next)
  (:method (opname (instruction bir:primop) next)
    (declare (ignore opname))
    ;; Like the default method on translate-conditional-test, compare the output
    ;; against NIL.
    (cmp:irc-cond-br
     (cmp:irc-icmp-eq (in (first (bir:outputs instruction))) (%nil))
     (second next) (first next))))

;;; Hash table from primop infos to rtype info.
;;; An rtype info is just a list (return-rtype argument-rtypes...)
;;; If there is no entry in the table, it's assumed to return (:object)
;;; and take :object arguments.
;;; See bir-to-bmir for more information about rtypes.
(defvar *primop-rtypes* (make-hash-table :test #'eq))

(defun primop-rtype-info (primop-info)
  (or (gethash (cleavir-primop-info:name primop-info) *primop-rtypes*)
      (list* '(:object)
             (make-list (cleavir-primop-info:ninputs primop-info)
                        :initial-element :object))))

;;; Define a primop that returns values.
;;; param-info is either (return-rtype param-rtypes...) or an integer; the
;;; latter is short for taking that many :objects and returning (:object).
;;; For example, (defvprimop foo 2)
;;;              = (defvprimop foo ((:object) :object :object))
;;; The BODY is used as a translate-primop method, where the call instruction
;;; is available bound to INSTPARAM.
;;; The NAME can be a symbol or a list (SYMBOL ...) where ... are options,
;;; sort of like defstruct. So far the only option is :flags.
(defmacro defvprimop (name param-info (instparam) &body body)
  (let ((name (if (consp name) (first name) name))
        (options (if (consp name) (rest name) nil))
        (param-info (if (integerp param-info)
                        (list* '(:object) (make-list param-info
                                                     :initial-element :object))
                        param-info))
        (nsym (gensym "NAME")))
    (destructuring-bind (&key flags) options
      `(progn
         (cleavir-primop-info:defprimop ,name ,(length (rest param-info))
           :value ,@flags)
         (setf (gethash ',name *primop-rtypes*) '(,@param-info))
         (defmethod translate-primop ((,nsym (eql ',name)) ,instparam)
           (out (progn ,@body) (first (bir:outputs ,instparam))))
         ',name))))

;;; Like defvprimop for the case where the body is just an intrinsic.
(defmacro defvprimop-intrinsic (name param-info intrinsic)
  ;; TODO: Assert argument types? Or maybe that should be done at a lower level
  ;; in irc-intrinsic-etc.
  `(defvprimop ,name ,param-info (inst)
     (%intrinsic-invoke-if-landing-pad-or-call
      ,intrinsic (mapcar #'in (bir:inputs inst)))))

;;; Define a primop called for effect.
;;; Here param-info is parameters only.
(defmacro defeprimop (name param-info (instparam) &body body)
  (let ((name (if (consp name) (first name) name))
        (options (if (consp name) (rest name) nil))
        (param-info
          (list* () (if (integerp param-info)
                        (make-list param-info :initial-element :object)
                        param-info)))
        (nsym (gensym "NAME")))
    (destructuring-bind (&key flags) options
      `(progn
         (cleavir-primop-info:defprimop ,name ,(length (rest param-info))
           :effect ,@flags)
         (setf (gethash ',name *primop-rtypes*) '(,@param-info))
         (defmethod translate-primop ((,nsym (eql ',name)) ,instparam)
           ,@body)
         ',name))))

;;; Define a primop used as a conditional test.
;;; Here param-info is parameters only.
;;; The body is used for translate-conditional-primop, which is expected to
;;; return an LLVM i1 Value.
(defmacro deftprimop (name param-info (instparam nextparam) &body body)
  (let ((name (if (consp name) (first name) name))
        (options (if (consp name) (rest name) nil))
        (param-info
          (list* '(:object)
                 (if (integerp param-info)
                     (make-list param-info :initial-element :object)
                     param-info)))
        (nsym (gensym "NAME")))
    (destructuring-bind (&key flags) options
      `(progn
         (cleavir-primop-info:defprimop ,name ,(length (rest param-info)) 2
           ,@flags)
         (setf (gethash ',name *primop-rtypes*) '(,@param-info))
         (defmethod translate-primop ((,nsym (eql ',name)) ,instparam)
           (declare (ignore ,instparam)))
         (defmethod translate-conditional-primop ((,nsym (eql ',name))
                                                  ,instparam ,nextparam)
           ,@body)
         ',name))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Particular primops
;;;

(macrolet ((def-float-compare (sfname dfname op reversep)
             `(progn
                (deftprimop ,sfname (:single-float :single-float)
                  (inst next)
                  (assert (= (length (bir:inputs inst)) 2))
                  (let ((,(if reversep 'i2 'i1)
                          (in (first (bir:inputs inst))))
                        (,(if reversep 'i1 'i2)
                          (in (second (bir:inputs inst)))))
                    (assert (llvm-sys:type-equal (llvm-sys:get-type i1)
                                                 cmp:%float%))
                    (assert (llvm-sys:type-equal (llvm-sys:get-type i2)
                                                 cmp:%float%))
                    (cmp:irc-cond-br (,op i1 i2) (first next) (second next))))
                (deftprimop ,dfname (:double-float :double-float)
                  (inst next)
                  (assert (= (length (bir:inputs inst)) 2))
                  (let ((,(if reversep 'i2 'i1)
                          (in (first (bir:inputs inst))))
                        (,(if reversep 'i1 'i2)
                          (in (second (bir:inputs inst)))))
                    (assert (llvm-sys:type-equal (llvm-sys:get-type i1)
                                                 cmp:%double%))
                    (assert (llvm-sys:type-equal (llvm-sys:get-type i2)
                                                 cmp:%double%))
                    (cmp:irc-cond-br (,op i1 i2) (first next) (second next)))))))
  (def-float-compare core::two-arg-sf-=  core::two-arg-df-=  %fcmp-oeq nil)
  (def-float-compare core::two-arg-sf-<  core::two-arg-df-<  %fcmp-olt nil)
  (def-float-compare core::two-arg-sf-<= core::two-arg-df-<= %fcmp-ole nil)
  (def-float-compare core::two-arg-sf->  core::two-arg-df->  %fcmp-olt   t)
  (def-float-compare core::two-arg-sf->= core::two-arg-df->= %fcmp-ole   t))

(macrolet ((def-float-unop (sfname sfintrinsic dfname dfintrinsic)
             `(progn
                ;; NOTE: marking these flushable might change fp exception
                ;; behavior - do we care? not sure.
                (defvprimop-intrinsic (,sfname :flags (:flushable))
                    ((:single-float) :single-float)
                  ,sfintrinsic)
                (defvprimop-intrinsic (,dfname :flags (:flushable))
                    ((:double-float) :double-float)
                  ,dfintrinsic))))
  (def-float-unop core::sf-abs   "llvm.fabs.f32" core::df-abs   "llvm.fabs.f64")
  (def-float-unop core::sf-sqrt  "llvm.sqrt.f32" core::df-sqrt  "llvm.sqrt.f64")
  (def-float-unop core::sf-exp   "llvm.exp.f32"  core::df-exp   "llvm.exp.f64")
  (def-float-unop core::sf-log   "llvm.log.f32"  core::df-log   "llvm.log.f64")
  (def-float-unop core::sf-cos   "llvm.cos.f32"  core::df-cos   "llvm.cos.f64")
  (def-float-unop core::sf-sin   "llvm.sin.f32"  core::df-sin   "llvm.sin.f64")
  (def-float-unop core::sf-tan   "tanf"          core::df-tan   "tan")
  (def-float-unop core::sf-acos  "acosf"         core::df-acos  "acos")
  (def-float-unop core::sf-asin  "asinf"         core::df-asin  "asin")
  (def-float-unop core::sf-cosh  "coshf"         core::df-cosh  "cosh")
  (def-float-unop core::sf-sinh  "sinhf"         core::df-sinh  "sinh")
  (def-float-unop core::sf-tanh  "tanhf"         core::df-tanh  "tanh")
  (def-float-unop core::sf-acosh "acoshf"        core::df-acosh "acosh")
  (def-float-unop core::sf-asinh "asinhf"        core::df-asinh "asinh")
  (def-float-unop core::sf-atanh "atanhf"        core::df-atanh "atanh"))

(macrolet ((def-float-binop-op (sfname dfname ircop)
             `(progn
                (defvprimop (,sfname :flags (:flushable))
                    ((:single-float) :single-float :single-float)
                  (inst)
                  (assert (= 2 (length (bir:inputs inst))))
                  (let ((i1 (in (first (bir:inputs inst))))
                        (i2 (in (second (bir:inputs inst)))))
                    (assert (llvm-sys:type-equal (llvm-sys:get-type i1)
                                                 cmp:%float%))
                    (assert (llvm-sys:type-equal (llvm-sys:get-type i2)
                                                 cmp:%float%))
                    (,ircop i1 i2)))
                (defvprimop (,dfname :flags (:flushable))
                    ((:double-float) :double-float :double-float)
                  (inst)
                  (assert (= 2 (length (bir:inputs inst))))
                  (let ((i1 (in (first (bir:inputs inst))))
                        (i2 (in (second (bir:inputs inst)))))
                    (assert (llvm-sys:type-equal (llvm-sys:get-type i1)
                                                 cmp:%double%))
                    (assert (llvm-sys:type-equal (llvm-sys:get-type i2)
                                                 cmp:%double%))
                    (,ircop i1 i2)))))
           (def-float-binop-i (sfname sfintrinsic dfname dfintrinsic)
             `(progn
                (defvprimop-intrinsic ,sfname
                    ((:single-float) :single-float :single-float)
                  ,sfintrinsic)
                (defvprimop-intrinsic ,dfname
                    ((:double-float) :double-float :double-float)
                  ,dfintrinsic))))
  (def-float-binop-op core::two-arg-sf-+ core::two-arg-df-+ %fadd)
  (def-float-binop-op core::two-arg-sf-- core::two-arg-df-- %fsub)
  (def-float-binop-op core::two-arg-sf-* core::two-arg-df-* %fmul)
  (def-float-binop-op core::two-arg-sf-/ core::two-arg-df-/ %fdiv)
  (def-float-binop-i core::sf-expt "llvm.pow.f32" core::df-expt "llvm.pow.f64"))

(defvprimop (core::sf-ftruncate :flags (:flushable))
    ((:single-float :single-float) :single-float :single-float)
  (inst)
  (assert (= 2 (length (bir:inputs inst))))
  (let ((i1 (in (first (bir:inputs inst))))
        (i2 (in (second (bir:inputs inst)))))
    (assert (llvm-sys:type-equal (llvm-sys:get-type i1) cmp:%float%))
    (assert (llvm-sys:type-equal (llvm-sys:get-type i2) cmp:%float%))
    ;; I think this is the best instruction sequence, but I am not sure.
    (list (%intrinsic-call "llvm.trunc.f32" (list (%fdiv i1 i2)))
          (%frem i1 i2))))
(defvprimop (core::df-ftruncate :flags (:flushable))
    ((:double-float :double-float) :double-float :double-float)
  (inst)
  (assert (= 2 (length (bir:inputs inst))))
  (let ((i1 (in (first (bir:inputs inst))))
        (i2 (in (second (bir:inputs inst)))))
    (assert (llvm-sys:type-equal (llvm-sys:get-type i1) cmp:%double%))
    (assert (llvm-sys:type-equal (llvm-sys:get-type i2) cmp:%double%))
    (list (%intrinsic-call "llvm.trunc.f64" (list (%fdiv i1 i2)))
          (%frem i1 i2))))

(defvprimop (core::sf-negate :flags (:flushable))
    ((:single-float) :single-float) (inst)
  (assert (= 1 (length (bir:inputs inst))))
  (let ((arg (in (first (bir:inputs inst)))))
    (assert (llvm-sys:type-equal (llvm-sys:get-type arg) cmp:%float%))
    (%fneg arg)))
(defvprimop (core::df-negate :flags (:flushable))
    ((:double-float) :double-float) (inst)
  (assert (= 1 (length (bir:inputs inst))))
  (let ((arg (in (first (bir:inputs inst)))))
    (assert (llvm-sys:type-equal (llvm-sys:get-type arg) cmp:%double%))
    (%fneg arg)))

(defvprimop (core::single-to-double :flags (:flushable))
    ((:double-float) :single-float) (inst)
  (assert (= 1 (length (bir:inputs inst))))
  (let ((arg (in (first (bir:inputs inst)))))
    (assert (llvm-sys:type-equal (llvm-sys:get-type arg) cmp:%float%))
    (%fpext arg cmp:%double%)))
(defvprimop (core::double-to-single :flags (:flushable))
    ((:single-float) :double-float) (inst)
  (assert (= 1 (length (bir:inputs inst))))
  (let ((arg (in (first (bir:inputs inst)))))
    (assert (llvm-sys:type-equal (llvm-sys:get-type arg) cmp:%double%))
    (%fptrunc arg cmp:%float%)))

(defvprimop (core::fixnum-to-single :flags (:flushable))
    ((:single-float) :fixnum) (inst)
  (assert (= 1 (length (bir:inputs inst))))
  (let* ((arg (in (first (bir:inputs inst))))
         (fix (cmp:irc-ashr arg cmp:+fixnum-shift+ :exact t)))
    (%sitofp fix cmp:%float%
             (datum-name-as-string (first (bir:outputs inst))))))
(defvprimop (core::fixnum-to-double :flags (:flushable))
    ((:double-float) :fixnum) (inst)
  (assert (= 1 (length (bir:inputs inst))))
  (let* ((arg (in (first (bir:inputs inst))))
         (fix (cmp:irc-ashr arg cmp:+fixnum-shift+ :exact t)))
    (%sitofp fix cmp:%double%
             (datum-name-as-string (first (bir:outputs inst))))))

(defvprimop-intrinsic (core::sf-vref :flags (:flushable))
    ((:single-float) :object :object)
  "cc_simpleFloatVectorAref")
(defvprimop-intrinsic (core::df-vref :flags (:flushable))
    ((:double-float) :object :object)
  "cc_simpleDoubleVectorAref")

;;; These return the new value because it's a bit involved to rewrite BIR to use
;;; a linear datum more than once.
(defvprimop core::sf-vset ((:single-float) :single-float :object :object) (inst)
  (let ((args (mapcar #'in (bir:inputs inst))))
    (assert (llvm-sys:type-equal (llvm-sys:get-type (first args)) cmp:%float%))
    (%intrinsic-invoke-if-landing-pad-or-call "cc_simpleFloatVectorAset" args)
    (first args)))
(defvprimop core::df-vset ((:double-float) :double-float :object :object) (inst)
  (let ((args (mapcar #'in (bir:inputs inst))))
    (assert (llvm-sys:type-equal (llvm-sys:get-type (first args)) cmp:%double%))
    (%intrinsic-invoke-if-landing-pad-or-call "cc_simpleDoubleVectorAset" args)
    (first args)))

;;;

(defvprimop (core::fixnum-lognot :flags (:flushable)) ((:fixnum) :fixnum) (inst)
  (let* ((arg (in (first (bir:inputs inst))))
         ;; LLVM does not have a dedicated lognot, and instead
         ;; represents it as xor whatever, -1.
         ;; We want to keep the tag bits zero, so we skip the rigamarole
         ;; by just XORing directly with -4 (or whatever, based on how
         ;; many tag bits we use).
         (other (%i64 (ldb (byte 64 0) (ash -1 cmp:+fixnum-shift+))))
         (label (datum-name-as-string (first (bir:outputs inst)))))
    (cmp:irc-xor arg other label)))

;;; NOTE: 0 & 0, 0 | 0, and 0 ^ 0 are all zero, so these operations all
;;; preserve the zero fixnum tag without any issue.
(macrolet ((deflog2 (name op)
             `(defvprimop (,name :flags (:flushable))
                  ((:fixnum) :fixnum :fixnum) (inst)
                (let ((arg1 (in (first (bir:inputs inst))))
                      (arg2 (in (second (bir:inputs inst)))))
                  (,op arg1 arg2)))))
  (deflog2 core::fixnum-logand cmp:irc-and)
  (deflog2 core::fixnum-logior cmp:irc-or)
  (deflog2 core::fixnum-logxor cmp:irc-xor))

;; Wrapping addition of tagged fixnums.
(defvprimop (core::fixnum-add :flags (:flushable))
    ((:fixnum) :fixnum :fixnum) (inst)
  (let ((arg1 (in (first (bir:inputs inst))))
        (arg2 (in (second (bir:inputs inst)))))
    (cmp:irc-add arg1 arg2)))
(defvprimop (core::fixnum-sub :flags (:flushable))
    ((:fixnum) :fixnum :fixnum) (inst)
  (let ((arg1 (in (first (bir:inputs inst))))
        (arg2 (in (second (bir:inputs inst)))))
    (cmp:irc-sub arg1 arg2)))

;; For division we don't need to untag the inputs but do need to
;; shift the quotient.
(defvprimop (core::fixnum-truncate :flags (:flushable))
    ((:fixnum :fixnum) :fixnum :fixnum) (inst)
  (let* ((arg1 (in (first (bir:inputs inst))))
         (arg2 (in (second (bir:inputs inst))))
         (quo (cmp:irc-sdiv arg1 arg2))
         (tquo (cmp:irc-shl quo cmp:+fixnum-shift+ :nsw t))
         (rem (cmp:irc-srem arg1 arg2)))
    (list tquo rem)))

(macrolet ((def-fixnum-compare (name op)
             `(progn
                (deftprimop ,name (:fixnum :fixnum)
                  (inst next)
                  (assert (= (length (bir:inputs inst)) 2))
                  ;; NOTE: We do not HAVE to cast to an integer type,
                  ;; as icmp works fine on pointers directly.
                  ;; However, LLVM doesn't seem to be very intelligent
                  ;; about pointer comparisons, e.g. it does not fold
                  ;; them even when both arguments are inttoptr of
                  ;; constants. So we use the fixnum rtype.
                  (let ((i1 (in (first (bir:inputs inst))))
                        (i2 (in (second (bir:inputs inst)))))
                    (cmp:irc-cond-br (,op i1 i2)
                                     (first next) (second next)))))))
  (def-fixnum-compare core::two-arg-fixnum-=  cmp:irc-icmp-eq)
  (def-fixnum-compare core::two-arg-fixnum-<  cmp:irc-icmp-slt)
  (def-fixnum-compare core::two-arg-fixnum-<= cmp:irc-icmp-sle)
  (def-fixnum-compare core::two-arg-fixnum->  cmp:irc-icmp-sgt)
  (def-fixnum-compare core::two-arg-fixnum->= cmp:irc-icmp-sge))

(defvprimop (core::fixnum-positive-logcount :flags (:flushable))
    ((:fixnum) :fixnum) (inst)
  (let* ((arg (in (first (bir:inputs inst))))
         (label (datum-name-as-string (first (bir:outputs inst))))
         ;; NOTE we do not need to shift the argument: the tag is all zero
         ;; so it won't affect the population count.
         (count (%intrinsic-call "llvm.ctpop.i64" (list arg))))
    (cmp:irc-shl count cmp:+fixnum-shift+ :label label :nsw t)))

(defvprimop (core::fixnum-ashr :flags (:flushable))
    ((:fixnum) :fixnum :fixnum) (inst)
  (let* ((int (in (first (bir:inputs inst))))
         ;; NOTE: shift must be 0-63 inclusive or shifted is poison!
         (shift (in (second (bir:inputs inst))))
         (ushift (cmp:irc-ashr shift cmp:+fixnum-shift+ :exact t))
         (shifted (cmp:irc-ashr int ushift))
         (demask (%i64 (ldb (byte 64 0) (lognot cmp:+fixnum-mask+))))
         ;; zero the tag bits
         (fixn (cmp:irc-and shifted demask
                            (datum-name-as-string
                             (first (bir:outputs inst))))))
    fixn))

;;; Primops for debugging

(defeprimop core:set-breakstep () (inst)
  (declare (ignore inst))
  (%intrinsic-call "cc_set_breakstep" ()))

(defeprimop core:unset-breakstep () (inst)
  (declare (ignore inst))
  (%intrinsic-call "cc_unset_breakstep" ()))
