;; Set features :clasp-min for minimal system without CLOS
;; :clos to compile with CLOS
;;


#+(or)
(eval-when (:compile-toplevel :execute)
  (setq core:*debug-eval* t))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (core:select-package "CORE"))

#+(or)(setq *features* (cons :dbg-print *features*))
(SYS:*MAKE-SPECIAL '*echo-repl-tpl-read*)
(export '(*echo-repl-tpl-read*
          ihs-top ; for asdf compatibility only; remove soon
          cons-car
          cons-cdr
          debug-break))
(export '*trace-startup*)


;;; ------------------------------------------------------------
;;;
;;; Set *echo-repl-read* to t to print each repl form
;;;
(setq *echo-repl-read* nil)

;;; ------------------------------------------------------------
;;; Turn on printing messages as object files are converted to runnable code
;;;
(if (member :dump-repl-object-files *features*)
    (llvm-sys:debug-object-files 'llvm-sys:debug-object-files-print)
    (if (member :debug-object-files *features*)
        (llvm-sys:debug-object-files 'llvm-sys:debug-object-files-print-save)))

(setq *echo-repl-tpl-read* (member :emacs-inferior-lisp *features*))
(setq *load-print* nil)

(setq cl:*print-circle* nil)

(sys:*make-special 'core::*clang-bin*)
(export 'core::*clang-bin*)


;;; --------------------------------------------------
;;;
;;; Use force-compile-file-serial feature to
;;; shutdown compile-file-parallel.
;;;
(if (member :force-compile-file-serial *features*)
    (setq cmp:*use-compile-file-parallel* nil))

(cond
  ((member :generate-faso *features*)
   (setq core:*clasp-build-mode* :faso))
  ((member :generate-fasoll *features*)
   (setq core:*clasp-build-mode* :fasoll))
  ((member :generate-fasobc *features*)
   (setq core:*clasp-build-mode* :fasobc)))
  
(if (member :generate-faso *features*)
    (setq core:*clasp-build-mode* :faso))
                                  

(setq cmp:*default-object-type* core:*clasp-build-mode*)


;;; ------------------------------------------------------------
;;;
;;;   Turn on flow tracker
;;;

#+debug-flow-tracker
(if (member :flow-tracker *features*)
    (progn
      (core:fmt t "Turning flow-tracker on%N")
      (gctools:flow-tracker-on)))


;;; ------------------------------------------------------------
;;;
;;;   Sanity check that stamps are working properly
;;;

(eval-when (:compile-toplevel :execute)
  (let* ((obj "asdf")
         (stamp (core:instance-stamp obj))
         (class-stamp (core:class-stamp-for-instances (core:instance-class obj)))
         (map-stamp (gethash (core:name-of-class (core:instance-class obj)) core:+type-header-value-map+)))
    (if (not (numberp stamp))
        (progn
          (core:fmt t "Sanity check failure stamp {} must be a number%N" stamp)
          (core:cabort))
        (if (not (numberp class-stamp))
            (progn
              (core:fmt t "Sanity check failure class-stamp {} must be a number%N" class-stamp)
              (core:cabort))
            (if (not (numberp map-stamp))
                (progn
                  (core:fmt t "Sanity check failure map-stamp {} must be a number%N" map-stamp)
                  (finish-output)
                  (core:cabort)))))
    (if (not (= stamp class-stamp))
        (progn
          (core:fmt t "For object {} there is a mismatch between the stamp {} and the class-stamp {}%N"
                        obj stamp class-stamp)
          (finish-output)
          (core:cabort))
        (if (not (= stamp map-stamp))
            (progn
              (core:fmt t "For object {} there is a mismatch between the stamp {} and the class-stamp {}%N"
                            obj stamp class-stamp)
              (finish-output)
              (core:cabort))))))

;; When boostrapping in stages, set this feature,
;; it guarantees that everything that is declared at compile/eval time
;; gets declared at load-time
;; Turn this off and recompile everything once the system has
;; been bootstrapped
(setq *features* (cons :clasp-boot *features*)) ;; When bootstrapping in stages

;; Set up a few things for the CLOS package
(export '(clos::standard-class) "CLOS")

;; Setup a few things for the GRAY streams package
(eval-when (:execute :compile-toplevel :load-toplevel)
  (core::select-package :gray))
(shadow '(STREAM-ELEMENT-TYPE OPEN-STREAM-P OUTPUT-STREAM-P INPUT-STREAM-P STREAMP CLOSE))

;; Setup a few things for the CORE package
(eval-when (:execute :compile-toplevel :load-toplevel)
  (core::select-package :core))

(sys:*make-special '*use-cleavir-compiler*)
(sys:*make-special '*eval-with-env-hook*)

;; Setup a few things for the CMP package
(eval-when (:execute :compile-toplevel :load-toplevel)
  (core::select-package :cmp))
(sys:*make-special '*dbg-generate-dwarf*)
(setq *dbg-generate-dwarf* (null (member :disable-dbg-generate-dwarf *features*)))
(export '(llvm-link link-bitcode-modules link-fasoll-modules link-fasobc-modules))
;;; Turn on aclasp/bclasp activation-frame optimization
(sys:*make-special '*activation-frame-optimize*)
(setq *activation-frame-optimize* t)
#-debug-dont-optimize-bclasp (setq *features* (cons :optimize-bclasp *features*))
(sys:*make-special '*use-human-readable-bitcode*)
(setq *use-human-readable-bitcode* (member :use-human-readable-bitcode *features*))
(sys:*make-special '*compile-file-debug-dump-module*)
(sys:*make-special '*debug-compile-file*)
(if (boundp '*compile-file-debug-dump-module*)
    nil
    (setq *compile-file-debug-dump-module* t))
(sys:*make-special '*compile-debug-dump-module*)
(if (boundp '*compile-debug-dump-module*)
    nil
    (setq *compile-debug-dump-module* nil))
(setq *debug-compile-file* (member :debug-compile-file *features*))
(sys:*make-special '*debug-cclasp-cmp*)
(setq *debug-cclasp-cmp* nil)
(export '*debug-cclasp-cmp*)

(export '(*compile-file-debug-dump-module* *compile-debug-dump-module* *use-human-readable-bitcode*))
(use-package :core)

(eval-when (:execute :compile-toplevel :load-toplevel)
  (select-package :core))

(if (find-package "C")
    nil
    (make-package "C" :use '(:cl :core)))

(eval-when (:execute :compile-toplevel :load-toplevel)
  (if (find-package "SEQUENCE")
      nil
      (make-package "SEQUENCE" :use '())))

(eval-when (:execute :compile-toplevel :load-toplevel)
  (if (find-package "LITERAL")
      nil
      (make-package "LITERAL" :use '(:cl :core))))

(eval-when (:execute :compile-toplevel :load-toplevel)
  (if (find-package "CLASP-CLEAVIR")
      nil
      (make-package "CLASP-CLEAVIR" :use '(:CL))))

;;; Setup a few things for the EXT package

;;; Imports
(import 'core:quit :ext)
(import 'core:getpid :ext)
(import 'core:argc :ext)
(import 'core:argv :ext)
(import 'core:rmdir :ext)
(import 'core:mkstemp :ext)
(import 'core:weak-pointer-value :ext)
(import 'core:make-weak-pointer :ext)
(import 'core:weak-pointer-valid :ext)
(import 'core:hash-table-weakness :ext)

;;; EXT exports
(eval-when (:execute :compile-toplevel :load-toplevel)
  (select-package :ext))

(export '(*module-provider-functions*
          *source-location-kinds*
          current-source-location
          source-location
          source-location-pathname
          source-location-offset
          source-location-definer
          source-location-description
          compiled-function-name
          compiled-function-file
          array-index
          byte8
          integer8
          byte16
          integer16
          byte32
          integer32
          byte64
          integer64
          assume-no-errors
          sequence-stream
          all-encodings
          make-encoding
          assume-right-type
          assert-error
          float-nan-p
          float-infinity-p
          character-coding-error
          character-encoding-error
          character-decoding-error
          stream-encoding-error
          stream-decoding-error
          generate-encoding-hashtable
          quit
          with-float-traps-masked
          enable-interrupt default-interrupt ignore-interrupt
          get-signal-handler set-signal-handler
          *ed-functions*
          ;;; for asdf and slime and trivial-garbage to use ext:
          getpid argc argv rmdir mkstemp weak-pointer-value make-weak-pointer weak-pointer-valid hash-table-weakness))
(core:*make-special '*module-provider-functions*)
(core:*make-special '*source-location*)
(setq *source-location* nil)
(export 'current-source-location)
;;; Function: (EXT:CURRENT-SOURCE-LOCATION)
;;; - Returns the source location of the current top-level form
;;;   or nil if it's not known.
(core:fset
 'current-source-location
 #'(lambda () core:*current-source-pos-info*))

(eval-when (:execute :compile-toplevel :load-toplevel)
  (core:select-package :core))

;;; Have to do this early so all defvars are ok.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (sys:*make-special '*variable-source-infos*))
(if (boundp '*variable-source-infos*)
    nil
    (set '*variable-source-infos*
         (make-hash-table :test #'eq :thread-safe t)))

(si:fset 'core::defvar #'(lambda (whole env)
                           (declare (ignore env))
                           (let ((var (cadr whole))
                                 (formp (cddr whole))
                                 (form (caddr whole)))
                             "Syntax: (defvar name form [doc])
Declares the global variable named by NAME as a special variable and assigns
the value of FORM to the variable.  The doc-string DOC, if supplied, is saved
as a VARIABLE doc and can be retrieved by (documentation 'NAME 'variable)."
                             `(LOCALLY (DECLARE (SPECIAL ,var))
                                (SYS:*MAKE-SPECIAL ',var)
                                ,@(if formp
                                      `((if (boundp ',var)
                                            ',var
                                            (progn
                                              (setq ,var ,form)
                                              ',var)))))))
         t)
(export 'defvar)

(si:fset 'core::defparameter #'(lambda (whole env)
                                 (declare (ignore env))
                                 (let ((var (cadr whole))
                                       (form (caddr whole)))
                                   "Syntax: (defparameter name form [doc])
Declares the global variable named by NAME as a special variable and assigns
the value of FORM to the variable.  The doc-string DOC, if supplied, is saved
as a VARIABLE doc and can be retrieved by (documentation 'NAME 'variable)."
                                   `(LOCALLY (DECLARE (SPECIAL ,var))
                                      (SYS:*MAKE-SPECIAL ',var)
                                      (SETQ ,var ,form)
                                      ',var)))
         t)
(export 'defparameter)



(si:fset 'core::defconstant #'(lambda (whole env)
                                (declare (ignore env))
                                (let ((var (cadr whole))
                                      (form (caddr whole)))
                                  "Syntax: (defconstant name form [doc])
Declares the global variable named by NAME as a special variable and assigns
the value of FORM to the variable.  The doc-string DOC, if supplied, is saved
as a VARIABLE doc and can be retrieved by (documentation 'NAME 'variable)."
                                  `(if (core:symbol-constantp ',var)
                                       nil
                                       (progn
                                         (set ',var ,form)
                                         (funcall #'(setf core:symbol-constantp) t ',var)))))
         t)
(export 'defconstant)

(if (boundp '+ecl-safe-declarations+)
    nil ; don't redefine constant
    (defconstant +ecl-safe-declarations+
      '(optimize (safety 2) (speed 1) (debug 1) (space 1))))

(defvar +io-syntax-progv-list+
  (list
   '(
     *print-pprint-dispatch* #|  See end of pprint.lisp  |#
     *print-array*
     *print-base*
     *print-case*
     *print-circle*
     *print-escape*
     *print-gensym*
     *print-length*
     *print-level*
     *print-lines*
     *print-miser-width*
     *print-pretty*
     *print-radix*
     *print-readably*
     *print-right-margin*
     *read-base*
     *read-default-float-format*
     *read-eval*
     *read-suppress*
     *readtable*
     *package*
     si::*sharp-eq-context*
     si::*circle-counter*)               ;
   nil                                   ;;  *pprint-dispatch-table*
   t                                     ;;  *print-array*
   10                                    ;;  *print-base*
   :upcase                               ;;  *print-case*
   nil                                   ;;  *print-circle*
   t                                     ;;  *print-escape*
   t                                     ;;  *print-gensym*
   nil                                   ;;  *print-length*
   nil                                   ;;  *print-level*
   nil                                   ;;  *print-lines*
   nil                                   ;;  *print-miser-width*
   nil                                   ;;  *print-pretty*
   nil                                   ;;  *print-radix*
   t                                     ;;  *print-readably*
   nil                                   ;;  *print-right-margin*
   10                                    ;;  *read-base*
   'single-float ;;  *read-default-float-format*
   t             ;;  *read-eval*
   nil           ;;  *read-suppress*
   *readtable*   ;;  *readtable*
   (find-package :CL-USER)               ;;  *package*
   nil                                   ;;  si::*sharp-eq-context*
   nil                                   ;;  si::*circle-counter*
   ))

(eval-when (:execute :compile-toplevel :load-toplevel)
  (core::select-package :cl))
(defvar *print-pretty* nil)  ;; Turn this on by default
(defvar *print-level* nil)
(defvar *print-length* nil)
(defvar *print-base* 10)
(defvar *print-radix* nil)
(defvar *read-default-float-format* 'double-float)



(core::export 'defun)
(eval-when (:execute :compile-toplevel :load-toplevel)
  (core::select-package :core))
(export 'bind-vaslist)

(defparameter *debug-bclasp* (if (member :debug-bclasp-lisp *features*) t nil))

(defvar *special-init-defun-symbol* (gensym "special-init-defun-symbol"))

;;; A temporary definition of defun - the real one is in evalmacros
#+clasp-min
(eval-when (:execute)
  (si:fset 'defun
           #'(lambda (def env)
               (let ((name (second def))      ;cadr
                     (lambda-list (third def)) ; caddr
                     (lambda-body (cdddr def))) ; cdddr
                 (multiple-value-call
                     (function (lambda (&optional (decl) (body) (doc) &rest rest)
                       (declare (ignore rest))
                       (if decl (setq decl (list (cons 'declare decl))))
                       (let ((func `#'(lambda ,lambda-list ,@decl ,@doc (block ,(si::function-block-name name) ,@body))))
                         ;;(core:fmt t "PRIMITIVE DEFUN defun --> {}%N" func )
                          `(progn (eval-when (:compile-toplevel)
                                    (cmp::register-global-function-def 'defun ',name))
                                  (si:fset ',name ,func nil ',lambda-list)))))
                   (si::process-declarations lambda-body nil #| No documentation until the real DEFUN is defined |#))))
           t))

(export '(defun))

;;; Define these here so that Cleavir can do inlining
(defvar *defun-inline-hook* nil)
(defvar *do-inline-hook* nil)
(defvar *proclaim-hook* nil)
(export '(*defun-inline-hook*
          *do-inline-hook*
          *proclaim-hook*))

;; Discard documentation until helpfile.lisp is loaded
(defun set-documentation (o d s) (declare (ignore o d s)) nil)

(defun proclaim (decl)
  "Args: (decl-spec)
Gives a global declaration.  See DECLARE for possible DECL-SPECs."
  ;;decl must be a proper list
  (if (not (core:proper-list-p decl))
      (error 'type-error
             :datum decl
             :expected-type '(and list (satisfies core:proper-list-p)))) 
  (cond
    ((eq (car decl) 'SPECIAL)
     (mapc #'sys::*make-special (cdr decl)))
    ((eq (car decl) 'cl:inline)
     (dolist (name (cdr decl))
       (core:hash-table-setf-gethash *functions-to-inline* name t)
       (remhash name *functions-to-notinline*)))
    ((eq (car decl) 'cl:notinline)
     (dolist (name (cdr decl))
       (core:hash-table-setf-gethash *functions-to-notinline* name t)
       (remhash name *functions-to-inline*)))
    (*proclaim-hook*
     (funcall *proclaim-hook* decl))))

(defun global-inline-status (name)
  "Return 'cl:inline 'cl:notinline or nil"
  (cond
    ((declared-global-inline-p name) 'cl:inline)
    ((declared-global-notinline-p name) 'cl:notinline)
    (t nil)))

(export '(global-inline-status
          declared-global-notinline-p
          declared-global-inline-p))

;; This is used extensively in the ecl compiler and once in predlib.lisp
(defvar *alien-declarations* ())
(export '*alien-declarations*)

(defun split-at-white-space (s) (split s " "))

(defun default-link-flags ()
  "Return the link flags and the library dir where libLTO.<library-extension> can be found and the library extension"
  (let ((stream (nth-value 2 (ext:vfork-execvp (list "llvm-config" "--ldflags" "--libdir" "--libs") t))))
    (let* ((ldflags (split-at-white-space (read-line stream)))
           #+(or)(clasp-lib-dir (core:fmt nil "-L{}" (namestring (translate-logical-pathname "app-resources:lib;common;lib;"))))
           (libdir (read-line stream))
           (libdir-flag (list (core:fmt nil "-L{}" libdir)))
           (libs (split-at-white-space (read-line stream)))
           (build-lib (split-at-white-space *build-lib*))
           (build-stlib (split-at-white-space *build-stlib*))
           (build-linkflags (split-at-white-space *build-linkflags*))
           (link-flags (append ldflags #+(or)(list clasp-lib-dir) build-linkflags libdir-flag libs build-stlib build-lib)))
      (close stream)
      (if (member :use-boehm *features*)
          (setq link-flags (cons "-lgc" link-flags)))
      (let ((library-extension (if (member :target-os-darwin *features*)
                                   "dylib"
                                   "so")))
        (values link-flags libdir library-extension)))))

(defun link-flags ()
  (default-link-flags))
(export 'link-flags)


(si:fset 'and
         #'(lambda (whole env)
             (declare (ignore env))
             (let ((forms (cdr whole)))
               (if (null forms)
                   t
                   (if (null (cdr forms))
                       (car forms)
                         `(if ,(car forms)
                              (and ,@(cdr forms)))))))
           t)

(si:fset 'or
         #'(lambda (whole env)
             (declare (ignore env))
             (let ((forms (cdr whole)))
               (if (null forms)
                   nil
                   (if ( null (cdr forms))
                       (car forms)
                       (let ((tmp (gensym)))
                         `(let ((,tmp ,(car forms)))
                            (if ,tmp
                                ,tmp
                                (or ,@(cdr forms)))))))))
           t )
(export '(and or))

(defun build-target-dir (type &optional stage)
  (declare (ignore type))
  (let* ((stage (if stage
                    stage
                    (default-target-stage)))
         (type-modified-host-suffix (build-configuration))
         (bitcode-host (core:fmt nil "{}{}-bitcode" stage type-modified-host-suffix)))
    bitcode-host))

(defun default-target-stage ()
  (let ((stage (if (member :cclasp *features*)
                   "c"
                   (if (member :bclasp *features*)
                       (if (member :compiling-cleavir *features*)
                           "pre"
                           "b")
                       "a"))))
    stage))


(defun build-configuration ()
  (let ((gc (cond
              ((member :use-mps *features*) "mps")
              ((member :use-mmtk *features*)
               (if (member :use-precise-gc *features*)
                   "mmtkprecise"
                   "mmtk"))
              ((member :use-boehm *features*)
               (if (member :use-precise-gc *features*)
                   "boehmprecise"
                   "boehm"))
              (t (error "Unknown clasp configuration"))))
        (mpi (if (member :use-mpi *features*) "-mpi" "")))
    (core:fmt nil "{}-{}{}" (lisp-implementation-type) gc mpi)))

(defun ensure-relative-pathname (input)
  "If the input pathname is absolute then search for src, or generated and return
a relative path from there."
  #+(or)(core:fmt t "ensure-relative-pathname input = {}   sys-pn = {}%N" input sys-pn)
  (let ((result
         (cond
           ((eq :relative (car (pathname-directory input)))
            (make-pathname :directory (pathname-directory input)
                           :name (pathname-name input)))
           ((eq :absolute (car (pathname-directory input)))
            (make-pathname :directory (cons :relative (strip-root (pathname-directory input)))
                           :name (pathname-name input)))
           (t (error "ensure-relative-pathname could not handle ~a" input)))))
    #+(or)(core:fmt t "ensure-relative-pathname result = {}%N" result)
    result))


(defun build-inline-bitcode-pathname (link-type &optional (filetype :intrinsics))
  (let ((name (cond
                ((eq filetype :intrinsics) "intrinsics")
                ((eq filetype :builtins) "builtins-no-debug-info")
                (t (error "illegal filetype - only :intrinsics or :builtins allowed")))))
    (cond
      ((eq link-type :fasl)
       (translate-logical-pathname (core:fmt nil "lib:{}-{}-cxx.a" +bitcode-name+ name)))
      ((eq link-type :compile)
       (translate-logical-pathname (core:fmt nil "app-bitcode:{}-{}-cxx.bc" +bitcode-name+ name)))
      ((eq link-type :executable)
       (translate-logical-pathname (core:fmt nil "lib:{}-all-cxx.a" +bitcode-name+)))
      (t (error "Provide a bitcode file for the link-type ~a" link-type)))))

(defun build-common-lisp-bitcode-pathname ()
  (translate-logical-pathname (pathname (core:fmt nil "lib:{}clasp-{}-common-lisp.bc" (default-target-stage) +variant-name+))))
(export '(build-inline-bitcode-pathname build-common-lisp-bitcode-pathname))
#+(or)
(progn
  (defconstant +image-pathname+ (make-pathname :directory '(:relative) :name "image" :type "fasl"))
  (export '(+image-pathname+ )))
(defun bitcode-extension ()
  (if cmp::*use-human-readable-bitcode*
      "ll"
      "bc"))
(export 'bitcode-extension)

(defun build-extension (type)
  (if (eq type :fasl)
      "fasl"
      (if (eq type :bitcode)
          (if cmp::*use-human-readable-bitcode*
              "ll"
              "bc")
          (if (eq type :ll)
              "ll"
              (if (eq type :object)
                  "o"
                  (if (eq type :fasp)
                      "fasp"
                      (if (eq type :faso)
                          "faso"
                          (if (eq type :fasoll)
                              "fasoll"
                              (if (eq type :faspll)
                                  "faspll"
                                  (if (eq type :fasobc)
                                      "fasobc"
                                      (if (eq type :faspbc)
                                          "faspbc"
                                          (error "Unsupported build-extension type ~a" type))))))))))))

(defun build-library-type (type)
  "Given the object-type TYPE return what type of library it generates"
  (if (eq type :fasl)
      :fasl
      (if (eq type :object)
          :fasl
          (if (eq type :fasp)
              :fasp
              (if (eq type :faso)
                  :fasp
                  (if (eq type :fasoll)
                      :faspll
                      (if (eq type :faspll)
                          :faspll
                          (if (eq type :fasobc)
                              :faspbc
                              (if (eq type :faspbc)
                                  :faspbc
                                  (error "Unsupported build-extension type ~a" type))))))))))

(defun build-pathname (partial-pathname &optional (type :lisp) stage)
  "If partial-pathname is nil and type is :fasl or :executable then construct the name using
the stage, the +application-name+ and the +bitcode-name+"
  (flet ((find-lisp-source (module root)
           (or
            (probe-file (merge-pathnames (merge-pathnames module (make-pathname :type "lsp")) root))
            (probe-file (merge-pathnames (merge-pathnames module (make-pathname :type "lisp")) root))
            (error "Could not find a lisp source file with root: ~a module: ~a" root module))))
    (let ((target-host "lib")
          (target-dir (build-target-dir type stage)))
      #+dbg-print(core:fmt t "DBG-PRINT build-pathname module: {}%N" module)
      #+dbg-print(core:fmt t "DBG-PRINT build-pathname target-host: {}%N" target-host)
      #+dbg-print(core:fmt t "DBG-PRINT build-pathname target-dir: {}%N" target-dir)
      (let ((result
              (cond
                ((eq type :lisp)
                 (let ((module (ensure-relative-pathname partial-pathname)))
                   (cond
                     ((string= "generated" (second (pathname-directory module)))
                      ;; Strip the "generated" part of the directory
                      (find-lisp-source (make-pathname
                                         :directory (cons :relative (cddr (pathname-directory module)))
                                         :name (pathname-name module))
                                        (translate-logical-pathname "GENERATED:")))
                     (t
                      (find-lisp-source module (translate-logical-pathname "SOURCE-DIR:"))))))
                ((eq type :executable)
                 (let* ((stage-char (default-target-stage))
                        (filename (core:fmt nil "{}{}-{}" stage-char +application-name+ +bitcode-name+))
                        (exec-pathname (merge-pathnames (make-pathname :name filename :type nil) (translate-logical-pathname "app-executable:") )))
                   exec-pathname))
                ((and (null partial-pathname) (eq type :fasl))
                 (let* ((stage-char (default-target-stage))
                        (filename (core:fmt nil "{}{}-{}-image" stage-char +application-name+ +bitcode-name+))
                        (exec-pathname (merge-pathnames (make-pathname :name filename :type "fasl") (translate-logical-pathname "app-fasl:"))))
                   exec-pathname))
                (t
                 (merge-pathnames (merge-pathnames (ensure-relative-pathname partial-pathname)
                                                   (make-pathname :directory (list :relative target-dir) :type (build-extension type)))
                                  (translate-logical-pathname (make-pathname :host target-host)))))))
        result))))
(export '(build-pathname build-extension))


(eval-when (:execute)
  (load (build-pathname #P"src/lisp/kernel/cmp/jit-setup"))
  (load (build-pathname #P"src/lisp/kernel/clsymbols")))

(defun entry-filename (filename-or-cons)
  "If filename-or-cons is a list then the first entry is a filename"
  (if (consp filename-or-cons)
      (car filename-or-cons)
      filename-or-cons))

(defun entry-compile-file-options (entry)
  (if (consp entry)
      (cadr entry)
      nil))

(defun delete-init-file (entry &key (really-delete t) stage)
  (let* ((module (entry-filename entry))
         (bitcode-path (build-pathname module :bitcode stage)))
    (if (probe-file bitcode-path)
        (if really-delete
            (progn
              (core:fmt t "     Deleting bitcode: {}%N" bitcode-path)
              (delete-file bitcode-path))))))


;; I need to search the list rather than using features because *features* may change at runtime
(defun default-target-backend (&optional given-stage)
  (let* ((stage (if given-stage
                    given-stage
                    (default-target-stage)))
         (garbage-collector (build-configuration))
         (target-backend (core:fmt nil "{}{}" stage garbage-collector)))
    target-backend))
(export 'default-target-backend)

(defvar *target-backend* (default-target-backend))
(export '*target-backend*)

(defun bitcode-exists-and-up-to-date (entry)
  (let* ((filename (entry-filename entry))
         (source-path (build-pathname filename))
         (bitcode-path (build-pathname filename cmp:*default-object-type*))
         (found-bitcode (probe-file bitcode-path)))
    (if found-bitcode
        (> (file-write-date bitcode-path)
           (file-write-date source-path))
        nil)))

(defun default-prologue-form (&optional features)
  `(progn
     ,@(mapcar #'(lambda (f) `(push ,f *features*)) features)
     (if (core:is-interactive-lisp)
         (core:fmt t "Starting {} ... loading image...%N" (lisp-implementation-version)))))

(export '*extension-startup-loads*) ;; ADDED: frgo, 2016-08-10
(defvar *extension-startup-loads* nil)

(export 'process-extension-loads)
(defun process-extension-loads ()
  (if (not (member :ignore-extensions *features*))
      (progn
        (mapcar #'(lambda (entry)
                    (if (eq (car entry) 'cl:load)
                        (let ((file (cadr entry)))
                          (if (probe-file file)
                              (load file)
                              (core:fmt t "Extension file {} not present.%N" file)))
                        (let ((cmd (read-from-string (cdr entry))))
                          (apply (car cmd) (cdr cmd)))))
                core:*extension-startup-loads*)
        (mapcar #'(lambda (entry)
                    (funcall entry))
                core:*extension-startup-evals*))))

(export 'process-command-line-load-eval-sequence)
(defun process-command-line-load-eval-sequence ()
  (mapcar #'(lambda (entry)
              (if (eq (car entry) :load)
                  (load (cdr entry))
                  (let ((cmd (read-from-string (cdr entry))))
                    (eval cmd))))
          (core:command-line-load-eval-sequence)))

(export 'maybe-load-clasprc)
(defun maybe-load-clasprc ()
  "Maybe load the users startup code"
  (if (not (core:no-rc-p))
      (let ((clasprc (make-pathname :name (core:rc-file-name)
                                    :defaults (user-homedir-pathname))))
        (if (probe-file clasprc)
            (core:load-source clasprc)))))

(defun tpl-default-pathname-defaults-command ()
  (print *default-pathname-defaults*))

(defun tpl-change-default-pathname-defaults-dir-command (raw-dir)
  (let* ((corrected-dir (format nil "~a/" (string-right-trim "/" (string raw-dir))))
         (dir (pathname-directory (parse-namestring corrected-dir)))
         (pn-dir (mapcar #'(lambda (x) (if (eq x :up) :back x)) dir))
         (new-pathname (merge-pathnames (make-pathname :directory pn-dir) *default-pathname-defaults*))
         )
    (setq *default-pathname-defaults* new-pathname)))


;;; I moved the build system code out of init.lisp and
;;; put it in clasp-builder.lisp

(if (member :clasp-builder *features*)
    (load "source-dir:src;lisp;kernel;clasp-builder.lisp"))


(defun tpl-hook (cmd)
  (cond
    ((eq (car cmd) :pwd) (tpl-default-pathname-defaults-command))
    ((eq (car cmd) :cd) (tpl-change-default-pathname-defaults-dir-command (cadr cmd)))
    (t (core:fmt t "Unknown command {}%N" cmd))))

(setq *top-level-command-hook* #'tpl-hook)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Start everything up
;;

(export 'core:top-level)

#-(or aclasp bclasp cclasp)
(eval-when (:execute)
  (process-command-line-load-eval-sequence)
  (if (core:noinform-p)
      nil
      (core:fmt t "Low level repl - in init.lisp%N"))
  (core:low-level-repl))

#-(or bclasp cclasp)
(eval-when (:execute :load-top-level)
  (core:fmt t "init.lisp  %N!\n!\n! Hello from the bottom of init.lisp - for some reason execution is passing through here\n!\n!\n"))
