/*
    File: num_arith.cc
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
/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    num_arith.c  -- Arithmetic operations
*/
/*
    Copyright (c) 1990, Giuseppe Attardi.
    Copyright (c) 2001, Juan Jose Garcia Ripoll.
    Copyright (c) 2013, Christian E. Schafmeister

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#include <clasp/core/foundation.h>
#include <clasp/core/object.h>
#include <clasp/core/symbolTable.h>
#include <clasp/core/numbers.h>
#include <clasp/core/bignum.h>
#include <clasp/core/num_arith.h>
#include <clasp/core/wrappers.h>
#include <clasp/core/mathDispatch.h>

namespace core {

// This is a truncating division.
Integer_sp clasp_integer_divide(Integer_sp x, Integer_sp y) {
  MATH_DISPATCH_BEGIN(x, y) {
  case_Fixnum_v_Fixnum : {
      Fixnum fy = y.unsafe_fixnum();
      if (fy == 0)
        ERROR_DIVISION_BY_ZERO(x, y);
      else
        // Note that / truncates towards zero as of C++11, as we want.
        return clasp_make_fixnum(x.unsafe_fixnum() / fy);
    }
  case_Fixnum_v_Bignum :
    return _clasp_fix_divided_by_big(x.unsafe_fixnum(),
                                     gc::As_unsafe<Bignum_sp>(y));
  case_Bignum_v_Fixnum : {
      Fixnum fy = y.unsafe_fixnum();
      if (fy == 0)
        ERROR_DIVISION_BY_ZERO(x, y);
      else
        return _clasp_big_divided_by_fix(gc::As_unsafe<Bignum_sp>(x),
                                         y.unsafe_fixnum());
    }
  case_Bignum_v_Bignum :
    return _clasp_big_divided_by_big(gc::As_unsafe<Bignum_sp>(x),
                                     gc::As_unsafe<Bignum_sp>(y));
  case_Fixnum_v_NextBignum :
    return fix_divided_by_next(x.unsafe_fixnum(),
                               gc::As_unsafe<TheNextBignum_sp>(x));
  case_NextBignum_v_Fixnum : {
      T_mv trunc = core__next_ftruncate(gc::As_unsafe<TheNextBignum_sp>(x),
                                        y.unsafe_fixnum());
      T_sp quotient = trunc;
      return gc::As_unsafe<Integer_sp>(trunc);
    }
  case_NextBignum_v_NextBignum : {
      // FIXME: MPN doesn't export a quotient-only division that I can see,
      // but we could call a version of truncate that doesn't cons up the
      // actual bignum for the remainder, hypothetically.
      // Would save some heap allocation.
      T_mv trunc = core__next_truncate(gc::As_unsafe<TheNextBignum_sp>(x),
                                       gc::As_unsafe<TheNextBignum_sp>(y));
      T_sp quotient = trunc;
      return gc::As_unsafe<Integer_sp>(trunc);
    }
  };
  MATH_DISPATCH_END();
  UNREACHABLE();
}

CL_LAMBDA(&rest nums);
CL_DECLARE();
CL_DOCSTRING("gcd");
CL_DEFUN Integer_sp cl__gcd(List_sp nums) {
  if (nums.nilp())
    return clasp_make_fixnum(0);
  /* INV: clasp_gcd() checks types */
  Integer_sp gcd = gc::As<Integer_sp>(oCar(nums));
  nums = oCdr(nums);
  if (nums.nilp()) {
    return (clasp_minusp(gcd) ? gc::As<Integer_sp>(clasp_negate(gcd)) : gcd);
  }
  while (nums.consp()) {
    gcd = clasp_gcd(gcd, gc::As<Integer_sp>(oCar(nums)));
    nums = oCdr(nums);
  }
  return gcd;
}

// NOTE: C++17 defines a gcd which could hypothetically be faster than
// Euclid's algorithm. (Probably not though, machine integers are small.)
// In any case we should probably use it, if C++ implementations ever
// reliably get that far.
gc::Fixnum gcd(gc::Fixnum a, gc::Fixnum b)
{
    if (a == 0)
      return (std::abs(b));
    return gcd(b % a, a);
}

Integer_sp clasp_gcd(Integer_sp x, Integer_sp y, int yidx) {
  MATH_DISPATCH_BEGIN(x, y) {
  case_Fixnum_v_Fixnum :
    return clasp_make_fixnum(gcd(x.unsafe_fixnum(), y.unsafe_fixnum()));
  case_Fixnum_v_NextBignum :
    return core__next_fgcd(gc::As_unsafe<TheNextBignum_sp>(y),
                           x.unsafe_fixnum());
  case_NextBignum_v_Fixnum :
    return core__next_fgcd(gc::As_unsafe<TheNextBignum_sp>(x),
                           y.unsafe_fixnum());
  case_NextBignum_v_NextBignum :
    return core__next_gcd(gc::As_unsafe<TheNextBignum_sp>(x),
                          gc::As_unsafe<TheNextBignum_sp>(y));
  case_Fixnum_v_Bignum : {
      x = Bignum_O::create(x.unsafe_fixnum());
      break;
    }
  case_Bignum_v_Fixnum : {
      y = Bignum_O::create(y.unsafe_fixnum());
      break;
    }
    default: break;
  };
  MATH_DISPATCH_END();
  Bignum_sp temp = gc::As<Bignum_sp>(_clasp_big_gcd(gc::As<Bignum_sp>(x),
                                                    gc::As<Bignum_sp>(y)));
  if (temp->fits_sint_p())
    return clasp_make_fixnum(temp->as_int());
  else return temp;
}

CL_LAMBDA(&rest args);
CL_DECLARE();
CL_DOCSTRING("lcm");
CL_DEFUN Integer_sp cl__lcm(List_sp nums) {
  if (nums.nilp())
    return clasp_make_fixnum(1);
  /* INV: clasp_gcd() checks types. By placing `numi' before `lcm' in
	   this call, we make sure that errors point to `numi' */
  Integer_sp lcm = gc::As<Integer_sp>(oCar(nums));
  int yidx = 1;
  nums = oCdr(nums);
  while (nums.consp()) {
    Integer_sp numi = gc::As<Integer_sp>(oCar(nums));
    nums = oCdr(nums);
    yidx++;
    Number_sp t = clasp_times(lcm, numi);
    Number_sp g = clasp_gcd(numi, lcm);
    if (!clasp_zerop(g)) {
      lcm = gc::As<Integer_sp>(clasp_divide(t, g));
    }
  }
  return clasp_minusp(lcm) ? gc::As<Integer_sp>(clasp_negate(lcm)) : gc::As<Integer_sp>(lcm);
};

  SYMBOL_EXPORT_SC_(ClPkg, gcd);
  SYMBOL_EXPORT_SC_(ClPkg, lcm);

};
