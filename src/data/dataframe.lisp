;;; -*- mode: lisp -*-

;;; Time-stamp: <2013-03-17 12:57:13 tony>
;;; Creation:   <2008-03-12 17:18:42 blindglobe@gmail.com>
;;; File:       dataframe.lisp
;;; Author:     AJ Rossini <blindglobe@gmail.com>
;;; Copyright:  (c)2008--2010, AJ Rossini.  See LICENSE.mit in
;;;             toplevel directory for conditions.  

;;; Purpose:    Data packaging and access for Common Lisp Statistics,
;;;             using a DATAFRAME-LIKE virtual structure.  This redoes
;;;             dataframe structures in adfcolumn CLOS based
;;;             framework.  Currently contains the virtual class
;;;             DATAFRAME-LIKE.  The actual classes DATAFRAME-ARRAY
;;;             and DATAFRAME-MATRIXLIKE should be in a separate file. 

;;; What is this talk of 'release'? Klingons do not make software
;;; 'releases'.  Our software 'escapes', leaving a bloody trail of
;;; designers and quality assurance people in its wake.

(in-package :cls-dataframe)

;;; No real basis for work, there is a bit of new-ness and R-ness to
;;; this work. In particular, the notion of relation is key and
;;; integral to the analysis.  Tables are related and matched vectors,
;;; for example.  "column" vectors are related observations (by
;;; measure/recording) while "row" vectors are related readings (by
;;; case, possibly independence).  When possible, we want to place
;;; statistical semantics into the computational data object -- so for
;;; example, to state that it is a violation of use to consider rows
;;; which are not at the least conditionally independent (though the
;;; conditioning should be outside the data set, not internally
;;; specified), though the assumption violation should not be set up
;;; so that we can never violate -- only be reminded that we are
;;; indeed violating it, under the principle that statistical
;;; assumptions are made to be violated.

;;; Using the principle of how to design functional approaches, we
;;; want a verb-driven API for data collection construction.  We
;;; should encode independence or lack of, as a computable status.

;;; TODO: Need to figure out statistically-typed vectors.  We then map
;;; a series of typed vectors over to tables where columns are equal
;;; typed.  In a sense, this is a relation (1-1) of equal-typed
;;; arrays.  For the most part, this ends up making the R data.frame
;;; into a relational building block (considering 1-1 mappings using
;;; row ID as a relation).  Is this a worthwhile generalization or
;;; communicable analogy?

;;; verbs vs semantics for DF construction -- consider the possibily
;;; of how adverbs and verbs relate, where to put which semantically
;;; to allow for general approach.

;;; Need to consider modification APIs
;;; actions are:
;;; - import 
;;; - get/set row names (case names)
;;;          column names (variable names)
;;;          dataset values
;;;          annotation/metadata
;;; -   make sure that we do coherency checking in the exported
;;;     functions.
;;; - reshapeData/reformat/reshape a reformed version of the dataset (no
;;;           additional input). 
;;;           either overwriting or not, i.e. with or without copy.
;;; - check consistency of resulting data with metadata and related
;;;           data information.

;;; Is there any need for an N-way dataframe (N>2) ?  Am currently
;;; assuming not, that this is specializing only the "independent
;;; cases"-by-variables format and that there would be other tools for
;;; other structures.  In particular, we should be able to insert

;;; Misc Functions (to move into a lisp data manipulation support package)

(defun strsym->indexnum (df strsym)
  "Returns a number indicating the DF column labelled by STRSYM.
Probably should be generic/methods dispatching on DATAFRAME-LIKE type."
  (position strsym (varlabels df)))

