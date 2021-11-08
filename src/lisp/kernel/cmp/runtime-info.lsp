;;(in-package :cmp)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (core:select-package :cmp))

(defvar +cxx-data-structures-info+ (llvm-sys:cxx-data-structures-info))

(defun get-cxx-data-structure-info (name &optional (info +cxx-data-structures-info+))
  (let ((find (assoc name info)))
    (or find (error "Could not find ~a in cxx-data-structures-info --> ~s~%" name info))
    (cdr find)))
(defvar +multiple-values-limit+ (get-cxx-data-structure-info :multiple-values-limit))
(defvar +sizeof-size_t+ (get-cxx-data-structure-info 'core:size-t))
(defvar +optimized-slot-index-index+ (get-cxx-data-structure-info :optimized-slot-index-index))
(defvar +void*-size+ (get-cxx-data-structure-info :void*-size))
(defvar +value-frame-parent-offset+ (get-cxx-data-structure-info :value-frame-parent-offset))
(defvar +closure-entry-point-offset+ (get-cxx-data-structure-info :closure-entry-point-offset))
(defvar +global-entry-point-entry-points-offset+ (get-cxx-data-structure-info :global-entry-point-entry-points-offset))
(defvar +unused-stamp+ (get-cxx-data-structure-info :unused-stamp))
(defvar +fixnum-stamp+ (get-cxx-data-structure-info :fixnum-stamp))
(defvar +cons-stamp+ (get-cxx-data-structure-info :cons-stamp))
(defvar +vaslist-stamp+ (get-cxx-data-structure-info :vaslist_s-stamp))
(defvar +character-stamp+ (get-cxx-data-structure-info :character-stamp))
(defvar +single-float-stamp+ (get-cxx-data-structure-info :single-float-stamp))
(defvar +instance-rack-stamp-offset+ (get-cxx-data-structure-info :instance-rack-stamp-offset))
(defvar +instance-rack-offset+ (get-cxx-data-structure-info :instance-rack-offset))
(defvar +instance-stamp+ (get-cxx-data-structure-info :instance-stamp))
(defvar +funcallable-instance-stamp+ (get-cxx-data-structure-info :funcallable-instance-stamp))
(defvar +class-rep-stamp+ (get-cxx-data-structure-info :class-rep-stamp))
(defvar +wrapped-pointer-stamp+ (get-cxx-data-structure-info :wrapped-pointer-stamp))
(defvar +literal-tag-char-code+ (get-cxx-data-structure-info :literal-tag-char-code))
(defvar +derivable-cxx-object-stamp+ (get-cxx-data-structure-info :derivable-stamp))
(defvar +instance-stamp+ (get-cxx-data-structure-info :instance-stamp))
(defvar +c++-stamp-max+ (get-cxx-data-structure-info :c++-stamp-max))
(defvar +header-size+ (get-cxx-data-structure-info :header-size))
(defvar +header-stamp-offset+ (get-cxx-data-structure-info :header-stamp-offset))
(defvar +header-stamp-size+ (get-cxx-data-structure-info :header-stamp-size))
(defvar +where-tag-mask+ (get-cxx-data-structure-info :where-tag-mask))

(defvar +ptag-mask+ (get-cxx-data-structure-info :ptag-mask))
(defvar +mtag-mask+ (get-cxx-data-structure-info :mtag-mask))
(defvar +DERIVABLE-WTAG+ (get-cxx-data-structure-info :DERIVABLE-WTAG))
(defvar +RACK-WTAG+ (get-cxx-data-structure-info :RACK-WTAG))
(defvar +WRAPPED-WTAG+ (get-cxx-data-structure-info :WRAPPED-WTAG))
(defvar +HEADER-WTAG+ (get-cxx-data-structure-info :HEADER-WTAG))
(defvar +MAX-WTAG+ (get-cxx-data-structure-info :MAX-WTAG))
(defvar +MTAG-WIDTH+ (get-cxx-data-structure-info :MTAG-WIDTH))
(defvar +WTAG-WIDTH+ (get-cxx-data-structure-info :WTAG-WIDTH))
(defvar +GENERAL-MTAG-SHIFT+ (get-cxx-data-structure-info :GENERAL-MTAG-SHIFT))

(defvar +derivable-where-tag+ (get-cxx-data-structure-info :derivable-where-tag))
(defvar +rack-where-tag+ (get-cxx-data-structure-info :rack-where-tag))
(defvar +wrapped-where-tag+ (get-cxx-data-structure-info :wrapped-where-tag))
(defvar +header-where-tag+ (get-cxx-data-structure-info :header-where-tag))
(defvar +where-tag-width+ (get-cxx-data-structure-info :where-tag-width))
(defvar +fixnum-mask+ (get-cxx-data-structure-info :fixnum-mask))
(defvar +fixnum-shift+ (get-cxx-data-structure-info :fixnum-shift))
#+(or)(defvar +stamp-in-rack-mask+ (get-cxx-data-structure-info :stamp-in-rack-mask))
#+(or)(defvar +stamp-needs-call-mask+ (get-cxx-data-structure-info :stamp-needs-call-mask))
(defvar +immediate-mask+ (get-cxx-data-structure-info :immediate-mask))
(defvar +cons-tag+ (get-cxx-data-structure-info :cons-tag))
#+tag-bits4(defvar +vaslist-ptag-mask+ (get-cxx-data-structure-info :vaslist-ptag-mask))
(defvar +alignment+ (get-cxx-data-structure-info :alignment))
(defvar +vaslist0-tag+ (get-cxx-data-structure-info :vaslist0-tag))
#+tag-bits4(defvar +vaslist1-tag+ (get-cxx-data-structure-info :vaslist1-tag))
(defvar +fixnum00-tag+ (get-cxx-data-structure-info :fixnum00-tag))
(defvar +fixnum01-tag+ (get-cxx-data-structure-info :fixnum01-tag))
#+tag-bits4(defvar +fixnum10-tag+ (get-cxx-data-structure-info :fixnum10-tag))
#+tag-bits4(defvar +fixnum11-tag+ (get-cxx-data-structure-info :fixnum11-tag))
(defvar +character-tag+ (get-cxx-data-structure-info :character-tag))
(defvar +single-float-tag+ (get-cxx-data-structure-info :single-float-tag))
(defvar +single-float-shift+ (get-cxx-data-structure-info :single-float-shift))
(defvar +general-tag+ (get-cxx-data-structure-info :general-tag))
(defvar +vaslist-size+ (get-cxx-data-structure-info :vaslist-size))
(defvar +vaslist-args-offset+ (get-cxx-data-structure-info :vaslist-args-offset))
(defvar +vaslist-nargs-offset+ (get-cxx-data-structure-info :vaslist-nargs-offset))
(defvar +void*-size+ (get-cxx-data-structure-info :void*-size))
(defvar +jmp-buf-size+ (get-cxx-data-structure-info :jmp-buf-size))
(defvar +alignment+ (get-cxx-data-structure-info :alignment))
(defvar +args-in-registers+ (get-cxx-data-structure-info :lcc-args-in-registers))
(export '(+fixnum-mask+ +ptag-mask+ +immediate-mask+
          +cons-tag+ +fixnum-tag+ +character-tag+ +single-float-tag+
          +general-tag+ +vaslist-size+ +void*-size+ +alignment+ ))
(defvar +cons-car-offset+ (get-cxx-data-structure-info :cons-car-offset))
(defvar +cons-cdr-offset+ (get-cxx-data-structure-info :cons-cdr-offset))
(defvar +uintptr_t-size+ (get-cxx-data-structure-info :uintptr_t-size))
(defvar +t-size+ (get-cxx-data-structure-info 'core:tsp))
(defvar +simple-vector._length-offset+ (get-cxx-data-structure-info :simple-vector._length-offset))
(defvar +simple-vector._data-offset+ (get-cxx-data-structure-info :simple-vector._data-offset))
(defvar +size_t-bits+ (get-cxx-data-structure-info :size_t-bits))
(defvar +entry-point-arity-begin+ (get-cxx-data-structure-info :entry-point-arity-begin))
(defvar +entry-point-arity-end+ (get-cxx-data-structure-info :entry-point-arity-end))
(defvar +number-of-entry-points+ (get-cxx-data-structure-info :number-of-entry-points))

