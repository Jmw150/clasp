(in-package :cscrape)

(define-constant +begin-tag+ "BEGIN_TAG_bfc54f90bafadf5" :test 'equal)
(define-constant +end-tag+ "END_TAG_bfc54f90bafadf5" :test 'equal)

(defun concat-ds (short long)
  (cond
    ((and short (null long))
     short)
    (long
     (break "short: ~s long: ~s" short long))))

(defun fill-config (config line)
  (let* ((trimmed (string-trim " " line))
         (var-start (position #\space trimmed))
         (data-start (position #\< trimmed :start var-start))
         (var (string-trim " " (subseq trimmed var-start data-start)))
         (data (string-trim " <>" (subseq trimmed data-start))))
    (setf (gethash (intern var :keyword) config) data)))

(defun read-application-config (filename)
  (let ((config (make-hash-table :test #'equal)))
    (with-open-file (fin filename :direction :input :external-format :utf-8)
      (loop for l = (read-line fin nil 'eof)
         until (eq l 'eof)
         for tl = (string-trim '(#\space #\tab) l)
         do (cond
              ((string= (subseq tl 0 7) "#define")
               (fill-config config tl))
              (t (error "Illegal application.config line: ~a" l)))))
    config))
