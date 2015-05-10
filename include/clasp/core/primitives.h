/*
    File: primitives.h
*/

/*
Copyright (c) 2014, Christian E. Schafmeister
 
CLASP is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
 
See directory 'clasp/licenses' for full details.
 
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/
/* -^- */
#ifndef	_core_primitives_H
#define _core_primitives_H

#include <clasp/core/object.h>
#include <clasp/core/corePackage.fwd.h>
#include <clasp/core/lispVector.h>
#include <clasp/core/character.fwd.h>
#include <clasp/core/wrappers.h>


namespace core
{


    extern T_sp cl_macroFunction(Symbol_sp symbol, T_sp env);
    extern T_mv af_separatePairList(List_sp listOfPairs);

    extern Symbol_mv af_functionBlockName(T_sp functionName);

    extern void af_ensure_single_dispatch_generic_function(Symbol_sp gfname, LambdaListHandler_sp llh);

    extern T_mv af_read_delimited_list(Character_sp chr, T_sp input_stream_designator, T_sp recursive_p);

    T_sp cl_read(T_sp input_stream_designator, T_sp eof_error_p=_Nil<T_O>(), T_sp eof_value=_Nil<T_O>(), T_sp recursive_p=_Nil<T_O>());

    extern void af_ensureSingleDispatchMethod(Symbol_sp gfname, Class_sp receiver_class, LambdaListHandler_sp lambda_list_handler, List_sp declares, gc::Nilable<Str_sp> docstring, Function_sp body );


#if 0
    EXTERN_FN(read);
    EXTERN_FN(read_delimited_list);
    EXTERN_FN(convert_to_list_of_classes);

    EXTERN_GENERIC(make_instance);
    EXTERN_GENERIC(ensure_class_using_class);
    EXTERN_GENERIC(reinitialize_instance);
#endif

    T_sp af_type_of(T_sp x);
    T_sp af_notany(T_sp predicate, List_sp sequences);
    T_sp af_every(T_sp predicate, List_sp sequences);

    T_sp cl_mapcar(T_sp func_desig, List_sp lists);

    List_sp af_append(List_sp lists);

    
//    Stream_mv af_open(T_sp filespec, Symbol_sp direction, T_sp element_type, T_sp if_exists, T_sp if_does_not_exist, T_sp external_format );

    Symbol_mv af_gensym(T_sp x);







    class SequenceStepper
    {
    public:
	virtual bool advance() = 0;
	virtual T_sp element() const = 0;
	virtual ~SequenceStepper() {};
    };




    class VectorStepper : public SequenceStepper
    {
        FRIEND_GC_SCANNER();
    GCPRIVATE:
	Vector_sp	_Domain;
	int		_Index;
    public:
	VectorStepper(Vector_sp domain) : _Domain(domain), _Index(0) {}; 
	virtual bool advance() { this->_Index++; return (this->_Index >= cl_length(this->_Domain));};
	virtual T_sp element() const
	{
	    if (this->_Index<cl_length(this->_Domain))
	    {
		return this->_Domain->elt(this->_Index);
	    } else
	    {
		return _Nil<T_O>();
	    }
	};
    };





    class ConsStepper : public SequenceStepper
    {
        FRIEND_GC_SCANNER();
    public://private
	List_sp	_Cur;
    public:
	ConsStepper(List_sp first) : _Cur(first) {};
	virtual bool advance() { this->_Cur = oCdr(this->_Cur); return this->_Cur.nilp(); };
	virtual T_sp element() const { return oCar(this->_Cur);};
    };







    /*! A class that generates lists of elements drawn from a list of sequences.
      Given (a1 a2 a3) (b1 b2 b3) (c1 c2 c3)
      Will successively generate (a1 b1 c1) (a2 b2 c2) (a3 b3 c3) */
    class ListOfSequenceSteppers //: public gctools::StackRoot
    {
	friend class ListOfListSteppers;
    private:
        gctools::Vec0<SequenceStepper*>	_Steppers;
	bool				_AtEnd;
    public:
	ListOfSequenceSteppers() {};
	ListOfSequenceSteppers(List_sp sequences);
	virtual ~ListOfSequenceSteppers();
	bool atEnd() const { return this->_AtEnd;};
//	List_sp makeListFromCurrentSteppers() const;
	void fillValueFrameUsingCurrentSteppers(ActivationFrame_sp frame) const;
	/* Advance all of the steppers - return false if the end is hit otherwise true */
	bool advanceSteppers();
	int size() { return this->_Steppers.size();};

    };
};


namespace core {
    T_sp cl_mapc(T_sp op, List_sp lists);
    T_sp cl_mapcar(T_sp op, List_sp lists);

};





namespace core {

    /*! Return the SourceFileInfo for the obj - if obj is nil then return 
      one for anonymous */

    /*! Expose the primitives to cando */
    void	initialize_primitives();
    /*! Expose the primitives to python */
    void	initializePythonPrimitives(Lisp_sp lisp);







};
#endif /* _core_primitives_H */
