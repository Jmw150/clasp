(in-package #:cmp)

;;;; Top-level interface: CL:COMPILE

;;; Use the *cleavir-compile-hook* to determine which compiler to use
;;; if nil == bclasp. Code for the bclasp compiler is in codegen.lisp;
;;; look for bclasp-compile*.

(defparameter *lambda-args-num* 0)

(defmacro with-module (( &key module
                           (optimize nil)
                           (optimize-level '*optimization-level*)
                           dry-run) &rest body)
  `(let* ((*the-module* ,module))
     (or *the-module* (error "with-module *the-module* is NIL"))
     (multiple-value-prog1
         (with-irbuilder ((llvm-sys:make-irbuilder (thread-local-llvm-context)))
           ,@body)
       (cmp-log "About to optimize-module%N")
       ;;(cmp-log-dump-module ,module)
       (when (and ,optimize ,optimize-level (null ,dry-run)) (funcall ,optimize ,module ,optimize-level )))))

;;; See NOTE on compile-in-env below.
(defun compile-with-hook (compile-hook definition env pathname
                          &key (linkage 'llvm-sys:internal-linkage) name)
  "Dispatch to clasp compiler or cleavir-clasp compiler if available.
We could do more fancy things here - like if cleavir-clasp fails, use the clasp compiler as backup."
  (with-compilation-results ()
    (if compile-hook
        (funcall compile-hook definition env pathname
                 :linkage linkage :name name)
        (bclasp-compile* definition env pathname :linkage linkage :name name))))

;;; NOTE: cclasp may pass a definition that is a CST or AST.
;;; As such, this function should probably not examine the definition at all.
(defun compile-in-env (definition env
                       &optional (compile-hook *cleavir-compile-hook*)
                         (linkage 'llvm-sys:internal-linkage) name)
  "Compile in the given environment"
  (with-compiler-env ()
    (let* ((module (create-run-time-module-for-compile)))
      ;; Link the C++ intrinsics into the module
      (with-module (:module module
                    :optimize nil)
        (cmp-log "Dumping module%N")
        (cmp-log-dump-module module)
        (let ((pathname (if *load-pathname* (namestring *load-pathname*) "repl-code")))
          (compile-with-hook compile-hook definition env pathname :linkage linkage :name name))))))

(defun compile (name &optional definition)
  (multiple-value-bind (function warnp failp)
      ;; Get the actual compiled function and warnp+failp.
      (cond
        ((compiled-function-p definition)
         (values definition nil nil))
        ((interpreted-function-p definition)
         ;; Recover the lambda-expression from the interpreted-function
         (multiple-value-bind (lambda-expression wrapped-env)
             (generate-lambda-expression-from-interpreted-function definition)
           (cmp-log "About to compile  name: {}  lambda-expression: {} wrapped-env: {}%N" name lambda-expression wrapped-env)
           (compile-in-env lambda-expression wrapped-env *cleavir-compile-hook* 'llvm-sys:external-linkage name)))
        ((functionp definition)
         (error "COMPILE doesn't know how to handle this type of function"))
        ((and (consp definition) (eq (car definition) 'lambda))
         (cmp-log "compile form: {}%N" definition)
         (compile-in-env definition nil *cleavir-compile-hook* 'llvm-sys:internal-linkage name))
        ((null definition)
         (let ((func (cond ((fboundp name) (fdefinition name))
                           ((and (symbolp name) (macro-function name)))
                           (t (error "No definition for ~a" name)))))
           (cond
             ((interpreted-function-p func)
              ;; Recover the lambda-expression from the interpreted-function
              (multiple-value-bind (lambda-expression wrapped-env)
                  (generate-lambda-expression-from-interpreted-function func)
                (cmp-log "About to compile  name: {}  lambda-expression: {} wrapped-env: {}%N" name lambda-expression wrapped-env)
                (compile-in-env lambda-expression wrapped-env *cleavir-compile-hook* 'llvm-sys:internal-linkage name)))
             ((compiled-function-p func)
              (values func nil nil))
             ((core:instancep func) ; FIXME: funcallable-instance-p, probably
              (let ((user-func (clos:get-funcallable-instance-function func)))
                (when (and user-func (interpreted-function-p user-func))
                  (let ((compiled-user-func (compile nil user-func)))
                    (when (not (eq user-func compiled-user-func))
                      (clos:set-funcallable-instance-function func compiled-user-func)))))
              (values func nil nil))
             (t (error "COMPILE doesn't know how to handle this type of function")))))
        (t (error "Illegal combination of arguments for compile: ~a ~a, class-of definition ~a" name definition (class-of definition))))
    ;; Bind the name if applicable.
    (cond ((and (symbolp name) (macro-function name))
           (setf (macro-function name) function)
           (values name warnp failp))
          (name
           (setf (fdefinition name) function)
           (values name warnp failp))
          (t (values function warnp failp)))))

(defun compiler-stats ()
  (core:fmt t "Accumulated finalization time {}%N" llvm-sys:*accumulated-llvm-finalization-time*)
  (core:fmt t "Most recent finalization time {}%N" llvm-sys:*most-recent-llvm-finalization-time*)
  (core:fmt t "Number of compilations {}%N" llvm-sys:*number-of-llvm-finalizations*))

(export 'compiler-stats)

#+(or bclasp cclasp)
(progn
  (defun bclasp-compile (form &optional definition)
    (let ((cmp:*cleavir-compile-hook* nil)
          (cmp:*cleavir-compile-file-hook* nil)
          (core:*use-cleavir-compiler* nil)
          (core:*eval-with-env-hook* #'core:interpret-eval-with-env))
      (compile form definition)))
  (export 'bclasp-compile))
