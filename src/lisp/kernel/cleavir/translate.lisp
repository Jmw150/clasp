(in-package #:clasp-cleavir)

;;; Backend information associated with a BIR function.
(defclass llvm-function-info ()
  (;; In BIR, function environments are sets but we'd like to have it
   ;; be a list to ensure ordering.
   (%environment :initarg :environment :type list :reader environment)
   ;; The argument variables of the function lambda list.
   (%arguments :initarg :arguments :type list :reader arguments)
   ;; The eXternal Entry Point is in charge of loading values and
   ;; cells from the closure vector and parsing the number of arguments.
   (%xep-function :initarg :xep-function :reader xep-function)
   (%xep-function-description :initarg :xep-function-description :reader xep-function-description)
   (%main-function :initarg :main-function :reader main-function)
   (%main-function-description :initarg :main-function-description :reader main-function-description)))

(defun lambda-list-too-hairy-p (lambda-list)
  (multiple-value-bind (reqargs optargs rest-var
                        key-flag keyargs aok aux varest-p)
      (cmp::process-cleavir-lambda-list lambda-list)
    (declare (ignore reqargs optargs rest-var keyargs aok aux))
    (or key-flag varest-p)))

(defun xep-needed-p (function)
  (or (bir:enclose function)
      ;; We need a XEP for more involved lambda lists.
      (lambda-list-too-hairy-p (bir:lambda-list function))
      ;; Assume that a function with no enclose and no local calls is
      ;; toplevel and needs an XEP. Else it would have been removed or
      ;; deleted as it is unreferenced otherwise.
      (cleavir-set:empty-set-p (bir:local-calls function))))

(defun allocate-llvm-function-info (function &key (linkage 'llvm-sys:internal-linkage))
  (let* ((lambda-name (get-or-create-lambda-name function))
         (llvm-function-name (cmp:jit-function-name lambda-name))
         (function-info (calculate-function-info function lambda-name))
         (arguments
           (let ((arglist '()))
             (dolist (item (bir:lambda-list function))
               (unless (symbolp item)
                 (if (consp item)
                     (ecase (length item)
                       (2
                        (push (first item) arglist)
                        (push (second item) arglist))
                       (3
                        (push (second item) arglist)
                        (push (third item) arglist)))
                     (push item arglist))))
             (nreverse arglist))))
    (multiple-value-bind (the-function function-description)
        (cmp:irc-cclasp-function-create
         (llvm-sys:function-type-get
          cmp::%tmv%
          (make-list (+ (cleavir-set:size (bir:environment function))
                        (length arguments))
                     :initial-element cmp::%t*%))
         'llvm-sys:private-linkage
         llvm-function-name
         cmp:*the-module*
         function-info)
      (multiple-value-bind (xep-function xep-function-description)
          (if (xep-needed-p function)
              (cmp:irc-cclasp-function-create
               cmp:%fn-prototype%
               linkage
               llvm-function-name
               cmp:*the-module*
               function-info)
              (values :xep-unallocated :xep-unallocated))
        (make-instance 'llvm-function-info
          :environment (cleavir-set:set-to-list (bir:environment function))
          :main-function the-function
          :main-function-description function-description
          :xep-function xep-function
          :xep-function-description xep-function-description
          :arguments arguments)))))

;;; Return value is unspecified/irrelevant.
(defgeneric translate-simple-instruction (instruction abi))

;;; Ditto
(defgeneric translate-terminator (instruction abi next))

;;; Ditto
(defgeneric translate-primop (opname instruction))

;;; In CSTs and stuff the origin is (spi . spi). Use the head.
(defun origin-spi (origin)
  (if (consp origin) (car origin) origin))

(defun ensure-origin (origin &optional (num 999905))
  (or origin
      (core:make-source-pos-info "no-source-info-available" num num num)))

;;; Put in source info.
(defmethod translate-simple-instruction :around
    ((instruction bir:instruction) abi)
  (declare (ignore abi))
  (cmp:with-debug-info-source-position ((ensure-origin
                                         (bir:origin instruction)
                                         999902))
    (call-next-method)))
(defmethod translate-terminator :around
    ((instruction bir:instruction) abi next)
  (declare (ignore abi next))
  (cmp:with-debug-info-source-position ((ensure-origin
                                         (bir:origin instruction)
                                         999903))
    (call-next-method)))

(defmethod translate-terminator ((instruction bir:unreachable)
                                 abi next)
  (declare (ignore abi next))
  (cmp:irc-unreachable))

(defmethod translate-terminator ((instruction bir:returni) abi next)
  (declare (ignore abi next))
  (cmp:irc-ret (in (first (bir:inputs instruction)))))

(defmethod translate-terminator ((inst bir:values-save) abi next)
  (declare (ignore abi))
  (let* ((tmv (in (first (bir:inputs inst))))
         (outp (first (bir:outputs inst)))
         (nvals (cmp:irc-tmv-nret tmv))
         (primary (cmp:irc-tmv-primary tmv))
         ;; NOTE: Must be done BEFORE the alloca.
         (save (%intrinsic-call "llvm.stacksave" nil))
         (mv-temp (cmp:alloca-temp-values nvals)))
    (setf (dynenv-storage inst) (list save nvals mv-temp))
    (out (%intrinsic-call "cc_save_values" (list nvals primary mv-temp)) outp))
  ;; Continue
  (cmp:irc-br (first next)))

(defgeneric undo-dynenv (dynamic-environment tmv))

(defmethod undo-dynenv ((dynamic-environment bir:dynamic-leti) tmv)
  ;; Could undo stack allocated cells here
  (declare (ignore tmv)))
(defmethod undo-dynenv ((dynenv bir:catch) tmv)
  ;; ditto, and mark the continuation out of extent
  (declare (ignore tmv)))
(defmethod undo-dynenv ((dynenv bir:values-save) tmv)
  (declare (ignore tmv))
  (destructuring-bind (stackpos storage1 storage2)
      (dynenv-storage dynenv)
    (declare (ignore storage1 storage2))
    (%intrinsic-call "llvm.stackrestore" (list stackpos))))

(defun translate-local-unwind (jump tmv)
  (loop with target = (bir:dynamic-environment
                       (first (bir:next jump)))
        for de = (bir:dynamic-environment jump)
          then (bir:parent de)
        when (eq target de)
          do (loop-finish)
        when (typep de 'bir:function)
          do (error "BUG: Dynamic environment chain screwed up somehow")
        do (undo-dynenv de tmv)))

(defmethod translate-terminator ((instruction bir:jump) abi next)
  (declare (ignore abi))
  (assert (= (length next) 1))
  (when (bir:unwindp instruction)
    (if (and (= (length (bir:outputs instruction)) 1)
             (eq (cc-bmir:rtype (first (bir:outputs instruction)))
                 :multiple-values))
        (translate-local-unwind instruction
                                (in (first (bir:inputs instruction))))
        (translate-local-unwind instruction nil)))
  (loop for in in (bir:inputs instruction)
        for out in (bir:outputs instruction)
        do (phi-out (in in) out (llvm-sys:get-insert-block cmp:*irbuilder*)))
  (cmp:irc-br (first next)))

(defgeneric translate-conditional-test (instruction next))

(defmethod translate-conditional-test (instruction next)
  ;; When the test is not a conditional test, just grab the value and
  ;; compare to NIL.
  (cmp:irc-cond-br
   (cmp:irc-icmp-eq (in (first (bir:outputs instruction))) (%nil))
   (second next) (first next)))
(defmethod translate-conditional-test
    ((instruction bir:conditional-test) next)
  (declare (ignore next))
  (error "Don't know how to translate this conditional test ~a." instruction))

(defmethod translate-conditional-test ((instruction bir:eq-test) next)
  (let ((inputs (bir:inputs instruction)))
    (cmp:irc-cond-br
     (cmp:irc-icmp-eq (in (first inputs)) (in (second inputs)))
     (first next) (second next))))

(defmacro define-tag-test (inst mask tag)
  `(defmethod translate-conditional-test ((instruction ,inst) next)
     (cmp:compile-tag-check (in (first (bir:inputs instruction)))
                            ,mask ,tag
                            (first next) (second next))))
(define-tag-test cc-bmir:fixnump cmp:+fixnum-mask+ cmp:+fixnum00-tag+)
(define-tag-test cc-bmir:consp cmp:+immediate-mask+ cmp:+cons-tag+)
(define-tag-test cc-bmir:characterp cmp:+immediate-mask+ cmp:+character-tag+)
(define-tag-test cc-bmir:single-float-p
  cmp:+immediate-mask+ cmp:+single-float-tag+)
(define-tag-test cc-bmir:generalp cmp:+immediate-mask+ cmp:+general-tag+)

(defmethod translate-conditional-test ((instruction cc-bmir:headerq) next)
  (cmp:compile-header-check
   (cc-bmir:info instruction)
   (in (first (bir:inputs instruction)))
   (first next) (second next)))

(defmethod translate-terminator ((instruction bir:ifi) abi next)
  (declare (ignore abi))
  (let ((in (first (bir:inputs instruction))))
    (etypecase in
      (bir:output
       (translate-conditional-test (bir:definition in) next))
      ((or bir:phi bir:argument)
       (cmp:irc-cond-br (cmp:irc-icmp-eq (in in) (%nil))
                        (second next) (first next))))))

(defmethod translate-simple-instruction
    ((instruction bir:conditional-test) abi)
  ;; Since we translate-conditional-test from the ifi instead, do nothing.
  (declare (ignore instruction abi)))

(defmethod translate-terminator ((instruction bir:case) abi next)
  (declare (ignore abi))
  (assert (= (length next) (length (bir:next instruction))
             (1+ (length (bir:comparees instruction)))))
  (let* ((input (in (first (bir:inputs instruction))))
         (default (first (last next)))
         (dests (butlast next))
         (comparees (bir:comparees instruction))
         (ncases (loop for list in comparees summing (length list)))
         (only-fixnums-p (loop for list in comparees
                               always (every #'core:fixnump list)))
         ;; LLVM does better with contiguous ranges. It's not smart enough to
         ;; recognize that it could get a contiguous range by shifting.
         ;; (Or maybe it doesn't care. How often does that happen?)
         (rinput (if only-fixnums-p
                     (let ((fixnum-block (cmp:irc-basic-block-create "is-fixnum")))
                       ;; same as fixnump instruction
                       (cmp:compile-tag-check input
                                              cmp:+fixnum-mask+
                                              cmp:+fixnum00-tag+
                                              fixnum-block default)
                       (cmp:irc-begin-block fixnum-block)
                       (cmp:irc-untag-fixnum input cmp:%i64% "switch-input"))
                     (cmp:irc-ptr-to-int input cmp:%i64%)))
         (switch (cmp:irc-switch rinput default ncases)))
    (loop for list in comparees
          for dest in dests
          do (loop for object in list
                   for immediate = (core:create-tagged-immediate-value-or-nil object)
                   do (assert (not (null immediate)))
                      (cmp:irc-add-case switch
                                        (%i64 (if only-fixnums-p
                                                  (ash immediate -2)
                                                  immediate))
                                        dest)))))

(defun translate-sjlj-catch (catch successors)
  ;; Call setjmp, switch on the result.
  (let ((normal-successor (first successors))
        (bufp (cmp:alloca cmp::%jmp-buf-tag% 1 "jmp-buf")))
    (out (cmp:irc-bit-cast bufp cmp:%t*%) catch)
    (multiple-value-bind (iblocks blocks successors)
        ;; We only care about iblocks that are actually unwound to.
        (loop for iblock in (rest (bir:next catch))
              for successor in (rest successors)
              when (has-entrances-p iblock)
                collect iblock into iblocks
                and collect (cmp:irc-basic-block-create "catch-restore")
                      into blocks
                and collect successor into successors
              finally (return (values iblocks blocks successors)))
      (let* ((sj (%intrinsic-call "_setjmp" (list bufp)))
             (default (cmp:irc-basic-block-create "catch-default"))
             (sw (cmp:irc-switch sj default (1+ (length iblocks)))))
        (cmp:irc-begin-block default)
        (cmp:irc-unreachable)
        (cmp:irc-add-case sw (%i32 0) normal-successor)
        (loop for succ in successors
              for block in blocks
              for iblock in iblocks
              for destination-id = (get-destination-id iblock)
              for phi = (and (= (length (bir:inputs iblock)) 1)
                             (first (bir:inputs iblock)))
              ;; 1+ because we can't pass 0 to longjmp, as in unwind below.
              do (cmp:irc-add-case sw (%i32 (1+ destination-id)) block)
                 (cmp:irc-begin-block block)
                 (when phi
                   (let ((mv (restore-multiple-value-0))
                         (rt (cc-bmir:rtype phi)))
                     (cond ((null rt))
                           ((equal rt '(:object))
                            (phi-out (cmp:irc-tmv-primary mv) phi block))
                           ((eq rt :multiple-values) (phi-out mv phi block))
                           ((every (lambda (x) (eq x :object)) rt)
                            (phi-out
                             (list* (cmp:irc-tmv-primary mv)
                                    (loop for i from 1 below (length rt)
                                          collect (cmp:irc-load
                                                   (return-value-elt i))))
                             phi block))
                           (t (error "BUG: Bad rtype ~a" rt)))))
                 (cmp:irc-br succ))))))

(defmethod translate-terminator ((instruction bir:catch) abi next)
  (declare (ignore abi))
  (cond
    ((cleavir-set:empty-set-p (bir:unwinds instruction))
     (cmp:irc-br (first next)))
    ((bir-transformations:simple-unwinding-p instruction)
     (translate-sjlj-catch instruction next))
    (t
     ;; Assign the catch the continuation.
     (out (%intrinsic-call "llvm.frameaddress" (list (%i32 0)) "frame")
          instruction)
     ;; Unconditional branch to the normal successor;
     ;; dynamic environment stuff is handled in layout-iblock.
     (cmp:irc-br (first next)))))

(defmethod translate-terminator ((instruction bir:unwind) abi next)
  (declare (ignore abi next))
  (let* ((cont (in (bir:catch instruction)))
         (inputs (bir:inputs instruction))
         (rv (first inputs))
         ;; Force the return values into a tmv for transmission.
         (rrv (when rv
                (let ((rt (cc-bmir:rtype rv)))
                  (cond ((equal rt '(:object))
                         (cmp:irc-make-tmv (%size_t 1) (in rv)))
                        ((eq rt :multiple-values) (in rv))
                        ((null rt) (error "BUG: Bad rtype ~a" rt))
                        ((every (lambda (x) (eq x :object)) rt)
                         (let ((vals (in rv))
                               (nvals (length rt)))
                           (loop for i from 1 below nvals
                                 for v in (rest vals)
                                 do (cmp:irc-store v (return-value-elt i)))
                           (cmp:irc-make-tmv (%size_t nvals) (first vals))))
                        (t (error "BUG: Bad rtype ~a" rt))))))
         (destination (bir:destination instruction))
         (destination-id (get-destination-id destination)))
    ;; Transmit values
    (when rv (save-multiple-value-0 rrv))
    ;; unwind
    (if (bir-transformations:simple-unwinding-p
         (bir:catch instruction))
        ;; SJLJ
        ;; (Note: No landing pad because in order for SJLJ to occur,
        ;;  the dynamic environment must just be the function.)
        (let ((bufp (cmp:irc-bit-cast cont cmp::%jmp-buf-tag*%)))
          (%intrinsic-invoke-if-landing-pad-or-call
           ;; 1+ because we can't pass 0 to longjmp.
           "_longjmp" (list bufp (%i32 (1+ destination-id)))))
        ;; C++ exception
        (cmp:with-landing-pad (never-entry-landing-pad
                               (bir:dynamic-environment instruction))
          (%intrinsic-invoke-if-landing-pad-or-call
           "cc_unwind" (list cont (%size_t destination-id))))))
  (cmp:irc-unreachable))

(defmethod translate-terminator ((instruction cc-bir:unwind-protect) abi next)
  (declare (ignore abi))
  (setf (dynenv-storage instruction)
        (in (first (bir:inputs instruction))))
  (cmp:irc-br (first next)))

(defmethod undo-dynenv ((dynenv cc-bir:unwind-protect) tmv)
  (flet ((cleanup ()
           ;; This is maybe-entry for the sake of e.g.
           ;; (block nil (unwind-protect (... (return ...)) ... (return ...)))
           (cmp:with-landing-pad (maybe-entry-landing-pad
                                  (bir:parent dynenv) *tags*)
             (closure-call-or-invoke (dynenv-storage dynenv) nil))))
    ;; We have to save values around it if we're in the middle of
    ;; returning values.
    (if tmv
        (let* ((nvals (cmp:irc-tmv-nret tmv))
               (primary (cmp:irc-tmv-primary tmv))
               (mv-temp (cmp:alloca-temp-values nvals)))
          (%intrinsic-call "cc_save_values" (list nvals primary mv-temp))
          (cleanup)
          (%intrinsic-call "cc_load_values" (list nvals mv-temp)))
        (cleanup))))

(defmethod translate-terminator ((instruction cc-bir:bind) abi next)
  (declare (ignore abi))
  (let* ((inputs (bir:inputs instruction))
         (sym (in (first inputs)))
         (val (in (second inputs))))
    (setf (dynenv-storage instruction)
          (list sym (%intrinsic-call "cc_TLSymbolValue" (list sym))))
    (%intrinsic-call "cc_setTLSymbolValue" (list sym val)))
  (cmp:irc-br (first next)))

(defmethod undo-dynenv ((dynenv cc-bir:bind) tmv)
  (declare (ignore tmv))
  (%intrinsic-call "cc_resetTLSymbolValue" (dynenv-storage dynenv)))

(defmethod translate-terminator
    ((instruction cc-bir:header-stamp-case) abi next)
  (declare (ignore abi))
  (let* ((stamp (in (first (bir:inputs instruction))))
         (stamp-i64 (cmp:irc-ptr-to-int stamp cmp:%i64%))
         (where (cmp:irc-and stamp-i64 (%i64 cmp:+where-tag-mask+)))
         (defaultb (cmp:irc-basic-block-create "impossible-default"))
         (sw (cmp:irc-switch where defaultb 4)))
    (cmp:irc-add-case sw (%i64 cmp:+derivable-where-tag+) (first next))
    (cmp:irc-add-case sw (%i64 cmp:+rack-where-tag+) (second next))
    (cmp:irc-add-case sw (%i64 cmp:+wrapped-where-tag+) (third next))
    (cmp:irc-add-case sw (%i64 cmp:+header-where-tag+) (fourth next))
    (cmp:irc-begin-block defaultb)
    (cmp:irc-unreachable)))

(defmethod translate-simple-instruction ((instruction bir:thei) abi)
  (declare (ignore abi))
  (let ((input (first (bir:inputs instruction)))
        (output (first (bir:outputs instruction))))
    (out (in input) output)))

(defmethod translate-simple-instruction ((instruction bir:enclose) abi)
  (declare (ignore abi))
  (let ((output (first (bir:outputs instruction))))
    (out (enclose (find-llvm-function-info (bir:code instruction))
                  (bir:extent instruction))
         output)))

(defmethod translate-simple-instruction :before
    ((instruction bir:abstract-call) abi)
  (declare (ignore instruction abi))
  ;; We must force all closure initializers to run before a call.
  (force-initializers))

;; LETI is a subclass of WRITEVAR, so we use a :before to bind the var.
(defmethod translate-simple-instruction :before ((instruction bir:leti) abi)
  (declare (ignore abi))
  (bind-variable (first (bir:outputs instruction))))

(defmethod translate-simple-instruction ((instruction bir:writevar)
                                         abi)
  (declare (ignore abi))
  (let ((i (in (first (bir:inputs instruction)))))
    (unless (llvm-sys:type-equal cmp:%t*% (llvm-sys:get-type i))
      (cleavir-bir-disassembler:display
       (bir:module (bir:function instruction)))
      (error "~a has wrong rtype; definitions ~a with definition-rtypes ~a; input rtype ~a"
             (first (bir:inputs instruction))
             (bir:definitions (first (bir:inputs instruction)))
             (cleavir-set:mapset
              'list
              #'cc-bir-to-bmir::definition-rtype
              (bir:definitions (first (bir:inputs instruction))))
             (cc-bmir:rtype (first (bir:inputs instruction)))))
              
    (variable-out i (first (bir:outputs instruction)))))

(defmethod translate-simple-instruction ((instruction bir:readvar) abi)
  (declare (ignore abi))
  (out (variable-in (first (bir:inputs instruction)))
       (first (bir:outputs instruction))))

(defun gen-rest-list (present-arguments)
  (if (null present-arguments)
      (%nil)
      ;; Generate a call to cc_list.
      ;; TODO: DX &rest lists.
      (%intrinsic-invoke-if-landing-pad-or-call
       "cc_listSTAR" (list* (%size_t (length present-arguments))
                            (%nil) present-arguments))))

(defun parse-local-call-optional-arguments (nopt arguments)
  (loop repeat nopt
        if arguments
          collect (pop arguments)
          and collect (cmp::irc-t)
        else
          collect (cmp:irc-undef-value-get cmp:%t*%)
          and collect (%nil)))

;; Create than argument list for a local call by parsing the callee's
;; lambda list and filling in the correct values at compile time. We
;; assume that we have already checked the validity of this call.
(defun parse-local-call-arguments (nreq nopt rest arguments)
  (let* ((reqargs (subseq arguments 0 nreq))
         (more (nthcdr nreq arguments))
         (optargs (parse-local-call-optional-arguments nopt more))
         (rest
           (cond ((not rest) nil)
                 ((eq rest :unused)
                  (list (cmp:irc-undef-value-get cmp:%t*%)))
                 (t (list (gen-rest-list (nthcdr nopt more)))))))
    (append reqargs optargs rest)))

(defun enclose (code-info extent &optional (delay t))
  (let* ((environment (environment code-info))
         (enclosed-function (xep-function code-info))
         (function-description (xep-function-description code-info)))
    (when (eq enclosed-function :xep-unallocated)
      (error "BUG: Tried to ENCLOSE a function with no XEP"))
    (if environment
        (let* ((ninputs (length environment))
               (sninputs (%size_t ninputs))
               (enclose
                 (ecase extent
                   (:dynamic
                    (%intrinsic-call
                     "cc_stack_enclose"
                     (list (cmp:alloca-i8 (core:closure-with-slots-size ninputs)
                                           :alignment cmp:+alignment+
                                           :label "stack-allocated-closure")
                           enclosed-function
                           (cmp:irc-bit-cast function-description cmp:%i8*%)
                           sninputs)))
                   (:indefinite
                    (%intrinsic-invoke-if-landing-pad-or-call
                     "cc_enclose"
                     (list enclosed-function
                           (cmp:irc-bit-cast function-description cmp:%i8*%)
                           sninputs))))))
          ;; We may not initialize the closure immediately in case it partakes
          ;; in mutual reference.
          ;; (If DELAY NIL is passed this delay is not necessary.)
          (if delay
              (delay-initializer
               (lambda ()
                 (%intrinsic-invoke-if-landing-pad-or-call
                  "cc_initialize_closure"
                  (list* enclose sninputs
                         (mapcar #'variable-as-argument environment)))))
              (%intrinsic-invoke-if-landing-pad-or-call
               "cc_initialize_closure"
               (list* enclose sninputs
                      (mapcar #'variable-as-argument environment))))
          enclose)
        ;; When the function has no environment, it can be compiled and
        ;; referenced as literal.
        (%closurette-value enclosed-function function-description))))

(defun append-tmv (inputs)
  (cond ((null inputs) (cmp:irc-make-tmv (%size_t 0) (%nil)))
        ((not (null (rest inputs))) (values-collect-multi inputs))
        ((and (typep (first inputs) 'bir:output)
              (typep (bir:definition (first inputs))
                     'bir:values-save))
         (destructuring-bind (stackpos storage1 storage2)
             (dynenv-storage
              (bir:definition (first inputs)))
           (declare (ignore stackpos))
           (%intrinsic-call "cc_load_values" (list storage1 storage2))))
        ((equal (cc-bmir:rtype (first inputs)) '(:object))
         (cmp:irc-make-tmv (%size_t 1) (in (first inputs))))
        ((listp (cc-bmir:rtype (first inputs)))
         (fixed-to-mv (in (first inputs))))
        (t
         (assert (eq (cc-bmir:rtype (first inputs)) :multiple-values))
         (in (first inputs)))))

(defun gen-check-for-rest (fname min max nargs variable)
  ;; No &rest, so we might have to signal too-many-arguments.
  ;; We can know statically that there will always be an error
  ;; if there are any fixed arguments at all, but we let LLVM
  ;; figure that out with constant folding (hopefully) rather than
  ;; detect it ourselves.
  (let* ((sum (loop for inp in variable
                    for insize
                      = (cond ((and (typep inp 'bir:output)
                                    (typep (bir:definition inp)
                                           'bir:values-save))
                               (nth-value 1 (dynenv-storage
                                             (bir:definition inp))))
                              ((listp (cc-bmir:rtype inp))
                               (%size_t (length (cc-bmir:rtype inp))))
                              (t (cmp:irc-tmv-nret (in inp))))
                    do (setf nargs (cmp:irc-add nargs insize))))
         (too-many (cmp:irc-basic-block-create "local-too-many-args"))
         (just-right (cmp:irc-basic-block-create "local-enough-args"))
         (test (cmp:irc-icmp-eq sum (%size_t 0))))
    (cmp:irc-cond-br test just-right too-many)
    (cmp:irc-begin-block too-many)
    (let* ((lit (literal:reference-literal fname t))
           (vala (cmp:irc-gep-variable (literal:ltv-global)
                                       (list (%size_t 0) (%i64 lit))))
           (val (cmp:irc-load vala)))
      (%intrinsic-invoke-if-landing-pad-or-call "cc_wrong_number_of_arguments"
                                                (list val sum min max))
      (cmp:irc-unreachable))
    (cmp:irc-begin-block just-right)))

(defun variable-rest-list (inputs)
  ;; Should be more sophisticated later, e.g. elide values-list calls
  (let ((tmv (append-tmv inputs)))
    (%intrinsic-invoke-if-landing-pad-or-call
     "cc_mvc_GatherRest" (list (cmp:irc-tmv-nret tmv)
                               (cmp:irc-tmv-primary tmv)
                               (%size_t 0)))))

(defun variable-local-call-arguments (nreq nopt rest-id name fixed variable)
  (cond ((and (zerop nreq) (zerop nopt))
         ;; Just the &rest parameter.
         (cond ((null rest-id)
                (gen-check-for-rest name nreq (+ nreq nopt)
                                    (%size_t (length fixed)) variable)
                nil)
               ((eq rest-id :unused)
                (list (cmp:irc-undef-value-get cmp:%t*%)))
               (t ; cons up a &rest list
                (list
                 (if (null variable)
                     (gen-rest-list fixed)
                     (let ((rl (variable-rest-list variable)))
                       (if (null fixed)
                           rl
                           (%intrinsic-invoke-if-landing-pad-or-call
                            "cc_listSTAR" (list* (%size_t (length fixed))
                                                 rl fixed)))))))))
        (t
         (assert (null fixed))
         (if (null variable) ; no actual variable arguments - &rest list only
             (cond ((null rest-id) nil)
                   ((eq rest-id :unused)
                    (list (cmp:irc-undef-value-get cmp:%t*%)))
                   (t (list (%nil))))
             ;; Parsing the remaining required and optional arguments is pretty
             ;; involved. We paste all remaining arguments together in the mv
             ;; vector, and then do a switch on the count there.
             ;; There are possibly some situations in which this could be
             ;; handled more efficiently, but I think the added complexity isn't
             ;; worth it for something that only happens with rare
             ;; multiple-value-call uses to begin with.
             (local-mv-switch (append-tmv variable) name nreq nopt rest-id)))))

(defmethod translate-simple-instruction ((inst cc-bmir:local-call-arguments)
                                         (abi abi-x86-64))
  (let* ((callee (bir:callee inst))
         (lambda-list (bir:lambda-list inst))
         (callee-info (find-llvm-function-info callee))
         (vargs (mapcar #'variable-as-argument (environment callee-info)))
         (inputs (bir:inputs inst))
         ;; Collect all inputs with fixed rtype until we hit an unfixed one.
         (prefix (loop while inputs
                       when (listp (cc-bmir:rtype (first inputs)))
                         append (in (pop inputs))))
         (nfargs (length prefix))
         ;; And here are any remaining inputs, which may include both variable
         ;; and fixed inputs, but which are headed by a variable one so there's
         ;; at least some uncertainty.
         (variable inputs))
    (multiple-value-bind (req opt rest-var key-flag keyargs aok aux varest-p)
        (cmp::process-cleavir-lambda-list lambda-list)
      (declare (ignore keyargs aok aux))
      (assert (and (not key-flag) (not varest-p)))
      (let* ((nreq (car req)) (nopt (car opt))
             (nfixed (+ nreq nopt))
             (rest-id (cond ((null rest-var) nil)
                            ((bir:unused-p rest-var) :unused)
                            (t t)))
             ;; Required arguments from the fixed.
             (freq (subseq prefix (min nfargs nreq)))
             ;; Optional
             (fopt (loop with true = (cmp::irc-t)
                         repeat nopt ; upper limit
                         for a in (nthcdr (min nfargs nreq) prefix)
                         collect a collect true))
             (remaining-nreq (max (- nreq nfargs) 0)) ; req to supply from vars
             (remaining-nopt (max (- nopt (- nfargs nreq)) 0)))
        (append vargs freq fopt
                (variable-local-call-arguments
                 remaining-nreq remaining-nopt rest-id
                 (bir:name callee)
                 ;; Remaining invariable arguments, if any
                 (nthcdr nfixed prefix)
                 variable))))))

(defun gen-local-call (callee lisp-arguments)
  (let ((callee-info (find-llvm-function-info callee)))
    (cond ((lambda-list-too-hairy-p (bir:lambda-list callee))
           ;; Has &key or something, so use the normal call protocol.
           ;; We allocate a fresh closure for every call. Hopefully this
           ;; isn't too expensive. We can always use stack allocation since
           ;; there's no possibility of this closure being stored in a closure
           ;; (If we local-call a self-referencing closure, the closure cell
           ;;  will get its value from some enclose.
           ;;  FIXME we could use that instead?)
           (closure-call-or-invoke
            (enclose callee-info :dynamic nil)
            (mapcar #'in lisp-arguments)))
          (t
           ;; Call directly.
           ;; Note that Cleavir doesn't make local-calls if there's an
           ;; argcount mismatch, so we don't need to sweat that.
           (multiple-value-bind (req opt rest-var key-flag keyargs aok aux
                                 varest-p)
               (cmp::process-cleavir-lambda-list (bir:lambda-list callee))
             (declare (ignore keyargs aok aux))
             (assert (and (not key-flag) (not varest-p)))
             (let* ((rest-id (cond ((null rest-var) nil)
                                   ((bir:unused-p rest-var) :unused)
                                   (t t)))
                    (subargs
                      (parse-local-call-arguments
                       (car req) (car opt) rest-id
                       (mapcar #'in lisp-arguments)))
                    (args (append (mapcar #'variable-as-argument
                                          (environment callee-info))
                                  subargs))
                    (function (main-function callee-info))
                    (result-in-registers
                      (cmp::irc-call-or-invoke function args)))
               (llvm-sys:set-calling-conv result-in-registers 'llvm-sys:fastcc)
               result-in-registers))))))

(defmethod translate-simple-instruction ((instruction bir:local-call)
                                         abi)
  (declare (ignore abi))
  (out (gen-local-call (bir:callee instruction)
                       (rest (bir:inputs instruction)))
       (first (bir:outputs instruction))))

(defmethod translate-simple-instruction ((instruction bir:call) abi)
  (declare (ignore abi))
  (let* ((inputs (bir:inputs instruction))
         (iinputs (mapcar #'in inputs))
         (output (first (bir:outputs instruction))))
    (out (closure-call-or-invoke
          (first iinputs) (rest iinputs))
         output)))

(defun general-mv-local-call (callee-info tmv)
  (%intrinsic-invoke-if-landing-pad-or-call
   "cc_call_multipleValueOneFormCallWithRet0"
   (list (enclose callee-info :dynamic nil) tmv)))

;;; Given a T_mv reference and a lambda list shape, generate code to compute
;;; the arguments for that lambda list from those values.
;;; Returns a list of LLVM values, the arguments for the lambda list.
(defun local-mv-switch (tmv name nreq nopt rest-id)
  (let* ((rnret (cmp:irc-tmv-nret tmv))
         (rprimary (cmp:irc-tmv-primary tmv))
         (nfixed (+ nreq nopt))
         (mismatch
           (unless (and (zerop nreq) rest-id)
             (cmp:irc-basic-block-create "lmvc-arg-mismatch")))
         (mte (if rest-id
                  (cmp:irc-basic-block-create "lmvc-more-than-enough")
                  mismatch))
         (merge (cmp:irc-basic-block-create "lmvc-after"))
         (sw (cmp:irc-switch rnret mte (+ 1 nreq nopt))))
    (labels ((load-return-value (n)
               (if (zerop n)
                   rprimary
                   (cmp:irc-load (return-value-elt n))))
             (load-return-values (low high)
               (loop for i from low below high
                     collect (load-return-value i)))
             (optionals (n)
               (parse-local-call-optional-arguments
                nopt (load-return-values nreq (+ nreq n)))))
      ;; Generate phis for the merge block's call.
      (cmp:irc-begin-block merge)
      (let ((opt-phis
              (loop for i below nopt
                    collect (cmp:irc-phi cmp:%t*% (1+ nopt))
                    collect (cmp:irc-phi cmp:%t*% (1+ nopt))))
            (rest-phi
              (cond ((null rest-id) nil)
                    ((eq rest-id :unused) (cmp:irc-undef-value-get cmp:%t*%))
                    (t (cmp:irc-phi cmp:%t*% (1+ nopt))))))
        ;; Generate the mismatch block, if it exists.
        (when mismatch
          (cmp:irc-begin-block mismatch)
          (let* ((lit (literal:reference-literal name t))
                 ;; FIXME: Do this at higher level as a constant-reference
                 ;; thereby avoiding code duplication
                 (vala (cmp:irc-gep-variable (literal:ltv-global)
                                             (list (%size_t 0) (%i64 lit))))
                 (val (cmp:irc-load vala)))
            (cmp::irc-intrinsic-call-or-invoke
             "cc_wrong_number_of_arguments"
             (list val rnret (%size_t nreq) (%size_t nfixed)))
            (cmp:irc-unreachable)))
        ;; Generate not-enough-args cases.
        (loop for i below nreq
              do (cmp:irc-add-case sw (%size_t i) mismatch))
        ;; Generate optional arg cases, including the exactly-enough case.
        (loop for i upto nopt
              for b = (cmp:irc-basic-block-create
                       (format nil "lmvc-optional-~d" i))
              do (cmp:irc-add-case sw (%size_t (+ nreq i)) b)
                 (cmp:irc-begin-block b)
                 (loop for phi in opt-phis
                       for val in (optionals i)
                       do (cmp:irc-phi-add-incoming phi val b))
                 (when (and rest-id (not (eq :unused rest-id)))
                   (cmp:irc-phi-add-incoming rest-phi (%nil) b))
                 (cmp:irc-br merge))
        ;; If there's a &rest, generate the more-than-enough arguments case.
        (when rest-id
          (cmp:irc-begin-block mte)
          (loop for phi in opt-phis
                for val in (optionals nopt)
                do (cmp:irc-phi-add-incoming phi val mte))
          (unless (eq rest-id :unused)
            (cmp:irc-phi-add-incoming
             rest-phi
             (%intrinsic-invoke-if-landing-pad-or-call
              "cc_mvcGatherRest" (list rnret rprimary (%size_t nfixed)))
             mte))
          (cmp:irc-br merge))
        ;; Generate the call, in the merge block.
        (cmp:irc-begin-block merge)
        (nconc (loop for j below nreq collect (load-return-value j))
               opt-phis
               (when rest-id (list rest-phi)))))))

(defun direct-mv-local-call (tmv callee-info name nreq nopt rest-var)
  (let* ((arguments (local-mv-switch tmv name nreq nopt
                                     (cond ((null rest-var) nil)
                                           ((bir:unused-p rest-var) :unused)
                                           (t t))))
         (environment (environment callee-info))
         (rarguments
           (nconc (mapcar #'variable-as-argument environment) arguments))
         (function (main-function callee-info))
         (call (cmp::irc-call-or-invoke function rarguments)))
    (llvm-sys:set-calling-conv call 'llvm-sys:fastcc)
    call))

(defmethod translate-simple-instruction
    ((instruction bir:mv-local-call) abi)
  (declare (ignore abi))
  (let* ((output (first (bir:outputs instruction)))
         (callee (bir:callee instruction))
         (callee-info (find-llvm-function-info callee))
         (tmv (in (second (bir:inputs instruction)))))
    (multiple-value-bind (req opt rest-var key-flag keyargs aok aux varest-p)
        (cmp::process-cleavir-lambda-list (bir:lambda-list callee))
      (declare (ignore keyargs aok aux))
      (out (if (or key-flag varest-p)
               (general-mv-local-call callee-info tmv)
               (direct-mv-local-call
                tmv callee-info (bir:name callee) (car req) (car opt) rest-var))
           output))))

(defmethod translate-simple-instruction ((instruction bir:mv-call) abi)
  (declare (ignore abi))
  (let ((output (first (bir:outputs instruction))))
    (out (%intrinsic-invoke-if-landing-pad-or-call
          "cc_call_multipleValueOneFormCallWithRet0"
          (list (in (first (bir:inputs instruction)))
                (in (second (bir:inputs instruction)))))
         output)))

(defmethod translate-simple-instruction ((instruction cc-bir:mv-foreign-call)
                                         abi)
  (let ((output (first (bir:outputs instruction))))
    (out (unsafe-multiple-value-foreign-call
          (cc-bir:function-name instruction)
          (mapcar #'in (bir:inputs instruction)) abi)
         output)))

(defmethod translate-simple-instruction
    ((instruction cc-bir:foreign-call-pointer) abi)
  (let ((inputs (bir:inputs instruction))
        (output (first (bir:outputs instruction))))
    (out (clasp-cleavir:unsafe-foreign-call-pointer
          :call (cc-bir:foreign-types instruction) (in (first inputs))
          (mapcar #'in (rest inputs)) abi)
         output)))

(defmethod translate-simple-instruction
    ((instruction cc-bir:defcallback) (abi abi-x86-64))
  (let* ((args (cc-bir:defcallback-args instruction))
         (closure (in (first (bir:inputs instruction)))))
    (cmp::gen-defcallback
     (first args) (second args) (third args) (fourth args)
     (fifth args) (sixth args) (seventh args) (eighth args)
     closure)))

(defmethod translate-simple-instruction
    ((instruction bir:fixed-to-multiple) (abi abi-x86-64))
  (let* ((inputs (bir:inputs instruction))
         (output (first (bir:outputs instruction)))
         (outputrt (cc-bmir:rtype output))
         (ninputs (length inputs)))
    (assert (equal (length outputrt) ninputs))
    (out (if (= ninputs 1) (in (first inputs)) (mapcar #'in inputs)) output)))

(defun fixed-to-mv (values)
  (let ((nvalues (length values)))
    (cond ((zerop nvalues)
           (cmp:irc-make-tmv (%size_t nvalues) (%nil)))
          (t
           (loop for i from 1
                 for v in (rest values)
                 do (cmp:irc-store v (return-value-elt i)))
           (cmp:irc-make-tmv (%size_t nvalues) (first values))))))

(defmethod translate-simple-instruction ((instr cc-bmir:ftm) (abi abi-x86-64))
  (let* ((input (bir:input instr))
         (inputrt (cc-bmir:rtype input))
         (output (bir:output instr))
         (outputrt (cc-bmir:rtype output)))
    (assert (and (listp inputrt) (every (lambda (x) (eq x :object)) inputrt)))
    (assert (eq outputrt :multiple-values))
    (cond ((equal inputrt '(:object))
           (out (cmp:irc-make-tmv (%size_t 1) (in input)) output))
          (t (out (fixed-to-mv (in input)) output)))))

(defmethod translate-simple-instruction ((instr cc-bmir:mtf) (abi abi-x86-64))
  (assert (= (length (bir:outputs instr)) 1))
  (assert (equal (cc-bmir:rtype (bir:output instr)) '(:object)))
  (out (cmp:irc-tmv-primary (in (bir:input instr))) (bir:output instr)))

(defmethod translate-simple-instruction ((inst cc-bmir:fixed-values-pad) abi)
  (declare (ignore abi))
  (let* ((input (bir:input inst)) (ins (in input))
         (inputrt (cc-bmir:rtype input)) (ninputs (length inputrt))
         (output (bir:output inst))
         (outputrt (cc-bmir:rtype output)) (noutputs (length outputrt)))
    (out (cond ((equal outputrt '(:object))
                ;; Single value object rtypes are not represented as lists, so
                ;; they have to be handled a little specially
                (cond ((equal inputrt '(:object)) ins)
                      ((null inputrt) (%nil))
                      (t (first ins))))
               ((equal inputrt '(:object))
                (cond ((null outputrt) nil)
                      ;; outputrt = (:object) handled above
                      (t (list* ins (make-list (1- noutputs)
                                               :initial-element (%nil))))))
               ((< (length outputrt) (length inputrt))
                ;; Shrink
                (subseq ins 0 ninputs))
               (t ;; Expand
                (append ins (make-list (- noutputs ninputs)
                                       :initial-element (%nil)))))
         output)))

(defmethod translate-simple-instruction ((inst cc-bmir:memref2) abi)
  (declare (ignore abi))
  (out (cmp::gen-memref-address (in (first (bir:inputs inst)))
                                (cc-bmir:offset inst))
       (first (bir:outputs inst))))

(defmethod translate-simple-instruction ((inst cc-bmir:load) abi)
  (declare (ignore abi))
  (out (cmp:irc-load-atomic (in (first (bir:inputs inst)))
                            :order (cmp::order-spec->order (cc-bir:order inst)))
       (first (bir:outputs inst))))

(defmethod translate-simple-instruction ((inst cc-bmir:store) abi)
  (declare (ignore abi))
  (cmp:irc-store-atomic
   (in (first (bir:inputs inst)))
   (in (second (bir:inputs inst)))
   :order (cmp::order-spec->order (cc-bir:order inst))))

(defmethod translate-simple-instruction ((inst cc-bir:fence) abi)
  (declare (ignore abi))
  (cmp::gen-fence (cc-bir:order inst)))

(defmethod translate-simple-instruction ((inst cc-bmir:cas) abi)
  (declare (ignore abi))
  (out (cmp:irc-cmpxchg (in (first (bir:inputs inst)))
                        (in (second (bir:inputs inst)))
                        (in (third (bir:inputs inst)))
                        :order (cmp::order-spec->order (cc-bir:order inst)))
       (first (bir:outputs inst))))

(defmethod translate-simple-instruction ((inst bir:vprimop) abi)
  (declare (ignore abi))
  (translate-primop (cleavir-primop-info:name (bir:info inst)) inst))

(defmethod translate-primop ((name (eql 'symbol-value)) inst)
  (out (%intrinsic-invoke-if-landing-pad-or-call
        "cc_safe_symbol_value" (list (in (first (bir:inputs inst)))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'fdefinition)) inst)
  (let ((symbol (in (first (bir:inputs inst)))))
    (out (cmp:irc-fdefinition symbol) (first (bir:outputs inst)))))
(defmethod translate-primop ((name (eql 'cc-bir::setf-fdefinition)) inst)
  (let ((setf-symbol (in (first (bir:inputs inst))))
        (outp (first (bir:outputs inst))))
    (out (cmp:irc-setf-fdefinition setf-symbol) outp)))
(defmethod translate-primop ((name (eql 'core::vector-length)) inst)
  (out (cmp::gen-vector-length (in (first (bir:inputs inst))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core::%displacement)) inst)
  (out (cmp:irc-real-array-displacement (in (first (bir:inputs inst))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core::%displaced-index-offset)) inst)
  (out
   (cmp:irc-tag-fixnum
    (cmp:irc-real-array-index-offset (in (first (bir:inputs inst)))))
   (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core::%array-total-size)) inst)
  (out (cmp:irc-tag-fixnum
        (cmp:irc-array-total-size (in (first (bir:inputs inst)))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core::%array-rank)) inst)
  (out (cmp:irc-tag-fixnum
        (cmp:irc-array-rank (in (first (bir:inputs inst)))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core::%array-dimension)) inst)
  (out (cmp:gen-%array-dimension (in (first (bir:inputs inst)))
                                 (in (second (bir:inputs inst))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'cleavir-primop:slot-read)) inst)
  (out (cmp::gen-instance-ref (in (first (bir:inputs inst)))
                              (in (second (bir:inputs inst))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'cleavir-primop:slot-write)) inst)
  (let ((inputs (bir:inputs inst)))
    (cmp::gen-instance-set (in (first inputs)) (in (second inputs))
                           (in (third inputs)))))
(defmethod translate-primop ((name (eql 'core::instance-cas)) inst)
  (let ((inputs (bir:inputs inst)))
    (out (cmp::gen-instance-cas (in (third inputs)) (in (fourth inputs))
                                (in (first inputs)) (in (second inputs)))
         (first (bir:outputs inst)))))
(defmethod translate-primop ((name (eql 'core:vaslist-pop)) inst)
  (out (cmp:gen-vaslist-pop (in (first (bir:inputs inst))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core:vaslist-length)) inst)
  (out (cmp:gen-vaslist-length (in (first (bir:inputs inst))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core::header-stamp)) inst)
  (out (cmp:irc-header-stamp (in (first (bir:inputs inst))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core::rack-stamp)) inst)
  (out (cmp:irc-rack-stamp (in (first (bir:inputs inst))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core::wrapped-stamp)) inst)
  (out (cmp:irc-wrapped-stamp (in (first (bir:inputs inst))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core::derivable-stamp)) inst)
  (out (cmp:irc-derivable-stamp (in (first (bir:inputs inst))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core:instance-rack)) inst)
  (out (cmp:gen-instance-rack (in (first (bir:inputs inst))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core:instance-rack-set)) inst)
  (cmp:gen-instance-rack-set (in (first (bir:inputs inst)))
                             (in (second (bir:inputs inst)))))
(defmethod translate-primop ((name (eql 'core:rack-ref)) inst)
  (out (cmp:gen-rack-ref (in (first (bir:inputs inst)))
                         (in (second (bir:inputs inst))))
       (first (bir:outputs inst))))
(defmethod translate-primop ((name (eql 'core:rack-set)) inst)
  (cmp:gen-rack-set (in (first (bir:inputs inst)))
                    (in (second (bir:inputs inst)))
                    (in (third (bir:inputs inst)))))

(defmethod translate-primop ((name cons) inst) ; FIXME
  (cond ((equal name '(setf symbol-value))
         (%intrinsic-invoke-if-landing-pad-or-call
          "cc_setSymbolValue" (mapcar #'in (bir:inputs inst))))
        (t
         (error "BUG: Don't know how to translate primop ~a" name))))

(defmethod translate-simple-instruction ((inst cc-bir:atomic-rack-read) abi)
  (declare (ignore abi))
  (out (cmp:gen-rack-ref (in (first (bir:inputs inst)))
                         (in (second (bir:inputs inst)))
                         :order (cmp::order-spec->order (cc-bir:order inst)))
       (first (bir:outputs inst))))
(defmethod translate-simple-instruction ((inst cc-bir:atomic-rack-write) abi)
  (declare (ignore abi))
  (cmp:gen-rack-set (in (second (bir:inputs inst)))
                    (in (third (bir:inputs inst)))
                    (in (first (bir:inputs inst)))
                    :order (cmp::order-spec->order (cc-bir:order inst))))
(defmethod translate-simple-instruction ((inst cc-bir:cas-rack) abi)
  (declare (ignore abi))
  (out (cmp:irc-cmpxchg (cmp::irc-rack-slot-address
                         (in (third (bir:inputs inst)))
                         (cmp::irc-untag-fixnum
                          (in (fourth (bir:inputs inst)))
                          cmp:%size_t% "slot-location"))
                        (in (first (bir:inputs inst)))
                        (in (second (bir:inputs inst)))
                        :order (cmp::order-spec->order (cc-bir:order inst)))
       (first (bir:outputs inst))))

(defun gen-vector-effective-address (array index element-type fixnum-type)
  (let* ((type (llvm-sys:type-get-pointer-to
                (cmp::simple-vector-llvm-type element-type)))
         (cast (cmp:irc-bit-cast array type))
         (untagged (cmp:irc-untag-fixnum index fixnum-type "vector-index")))
    ;; 0 is for LLVM reasons, that pointers are C arrays. or something.
    ;; For layout of the vector, check simple-vector-llvm-type's definition.
    ;; untagged is the actual offset.
    (cmp:irc-gep-variable
     cast
     (list (%i32 0) (%i32 cmp::+simple-vector-data-slot+) untagged) "aref")))

(defmethod translate-simple-instruction ((inst cc-bir:vref) abi)
  (let ((inputs (bir:inputs inst)))
    (out (cmp:irc-load-atomic
          (gen-vector-effective-address
           (in (first inputs)) (in (second inputs)) (cc-bir:element-type inst)
           (%default-int-type abi))
          :order (cmp::order-spec->order (cc-bir:order inst)))
         (first (bir:outputs inst)))))
(defmethod translate-simple-instruction ((inst cc-bir:vset) abi)
  (let ((inputs (bir:inputs inst)))
    (cmp:irc-store-atomic
     (in (first inputs))
     (gen-vector-effective-address
      (in (second inputs)) (in (third inputs)) (cc-bir:element-type inst)
      (%default-int-type abi))
     :order (cmp::order-spec->order (cc-bir:order inst)))))
(defmethod translate-simple-instruction ((inst cc-bir:vcas) abi)
  (let ((et (cc-bir:element-type inst))
        (inputs (bir:inputs inst)))
    (out (cmp:irc-cmpxchg
          ;; This will err if et = bit or the like.
          (gen-vector-effective-address
           (in (third inputs)) (in (fourth inputs)) et
           (%default-int-type abi))
          (in (first inputs)) (in (second inputs)))
         (first (bir:outputs inst)))))

(defun values-collect-multi (inputs)
  ;; First, assert that there's only one input that isn't a values-save.
  (loop with seen-non-save = nil
        for input in inputs
        for outp = (typep input 'bir:output)
        for inst = (and outp (bir:definition input))
        if (not (or (typep inst 'bir:values-save)
                    (listp (cc-bmir:rtype input))))
          do (if seen-non-save
                 (error "BUG: Can only have one variable non-save-values input, but saw ~a and ~a!" inst seen-non-save)
                 (setf seen-non-save inst)))
  (let* ((liven nil) ; index for the :variable storage.
         ;; Collect the form of each input.
         ;; Each datum is (symbol nvalues extra).
         ;; For saved values, the extra is the storage for it. For the current
         ;; values the extra is the primary value (since it's stored
         ;; separately)
         (data (loop for idx from 0
                     for input in inputs
                     for outputp = (typep input 'bir:output)
                     for inst = (and outputp (bir:definition input))
                     collect (cond ((typep inst 'bir:values-save)
                                    (list* :saved
                                           (rest (dynenv-storage inst))))
                                   ((listp (cc-bmir:rtype input))
                                    (let ((len (length (cc-bmir:rtype input)))
                                          (in (in input)))
                                      (list :fixed
                                            (%size_t len)
                                            (list* len (if (= len 1)
                                                           (list in)
                                                           in)))))
                                   (t
                                    (setf liven idx)
                                    (let ((i (in input)))
                                      (list :variable
                                            (cmp:irc-tmv-nret i)
                                            (cmp:irc-tmv-primary i)))))))
         ;; Collect partial sums of the number of values.
         (partial-sums
           (loop for (_1 size _2) in data
                 for n = size then (cmp:irc-add n size)
                 collect n))
         (n-total-values (first (last partial-sums)))
         ;; LLVM type is t**, i.e. this is a pointer to the 0th value.
         (valvec (%gep cmp:%t*[0]*% (multiple-value-array-address) '(0 0))))
    ;; Generate code to copy all the values into the temp storage.
    ;; First we need to move any live values, since otherwise they could be
    ;; overridden, unless they're at zero position since then they're already
    ;; in place. (in practice, this never happens right now, but maybe later?)
    (when (and liven (not (zerop liven)))
      (destructuring-bind (size primary) (rest (nth liven data))
        (let* ((spos (nth (1- liven) partial-sums))
               (sdest (cmp:irc-gep-variable valvec (list spos)))
               ;; Add one, since we store the primary separately
               (dest (%gep cmp:%t**% sdest '(1))))
          ;; Store the primary
          (cmp:irc-store primary (cmp:irc-gep-variable valvec (list spos)))
          ;; Copy the rest
          (%intrinsic-call "llvm.memmove.p0i8.p0i8.i64"
                           (list (cmp:irc-bit-cast dest cmp:%i8*%)
                                 ;; read from the start of the mv vector
                                 (cmp:irc-bit-cast valvec cmp:%i8*%)
                                 ;; Multiply size by sizeof(T_O*)
                                 ;; (subtract one for the primary, again)
                                 (cmp::irc-shl
                                  (cmp::irc-sub size (%size_t 1)) 3 :nuw t)
                                 ;; non volatile
                                 (%i1 0))))))
    ;; Now copy the rest
    (loop for (key size extra) in data
          for startn = (%size_t 0) then finishn
          for finishn in partial-sums
          for dest = (cmp:irc-gep-variable valvec (list startn))
          do (ecase key
               ((:saved)
                (%intrinsic-call "llvm.memcpy.p0i8.p0i8.i64"
                                 (list (cmp:irc-bit-cast dest cmp:%i8*%)
                                       (cmp:irc-bit-cast extra cmp:%i8*%)
                                       ;; Multiply by sizeof(T_O*)
                                       (cmp::irc-shl size 3 :nuw t)
                                       (%i1 0))))
               ((:fixed)
                (loop for i below (first extra) ; size
                      for v in (rest extra)
                      do (cmp:irc-store v (%gep cmp:%t**% dest (list i)))))
               ((:variable)))) ; done already
    ;; Now just return a T_mv. We load the primary from the vector again, which
    ;; is technically slightly inefficient.
    (cmp:irc-make-tmv n-total-values (cmp:irc-load valvec))))

(defmethod translate-simple-instruction ((inst bir:values-collect) abi)
  (declare (ignore abi))
  (out (append-tmv (bir:inputs inst)) (first (bir:outputs inst))))

(defmethod translate-simple-instruction
    ((inst bir:load-time-value-reference) abi)
  (declare (ignore abi))
  (out (let* ((ltv (first (bir:inputs inst)))
              (index (gethash ltv *constant-values*))
              (label ""))
         (cmp:irc-load
          (cmp:irc-gep-variable (literal:ltv-global)
                                (list (%size_t 0)
                                      (%i64 index))
                                label)))
       (first (bir:outputs inst))))

(defmethod translate-simple-instruction ((inst bir:constant-reference)
                                         abi)
  (declare (ignore abi))
  (out (let* ((constant (first (bir:inputs inst)))
              (immediate-or-index (gethash constant *constant-values*)))
         (assert immediate-or-index () "Constant not found!")
         (if (integerp immediate-or-index)
             (cmp:irc-load
              (cmp:irc-gep-variable (literal:ltv-global)
                                    (list (%size_t 0)
                                          (%i64 immediate-or-index))
                                    ;; Maybe we can have a nice label for this.
                                    ""))
             immediate-or-index))
       (first (bir:outputs inst))))

(defun initialize-iblock-translation (iblock)
  (let ((phis (bir:inputs iblock)))
    (unless (null phis)
      (cmp:irc-begin-block (iblock-tag iblock))
      (let ((ndefinitions (+ (cleavir-set:size (bir:predecessors iblock))
                             (cleavir-set:size (bir:entrances iblock)))))
        (loop for phi in phis
              for rt = (cc-bmir:rtype phi)
              for dat
                = (cond ((eq rt :multiple-values)
                         (cmp:irc-phi cmp::%tmv% ndefinitions))
                        ((equal rt '(:object))
                         (cmp:irc-phi cmp:%t*% ndefinitions))
                        ((and (listp rt)
                              (every (lambda (x) (eq x :object)) rt))
                         (loop repeat (length rt)
                               collect (cmp:irc-phi cmp:%t*% ndefinitions)))
                        (t (error "BUG: Bad rtype ~a" rt)))
              do (setf (gethash phi *datum-values*) dat))))))

(defun layout-iblock (iblock abi)
  (cmp:irc-begin-block (iblock-tag iblock))
  (cmp:with-landing-pad (maybe-entry-landing-pad
                         (bir:dynamic-environment iblock) *tags*)
    (let ((*enclose-initializers* '()))
      (loop with end = (bir:end iblock)
            for instruction = (bir:start iblock)
              then (bir:successor instruction)
            until (eq instruction end)
            do (translate-simple-instruction instruction abi)
            finally (progn
                      (force-initializers)
                      (translate-terminator
                       instruction abi
                       (mapcar #'iblock-tag (bir:next end))))))))

(defun function-source-pos-info (irfunction)
  (ensure-origin (origin-spi (bir:origin irfunction)) 999909))

(defun calculate-function-info (irfunction lambda-name)
  (let* ((origin (bir:origin irfunction))
         (spi (origin-spi origin)))
    (cmp:make-function-info
     :function-name lambda-name
     :lambda-list (bir:original-lambda-list irfunction)
     :docstring (bir:docstring irfunction)
     :declares nil
     :form nil
     :spi spi)))

(defun iblock-name (iblock)
  (let ((name (bir:name iblock)))
    (if name
        (string-downcase (symbol-name name))
        "iblock")))

(defun layout-xep-function* (the-function ir calling-convention abi)
  (declare (ignore abi))
  (cmp:with-irbuilder (cmp:*irbuilder-function-alloca*)
      ;; Parse lambda list.
    (cmp:compile-lambda-list-code (bir:lambda-list ir)
                                  calling-convention
                                  :argument-out #'out)
    ;; Import cells.
    (let* ((closure-vec (first (llvm-sys:get-argument-list the-function)))
           (llvm-function-info (find-llvm-function-info ir))
           (environment-values
             (loop for import in (environment llvm-function-info)
                   for i from 0
                   for offset = (cmp:%closure-with-slots%.offset-of[n]/t* i)
                   collect (cmp:irc-load-atomic
                            (cmp::gen-memref-address closure-vec offset)))))
      ;; Tail call the real function.
      (cmp:with-debug-info-source-position
          ((core:make-source-pos-info "no-source-info-available" 999905 999905 999905))
        (cmp:irc-ret
         (let ((c
                 (cmp:irc-create-call
                  (main-function llvm-function-info)
                  ;; Augment the environment lexicals as a local call would.
                  (nconc environment-values
                         (mapcar #'in (arguments llvm-function-info))))))
           (llvm-sys:set-calling-conv c 'llvm-sys:fastcc)
           c)))))
  the-function)

(defun layout-main-function* (the-function ir
                              body-irbuilder body-block
                              abi &key (linkage 'llvm-sys:internal-linkage))
  (declare (ignore linkage))
  (cmp:with-irbuilder (cmp:*irbuilder-function-alloca*)
    (cmp:with-irbuilder (body-irbuilder)
      (with-catch-pad-prep
          (cmp:irc-begin-block body-block)
        (cmp:with-landing-pad (never-entry-landing-pad ir)
          ;; Bind the arguments and the environment values
          ;; appropriately.
          (let ((llvm-function-info (find-llvm-function-info ir)))
            (loop for arg in (llvm-sys:get-argument-list the-function)
                  for lexical in (append (environment llvm-function-info)
                                         (arguments llvm-function-info))
                  do (setf (gethash lexical *datum-values*) arg)))
          ;; Branch to the start block.
          (cmp:irc-br (iblock-tag (bir:start ir)))
          ;; Lay out blocks.
          (bir:do-iblocks (ib ir)
            (layout-iblock ib abi))))))
  ;; Finish up by jumping from the entry block to the body block
  (cmp:with-irbuilder (cmp:*irbuilder-function-alloca*)
    (cmp:irc-br body-block))
  the-function)

(defun layout-xep-function (function lambda-name abi)
  (let* ((*datum-values* (make-hash-table :test #'eq))
         (llvm-function-name (cmp:jit-function-name lambda-name))
         (cmp:*current-function-name* llvm-function-name)
         (cmp:*gv-current-function-name*
           (cmp:module-make-global-string llvm-function-name "fn-name"))
         (llvm-function-type cmp:%fn-prototype%)
         (function-info (find-llvm-function-info function))
         (xep-function (xep-function function-info))
         (xep-function-description (xep-function-description function-info))
         (cmp:*current-function* xep-function)
         (cmp:*current-function-description* xep-function-description)
         (entry-block (cmp:irc-basic-block-create "entry" xep-function))
         (*function-current-multiple-value-array-address*
           nil)
         (cmp:*irbuilder-function-alloca*
           (llvm-sys:make-irbuilder (cmp:thread-local-llvm-context)))
         (source-pos-info (function-source-pos-info function))
         (lineno (core:source-pos-info-lineno source-pos-info)))
    (cmp:with-dbg-function (:lineno lineno :linkage-name llvm-function-name
                            :function-type llvm-function-type
                            :function xep-function)
      (llvm-sys:set-personality-fn xep-function
                                   (cmp:irc-personality-function))
      (llvm-sys:add-fn-attr xep-function 'llvm-sys:attribute-uwtable)
      (cmp:irc-set-insert-point-basic-block entry-block
                                            cmp:*irbuilder-function-alloca*)
      (cmp:with-irbuilder (cmp:*irbuilder-function-alloca*)
        (cmp:with-debug-info-source-position (source-pos-info)
          (let* ((fn-args (llvm-sys:get-argument-list xep-function))
                 (lambda-list (bir:lambda-list function))
                 (calling-convention
                   (cmp:setup-calling-convention
                    fn-args
                    :debug-on
                    (cleavir-policy:policy-value
                     (bir:policy function)
                     'save-register-args)
                    :cleavir-lambda-list lambda-list)))
            (layout-xep-function* xep-function function calling-convention abi)))))))

(defun layout-main-function (function lambda-name abi
                             &aux (linkage 'llvm-sys:private-linkage))
  (let* ((*tags* (make-hash-table :test #'eq))
         (*datum-values* (make-hash-table :test #'eq))
         (*dynenv-storage* (make-hash-table :test #'eq))
         (llvm-function-name (cmp:jit-function-name lambda-name))
         (cmp:*current-function-name* llvm-function-name)
         (cmp:*gv-current-function-name*
           (cmp:module-make-global-string llvm-function-name "fn-name"))
         (llvm-function-type cmp:%fn-prototype%)
         (function-info (find-llvm-function-info function))
         (the-function (main-function function-info))
         (function-description (main-function-description function-info))
         (cmp:*current-function* the-function)
         (cmp:*current-function-description* function-description)
         (entry-block (cmp:irc-basic-block-create "entry" the-function))
         (*function-current-multiple-value-array-address*
           nil)
         (cmp:*irbuilder-function-alloca*
           (llvm-sys:make-irbuilder (cmp:thread-local-llvm-context)))
         (body-irbuilder (llvm-sys:make-irbuilder
                          (cmp:thread-local-llvm-context)))
         (body-block (cmp:irc-basic-block-create "body"))
         (source-pos-info (function-source-pos-info function))
         (lineno (core:source-pos-info-lineno source-pos-info)))
    (cmp:with-dbg-function (:lineno lineno :linkage-name llvm-function-name
                            :function-type llvm-function-type
                            :function the-function)
      (llvm-sys:set-calling-conv the-function 'llvm-sys:fastcc)
      (llvm-sys:set-personality-fn the-function
                                   (cmp:irc-personality-function))
      (llvm-sys:add-fn-attr the-function 'llvm-sys:attribute-uwtable)
      (cmp:with-irbuilder (body-irbuilder)
        (bir:map-iblocks
         (lambda (ib)
           (setf (gethash ib *tags*)
                 (cmp:irc-basic-block-create
                  (iblock-name ib)))
           (initialize-iblock-translation ib))
         function))
      (cmp:irc-set-insert-point-basic-block entry-block
                                            cmp:*irbuilder-function-alloca*)
      (cmp:with-irbuilder (cmp:*irbuilder-function-alloca*)
        (cmp:with-debug-info-source-position (source-pos-info)
          (cmp:with-dbg-lexical-block
              (:lineno (core:source-pos-info-lineno source-pos-info))
            
            (layout-main-function* the-function function
                                   body-irbuilder body-block
                                   abi :linkage linkage)))))))

(defun layout-procedure (function lambda-name abi
                         &key (linkage 'llvm-sys:internal-linkage))
  (declare (ignore linkage))
  (when (xep-needed-p function)
    (layout-xep-function function lambda-name abi))
  (layout-main-function function lambda-name abi))

(defun get-or-create-lambda-name (bir)
  (or (bir:name bir) 'top-level))

;;; Given a BIR module, allocate its constants and load time
;;; values. We translate immediates directly, and use an index into
;;; the literal table for non-immediate constants.
(defun allocate-module-constants (module)
  (cleavir-set:doset (constant (bir:constants module))
    (let* ((value (bir:constant-value constant))
           (immediate (core:create-tagged-immediate-value-or-nil value)))
      (setf (gethash constant *constant-values*)
            (if immediate
                (cmp:irc-int-to-ptr
                 (%i64 immediate)
                 cmp:%t*%)
                (literal:reference-literal value t)))))
  (assert (or (cleavir-set:empty-set-p (bir:load-time-values module))
              (eq cst-to-ast:*compiler* 'cl:compile-file))
          ()
          "Found load-time-values to dump but not file compiling!")
  (cleavir-set:doset (load-time-value (bir:load-time-values module))
    (let ((form (bir:form load-time-value)))
      (setf (gethash load-time-value *constant-values*)
            ;; Allocate an index in the literal table for this load-time-value.
            (literal:load-time-value-from-thunk
             (compile-form form *clasp-env*))))))

(defun layout-module (module abi &key (linkage 'llvm-sys:internal-linkage))
  ;; Create llvm IR functions for each BIR function.
  (bir:do-functions (function module)
    ;; Assign IDs to unwind destinations.
    (let ((i 0))
      (cleavir-set:doset (entrance (bir:entrances function))
        (setf (gethash entrance *unwind-ids*) i)
        (incf i)))
    (setf (gethash function *function-info*)
          (allocate-llvm-function-info function :linkage linkage)))
  (allocate-module-constants module)
  (bir:do-functions (function module)
    (layout-procedure function (get-or-create-lambda-name function)
                      abi :linkage linkage)))

(defun translate (bir &key abi linkage)
  (let* ((*unwind-ids* (make-hash-table :test #'eq))
         (*function-info* (make-hash-table :test #'eq))
         (*constant-values* (make-hash-table :test #'eq)))
    (layout-module (bir:module bir) abi :linkage linkage)
    (cmp::potentially-save-module)
    (xep-function (find-llvm-function-info bir))))

(defun conversion-error-handler (condition)
  ;; Resignal the condition to see if anything higher up wants to handle it.
  ;; If not, continue compilation by replacing the errant form with a form
  ;; that will signal an error if it's reached at runtime.
  ;; The nature of this form is a bit tricky because it can't just include
  ;; the original condition, if we're in COMPILE-FILE - conditions aren't
  ;; necessarily dumpable, and nor is the source.
  ;; For now we just assume we're in COMPILE-FILE.
  (signal condition)
  (let* ((cst (cst-to-ast:cst condition))
         (form (cst:raw cst))
         (origin (cst:source cst)))
    (invoke-restart 'cst-to-ast:substitute-cst
                    (cst:reconstruct
                     `(error 'cmp:compiled-program-error
                             :form ,(with-standard-io-syntax
                                      (write-to-string form
                                                       :escape t :pretty t
                                                       :circle t :array nil))
                             :origin ',(origin-spi origin)
                             :condition ,(princ-to-string condition))
                     cst clasp-cleavir:*clasp-system* :default-source origin))))

(defun cst->ast (cst &optional (env *clasp-env*))
  "Compile a cst into an AST and return it.
Does not hoist.
COMPILE might call this with an environment in ENV.
COMPILE-FILE will use the default *clasp-env*."
  (handler-bind
      ((cst-to-ast:no-variable-info
         (lambda (condition)
           (cmp:warn-undefined-global-variable
            (origin-spi (cleavir-conditions:origin condition))
            (cst-to-ast:name condition))
           (invoke-restart 'cst-to-ast:consider-special)))
       (cst-to-ast:no-function-info
         (lambda (condition)
           (cmp:register-global-function-ref
            (cst-to-ast:name condition)
            (origin-spi (cleavir-conditions:origin condition)))
           (invoke-restart 'cst-to-ast:consider-global)))
       (cst-to-ast:compiler-macro-expansion-error
         (lambda (condition)
           (warn 'cmp:compiler-macro-expansion-error-warning
                 :origin (origin-spi (cst:source (cst-to-ast:cst condition)))
                 :condition condition)
           (continue condition)))
       ((and cst-to-ast:compilation-program-error
             ;; If something goes wrong evaluating an eval-when,
             ;; we just want a normal error signal-
             ;; we can't recover and keep compiling.
             (not cst-to-ast:eval-error))
         #'conversion-error-handler))
    (cst-to-ast:cst-to-ast cst env clasp-cleavir:*clasp-system*)))

;;; Given an AST that may not be a function-ast, wrap it
;;; in a function AST. Useful for the pattern of
;;; (eval form) = (funcall (compile nil `(lambda () ,form)))
;;; as this essentially does the lambda wrap.
(defun wrap-ast (ast)
  (ast:make-function-ast
   ast nil
   :origin (ast:origin ast)
   :policy (ast:policy ast)))

(defun ast->bir (ast system)
  (cleavir-ast-to-bir:compile-toplevel ast system))

(defvar *dis* nil)

(defun ver (module msg)
  (handler-bind
      ((error
         (lambda (e)
           (declare (ignore e))
           (warn msg))))
    (cleavir-bir:verify module)))

(defun bir-transformations (module system)
  (ver module "start")
  (when *dis* (cleavir-bir-disassembler:display module))
  (bir-transformations:module-eliminate-catches module)
  (ver module "elim catches")
  (bir-transformations:find-module-local-calls module)
  (ver module "local calls")
  (bir-transformations:module-optimize-variables module)
  (ver module "optimize vars")
  (bir-transformations:meta-evaluate-module module system)
  (ver module "meta")
  (cc-bir-to-bmir:reduce-module-typeqs module)
  (cc-bir-to-bmir:reduce-module-primops module)
  (bir-transformations:module-generate-type-checks module)
  (cc-bir-to-bmir:assign-module-rtypes module)
  (cc-bir-to-bmir:insert-values-coercion-into-module module)
  ;; These should happen last since they are like "post passes" which
  ;; do not modify the flow graph.
  ;; NOTE: These must come in this order to maximize analysis.
  (bir-transformations:determine-function-environments module)
  (bir-transformations:determine-closure-extents module)
  (bir-transformations:determine-variable-extents module)
  (when *dis* (cleavir-bir-disassembler:display module))
  (values))

(defun translate-ast (ast &key (abi *abi-x86-64*)
                               (linkage 'llvm-sys:internal-linkage)
                               (system *clasp-system*))
  (let* ((bir (ast->bir ast system))
         (module (bir:module bir)))
    ;;(bir:verify module)
    (bir-transformations module system)
    (bir:verify module)
    (translate bir :abi abi :linkage linkage)))

(defun bir-compile (form env pathname
                    &key (linkage 'llvm-sys:internal-linkage))
  (bir-compile-cst (cst:cst-from-expression form) env pathname :linkage linkage))

(defun bir-compile-cst (cst env pathname
                        &key (linkage 'llvm-sys:internal-linkage))
  (declare (ignore linkage))
  (let* (function
         ordered-raw-constants-list constants-table startup-fn shutdown-fn
         (cst-to-ast:*compiler* 'cl:compile)
         (ast (cst->ast cst env)))
    (declare (ignorable constants-table))
    (cmp:with-debug-info-generator (:module cmp:*the-module* :pathname pathname)
      (multiple-value-setq (ordered-raw-constants-list constants-table startup-fn shutdown-fn)
        (literal:with-rtv
            (setq function (translate-ast ast)))))
    (unless function
      (error "There was no function returned by translate-ast"))
    ;;(llvm-sys:dump-module cmp:*the-module* *standard-output*)
    (cmp:jit-add-module-return-function
     cmp:*the-module*
     function startup-fn shutdown-fn ordered-raw-constants-list)))

(defun bir-compile-in-env (form &optional env)
  (bir-compile-cst-in-env (cst:cst-from-expression form) env))

(defun bir-compile-cst-in-env (cst &optional env)
  (let ((cst-to-ast:*compiler* 'cl:compile)
        (core:*use-cleavir-compiler* t))
    (cmp:compile-in-env cst env #'bir-compile-cst cmp:*default-compile-linkage*)))

(defun compile-form (form &optional (env *clasp-env*))
  (let* ((cst (cst:cst-from-expression form))
         (pre-ast (cst->ast cst env))
         (ast (wrap-ast pre-ast)))
    (translate-ast ast)))

(defun compile-file-cst (cst &optional (env *clasp-env*))
  (let* ((cmp:*default-condition-origin* (origin-spi (cst:source cst)))
         (pre-ast (cst->ast cst env))
         (ast (wrap-ast pre-ast)))
    (literal:arrange-thunk-as-top-level
     (translate-ast ast :linkage cmp:*default-linkage*))))

(defun bir-loop-read-and-compile-file-forms (source-sin environment)
  (let ((eof-value (gensym))
        (eclector.reader:*client* *cst-client*)
        (eclector.readtable:*readtable* cl:*readtable*)
        (cst-to-ast:*compiler* 'cl:compile-file)
        (core:*use-cleavir-compiler* t))
    (loop
      ;; Required to update the source pos info. FIXME!?
      (peek-char t source-sin nil)
      ;; FIXME: if :environment is provided we should probably use a different read somehow
      (let* ((core:*current-source-pos-info* (cmp:compile-file-source-pos-info source-sin))
             (cst (eclector.concrete-syntax-tree:cst-read source-sin nil eof-value)))
        #+debug-monitor(sys:monitor-message "source-pos ~a" core:*current-source-pos-info*)
        (if (eq cst eof-value)
            (return nil)
            (progn
              (when *compile-print* (cmp::describe-form (cst:raw cst)))
              (core:with-memory-ramp (:pattern 'gctools:ramp)
                (compile-file-cst cst environment))))))))
