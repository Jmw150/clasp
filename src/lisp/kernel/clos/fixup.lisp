;; Should be commented out
#+(or)
(eval-when (:execute)
  (setq core:*echo-repl-read* t))

;;;;  -*- Mode: Lisp; Syntax: Common-Lisp; Package: CLOS -*-
;;;;
;;;;  Copyright (c) 1992, Giuseppe Attardi.
;;;;  Copyright (c) 2001, Juan Jose Garcia Ripoll.
;;;;
;;;;    This program is free software; you can redistribute it and/or
;;;;    modify it under the terms of the GNU Library General Public
;;;;    License as published by the Free Software Foundation; either
;;;;    version 2 of the License, or (at your option) any later version.
;;;;
;;;;    See file '../Copyright' for full details.

(in-package "CLOS")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; For debugging this file
;;; (Which happens a fair amount, because it's where CLOS begins use.)

;;; This will print every form as its compiled
#+(or)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (format t "Starting fixup.lisp")
  (setq *echo-repl-tpl-read* t)
  (setq *load-print* t)
  (setq *echo-repl-read* t))

#+mlog
(eval-when (:compile-toplevel :execute)
  (setq core::*debug-dispatch* t))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Define generics for core functions.

(defun function-to-method (name lambda-list specializers
                           &optional satiation-specializers (function (fdefinition name)))
  (mlog "function-to-method: name -> {} specializers -> {}  lambda-list -> {}%N" name specializers lambda-list)
  (mlog "function-to-method:  function -> {}%N" function)
  ;; since we still have method.lisp's add-method in place, it will try to add
  ;; the function-to-method-temp entry to *early-methods*. but then we unbind
  ;; that, so things are a bit screwy. We do it more manually.
  (let* ((f (ensure-generic-function 'function-to-method-temp)) ; FIXME: just make an anonymous one?
         (mf (make-%method-function-fast function))
         (method
           (make-method (find-class 'standard-method)
                        nil
                        (mapcar #'find-class specializers)
                        lambda-list
                        mf
                        (list
                         'leaf-method-p t))))
    ;; we're still using the old add-method, which adds things to *early-methods*.
    ;; We don't want to do that here, so we rebind *early-methods* and discard the value.
    (let ((*early-methods* nil))
      (add-method f method))
    ;; Put in a call history to speed things up a little.
    (loop with outcome = (make-effective-method-outcome
                          :methods (list method)
                          :form `(call-method ,method)
                          ;; Is a valid EMF.
                          :function function)
          for specializers in satiation-specializers
          collect (cons (map 'vector #'find-class specializers) outcome)
            into new-call-history
          finally (append-generic-function-call-history f new-call-history))
    ;; Finish setup
    (mlog "function-to-method: installed method%N")
    (setf-lambda-list f lambda-list) ; hook up the introspection
    ;; (setf generic-function-name) itself goes through here, so to minimize
    ;; bootstrap headaches we use the underlying writer directly.
    (setf-function-name f name)
    (setf (fdefinition name) f)
    (when (boundp '*early-methods*)
      (push (cons name (list method)) *early-methods*)))
  (fmakunbound 'function-to-method-temp))

(function-to-method 'compute-applicable-methods
                    '(generic-function arguments)
                    '(standard-generic-function t)
                    '((standard-generic-function cons) (standard-generic-function null))
                    #'std-compute-applicable-methods)

(function-to-method 'compute-applicable-methods-using-classes
                    '(generic-function classes)
                    '(standard-generic-function t)
                    '((standard-generic-function cons) (standard-generic-function null))
                    #'std-compute-applicable-methods-using-classes)

(function-to-method 'compute-effective-method
                    '(generic-function method-combination applicable-methods)
                    '(standard-generic-function method-combination t)
                    '((standard-generic-function method-combination cons)
                      (standard-generic-function method-combination null))
                    #'std-compute-effective-method)

(function-to-method 'generic-function-method-class '(gf)
                    '(standard-generic-function)
                    '((standard-generic-function)))

(function-to-method 'find-method-combination
                    '(gf method-combination-type-name method-combination-options)
                    '(standard-generic-function t t)
                    '((standard-generic-function symbol null)))

(function-to-method 'generic-function-name
                    '(generic-function)
                    '(standard-generic-function))

(function-to-method '(setf generic-function-name)
                    '(new-name generic-function)
                    '(t standard-generic-function))

(mlog "done with the first function-to-methods%N")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Satiate

;;; Every gf needs a specializer profile, not just satiated ones
;;; They pretty much all need one, and before any gf calls, so we do this
;;; before calling add-direct-method below

(dolist (method-info *early-methods*)
  (compute-gf-specializer-profile (fdefinition (car method-info))))

(mlog "About to satiate%N")

;;; Trickiness here.
;;; During build we first load this file as source. In that case we add only
;;; enough call history entries to boot the system.
;;; Then we compile this file. And in that compiler, we have full CLOS, so we
;;; can use the complicated satiation code to some extent. Importantly, we
;;; work out actual EMFs ahead of time so that they're in the FASL and don't
;;; have to compile those at runtime.
;;; The complicated stuff is in the :load-toplevel.
;;; TODO: Figure out precompiled discriminating functions too.
;;; Main problem there is making sure the stamps are the same at compile and load.
(eval-when (:execute)
  (satiate-minimal-generic-functions))
(eval-when (:load-toplevel)
  (satiate-clos))

(mlog "Done satiating%N")

;;; Generic functions can be called now!

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Make methods real

;;; First generic function calls done here.

(defun register-method-with-specializers (method)
  (loop for spec in (method-specializers method)
        do (add-direct-method spec method)))

(defun fixup-early-methods ()
  (dolist (method-info *early-methods*)
    (dolist (method (cdr method-info))
      (register-method-with-specializers method))))

(fixup-early-methods)

(makunbound '*early-methods*)

;;; *early-methods* is used by the primitive add-method in method.lisp.
;;; Avoid defining any new methods until the new add-method is installed.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Redefine ENSURE-GENERIC-FUNCTION

;;; Uses generic functions properly now.
;;; DEFMETHOD and INSTALL-METHOD and stuff call ensure-generic-function,
;;; so after this they will do generic function calls.

(defun ensure-generic-function (name &rest args &key &allow-other-keys)
  (mlog "ensure-generic-function  name -> {}  args -> {} %N" name args)
  (mlog "(not (fboundp name)) -> {}%N" (not (fboundp name)))
  (let ((gfun (si::traced-old-definition name)))
    (cond ((not (legal-generic-function-name-p name))
	   (simple-program-error "~A is not a valid generic function name" name))
          ((not (fboundp name))
           (mlog "A gfun -> {} name -> {}  args -> {}%N" gfun name args)
           ;;           (break "About to setf (fdefinition name)")
           (mlog "#'ensure-generic-function-using-class -> {}%N" #'ensure-generic-function-using-class )
	   (setf (fdefinition name)
		 (apply #'ensure-generic-function-using-class gfun name args)))
          ((si::instancep (or gfun (setf gfun (fdefinition name))))
           (mlog "B%N")
	   (let ((new-gf (apply #'ensure-generic-function-using-class gfun name args)))
	     new-gf))
	  ((special-operator-p name)
           (mlog "C%N")
	   (simple-program-error "The special operator ~A is not a valid name for a generic function" name))
	  ((macro-function name)
           (mlog "D%N")
	   (simple-program-error
            "The symbol ~A is bound to a macro and is not a valid name for a generic function" name))
          ((not *clos-booted*)
           (mlog "E%N")
           (setf (fdefinition name)
		 (apply #'ensure-generic-function-using-class nil name args))
           (fdefinition name))
	  (t
	   (simple-program-error "The symbol ~A is bound to an ordinary function and is not a valid name for a generic function" name)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Redefine things to their final form.

(defun method-p (method) (typep method 'METHOD))

(defun make-method (method-class qualifiers specializers arglist function options)
  (apply #'make-instance
	 method-class
	 :generic-function nil
	 :qualifiers qualifiers
	 :lambda-list arglist
	 :specializers specializers
	 :function function
	 :allow-other-keys t
	 options))

(defun all-keywords (l)
  (let ((all-keys '()))
    (do ((l (rest l) (cddddr l)))
	((null l)
	 all-keys)
      (push (first l) all-keys))))

(defun congruent-lambda-p (l1 l2)
  (multiple-value-bind (r1 opts1 rest1 key-flag1 keywords1 a-o-k1)
      (core:process-lambda-list l1 'FUNCTION)
    (multiple-value-bind (r2 opts2 rest2 key-flag2 keywords2 a-o-k2)
	(core:process-lambda-list l2 'FUNCTION)
      (and (= (length r2) (length r1))
           (= (length opts1) (length opts2))
           (eq (and (null rest1) (null key-flag1))
               (and (null rest2) (null key-flag2)))
           ;; All keywords mentioned in the genericf function
           ;; must be accepted by the method.
           (or (null key-flag1)
               (null key-flag2)
               ;; Testing for a-o-k1 here may not be conformant when
               ;; the fourth point of 7.6.4 is read literally, but it
               ;; is more consistent with the generic function calling
               ;; specification. Also it is compatible with popular
               ;; implementations like SBCL and CCL. -- jd 2020-04-07
               a-o-k1
               a-o-k2
               (null (set-difference (all-keywords keywords1)
                                     (all-keywords keywords2))))
           t))))

;;; auxiliary for add-method
;;; It takes a DEFMETHOD lambda list and returns a lambda list usable for
;;; initializing a generic function. The difficulty here is that the CLHS
;;; page for DEFMETHOD specifies that if a generic function is implicitly
;;; created, its lambda list lacks any specific keyword parameters.
;;; So (defmethod foo (... &key a)) (defmethod foo (... &key)) is legal.
;;; If we were to just use the same method lambda list, this would not be
;;; true.
(defun method-lambda-list-for-gf (lambda-list)
  (multiple-value-bind (req opt rest keyflag keywords aok)
      (core:process-lambda-list lambda-list 'function)
    (declare (ignore keywords))
    `(,@(rest req)
      ,@(unless (zerop (car opt))
          (cons '&optional (loop for (o) on (rest opt)
                                 by #'cdddr
                                 collect o)))
      ,@(when rest (list '&rest rest))
      ,@(when keyflag '(&key))
      ,@(when aok '(&allow-other-keys)))))

;;; It's possible we could use DEFMETHOD for these.

(defun add-method (gf method)
  ;; during boot it's a structure accessor
  (declare (notinline method-qualifiers remove-method))
  (declare (notinline reinitialize-instance)) ; bootstrap stuff
  ;;
  ;; 1) The method must not be already installed in another generic function.
  ;;
  (let ((other-gf (method-generic-function method)))
    (unless (or (null other-gf) (eq other-gf gf))
      (error "The method ~A belongs to the generic function ~A ~
and cannot be added to ~A." method other-gf gf)))
  ;;
  ;; 2) The method and the generic function should have congruent lambda
  ;;    lists. That is, it should accept the same number of required and
  ;;    optional arguments, and only accept keyword arguments when the generic
  ;;    function does.
  ;;
  (let ((new-lambda-list (method-lambda-list method)))
    (if (slot-boundp gf 'lambda-list)
	(let ((old-lambda-list (generic-function-lambda-list gf)))
	  (unless (congruent-lambda-p old-lambda-list new-lambda-list)
	    (error "Cannot add the method ~A to the generic function ~A because their lambda lists ~A and ~A are not congruent."
		   method gf new-lambda-list old-lambda-list))
          ;; Add any keywords from the method to the gf display lambda list.
          (maybe-augment-generic-function-lambda-list gf new-lambda-list))
	(reinitialize-instance
         gf :lambda-list (method-lambda-list-for-gf new-lambda-list))))
  ;;
  ;; 3) Finally, it is inserted in the list of methods, and the method is
  ;;    marked as belonging to a generic function.
  ;;
  (when (generic-function-methods gf)
    (let* ((method-qualifiers (method-qualifiers method)) 
	   (specializers (method-specializers method))
	   (found (find-method gf method-qualifiers specializers nil)))
      (when found
	(remove-method gf found))))
  ;;
  ;; Per AMOP's description of ADD-METHOD, we install the method by:
  ;;  i) Adding it to the list of methods.
  (push method (%generic-function-methods gf))
  (setf (%method-generic-function method) gf)
  ;;  ii) Adding the method to each specializer's direct-methods.
  (register-method-with-specializers method)
  ;;  iii) Computing a new discriminating function.
  ;;       Though in this case it will be the invalidated function.
  (update-gf-specializer-profile gf (method-specializers method))
  (compute-a-p-o-function gf)
  (update-generic-function-call-history-for-add-method gf method)
  (set-funcallable-instance-function gf (compute-discriminating-function gf))
  ;;  iv) Updating dependents.
  (update-dependents gf (list 'add-method method))
  gf)

(defun remove-method (gf method)
  (setf (%generic-function-methods gf)
	(delete method (generic-function-methods gf))
	(%method-generic-function method) nil)
  (loop for spec in (method-specializers method)
     do (remove-direct-method spec method))
  (compute-gf-specializer-profile gf)
  (compute-a-p-o-function gf)
  (update-generic-function-call-history-for-remove-method gf method)
  (set-funcallable-instance-function gf (compute-discriminating-function gf))
  (update-dependents gf (list 'remove-method method))
  gf)

#+(or)
(progn
  (sys:safe-trace instancep maybe-update-instance maybe-update-instances dispatch-miss)
  (sys:safe-trace perform-outcome)
  (sys:safe-trace check-gf-argcount dispatch-miss-info memoize-calls memoize-call force-dispatcher)
  (sys:safe-trace function-to-method safe-gf-specializer-profile safe-gf-call-history
                  specializer-call-history-generic-functions-push-new
                  generic-function-call-history)
  (sys:safe-trace std-compute-applicable-methods)
  (sys:safe-trace applicable-method-list sort-applicable-methods class-of)
  (sys:safe-trace generic-function-min-max-args)
  (sys:safe-trace ensure-generic-function)
  (sys:safe-trace make-%method-function-fast make-method add-method
                  make-effective-method-outcome append-generic-function-call-history)
  (sys:safe-trace setf-lambda-list setf-function-name)
  (sys:safe-trace (setf fdefinition))
  (sys:safe-trace invalidated-dispatch-function)
  (sys:safe-trace initialize-instance)
  (sys:safe-trace core:list-from-vaslist)
  (sys:safe-trace apply))

#+(or)
(progn
  (sys:safe-trace function-to-method)
  (sys:safe-trace instancep)
  (sys:safe-trace maybe-update-instance
                  maybe-update-instances
                  dispatch-miss
                  invalidated-dispatch-function
                  generate-discriminator-from-data
                  clos:interpret-dtree-program
                  interpreted-discriminator
                  dispatch-miss-va
                  core:apply0
                  core:apply1
                  core:apply2
                  core:apply3
                  core:apply4
                  perform-outcome
                  )
  )
#+(or)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (format t "Done remove-method ~a~%" (core:getpid))
  (y-or-n-p "About to function-to-method")
  )

;;(setq cmp:*debug-compiler* t)
(function-to-method 'add-method '(gf method) '(standard-generic-function standard-method)
                    '((standard-generic-function standard-method)
                      (standard-generic-function standard-reader-method)
                      (standard-generic-function standard-writer-method)))
(function-to-method 'remove-method '(gf method) '(standard-generic-function standard-method)
                    '((standard-generic-function standard-method)
                      (standard-generic-function standard-reader-method)
                      (standard-generic-function standard-writer-method)))
(function-to-method 'find-method '(gf qualifiers specializers &optional error)
                    '(standard-generic-function t t)
                    '((standard-generic-function null cons)
                      (standard-generic-function cons cons)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Error messages

(defgeneric no-applicable-method (gf &rest args)
  (declare (optimize (debug 3))))

(defmethod no-applicable-method (gf &rest args)
  (declare (optimize (debug 3)))
  (error 'no-applicable-method-error :generic-function gf :arguments args))

;;; FIXME: use actual condition classes

;;; FIXME: See method.lisp: This is not actually used normally.
(defmethod no-next-method (gf method &rest args)
  (declare (ignore gf))
  (error "In method ~A~%No next method given arguments ~A" method args))

(defun no-required-method (gf group-name &rest args)
  (error "No applicable methods in required group ~a for generic function ~a~@
          Given arguments: ~a"
         group-name (generic-function-name gf) args))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; MISCELLANY

(defmethod reader-method-class ((class std-class)
				(direct-slot direct-slot-definition)
				&rest initargs)
  (declare (ignore class direct-slot initargs))
  (find-class 'standard-reader-method))

(defmethod writer-method-class ((class std-class)
				(direct-slot direct-slot-definition)
				&rest initargs)
  (declare (ignore class direct-slot initargs))
  (find-class 'standard-writer-method))

(eval-when (:load-toplevel)
  (%satiate reader-method-class (standard-class standard-direct-slot-definition)
            (funcallable-standard-class standard-direct-slot-definition))
  (%satiate writer-method-class (standard-class standard-direct-slot-definition)
            (funcallable-standard-class standard-direct-slot-definition)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Finish initializing classes that we defined in C++ that
;;; are not in :COMMON-LISP or :SYS package
;;; so that we can use them as specializers for generic functions

(defun gather-cxx-classes ()
  (let ((additional-classes (reverse core:*all-cxx-classes*))
	classes)
    (dolist (class-symbol additional-classes)
      (unless (or (eq class-symbol 'core::model)
                  (eq class-symbol 'core::instance)
                  (assoc class-symbol +class-hierarchy+))
        (push class-symbol classes)))
    (nreverse classes)))

(defun add-cxx-class (class-symbol)
    (let* ((class (find-class class-symbol))
	   (supers-names (mapcar #'(lambda (x) (class-name x))
                                 (clos:direct-superclasses class))))
      (ensure-boot-class class-symbol :metaclass 'core:cxx-class ;; was 'builtin-class
                         :direct-superclasses supers-names)
      (finalize-inheritance class)))

(defun add-extra-classes (additional-classes)
  (dolist (class-symbol additional-classes)
    (add-cxx-class class-symbol)))

;;
;; Initialize all extra classes
;;
(add-extra-classes (gather-cxx-classes))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; We define the MAKE-LOAD-FORM for source-pos-info early, so that it can be
;;; used in the expansion of the defclass below.
;;; Most MAKE-LOAD-FORMs are in print.lisp.

(defmethod make-load-form ((object core:file-scope) &optional env)
  (declare (ignore env))
  (values
   `(core:make-cxx-object ,(find-class 'core:file-scope))
   `(core:decode
     ,object
     ',(core:encode object))))

(defmethod make-load-form ((object core:source-pos-info) &optional environment)
  (declare (ignore environment))
  (values
   `(core:make-cxx-object ,(find-class 'core:source-pos-info)
                          :sfi ,(core:file-scope
                                 (core:source-pos-info-file-handle object))
                          :fp ,(core:source-pos-info-filepos object)
                          :l ,(core:source-pos-info-lineno object)
                          :c ,(core:source-pos-info-column object))
   `(core:setf-source-pos-info-extra
     ',object
     ',(core:source-pos-info-inlined-at object)
     ',(core:source-pos-info-function-scope object))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; DEPENDENT MAINTENANCE PROTOCOL
;;;

(defmethod add-dependent ((c class) dep)
  (pushnew dep (class-dependents c)))

(defmethod add-dependent ((c generic-function) dependent)
  (pushnew dependent (generic-function-dependents c)))

(defmethod remove-dependent ((c class) dep)
  (setf (class-dependents c)
        (remove dep (class-dependents c))))

(defmethod remove-dependent ((c standard-generic-function) dep)
  (setf (generic-function-dependents c)
        (remove dep (generic-function-dependents c))))

(defmethod map-dependents ((c class) function)
  (dolist (d (class-dependents c))
    (funcall function d)))

(defmethod map-dependents ((c standard-generic-function) function)
  (dolist (d (generic-function-dependents c))
    (funcall function d)))

;; FIXME: dependence on core:closure-with-slots is not super
(%satiate map-dependents (standard-generic-function core:closure-with-slots)
          (standard-class core:closure-with-slots))

(defgeneric update-dependent (object dependent &rest initargs))

;; After this, update-dependents will work
(setf *clos-booted* 'map-dependents)


(defclass initargs-updater ()
  ())

(defun recursively-update-class-initargs-cache (a-class)
  ;; Bug #588: If a class is forward referenced and you define an initialize-instance
  ;; (or whatever) method on it, it got here and tried to compute valid initargs, which
  ;; involved taking the class-prototype, which couldn't be allocated of course.
  ;; There's no value in precomputing the initargs for an unfinished class, so we don't.
  (when (class-finalized-p a-class)
    (precompute-valid-initarg-keywords a-class)
    (mapc #'recursively-update-class-initargs-cache (class-direct-subclasses a-class))))

(defmethod update-dependent ((object generic-function) (dep initargs-updater)
			     &rest initargs
                             &key ((add-method added-method) nil am-p)
                               ((remove-method removed-method) nil rm-p)
                             &allow-other-keys)
  (declare (ignore initargs))
  (let ((method (cond (am-p added-method) (rm-p removed-method))))
    ;; update-dependent is also called when the gf itself is reinitialized, so make sure we actually have
    ;; a method that's added or removed
    (when method
      (let ((spec (first (method-specializers method)))) ; the class being initialized or allocated
        (when (classp spec) ; sanity check against eql specialization
          (recursively-update-class-initargs-cache spec))))))

;; NOTE that we can't use MAKE-INSTANCE since the
;; compiler macro in static-gfs will put in code
;; that the loader can't handle yet.
;; We could use NOTINLINE now that bclasp handles it,
;; but we don't need to go through make-instance's song and dance anyway.
(let ((x (with-early-make-instance () (x (find-class 'initargs-updater)) x)))
  (add-dependent #'shared-initialize x)
  (add-dependent #'initialize-instance x)
  (add-dependent #'allocate-instance x))

;; can't satiate this one, because the environment class will vary.
(function-to-method 'make-method-lambda
                    '(gf method lambda-form environment)
                    '(standard-generic-function standard-method t t))

;; ditto
(function-to-method 'expand-apply-method
                    '(method method-arguments arguments env)
                    '(standard-method t t t)
                    nil
                    #'std-expand-apply-method)

(function-to-method 'compute-discriminating-function '(gf)
                    '(standard-generic-function)
                    '((standard-generic-function)))

(function-to-method 'print-object
                    '(object stream)
                    '(t t))