(defun string->number (str)
  "Convert a string <str> representing a number to a number. A second
value is returned indicating the success of the conversion.  Examples:
   (string->number \"123\") ; =>  123 t
   (string->number \"1.23\") ; =>  1.23 t"
   (let ((*read-eval* nil)) ;; Q: replace nested let's with a let* (enforced serial eval)?
     (let ((num (read-from-string str)))
       (values num (numberp num)))))

#|
  (equal 'testme 'testme)
  (defparameter *test-pos* 'testme)
  (position *test-pos* (list 'a 'b 'testme 'c))
  (position #'(lambda (x) (equal x "testme")) (list "a" "b" "testme" "c"))
  (position #'(lambda (x) (equal x 1)) (list 2 1 3 4))
|#


(defun column-type-classifier (df column)
  "column type classifier, finds the smallest subtype that can
  accomodate the elements of list, in the ordering:

     fixnum < integer < float < complex < t

  Rational, float (any kind) are classified as double-float, and
  complex numbers as (complex double-float).  Meant to be used by
  dataframe constructors so we can guess at column data types. The
  presence of a non numeric in a column implies the column is
  represented as a non numeric, as reduces and numeric maps will
  fail.

  AJR: David made a great start, and what we need to do is construct
  appropriate statistical types to support AI-style guidance for
  appropriate statistical procedures, or at least give caveats for why
  they are not appropriate.

  By statistical types, I mean factors such as nominal, ordinal, as
  well as grouped observation structures such as
  profile-with-common-times, profile-with-heterogeneous-times,
  nestable-networks, separated-networks.

  So there could be:

  nominal < ordinal < fixnum < integer < ... 
  
  and for heterogeneous statistical components:

  profile-with-common-times < profile-with-heterogeneous-times <
  profile-unrelated

  nestable-networks < separated-networks

  or we could call them:

  network-with-common-features < network-with-no-common-features
  
  Please note that the above is NOT finalized, nor necessarily
  correct."

  (case (reduce #'max (map-column df #' 
				  (lambda (x)
				    (typecase x
				      (fixnum 0)
				      (integer 1)
				      ((or rational double-float) 2)
				      (complex 3)
				      (simple-array 4)
				      ((or symbol  keyword) 5)
				      (t 6))) column))
    (0 'fixnum)
    (1 'integer)
    (2 'double-float)
    (3 '(complex double-float))
    (4 'string) ;; for the moment a categorical variable
    (5 'keyword) ;; and likewise, regarded as a categorical varial
    (6 t))) ;; nil will end up here.
;;; abstract class: dataframe-like

;; In addition, see documentation string.  
;;
;; A dataframe-like class is an abstract class which looks like a
;; table, but has or follows or wishes it could satisfy the following
;; characteristics, suggestions, provisions, restrictions, conditions,
;; and suggestions:
;;
;; 1. within-column classed- and enforced-class columns (which could be classic
;;    comp-sci data classes, or statistically-originated classes, or any
;;    similar classed objects which could be statistically-processed
;;    data.  
;;    a. within-column classes should have appropriate API/methods for
;;       printing single values or a specified collection of values (subset,
;;       whole), as are requested. 
;;    b. a sensible means for modifying or replacing values (including
;;       with a means for missing or coarsened specification).
;;    c. For example: floating point values, printing only a subset of
;;       decimal places on demand; kinetic profiles, printing
;;       descriptive summary or full data, as requested.
;; 2. between-columns are associated with statistical variables for
;;    modeling purposes.  Columns, in the best of all worlds, should
;;    be components (singular values, vectors, paired-vectors describing
;;    kinetics, i.e. values and time-points, or values and
;;    state-points, networks, ordinal variables, nominal variables,
;;    real/rational data, integer, etc). 
;; 3. rows where the within-row relationship is that the data
;;    originate from a related observation.
;; 4. between-row relationships are that the observations are (conditionally)
;;    independent.  There should be metadata, though perhaps difficult to
;;    enforce, which should drive this (conditional) independence
;;    assumption, either that conditional on the dataset and generating
;;    process, the rows are independent, or that there is a within-row
;;    variable (classic variables such as center/site, or person/individual for
;;    classical longitudinal datastructures) for which conditional on this
;;    (or a number of similar) values, observations should be
;;    independent. 
;; 5. This abstract class needs an API, similar to xarray API. There
;;    should be methods for:
;;    a. retrieving values,
;;    b. setting (in the sense of changing) values,
;;    c. adding columns or rows,
;;    d. subsetting based on a query language.  This query language
;;       also needs an API so that class authors can utilize it as
;;       part of the subsetting.
;;    e. sensible printing (summaries or abbreviated components).
;; 6. Default storage type is a lisp array, but clearly one could
;;    build optimized array structues for all of them.
;; 7. we are building on matrix-like, so that we can steal
;;    pass-through, views, and copying routines from what is built for
;;    that.  Can we have an object which inherits from la-matrix and
;;    dataframe-like to become an la-dataframe ?   Part of what is
;;    needed is to ensure that as we progress through the the types, that
;;    we end up implementing at the right level.  
;;
;;    TODO: find out if matrix-like objects enforce common class for
;;    all values, or if it is just common storage type, i.e.:
;; 
;;    matrix-like -> la-matrix -> real-la-matrix -> double-la-matrix
;;    or  
;;    matrix-like -> la-matrix -> complex-la-matrix -> complex-double-la-matrix
;; 8. 

(defclass dataframe-like (matrix-like)
  (
   ;; STORE and STORE-CLASS need to be defined in the real
   ;; (non-virtual) class, since they define the storage mode.
   ;; Technically, we ought to be able to pull off store-class via
   ;; TYPE-OF, but that isn't quite clear at this point, since we
   ;; might want play corruption-tricks.  See the example in
   ;; dataframe-array.lisp for how this might work.  
   ;;
   ;; There could be examples of what this might end up be -- using
   ;; dataframe-like as a mix-in class, so that other structures share
   ;; some of the basic API work.
#|
   (store :initform nil
	  :accessor dataset
	  :documentation "not useful in the -like virtual class case,
 	    contains actual data")
   (store-class :initform nil
		:accessor store-class
		:documentation "Lisp class used for the dataframe storage.")
|#
   (var-types :initform nil
	      :initarg :var-types
	      :type list
	      :accessor var-types
	      :documentation "List of symbols representing classes
	        which describe the range of contents for a particular
	        variable. Symbols must be valid types for check-type,
	        or be morally equivalent (to be discussed what this
	        means later).  List order matches order of columns in
	        STORE. superceded by variables below.")

   ;; BIG question: do we lift out the dataframe metadata into a
   ;; separate class?  i.e. labels, statistical metadata related to
   ;; whether the variables are collected or set by design, or ...  I
   ;; (Tony) have not done this yet, but it is part of the goal of
   ;; having statistical thinking and philosophy embedded within the
   ;; business logic of this system.
   (case-labels :initform nil
		:initarg :case-labels
		:type list
		:accessor case-labels
		:documentation "labels used for describing cases (doc
		  metadata), possibly used for merging.")
   (var-labels :initform nil
	       :initarg :var-labels
	       :type list
	       :accessor var-labels
	       :documentation "Variable names. List order matches
	         order in STORE. superceded by variables below")
   (doc-string :initform nil
	       :initarg :doc
	       :accessor doc-string
	       :documentation "additional information, potentially
  	         uncomputable, possibly metadata, about dataframe-like
	         instance.")

   ;; The following probably belong along with the dataframe-array
   ;; class, NOT here.  Printing methods are in instance-specific
   ;; classes with real data.
   (variables :initarg :variables
	      :initform (list)
	      :accessor variables
	      :documentation " a plist of the meta data for each variable. ")
   (print-widths :initform nil
		 :initarg :print-widths
		 :accessor print-widths
		 :documentation " the print widths of each of the variables. "))
  (:documentation "Abstract class for standard statistical analysis
     dataset for (possible conditionally, externally) independent
     data.  Rows are considered to be independent, matching
     observations.  Columns are considered to be type-consistent,
     match a variable with distribution.  inherits from lisp-matrix
     base MATRIX-LIKE class.  MATRIX-LIKE (from lisp-matrix) is
     basically a rectangular table without storage.  We emulate that,
     and add storage, row/column labels, and within-column-typing.

     DATAFRAME-LIKE is the basic cases by variables framework.  Need
     to embed this within other structures which allow for generalized
     relations.  Goal is to ensure that relations imply and drive the
     potential for statistical relativeness such as correlation,
     interference, and similar concepts.

     So DATAFRAME-LIKE has column IDs (variable names), column
     types (variable class or type), row IDs (observation names and
     trackers), and a documentation string.

     STORE is the storage component.  We ignore this in the
     DATAFRAME-LIKE class, as it is the primary differentiator,
     spec'ing the structure used for storing the actual data.  We
     create methods which depend on STORE for access.  The only
     critical component is that STORE be a class which is
     xarray-compliant.  Examples of such mixins are DATAFRAME-ARRAY
     and DATAFRAME-MATRIXLIKE.  The rest of this structure is
     metadata."))

;;; Specializing on superclasses...
;;;
;;; Access and Extraction: implementations needed for any storage
;;; type.  But here, just to point out that we've got a specializing
;;; virtual subclass (DATAFRAME-LIKE specializing MATRIX-LIKE).


(defgeneric nvars (df)
  (:documentation "number of variables represented in storage type.")
  (:method ((df simple-array))
    (array-dimension df 1))
  (:method ((df dataframe-like))
    (xdim (store df) 1))
  (:method ((df array))
    (xdim df 1)))

#|
 (defun nvars-store (store)
  "Return number of variables (columns) in dataframe storage.  Doesn't
test that that list is a valid listoflist dataframe structure."
  (etypecase store
    (array (array-dimension store 1))
    (matrix-like (ncols store))
    (list (length (elt store 0)))))
|#

(defgeneric ncases (df)
  (:documentation "number of cases (indep, or indep within context,
  observantions) within DF storage form.")
  (:method ((df simple-array))
    (array-dimension df 0))
  (:method ((df matrix-like))
    (nrows df))
  (:method ((df list))
    (nrows df)) ;; probably should do a valid LISTOFLIST structure test but this would be inefficient
  (:method ((df array))
    (nrows df)))

(defun translate-column (df column &optional (nil-on-error nil))
  "for production use, we would wrap this in a handler to enable entry of the correct column id.
nil on error is for non interactive use"
  (typecase column
    (keyword
     (let ((col (position column (varlabels df))))
       (if col
	   col
	   (if nil-on-error nil
	       (error "Column name misspelt: try again ~a~%" column)))))
    (number column)
    (t (error "Invalid argument passed to translate-column ~a~%" column))))


(defun infer-dataframe-types (df)
  "infer the numeric types for each column in the dataframe. note that
all non numerc types are lumped into T, so further discrimination will
be required."
  (let ((column-types (loop for col  below (nvars df)
			    collect (column-type-classifier df col))))
    column-types))

;; Testing consistency/coherency.

(defgeneric consistent-dataframe-p (df)
  (:documentation "methods to check for consistency.  Mostly of
    internal interest, since ideally we'd have to use standard
    constructs to ensure that we do not get the dataframe structure
    misaligned.")
  ;; (:method (object) "General objects are not consistent dataframes!" nil)
  (:method ((df dataframe-like)) 
    "At minimum, must dispatch on virtual-class."
    (and
     ;; ensure dimensionality
     (= (length (var-labels df)) (ncols df)) ; array-dimensions (dataset df))
     (= (length (case-labels df)) (nrows df))
     (= (length (var-types df))  (ncols df))
     ;; ensure claimed STORE-CLASS
     ;; when dims are sane, ensure variable-typing is consistent
     (progn
       (dotimes (i (nrows df))
	 (dotimes (j (ncols df))
	   ;; xref bombs if not a df-like subclass so we don't worry
	   ;; about specialization.  Need to ensure xref throws a
	   ;; condition we can recover from.
	   ;; (check-type  (aref dt i j) (elt lot j)))))) ???
	   (typep (xref df i j) (nth j (var-types df))))) 
       t))))

(defun reduce-column (df function column )
  "reduce a column of a df with function yielding a scalar"
  (assert (and (>= column 0) (< column (ncols df))) )
  (loop with result = (xref df 0 column)
	for i from 1 below (nrows df) do
	  (setf result (funcall function result (xref df i column)))
	finally (return result)))

(defun map-column (df function column)
  (assert (and (>= column 0) (< column (ncols df))) )
  (loop with result = (make-sequence 'vector (nrows df) )
	for i from 1 below (nrows df) do
	  (setf (xref result i ) (funcall function (xref df i column)))
	finally (return result)))



;;; FUNCTIONS WHICH DISPATCH ON INTERNAL METHODS OR ARGS
;;;
;;; Q: change the following to generic functions and dispatch on 
;;; array, matrix, and dataframe?  Others?
(defun repeat-seq (n item)
  "dbh: append/recursion changed to loop.   It's a cleaner way to go.
  (repeat-seq 3 \"d\") ; => (\"d\" \"d\" \"d\")
  (repeat-seq 3 'd) ; => ('d 'd 'd)
  (repeat-seq 3 (list 1 2))"
  (if (>= n 1)
      (loop for i below n collect item  )))

(defun make-labels (initstr num)
  "generate a list of strings which can be used as labels, i.e. something like 
  (make-labels \"a\" 3) => '(\"a1\" \"a2\" \"a3\")."
  (check-type initstr string)
  (mapcar #'(lambda (x y)  (concatenate 'string x y))
	  (repeat-seq num initstr)
	  (mapcar #'(lambda (x) (format nil "~A" x)) (alexandria:iota num))))

(defun check-dataframe-params (data vartypes varlabels caselabels doc)
  "This will throw an exception (FIXME: Need to put together a CLS exception system, this could be part of it)"
  ;; type checking
  (check-type data (or matrix-like array list))
  (check-type caselabels sequence)
  (check-type varlabels sequence)
  (check-type vartypes sequence)
  (check-type doc string)
  ;; dimension checking
  (if vartypes   (assert (= (nvars data) (length vartypes))))
  (if varlabels  (assert (= (nvars data) (length varlabels))))
  (if caselabels (assert (= (ncases data) (length varlabels)))))



(defmacro build-dataframe (type) 
  `(progn
    (check-dataframe-params data vartypes varlabels caselabels doc)
    (let ((newcaselabels (if caselabels
			     caselabels
			     (make-labels "C" (ncases data))))
	  (newvarlabels (if varlabels
			    varlabels
			    (make-labels "V" (nvars data))))
	  ;; also should determine most restrictive possible (compsci
	  ;; and/or statistical) variable typing (integer, double,
	  ;; string, symbol, *).  FIXME: until we get the mixed typing system in place, we will just leave null
	  (newvartypes (if vartypes
			  vartypes
			  (make-labels "*" (nvars data)))))
      (make-instance ,type
		     :storage data
		     :nrows (length newcaselabels)
		     :ncols (length newvarlabels)
		     :case-labels newcaselabels
		     :var-labels newvarlabels
		     :var-types newvartypes))))

;;  (macroexpand '(build-dataframe 'test)))

(defgeneric make-dataframe2 (data &key vartypes varlabels caselabels doc)
  (:documentation "testing generic dispatch.  Data should be in table format desired for use."))


(defun make-comparison-function (df function field value)
  `#'(lambda (row) (funcall ,function (xref df row ,field) ,value)))

;;(defun dfquery (df ))

(defmethod dfextract (df  &key ( head 5) (tail 5) )
  "just for the moment "
  (let* ((rows (ncases df))
	 (head-rows (loop for row below  (min head rows) collect (dfrow df row)))
	 (tail-rows (loop for row from (max 0 (- rows tail)) below rows collect (dfrow df row))))
    ; this is only temprorary. need to get dataframe-list sorted out
    (make-dataframe (listoflist:listoflist->array  (append head-rows tail-rows))
		    :vartypes (vartypes df)
		    :varlabels (varlabels df))))

#| 
 (make-dataframe #2A((1.2d0 1.3d0) (2.0d0 4.0d0)))
 (make-dataframe #2A(('a 1) ('b 2)))
 (xref (make-dataframe #2A(('a 1) ('b 2))) 0 1)
 (xref (make-dataframe #2A(('a 1) ('b 2))) 1 0)
 (make-dataframe 4) ; ERROR, should we allow?
 (make-dataframe #2A((4)))
 (make-dataframe (rand 10 5)) ;; ERROR, but should work!
|#

(defparameter *CLS-DATE-FORMAT* :UK
  "should be one of :UK (d/m/y) :US (m/d/y) or maybe others as
  required.  Giving a hint to the parsing routine.  Suffix with a
  -TIME (is :US-TIME for MDY hhmmss. Or supply the ANTIK specification
  as a list '(2 1 0 3 4 5) ")

(defparameter *CLS-DATE-TEST-LIMIT* 5
  "The number of rows to check when deciding if the column is a date
  column or not.")


;;; Why is this "ANTIK"?  We naturally will be including the antik
;;; package within this framework. At this point we are heavy, heavy,
;;; heavy, and done on purpose.  Need to be heavy before we are
;;; light-weight.
(defun antik-date-format-helper (date)
  "provide decoding for shorthand notation in *CLS-DATE-FORMAT* or
allow the full spec to be supplied "
  (cond
    ((equal date :UK) '(2 1 0))
    ((equal date :UK-TIME) '(2 1 0 3 4 5))
    ((equal date :US) '(2 0 1))
    ((equal date :US-TIME) '(2 0 1 3 4 5))
    (t date)))

(defun date-conversion-fu (df)
  "for any string column in the dataframe, try to parse the first n
entries as a date according to the global format. If we can do that
successfully for at least one entry, the convert the column,
converting failures to nil"
  (labels ((read-timepoint (row column)
	     "read a timepoint. if there is an error return nil"
	     (handler-case
		 (antik:read-timepoint (xref df row column)
				       (antik-date-format-helper *CLS-DATE-FORMAT*))
	       (error () nil)))
	 
	   (date-column-detected (index)
	     "guess if the column has dates or not"
	     (loop
		for i below *CLS-DATE-TEST-LIMIT*
		collect  (read-timepoint i index) into result
		finally (return (some #'identity result))))
	 
	   (convert-date-column (column )
	     (loop for i below (nrows df) do
		  (setf (xref df i column) (read-timepoint i column)))))
    
    (let ((maybe-dates
	   (loop for i upto (length (vartypes df))
	      and item in (var-types df)
	      when (equal 'string item)
	      collect i)))
      
      (when maybe-dates
	(dolist (index maybe-dates)
	  (when (date-column-detected index)
	    (convert-date-column  index)
	    (setf (nth index (vartypes df) ) 'date)))))))

(defun classify-print-type (df column)
  (labels ((integer-variable (variable)
	     (member variable '(FIXNUM INTEGER RATIONAL)))
	   (float-variable (variable)
	     (member variable '(NUMBER FLOAT LONG-FLOAT SHORT-FLOAT SINGLE-FLOAT DOUBLE-FLOAT)))
	   (string-variable (variable)
	     (equal variable 'STRING))
	   (keyword-variable (variable)
	     (equal variable 'KEYWORD))
	   (date-variable (variable)
	     (member variable '(DATE ANTIK:TIMEPOINT))))

    (let ((variable-type (elt (var-types df) column)))
      
      (cond
	( (integer-variable variable-type) :INTEGER)
	((float-variable variable-type) :FLOAT)
	((keyword-variable variable-type) :KEYWORD)
	((string-variable variable-type) :STRING)
	((date-variable variable-type) :DATE)
	(t (error "classify-print-type, unrecognized type ~a~%" variable-type))))))
  
(defun determine-print-width (df  column)
  "build the format string by checking widths of each column. to be rewritten as a table "
  (labels ((numeric-width (the-col)
	     (reduce #'max (mapcar #'(lambda (x) (ceiling (log (abs x) 10))) (dfcolumn df the-col)) ))
	   (string-width (the-col)
	     (reduce  #'max (mapcar #'length (dfcolumn df the-col))))
	   (keyword-width (the-col)
	     (reduce #'max (mapcar #'(lambda (x) (length (symbol-name x))) (dfcolumn df the-col))))
	   ;; FIXME - what is the print width of a timepoint?
	   (date-width (the-col) 12))
    
    (case (classify-print-type df column)
      ((:INTEGER :FLOAT) (numeric-width column))
      (:KEYWORD          (keyword-width column))
      (:STRING           (string-width column))
      (:DATE             (date-width column))
      (t (error "determine-print-width, unrecognized type ~%" )))))


(defun make-variable-metadata (df)
  "This is a first attempt at consolidating the metadata for a
variable. ultimately i expect that the other lists will disappear when
I (DHodge?) figure out a convenient initiaslization method"
  (format t "vars = ~A~%" (nvars df))
  (loop for index below (nvars df) 
	collect
	(list
	 :name (elt (var-labels df) index) 
	 :type (elt (var-types df) index)
	 :print-type (classify-print-type df index)
	 :print-width (determine-print-width df index)) into variable-plist
	finally (setf (slot-value df 'variables) variable-plist)))

(defmethod initialize-instance :after ((df dataframe-like) &key)
  "Do post processing for variables after we initialize the object"
  ;; obviously I want to nuke var types & var labels at some point
  (unless (var-types df) 
    (setf (vartypes df) (infer-dataframe-types df)))
  (when (var-labels df)
    (setf (var-labels df) (mapcar #'(lambda (keyword)
				      (alexandria:make-keyword (string-upcase keyword))) (var-labels df))))
  (date-conversion-fu df)
  (make-variable-metadata df)
  (format t "Dataframe created:~% Variables ~{ ~a ~} ~% types  ~{~a,~}~%" (var-labels df) (var-types df)))

;;; FIXME: the following two functions hurt the eyes.  I think that
;;;
;;;      array->listoflist :order '(:column :row)
;;;
;;; would be a better approach.  But don't we already have this in the
;;; listoflist package?  and more critically, we should have this as a
;;; generic, so that it would be more like
;;;
;;;      dataframe->listoflist :order '(:column :row)
;;;

(defun row-order-as-list (ary)
  "Pull out data in row order into a list. naughty, should use xref"
  (let ((result (list))
	(nrows (nth 0 (array-dimensions ary)))
	(ncols (nth 1 (array-dimensions ary))))
    (dotimes (i ncols)
      (dotimes (j nrows)
	(append result (aref ary i j))))))

(defun col-order-as-list (ary)
  "Pull out data in column order into a list."
  (let ((result (list))
	(nrows (nth 0 (array-dimensions ary)))
	(ncols (nth 1 (array-dimensions ary))))
    (dotimes (i nrows)
      (dotimes (j ncols)
	(append result (aref ary i j))))))


;;; FIXME: need to have a by-reference and by-copy variant.
(defun transpose-array (ary)
  "map NxM to MxN."
  (make-array (reverse (array-dimensions ary))
      :initial-contents (col-order-as-list ary)))


(defun vartypes (df)
  "list of types for each column"
  (mapcar  (lambda (variable) (getf variable :name)) (variables  df))  )
;; or just:   (var-types df)  ??
;; something is not right about this...

(defun set-vartypes (df vt)
  (assert (= (length vt) (ncols df)))
  (setf (vartypes df) vt))

;;(defsetf vartypes set-vartypes)


;;; THE FOLLOWING 2 dual-sets done to provide error checking
;;; possibilities on top of the generic function structure.  Not
;;; intended as make-work!


(defun varlabels (df)
  "Variable-name handling for DATAFRAME-LIKE.  Needs error checking."
  (mapcar  (lambda (variable) (getf variable :type)) (variables  df)))
;; or just:   (var-labels df)  ??

(defun set-varlabels (df vl)
  "Variable-name handling for DATAFRAME-LIKE.  Needs error checking."
  (if (= (length (var-labels df))
	 (length vl))
      (setf (var-labels df) vl)
      (error "wrong size.")))

(defsetf varlabels set-varlabels) ;; FIXME!

;;; Case-name handling for Tables.  Needs error checking.
(defun caselabels (df)
  "Case-name handling for DATAFRAME-LIKE.  Needs error checking."
  (case-labels df))

(defun set-caselabels (df cl)
  "Case-name handling for DATAFRAME-LIKE.  Needs error checking."
  (if (= (length (case-labels df))
	 (length cl))
      (setf (case-labels df) cl)
      (error "set caselabels: wrong size.")))

(defsetf caselabels set-caselabels) ;; FIXME!


;;;;;;;;;;;; IMPLEMENTATIONS, with appropriate methods.
;; See also:
;; (documentation 'dataframe-like  'type)


;;; Do we establish methods for dataframe-like, which specialize to
;;; particular instances of storage?

(defparameter dataframe-print-formats
  '((FIXNUM . "~7D")
    (INTEGER . "~7D")
    (STRING . "~7A")
    (SIMPLE-STRING . "~A")
    (CONS . "~a")
    (SYMBOL . "~7a")
    (KEYWORD . "~7a")
    (RATIONAL . "~7a")
    (NUMBER . "~7a")
    (FLOAT . "~7a")
    (DATE . "~9a")
    (LONG-FLOAT . "~7,3G")
    (SHORT-FLOAT . "~7,3G")
    (SINGLE-FLOAT . "~7,3G")
    (DOUBLE-FLOAT . "~7,3G")))

(defparameter new-dataframe-print-formats
  '((FIXNUM . "D")
    (INTEGER . "D")
    (STRING . "A")
    (SIMPLE-STRING . "A")
    (CONS . "a")
    (SYMBOL . "7a")
    (KEYWORD . "a")
    (RATIONAL . "a")
    (NUMBER . "a")
    (FLOAT . "a")
    (DATE . "a")
    (LONG-FLOAT . "G")
    (SHORT-FLOAT . "~G")
    (SINGLE-FLOAT . "~G")
    (DOUBLE-FLOAT . "~G")))

(defun build-format-string (df)
  "build the format string by checking widths of each column. to be rewritten as a table "
  
  (loop for  variable in  (variables df) 
     collect (case (getf variable :print-type)
	       ((:INTEGER :KEYWORD :STRING :DATE) (format nil "~~~AA " (getf variable :print-width)))
	       (:FLOAT (format nil "~~~A,3G " (getf variable :print-width)))) into format-control
       
     finally  (return (format nil "~~{~{~a~}~~}~~%" format-control))))

(defun print-directive (df col)
  (cdr  (assoc (elt (vartypes df) col) DATAFRAME-PRINT-FORMATS)))

(defun print-headings (df stream)
  (loop for variable in (variables df)
     nconc (list
	    (1+ (max  (getf variable :print-width)
		      (length (symbol-name  (getf variable :name)))))
	    (getf variable :name) ) into control-string
     finally  (format stream "~{~VA~}~%" control-string) ))

(defun row (df row)
  (loop for col  below (ncols df)
     collect (xref df row col)))

(defmethod print-object ((object dataframe-like) stream)
  
  (print-unreadable-object (object stream :type t)
    (declare (optimize (debug 3)))
    (format stream " ~d x ~d" (nrows object) (ncols object))
    (terpri stream)
    ;; (format stream "~T ~{~S ~T~}" (var-labels object))
    (let ((format-control (build-format-string object))
	  (case-format (format nil "~~~AA: " (reduce #'max (mapcar #'length (case-labels object))))))
      (dotimes (j (ncols object))	; print labels
	(write-char #\tab stream)
	(write-char #\tab stream)
	(format stream "~T~A~T" (nth j (var-labels object))))
      (dotimes (i (nrows object))	; print obs row
	(terpri stream)
	(format stream case-format (nth i (case-labels object)))
	(format stream format-control (row object i))))))

#|
 (defun print-structure-relational (ds)
  "example of what we want the methods to look like.  Should be sort
of like a graph of spreadsheets if the storage is a relational
structure."
  (dolist (k (relations ds))
    (let ((currentRelationSet (getRelation ds k)))
      (print-as-row (var-labels currentRelationSet))
      (let ((j -1))
	(dolist (i (case-labels currentRelationSet))
	  (print-as-row
	   (append (list i)
		   (xref-obsn (dataset currentRelationSet)
                               (incf j)))))))))

 (defun testecase (s)
   (ecase s
     ((scalar) 1)
     ((asd asdf) 2)))

 (testecase 'scalar)
 (testecase 'asd)
 (testecase 'asdf)
 (testecase 'as)
|#


;;; Vector-like generalizations: we consider observation-like and
;;; variable-like to be abstract classes which provide row and column
;;; access to dataframe structures.  These will be specialized, in
;;; that rows correspond to an observation (or case?) which are
;;; multitype, while columns correspond to a variable, which must be
;;; singularly typed.

(defclass observation-like (dataframe-like)
  ()
  (:documentation "dataframe-like with only 1 row, is an observation-like."))

(defclass variable-like (dataframe-like)
  ()
  (:documentation "dataframe-like with only 1 column is a variable-like."))

;;; Need to implement views, i.e. dataframe-view-like,
;;; observation-view-like, variable-view-like.  



;;; Need to consider read-only variants, leveraging the xref
;;; strategy.



;;; Dataframe <-> Listoflist support
;; the following will be handy to help out folks adjust.  It should
;; provide a means to write code faster and better.
;; 
;; leverages listoflist support in our version of xarray
(defun listoflist->dataframe (lol) ; &key (type :row-major))
  "Create a cases-by-variables data frame consisting of numeric data,
from a ROW-MAJOR list-of-lists representation.  A COLUMN-MAJOR
representation should be handled using the transpose-listoflists
function."
  (check-type lol list) ; imperfect -- must verify all list elements are also lists.
  (if (listoflist:sublists-of-same-size-p lol)
      (make-dataframe  (listoflist:listoflist->array lol))
      (error "make-data-set-from-lists: no combining different length lists"))
  (error "make-data-set-from-lists: proposed name exists"))




;;; FIXME: THIS COMPLETELY OBSOLETE?
;;; from dataframe-xarray experiment

#| 
 (defmethod xref ((obj dataframe-like)  &rest subscripts)
  "For data-frame-like, dispatch on storage object."
  (xref (dataset obj) subscripts))

 (defmethod (setf xref) (value (obj dataframe-like) &rest subscripts)
  (setf (xref (dataset obj) subscripts) value))
  
 (defmethod xref ((obj matrix-like) &rest indices))
  
 (defmethod xtype ((obj dataframe-like))
  "Unlike the standard xtype, here we need to return a vector of the
  types.  Vectors can have single types, but arrays have single type.
  Dataframe-like have multiple types, variable-like single type,
  case-like has multiple types, and matrix-like has single type.")

 (defmethod xdims ((obj dataframe-like))
  (dataframe-dimensions obj))

 ;; use default methods at this point, except for potentially weird DFs
 (defmethod xdims* ())

 (defmethod xdim ((obj dataframe-like) index)
  (dataframe-dimension index))


 (defmethod xrank ())

 (defmethod slice ())
  
 (defmethod take ())

 (defmethod carray ())

 (defmacro with-dataframe (env &rest progn) 
  "Compute using variable names with with.data.frame type semantics.")

 (defmacro with-data (body)
  "Stream-handling, maintaining I/O through object typing.")

|#



(defun gen-seq (n &optional (start 1))
  "Generates an integer sequence of length N starting at START. Used
 for indexing.

 Possibly cleaner implementation:
  (loop (i n)
    (collect (+ i start)))
"
  (if (>= n start)
      (append (gen-seq (- n 1) start) (list n))))


