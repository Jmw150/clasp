;;; Set up everything to start cleavir

(progn
  (load "sys:kernel;clasp-builder.lisp")
  (defun cleavir-system ()
    (with-open-file (fin "source-dir:tools-for-build;cleavir-file-list.lisp" :direction :input)
      (read fin)))
  (defun load-cleavir ()
    (let* ((system (cleavir-system))
           (last (position-if (lambda (x) (search "inline-prep" x)) system))
           (subsystem (subseq system 0 last)))
      (format t "subsystem: ~s~%" subsystem)
      (format t "last position: ~s name ~s~%" last (elt system last))
      (core::load-system subsystem)))

  (defun start-cleavir ()
    (let ((system (cleavir-system)))
      (core::load-system system)
      (format t "Cleavir is go~%")))

  (defun load-cleavir-no-inline ()
    (let ((system (cleavir-system)))
      (core::load-system (butlast system 3))))

  (defun compile-stuff ()
    (dotimes (i 50)
      (format t "Compilation #~a~%" i)
      (compile-file "sys:kernel;lsp;setf.lisp" :output-file "/tmp/setf.fasl")))


  (defun cleavir-compile-file (&rest args)
    (let ((cmp:*cleavir-compile-file-hook* 'clasp-cleavir::bir-loop-read-and-compile-file-forms))
      (apply #'compile-file args)))

  )


#+(or)
(start-cleavir)

;;; Start cleavir with no inline
(progn
  (load-cleavir-no-inline)
  (format t "!!!!!!!!!!! Cleavir loaded~%"))
