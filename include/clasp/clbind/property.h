/*
    File: property.h
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
#ifndef clbind_property_H
#define clbind_property_H

#include <clasp/core/translators.h>

#include <clasp/clbind/clbind_wrappers.h>
#include <clasp/clbind/policies.h>
#include <clasp/clbind/details.h>

namespace clbind {

template <typename T>
struct memberpointertraits {};

template <typename M, typename C>
struct memberpointertraits<M C::*> {
  typedef M member_type;
  typedef C class_type;
};

  extern void trapGetterMethoid();
template <typename GetterPolicies, typename OT, typename VariablePtrType>
class TEMPLATED_FUNCTION_GetterMethoid : public core::BuiltinClosure_O {
public:
  typedef TEMPLATED_FUNCTION_GetterMethoid<GetterPolicies,OT,VariablePtrType> MyType;
  typedef core::BuiltinClosure_O TemplatedBase;

private:
  typedef typename memberpointertraits<VariablePtrType>::member_type MemberType;
  typedef clbind::Wrapper<MemberType,MemberType*> WrapperType;
  VariablePtrType _MemberPtr;

public:
  virtual size_t templatedSizeof() const { return sizeof(*this); };

public:
  TEMPLATED_FUNCTION_GetterMethoid(core::GlobalEntryPoint_sp ep, VariablePtrType p) : core::BuiltinClosure_O(ep), _MemberPtr(p){
    trapGetterMethoid();
  };
  inline static LCC_RETURN LISP_CALLING_CONVENTION() {
    MyType* closure = gctools::untag_general<MyType*>((MyType*)lcc_closure);
    INCREMENT_FUNCTION_CALL_COUNTER(closure);
    core::T_sp arg0((gctools::Tagged)lcc_args[0]);
    OT *objPtr = gc::As<core::WrappedPointer_sp>(arg0)->cast<OT>();
    MemberType &orig = (*objPtr).*(closure->_MemberPtr);
    return Values(translate::to_object<MemberType, translate::dont_adopt_pointer>::convert(orig));
  }
    static inline LISP_ENTRY_0() {
    return entry_point_n(lcc_closure,0,NULL);
  }
  static inline LISP_ENTRY_1() {
    core::T_O* args[1] = {lcc_farg0};
    return entry_point_n(lcc_closure,1,args);
  }
  static inline LISP_ENTRY_2() {
    core::T_O* args[2] = {lcc_farg0,lcc_farg1};
    return entry_point_n(lcc_closure,2,args);
  }
  static inline LISP_ENTRY_3() {
    core::T_O* args[3] = {lcc_farg0,lcc_farg1,lcc_farg2};
    return entry_point_n(lcc_closure,3,args);
  }
  static inline LISP_ENTRY_4() {
    core::T_O* args[4] = {lcc_farg0,lcc_farg1,lcc_farg2,lcc_farg3};
    return entry_point_n(lcc_closure,4,args);
  }
  static inline LISP_ENTRY_5() {
    core::T_O* args[5] = {lcc_farg0,lcc_farg1,lcc_farg2,lcc_farg3,lcc_farg4};
    return entry_point_n(lcc_closure,5,args);
  }

};
};

namespace clbind {
template <typename GetterPolicies, typename OT, typename MemberType>
class TEMPLATED_FUNCTION_GetterMethoid<GetterPolicies, OT, MemberType *const(OT::*)> : public core::BuiltinClosure_O {
 public:
  typedef TEMPLATED_FUNCTION_GetterMethoid<GetterPolicies,OT,MemberType *const(OT::*)> MyType;
  typedef core::BuiltinClosure_O TemplatedBase;

private:
  typedef clbind::Wrapper<MemberType,MemberType*> WrapperType;
  string _Name;
  typedef MemberType *const(OT::*VariablePtrType);
  VariablePtrType _MemberPtr;
public:
  virtual size_t templatedSizeof() const { return sizeof(*this); };
  
public:
  TEMPLATED_FUNCTION_GetterMethoid(core::GlobalEntryPoint_sp ep, VariablePtrType p) : BuiltinClosure_O(ep), _MemberPtr(p){
    trapGetterMethoid();
  };
  static inline LCC_RETURN LISP_CALLING_CONVENTION() {
    MyType* closure = gctools::untag_general<MyType*>((MyType*)lcc_closure);
    INCREMENT_FUNCTION_CALL_COUNTER(closure);
    core::T_sp arg0((gctools::Tagged)lcc_args[0]);
    OT *objPtr = gc::As<core::WrappedPointer_sp>(arg0)->cast<OT>();
    MemberType *ptr = (*objPtr).*(closure->_MemberPtr);
    return translate::to_object<MemberType *, translate::dont_adopt_pointer>::convert(ptr);
  }
    static inline LISP_ENTRY_0() {
    return entry_point_n(lcc_closure,0,NULL);
  }
  static inline LISP_ENTRY_1() {
    core::T_O* args[1] = {lcc_farg0};
    return entry_point_n(lcc_closure,1,args);
  }
  static inline LISP_ENTRY_2() {
    core::T_O* args[2] = {lcc_farg0,lcc_farg1};
    return entry_point_n(lcc_closure,2,args);
  }
  static inline LISP_ENTRY_3() {
    core::T_O* args[3] = {lcc_farg0,lcc_farg1,lcc_farg2};
    return entry_point_n(lcc_closure,3,args);
  }
  static inline LISP_ENTRY_4() {
    core::T_O* args[4] = {lcc_farg0,lcc_farg1,lcc_farg2,lcc_farg3};
    return entry_point_n(lcc_closure,4,args);
  }
  static inline LISP_ENTRY_5() {
    core::T_O* args[5] = {lcc_farg0,lcc_farg1,lcc_farg2,lcc_farg3,lcc_farg4};
    return entry_point_n(lcc_closure,5,args);
  }

};
};

template <typename GetterPolicies, typename OT, typename VariablePtrType>
class gctools::GCStamp<clbind::TEMPLATED_FUNCTION_GetterMethoid<GetterPolicies, OT, VariablePtrType>> {
public:
  virtual size_t templatedSizeof() const { return sizeof(*this); };
  
public:
  static gctools::GCStampEnum const StampWtag = gctools::GCStamp<typename clbind::TEMPLATED_FUNCTION_GetterMethoid<GetterPolicies, OT, VariablePtrType>::TemplatedBase>::Stamp;
};


namespace clbind {
template <typename SetterPolicies, typename OT, typename VariablePtrType>
class SetterMethoid : public core::BuiltinClosure_O {
public:
  typedef SetterMethoid<SetterPolicies,OT,VariablePtrType> MyType;
  typedef core::BuiltinClosure_O TemplatedBase;

private:
  typedef typename memberpointertraits<VariablePtrType>::member_type MemberType;
  typedef clbind::Wrapper<MemberType,MemberType*> WrapperType;
  VariablePtrType _MemberPtr;

public:
  virtual size_t templatedSizeof() const { return sizeof(*this); };

public:
  SetterMethoid(core::GlobalEntryPoint_sp gep, VariablePtrType p) : core::BuiltinClosure_O(gep), _MemberPtr(p){
  };
  inline static LCC_RETURN LISP_CALLING_CONVENTION() {
    MyType* closure = gctools::untag_general<MyType*>((MyType*)lcc_closure);
    INCREMENT_FUNCTION_CALL_COUNTER(closure);
    ASSERT(lcc_nargs==2);
    core::T_sp arg0((gctools::Tagged)lcc_args[0]);
    core::T_sp arg1((gctools::Tagged)lcc_args[1]);
    OT *objPtr = gc::As<core::WrappedPointer_sp>(arg1)->cast<OT>();
    translate::from_object<MemberType> fvalue(arg0);
    (*objPtr).*(closure->_MemberPtr) = fvalue._v;
    gctools::return_type retv(arg0.raw_(),1);
    return retv;
  }
    static inline LISP_ENTRY_0() {
    return entry_point_n(lcc_closure,0,NULL);
  }
  static inline LISP_ENTRY_1() {
    core::T_O* args[1] = {lcc_farg0};
    return entry_point_n(lcc_closure,1,args);
  }
  static inline LISP_ENTRY_2() {
    core::T_O* args[2] = {lcc_farg0,lcc_farg1};
    return entry_point_n(lcc_closure,2,args);
  }
  static inline LISP_ENTRY_3() {
    core::T_O* args[3] = {lcc_farg0,lcc_farg1,lcc_farg2};
    return entry_point_n(lcc_closure,3,args);
  }
  static inline LISP_ENTRY_4() {
    core::T_O* args[4] = {lcc_farg0,lcc_farg1,lcc_farg2,lcc_farg3};
    return entry_point_n(lcc_closure,4,args);
  }
  static inline LISP_ENTRY_5() {
    core::T_O* args[5] = {lcc_farg0,lcc_farg1,lcc_farg2,lcc_farg3,lcc_farg4};
    return entry_point_n(lcc_closure,5,args);
  }

};
};

namespace clbind {
template <typename SetterPolicies, typename OT, typename MemberType>
class SetterMethoid<SetterPolicies, OT, MemberType *const(OT::*)> : public core::BuiltinClosure_O {
 public:
  typedef SetterMethoid<SetterPolicies,OT,MemberType *const(OT::*)> MyType;
  typedef core::BuiltinClosure_O TemplatedBase;

private:
  typedef clbind::Wrapper<MemberType,MemberType*> WrapperType;
  string _Name;
  typedef MemberType *const(OT::*VariablePtrType);
  VariablePtrType _MemberPtr;
public:
  virtual size_t templatedSizeof() const { return sizeof(*this); };

public:
  SetterMethoid(core::GlobalEntryPoint_sp gep, VariablePtrType p) : BuiltinClosure_O(gep), _MemberPtr(p){
  };
  static inline LCC_RETURN LISP_CALLING_CONVENTION() {
    MyType* closure = gctools::untag_general<MyType*>((MyType*)lcc_closure);
    INCREMENT_FUNCTION_CALL_COUNTER(closure);
    core::T_sp arg0((gctools::Tagged)lcc_args[0]);
    core::T_sp arg1((gctools::Tagged)lcc_args[1]);
    OT *objPtr = gc::As<core::WrappedPointer_sp>(arg1)->cast<OT>();
    translate::from_object<MemberType> fvalue(arg0);
    (*objPtr).*(closure->_MemberPtr) = fvalue._v;
    typename gctools::return_type ret(arg0.raw_(),1);
    return ret;
  }
    static inline LISP_ENTRY_0() {
    return entry_point_n(lcc_closure,0,NULL);
  }
  static inline LISP_ENTRY_1() {
    core::T_O* args[1] = {lcc_farg0};
    return entry_point_n(lcc_closure,1,args);
  }
  static inline LISP_ENTRY_2() {
    core::T_O* args[2] = {lcc_farg0,lcc_farg1};
    return entry_point_n(lcc_closure,2,args);
  }
  static inline LISP_ENTRY_3() {
    core::T_O* args[3] = {lcc_farg0,lcc_farg1,lcc_farg2};
    return entry_point_n(lcc_closure,3,args);
  }
  static inline LISP_ENTRY_4() {
    core::T_O* args[4] = {lcc_farg0,lcc_farg1,lcc_farg2,lcc_farg3};
    return entry_point_n(lcc_closure,4,args);
  }
  static inline LISP_ENTRY_5() {
    core::T_O* args[5] = {lcc_farg0,lcc_farg1,lcc_farg2,lcc_farg3,lcc_farg4};
    return entry_point_n(lcc_closure,5,args);
  }

};
};

template <typename SetterPolicies, typename OT, typename VariablePtrType>
class gctools::GCStamp<clbind::SetterMethoid<SetterPolicies, OT, VariablePtrType>> {
public:
  virtual size_t templatedSizeof() const { return sizeof(*this); };

public:
  static gctools::GCStampEnum const StampWtag = gctools::GCStamp<typename clbind::SetterMethoid<SetterPolicies, OT, VariablePtrType>::TemplatedBase>::Stamp;
};

#endif
