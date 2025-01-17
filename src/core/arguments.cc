/*
    File: arguments.cc
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
#include <clasp/core/foundation.h>
#include <clasp/core/object.h>
#include <clasp/core/symbolTable.h>
#include <clasp/core/lambdaListHandler.h>
#include <clasp/core/activationFrame.h>
#include <clasp/core/arguments.h>

namespace core {

List_sp Argument::lambda_list() const {
  return ((this->_ArgTarget));
};

Symbol_sp Argument::symbol() const {
  return ((gc::As<Symbol_sp>(this->_ArgTarget)));
};

List_sp Argument::classified() const {
  if (this->_ArgTargetFrameIndex == SPECIAL_TARGET) {
    return coerce_to_list(Cons_O::create(ext::_sym_specialVar, this->_ArgTarget));
  } else if (this->_ArgTargetFrameIndex >= 0) {
    return coerce_to_list(Cons_O::create(ext::_sym_lexicalVar, Cons_O::create(this->_ArgTarget, make_fixnum(this->_ArgTargetFrameIndex))));
  } else if (this->_ArgTargetFrameIndex == UNDEFINED_TARGET) {
    return ((nil<List_V>()));
  }
  SIMPLE_ERROR(("Illegal target"));
}

LambdaListHandler_sp Argument::lambdaListHandler() const {
  return ((gc::As<LambdaListHandler_sp>(this->_ArgTarget)));
}

string Argument::asString() const {
  stringstream ss;
  ss << "#<Argument ";
  ss << ":target ";
  ss << _rep_(this->_ArgTarget);
  ss << " :tfi ";
  ss << this->_ArgTargetFrameIndex;
  ss << " >  ";
  return ((ss.str()));
}

string ArgumentWithDefault::asString() const {
  stringstream ss;
  ss << "#<ArgumentWithDefault ";
  ss << ":target ";
  ss << _rep_(this->_ArgTarget);
  ss << " :tfi ";
  ss << this->_ArgTargetFrameIndex;
  ss << " :default ";
  ss << _rep_(this->_Default);
  ss << " >  ";
  return ((ss.str()));
}

string RequiredArgument::asString() const {
  stringstream ss;
  ss << "#<RequiredArgument ";
  ss << ":target ";
  this->Base::asString();
  ss << " >  ";
  return ((ss.str()));
}

string OptionalArgument::asString() const {
  stringstream ss;
  ss << "#<OptionalArgument ";
  ss << ":target ";
  ss << this->Base::asString();
  if (this->_Sensor.isDefined()) {
    ss << " :sensor ";
    ss << this->_Sensor.asString();
  }
  ss << " >  ";
  return ((ss.str()));
}

string RestArgument::asString() const {
  stringstream ss;
  ss << "#<RestArgument ";
  ss << ":target ";
  ss << _rep_(this->_ArgTarget);
  ss << " :tfi ";
  ss << this->_ArgTargetFrameIndex;
  ss << " >  ";
  return ((ss.str()));
}

string KeywordArgument::asString() const {
  stringstream ss;
  ss << "#<KeywordArgument ";
  ss << ":keyword " << _rep_(this->_Keyword);
  ss << " :target ";
  ss << this->Base::asString();
  if (this->_Sensor.isDefined()) {
    ss << " :sensor ";
    ss << this->_Sensor.asString();
  }
  ss << " >  ";
  return ((ss.str()));
}

string AuxArgument::asString() const {
  stringstream ss;
  ss << "#<AuxArgument ";
  ss << ":target ";
  this->Base::asString();
  ss << " :expression ";
  ss << _rep_(this->_Expression);
  ss << " >  ";
  return ((ss.str()));
}

void ScopeManager::new_special_binding(Symbol_sp var, T_sp val)
{
  this->_Bindings[this->_NextBindingIndex]._Var = var;
  this->_Bindings[this->_NextBindingIndex]._Val = var->threadLocalSymbolValue();
  this->_NextBindingIndex++;
  var->set_threadLocalSymbolValue(val);
}

ScopeManager::~ScopeManager() {
  for ( size_t ii = 0; ii<this->_NextBindingIndex; ++ii ) {
    gc::As_unsafe<Symbol_sp>(this->_Bindings[ii]._Var)->set_threadLocalSymbolValue(this->_Bindings[ii]._Val);
  }
}

void ValueEnvironmentDynamicScopeManager::ensureLexicalElementUnbound( const Argument& argument) {
  this->new_binding(argument,unbound<core::T_O>());
}


bool ValueEnvironmentDynamicScopeManager::lexicalElementBoundP_(const Argument &argument) {
  return ((this->_Environment->activationFrameElementBoundP(argument._ArgTargetFrameIndex)));
}

void ValueEnvironmentDynamicScopeManager::new_binding(const Argument &argument, T_sp val) {
  if (argument._ArgTargetFrameIndex == SPECIAL_TARGET) {
    Symbol_sp sym = gc::As_unsafe<Symbol_sp>(argument._ArgTarget);
    this->new_special_binding(sym, val);
    return;
  }
  ASSERTF(argument._ArgTargetFrameIndex >= 0, BF("Illegal ArgTargetIndex[%d] for lexical variable[%s]") % argument._ArgTargetFrameIndex % _rep_(argument._ArgTarget));
  T_sp argTarget = argument._ArgTarget;
  this->_Environment->new_binding(gc::As<Symbol_sp>(argTarget), argument._ArgTargetFrameIndex, val);
}

void ValueEnvironmentDynamicScopeManager::va_rest_binding(const Argument &argument) {
  if (argument._ArgTargetFrameIndex == SPECIAL_TARGET) {
    SIMPLE_ERROR(("You cannot bind &VA-REST argument to a special"));
  }
  ASSERTF(argument._ArgTargetFrameIndex >= 0, BF("Illegal ArgTargetIndex[%d] for lexical variable[%s]") % argument._ArgTargetFrameIndex % _rep_(argument._ArgTarget));
  Vaslist_sp valist(&this->valist());
  T_sp argTarget = argument._ArgTarget;
  this->_Environment->new_binding(gc::As<Symbol_sp>(argTarget), argument._ArgTargetFrameIndex, valist);
}

void ValueEnvironmentDynamicScopeManager::new_variable(List_sp classified, T_sp val) {
  Symbol_sp type = gc::As<Symbol_sp>(oCar(classified));
  if (type == ext::_sym_lexicalVar) {
    Symbol_sp sym = gc::As<Symbol_sp>(oCadr(classified));
    int idx = unbox_fixnum(gc::As<Fixnum_sp>(oCddr(classified)));
    ASSERTF(idx >= 0, BF("Illegal target index[%d] for lexical variable[%s]") % idx % _rep_(sym));
    this->_Environment->new_binding(sym, idx, val);
    return;
  } else if (type == ext::_sym_specialVar) {
    Symbol_sp sym = gc::As<Symbol_sp>(oCdr(classified));
    this->new_special_binding(sym,val);
    return;
  }
  SIMPLE_ERROR(("Illegal classified type: %s\n") , _rep_(classified));
}

void ValueEnvironmentDynamicScopeManager::new_special(List_sp classified) {
  ASSERT(oCar(classified) == _sym_declaredSpecial);
  Symbol_sp sym = gc::As<Symbol_sp>(oCdr(classified));
  this->_Environment->defineSpecialBinding(sym);
}


void StackFrameDynamicScopeManager::new_binding(const Argument &argument, T_sp val) {
  if (argument._ArgTargetFrameIndex == SPECIAL_TARGET) {
    Symbol_sp sym = gc::As_unsafe<Symbol_sp>(argument._ArgTarget);
    this->new_special_binding(sym, val);
    return;
  }
  ASSERTF(argument._ArgTargetFrameIndex >= 0, BF("Illegal ArgTargetIndex[%d] for lexical variable[%s]") % argument._ArgTargetFrameIndex % _rep_(argument._ArgTarget));
  gctools::fill_frame_one_indexed( &this->frame, argument._ArgTargetFrameIndex, val.raw_() );
}

void StackFrameDynamicScopeManager::va_rest_binding(const Argument &argument) {
  if (argument._ArgTargetFrameIndex == SPECIAL_TARGET) {
    SIMPLE_ERROR(("You cannot bind &VA-REST argument to a special"));
  }
  ASSERTF(argument._ArgTargetFrameIndex >= 0, BF("Illegal ArgTargetIndex[%d] for lexical variable[%s]") % argument._ArgTargetFrameIndex % _rep_(argument._ArgTarget));
  Vaslist_sp valist(&this->valist());
  gctools::fill_frame_one_indexed( &this->frame, argument._ArgTargetFrameIndex, valist.raw_() );
}

void StackFrameDynamicScopeManager::ensureLexicalElementUnbound( const Argument& argument) {
  this->frame.mkunboundValue_(argument._ArgTargetFrameIndex);
}

bool StackFrameDynamicScopeManager::lexicalElementBoundP_(const Argument &argument) {
  //  core::T_O **array(frame::ValuesArray(this->frame));
  return !gctools::tagged_unboundp(this->frame.value_(argument._ArgTargetFrameIndex));
}

T_sp StackFrameDynamicScopeManager::lexenv() const {
  //  printf("%s:%d Returning nil as the lexical environment for a StackFrameDynamicScopeManager\n", __FILE__, __LINE__);
  return nil<core::T_O>();
}
};
