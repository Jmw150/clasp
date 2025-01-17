;;;;  -*- Mode: Lisp; Syntax: Common-Lisp; Package: SYSTEM -*-
;;;;
;;;;  Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
;;;;  Copyright (c) 1990, Giuseppe Attardi.
;;;;
;;;;    This program is free software; you can redistribute it and/or
;;;;    modify it under the terms of the GNU Library General Public
;;;;    License as published by the Free Software Foundation; either
;;;;    version 2 of the License, or (at your option) any later version.
;;;;
;;;;    See file '../Copyright' for full details.

;;;;	module routines

;; This is taken from SBCL's code/module.lisp which is in the public
;; domain.

(in-package "SYSTEM")

;;;; exported specials

(defparameter *modules* ()
  "This is a list of module names that have been loaded into Lisp so far.
It is used by PROVIDE and REQUIRE.")

(defparameter ext:*module-provider-functions* nil
  "See function documentation for REQUIRE")

;;;; PROVIDE and REQUIRE

(defun provide (module-name)
  "Adds a new module name to *MODULES* indicating that it has been loaded.
Module-name is a string designator"
  (let ((module-as-string (string module-name)))
    (pushnew module-as-string *modules* :test #'string=)
    (when (and (find-package :asdf)(string= "ASDF" (string-upcase module-as-string)))
      (funcall (find-symbol (string-upcase "register-immutable-system") :asdf) :asdf))
    )
  t)

(defparameter *requiring* nil)

(defun require-error (control &rest arguments)
  (error "Module error: ~?" control arguments))

(defun require (module-name &optional pathnames)
  "Loads a module, unless it already has been loaded. PATHNAMES, if supplied,
is a designator for a list of pathnames to be loaded if the module
needs to be. If PATHNAMES is not supplied, functions from the list
ext:*MODULE-PROVIDER-FUNCTIONS* are called in order with MODULE-NAME
as an argument, until one of them returns non-NIL.  User code is
responsible for calling PROVIDE to indicate a successful load of the
module."
  (let ((name (string module-name)))
    (when (member name *requiring* :test #'string=)
      (require-error "~@<Could not ~S ~A: circularity detected. Please check ~
           your configuration.~:@>" 'require module-name))
    (let ((saved-modules (copy-list *modules*))
	  (*requiring* (cons name *requiring*)))
      (unless (member name *modules* :test #'string=)
	(cond (pathnames
	       (unless (listp pathnames) (setq pathnames (list pathnames)))
	       ;; ambiguity in standard: should we try all pathnames in the
	       ;; list, or should we stop as soon as one of them calls PROVIDE?
	       (dolist (ele pathnames t)
		 (load ele)))
	      (t
	       (unless (some (lambda (p) (funcall p module-name))
			     ext:*module-provider-functions*)
		 (require-error "Don't know how to ~S ~A."
				'require module-name)))))
      (set-difference *modules* saved-modules))))

;;; Set up a MODULES host pathname that points to the precompiled modules for this stage/gc
(setf (logical-pathname-translations "MODULES")
      (list (list "**;*.*" (make-pathname :host "LIB"
                                          :directory (list :absolute (core:fmt nil "{}-bitcode" (default-target-backend)) "src" "lisp" :wild-inferiors)
                                          :name :wild
                                          :type :wild))))
(setf (logical-pathname-translations "MODULES-SOURCE")
      (list (list "**;*.*" (make-pathname :host "SOURCE-DIR"
                                          :directory (list :absolute "src" "lisp" :wild-inferiors)
                                          :name :wild
                                          :type :wild))))

(defparameter *module-extensions* (list "fasl" "FASL" "fasp" "FASP" "faspll" "FASPLL" "faspbc" "FASPBC" "lsp" "lisp" "LSP" "LISP"))

(defun clasp-module-provider (module)
  (flet ((try-it (path)
           (when (member :debug-require *features*)
             (format t "REQUIRE is searching in modules: ~a~%" path))
           (when (load path :if-does-not-exist nil)
             (return-from clasp-module-provider t))))
    (dolist (name (list (string module) (string-downcase module)))
      (dolist (directory (list
                          (list :relative)
                          #+(or)(list :relative name)
                          #+(or)(list :relative "kernel" name)
                          (list :relative "modules" name)))
        (dolist (type *module-extensions*)
          (try-it (merge-pathnames
                   (translate-logical-pathname (make-pathname :name name :type type :directory directory))
                   (translate-logical-pathname (make-pathname :host "MODULES"))))
          (try-it (merge-pathnames
                   (translate-logical-pathname (make-pathname :name name :type type :directory directory))
                   (translate-logical-pathname (make-pathname :host "MODULES-SOURCE")))))))))

(pushnew 'clasp-module-provider ext:*module-provider-functions*)
