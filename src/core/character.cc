/*
    File: character.cc
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
//#define DEBUG_LEVEL_FULL

#pragma clang diagnostic push
//#pragma clang diagnostic ignored "-Wunused-local-typedef"
#include <boost/algorithm/string.hpp>
#pragma clang diagnostic pop
#include <clasp/core/foundation.h>
#include <clasp/core/primitives.h> // core__list_from_vaslist
#include <clasp/core/common.h>
#include <clasp/core/array.h>
#include <clasp/core/symbolTable.h>
#include <clasp/core/environment.h>
#include <clasp/core/designators.h>
#include <clasp/core/character.h>
#include <clasp/core/numberToString.h>
#include <clasp/core/wrappers.h>
#include <clasp/core/exceptions.h>
#include <clasp/core/hashTableEqual.h>
#include <clasp/core/evaluator.h>

namespace core {


void handleWideCharactersError(claspCharacter cc)
{
  SIMPLE_ERROR(("A wide character with the value %d was encountered in a function that needed a base-char") , cc);
}

CL_LAMBDA(arg)
CL_DECLARE();
CL_DOCSTRING(R"dx(CLHS: graphic-char-p)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__graphic_char_p(Character_sp cc) {
  claspCharacter c = clasp_as_claspCharacter(cc);
  // Does not seem to work as it should for codes > 255, not even in Xcode, not even with iswgraph instead of isgraph
  // return x == ' ' || iswgraph(x);
  // Translated from ccl definition in %control-char-p/graphic-char-p
  // sbcl does return c > 159 || ((31 < c) && (c < 127));
  if (
            ((c >= 0x00) && (c <= 0x1f))     ||
            ((c >= 0x7f) && (c <= 0x9f))     ||
            (c == 0x34f)                     ||
            ((c >= 0x200c) && (c <= 0x200f)) ||
            ((c >= 0x202a) && (c <= 0x202e)) ||
            ((c >= 0x2060) && (c <= 0x2063)) ||
            ((c >= 0x206a) && (c <= 0x206f)) ||
            ((c >= 0xf700) && (c <= 0xf7ff)) ||
            ((c >= 0xfe00) && (c <= 0xfe0f)) ||
            ((c >= 0xfeff) && (c <= 0xfeff)) ||
            ((c >= 0xfff0) && (c <= 0xfffd)) ||
            ((c >= 0xe0000) && (c <= 0xefffd))
            )
    return false;
    else return true;
};

CL_LAMBDA(arg)
CL_DECLARE();
CL_DOCSTRING(R"dx(lower_case_p)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__lower_case_p(Character_sp c) {
  claspCharacter x = clasp_as_claspCharacter(c);
  return clasp_islower(x);
};

CL_LAMBDA(arg)
CL_DECLARE();
CL_DOCSTRING(R"dx(upper_case_p)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__upper_case_p(Character_sp c) {
  claspCharacter x = clasp_as_claspCharacter(c);
  return clasp_isupper(x);
};

CL_LAMBDA(arg)
CL_DECLARE();
CL_DOCSTRING(R"dx(both_case_p)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__both_case_p(Character_sp c) {
  claspCharacter x = clasp_as_claspCharacter(c);
  return clasp_isupper(x) || clasp_islower(x);
};

CL_LAMBDA(char)
CL_DECLARE();
CL_DOCSTRING(R"dx(alphanumericp)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__alphanumericp(Character_sp ch) {
  claspCharacter x = clasp_as_claspCharacter(ch);
  if (x < 128) {
    return isalpha(x) || isdigit(x);
  }
  return false;
};

CL_LAMBDA(char)
CL_DECLARE();
CL_DOCSTRING(R"dx(charUpcase)dx")
DOCGROUP(clasp)
CL_DEFUN Character_sp cl__char_upcase(Character_sp ch) {
  return clasp_make_character(claspCharacter_upcase(clasp_as_claspCharacter(ch)));
};

CL_LAMBDA(char)
CL_DECLARE();
CL_DOCSTRING(R"dx(charDowncase)dx")
DOCGROUP(clasp)
CL_DEFUN Character_sp cl__char_downcase(Character_sp ch) {
  return clasp_make_character(claspCharacter_downcase(clasp_as_claspCharacter(ch)));
};

/*! Return -1 if a<b
      0 if a == b
      +1 if a > b
    */
inline int claspCharacter_basic_compare(claspCharacter na, claspCharacter nb) {
  if (na < nb)
    return -1;
  if (na == nb)
    return 0;
  return 1;
}

// Do <=, <, whatever, based on s and t and the above.
bool character_comparison(int s, int t, Character_sp x, Character_sp y,
                          bool preserve_case = true) {
  claspCharacter cx = clasp_as_claspCharacter(x);
  claspCharacter cy = clasp_as_claspCharacter(y);
  if (!preserve_case) {
    cx = claspCharacter_upcase(cx);
    cy = claspCharacter_upcase(cy);
  }
  int dir = s * claspCharacter_basic_compare(cx, cy);
  return !(dir < t);
}

bool monotonic(int s, int t, Vaslist_sp args, bool preserve_case = true) {
  Character_sp x = gc::As<Character_sp>(args->next_arg());
  Character_sp y;
  while (args->remaining_nargs() != 0) {
    y = gc::As<Character_sp>(args->next_arg());
    // If we find a false comparison we exit immediately.
    if (!(character_comparison(s, t, x, y, preserve_case)))
      return false;
    x = y;
  }
  return true;
};

CL_LAMBDA(char1 char2)
CL_DECLARE();
CL_DOCSTRING(R"dx(two-arg char<)dx")
DOCGROUP(clasp)
CL_DEFUN bool core__two_arg_char_LT_(Character_sp char1, Character_sp char2) {
  return character_comparison(-1, 1, char1, char2);
}

CL_LAMBDA(core:&va-rest args)
CL_DECLARE();
CL_DOCSTRING(R"dx(Return true if characters are monotonically increasing)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__char_LT_(Vaslist_sp args) {
  if (args->remaining_nargs() == 0) PROGRAM_ERROR();
  else return monotonic(-1, 1, args);
};

CL_LAMBDA(char1 char2)
CL_DECLARE();
CL_DOCSTRING(R"dx(two-arg char>)dx")
DOCGROUP(clasp)
CL_DEFUN bool core__two_arg_char_GT_(Character_sp char1, Character_sp char2) {
  return character_comparison(1, 1, char1, char2);
}

CL_LAMBDA(core:&va-rest args)
CL_DECLARE();
CL_DOCSTRING(R"dx(Return true if characters are monotonically decreasing)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__char_GT_(Vaslist_sp args) {
  if (args->remaining_nargs() == 0) PROGRAM_ERROR();
  else return monotonic(1, 1, args);
};

CL_LAMBDA(char1 char2)
CL_DECLARE();
CL_DOCSTRING(R"dx(two-arg char<=)dx")
DOCGROUP(clasp)
CL_DEFUN bool core__two_arg_char_LE_(Character_sp char1, Character_sp char2) {
  return character_comparison(-1, 0, char1, char2);
}

CL_LAMBDA(core:&va-rest args)
CL_DECLARE();
CL_DOCSTRING(R"dx(Return true if characters are monotonically non-decreasing)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__char_LE_(Vaslist_sp args) {
  if (args->remaining_nargs() == 0) PROGRAM_ERROR();
  else return monotonic(-1, 0, args);
};

CL_LAMBDA(char1 char2)
CL_DECLARE();
CL_DOCSTRING(R"dx(two-arg char>=)dx")
DOCGROUP(clasp)
CL_DEFUN bool core__two_arg_char_GE_(Character_sp char1, Character_sp char2) {
  return character_comparison(1, 0, char1, char2);
}

CL_LAMBDA(core:&va-rest args)
CL_DECLARE();
CL_DOCSTRING(R"dx(Return true if characters are monotonically non-increasing)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__char_GE_(Vaslist_sp args) {
  if (args->remaining_nargs() == 0) PROGRAM_ERROR();
  else return monotonic(1, 0, args);
};

CL_LAMBDA(char1 char2)
CL_DECLARE();
CL_DOCSTRING(R"dx(two-arg char-lessp)dx")
DOCGROUP(clasp)
CL_DEFUN bool core__two_arg_char_lessp(Character_sp char1, Character_sp char2) {
  return character_comparison(-1, 1, char1, char2, false);
}

CL_LAMBDA(core:&va-rest args)
CL_DECLARE();
CL_DOCSTRING(R"dx(Return true if characters are monotonically increasing, ignore case)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__char_lessp(Vaslist_sp args) {
  if (args->remaining_nargs() == 0) PROGRAM_ERROR();
  else return monotonic(-1, 1, args, false);
};

CL_LAMBDA(char1 char2)
CL_DECLARE();
CL_DOCSTRING(R"dx(two-arg char-greaterp)dx")
DOCGROUP(clasp)
CL_DEFUN bool core__two_arg_char_greaterp(Character_sp char1, Character_sp char2) {
  return character_comparison(1, 1, char1, char2, false);
}

CL_LAMBDA(core:&va-rest args)
CL_DECLARE();
CL_DOCSTRING(R"dx(Return true if characters are monotonically decreasing, ignore case)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__char_greaterp(Vaslist_sp args) {
  if (args->remaining_nargs() == 0) PROGRAM_ERROR();
  else return monotonic(1, 1, args, false);
};

CL_LAMBDA(char1 char2)
CL_DECLARE();
CL_DOCSTRING(R"dx(two-arg char-not-greaterp)dx")
DOCGROUP(clasp)
CL_DEFUN bool core__two_arg_char_not_greaterp(Character_sp char1, Character_sp char2) {
  return character_comparison(-1, 0, char1, char2, false);
}

CL_LAMBDA(core:&va-rest args)
CL_DECLARE();
CL_DOCSTRING(R"dx(Return true if characters are monotonically non-increasing, ignore case)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__char_not_greaterp(Vaslist_sp args) {
  if (args->remaining_nargs() == 0) PROGRAM_ERROR();
  else return monotonic(-1, 0, args, false);
};

CL_LAMBDA(char1 char2)
CL_DECLARE();
CL_DOCSTRING(R"dx(two-arg char-not-lessp)dx")
DOCGROUP(clasp)
CL_DEFUN bool core__two_arg_char_not_lessp(Character_sp char1, Character_sp char2) {
  return character_comparison(1, 0, char1, char2, false);
}

CL_LAMBDA(core:&va-rest args)
CL_DECLARE();
CL_DOCSTRING(R"dx(Return true if characters are monotonically non-decreasing, ignore case)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__char_not_lessp(Vaslist_sp args) {
  if (args->remaining_nargs() == 0) PROGRAM_ERROR();
  else return monotonic(1, 0, args, false);
};

CL_LAMBDA(core:&va-rest args)
CL_DECLARE();
CL_DOCSTRING(R"dx(NE_)dx")
DOCGROUP(clasp)
CL_DEFUN T_sp cl__char_NE_(Vaslist_sp args) {
  // Just like cl___NE_
  switch (args->remaining_nargs()) {
    /* I expect the order of likelihood is 2, 3, 1, >3, 0.
     * I don't think the compiler takes the order in a switch
     * very seriously, though, so it's just in order. */
  case 0:
      SIMPLE_PROGRAM_ERROR("CHAR/= needs at least 1 argument",nil<T_O>());
  case 1: {
    // the first arg needs to be a character - check that
    gc::As<Character_sp>(args->next_arg());
    return _lisp->_true();
  }
  case 2: {
    claspCharacter a = clasp_as_claspCharacter(gc::As<Character_sp>(args->next_arg()));
    claspCharacter b = clasp_as_claspCharacter(gc::As<Character_sp>(args->next_arg()));
    if (a == b) return nil<T_O>();
    else return _lisp->_true();
  }
  case 3: {
    claspCharacter a = clasp_as_claspCharacter(gc::As<Character_sp>(args->next_arg()));
    claspCharacter b = clasp_as_claspCharacter(gc::As<Character_sp>(args->next_arg()));
    claspCharacter c = clasp_as_claspCharacter(gc::As<Character_sp>(args->next_arg()));
    if ((a == b) || (a == c) || (b == c)) return nil<T_O>();
    else return _lisp->_true();
  }
  default: {
    /* General case is a nested loop.
     * We're going to iterate over the arguments several times,
     * so a valist isn't going to cut it. */
    List_sp largs = core__list_from_vaslist(args);
    while (largs.notnilp()) {
      claspCharacter c1 = clasp_as_claspCharacter(gc::As<Character_sp>(oCar(largs)));
      for (List_sp cur = oCdr(largs); cur.notnilp(); cur = oCdr(cur)) {
        claspCharacter c2 = clasp_as_claspCharacter(gc::As<Character_sp>(oCar(cur)));
        if (c1 == c2) return nil<T_O>();
      }
      largs = oCdr(largs);
    }
    return _lisp->_true();
  }
  }
}

CL_LAMBDA(core:&va-rest args)
CL_DECLARE();
CL_DOCSTRING(R"dx(EQ_)dx")
DOCGROUP(clasp)
CL_DEFUN T_sp cl__char_EQ_(Vaslist_sp args) {
  switch (args->remaining_nargs()) {
  case 0:
      PROGRAM_ERROR();
  case 1: {
    gc::As<Character_sp>(args->next_arg());
    return _lisp->_true();
  }
  case 2: {
    claspCharacter a = clasp_as_claspCharacter(gc::As<Character_sp>(args->next_arg()));
    claspCharacter b = clasp_as_claspCharacter(gc::As<Character_sp>(args->next_arg()));
    if (a == b) return _lisp->_true();
    return nil<T_O>();
  }
  default: {
    claspCharacter a = clasp_as_claspCharacter(gc::As<Character_sp>(args->next_arg()));
    while (args->remaining_nargs()) {
      claspCharacter b = clasp_as_claspCharacter(gc::As<Character_sp>(args->next_arg()));
      if (a!=b) {
        return ((nil<T_O>()));
      }
    }
    return _lisp->_true();
  }
  };
};

CL_LAMBDA(&rest args)
CL_DECLARE();
CL_DOCSTRING(R"dx(Like char_NE_ but ignore case)dx")
DOCGROUP(clasp)
CL_DEFUN T_mv cl__char_not_equal(List_sp args) {
  if (args.nilp())
      PROGRAM_ERROR();
  while (args.notnilp()) {
    claspCharacter a = clasp_as_claspCharacter(gc::As<Character_sp>(oCar(args)));
    a = claspCharacter_upcase(a);
    for (List_sp cur = oCdr(args); cur.notnilp(); cur = oCdr(cur)) {
      claspCharacter b = clasp_as_claspCharacter(gc::As<Character_sp>(oCar(cur)));
      b = claspCharacter_upcase(b);
      if (a == b) return (Values(nil<T_O>()));
    }
    args = oCdr(args);
  }
  return Values(_lisp->_true());
}

bool clasp_charEqual2(T_sp x, T_sp y) {
  if (x.characterp() && y.characterp()) {
    claspCharacter cx = claspCharacter_upcase(x.unsafe_character());
    claspCharacter cy = claspCharacter_upcase(y.unsafe_character());
    return cx == cy;
  }
  return false;
}

// FIXME: redundant with the above
CL_LAMBDA(char1 char2)
CL_DECLARE();
CL_DOCSTRING(R"dx(Two-arg char-equal)dx")
DOCGROUP(clasp)
CL_DEFUN bool core__two_arg_char_equal(Character_sp x, Character_sp y) {
  claspCharacter cx = claspCharacter_upcase(x.unsafe_character());
  claspCharacter cy = claspCharacter_upcase(y.unsafe_character());
  return cx == cy;
}

CL_LAMBDA(core:&va-rest chars)
CL_DECLARE();
CL_DOCSTRING(R"dx(EQ_)dx")
DOCGROUP(clasp)
CL_DEFUN T_sp cl__char_equal(Vaslist_sp chars) {
  switch (chars->remaining_nargs()) {
  case 0:
      PROGRAM_ERROR();
  case 1: {
    gc::As<Character_sp>(chars->next_arg());
    return _lisp->_true();
  }
  case 2: {
    claspCharacter a = clasp_as_claspCharacter(gc::As<Character_sp>(chars->next_arg()));
    a = claspCharacter_upcase(a);
    claspCharacter b = clasp_as_claspCharacter(gc::As<Character_sp>(chars->next_arg()));
    b = claspCharacter_upcase(b);
    if (a == b) return _lisp->_true();
    return nil<T_O>();
  }
  default: {
    claspCharacter a = clasp_as_claspCharacter(gc::As<Character_sp>(chars->next_arg()));
    a = claspCharacter_upcase(a);
    while (chars->remaining_nargs()) {
      claspCharacter b = clasp_as_claspCharacter(gc::As<Character_sp>(chars->next_arg()));
      b = claspCharacter_upcase(b);
      if (a!=b) {
        return ((nil<T_O>()));
      }
    }
    return _lisp->_true();
  }
  };
};

Character_sp clasp_character_create_from_name(string const &name) {
  Character_sp ch;
  string ssup = boost::to_upper_copy(name);
  if ((ssup == "TAB") || (ssup == "Tab"))
    ch = clasp_make_standard_character(TAB_CHAR);
  else if ((ssup == "NEWLINE") || (ssup == "Newline"))
    ch = clasp_make_standard_character(NEWLINE_CHAR);
  else if ((ssup == "LINEFEED") || (ssup == "Linefeed"))
    ch = clasp_make_standard_character(LINE_FEED_CHAR);
  else if ((ssup == "PAGE") || (ssup == "Page"))
    ch = clasp_make_standard_character(PAGE_CHAR);
  else if ((ssup == "RETURN") || (ssup == "Return"))
    ch = clasp_make_standard_character(RETURN_CHAR);
  else if ((ssup == "DEL") || (ssup == "Del" ))
    ch = clasp_make_standard_character(RUBOUT_CHAR);
  else if ((ssup == "ESCAPE") || (ssup == "Escape"))
    ch = clasp_make_standard_character(ESCAPE_CHAR);
  else if ((ssup == "SPACE") || (ssup == "Space"))
    ch = clasp_make_standard_character(' ');
  else if ((ssup == "BACKSPACE") || (ssup == "Backspace"))
    ch = clasp_make_standard_character(BACKSPACE_CHAR);
  else if ((ssup == "RUBOUT") || (ssup == "Rubout"))
    ch = clasp_make_standard_character(RUBOUT_CHAR);
  else if ((ssup == "BELL") || (ssup == "Bell") || (ssup == "Bel"))
    ch = clasp_make_standard_character(BELL_CHAR);
  else {
    SIMPLE_ERROR(("Unknown character name[%s]") , ssup);
  }
  return ch;
}
};
namespace core {


const char* OrderedCharacterNames[] = {
    "NUL",
    "SOH", "STX", "ETX", "EOT",
    "ENQ", "ACK", "BEL", "Backspace",
    "Tab", "Newline", "VT",
    "Page", "Return", "SO", "SI",
    "DLE", "DC1", "DC2", "DC3",
    "DC4", "NAK", "SYN", "ETB",
    "CAN", "EM", "SUB", "ESC",
    "FS", "GS", "RS", "US",
    "Space", "EXCLAMATION_MARK", "QUOTATION_MARK", "NUMBER_SIGN",
    "DOLLAR_SIGN", "PERCENT_SIGN", "AMPERSAND", "APOSTROPHE",
    "LEFT_PARENTHESIS", "RIGHT_PARENTHESIS", "ASTERISK", "PLUS_SIGN",
    "COMMA", "HYPHEN-MINUS", "FULL_STOP", "SOLIDUS",
    "DIGIT_ZERO", "DIGIT_ONE", "DIGIT_TWO", "DIGIT_THREE",
    "DIGIT_FOUR", "DIGIT_FIVE", "DIGIT_SIX", "DIGIT_SEVEN",
    "DIGIT_EIGHT", "DIGIT_NINE", "COLON", "SEMICOLON",
    "LESS-THAN_SIGN", "EQUALS_SIGN", "GREATER-THAN_SIGN", "QUESTION_MARK",
    "COMMERCIAL_AT", "LATIN_CAPITAL_LETTER_A", "LATIN_CAPITAL_LETTER_B", "LATIN_CAPITAL_LETTER_C",
    "LATIN_CAPITAL_LETTER_D", "LATIN_CAPITAL_LETTER_E", "LATIN_CAPITAL_LETTER_F", "LATIN_CAPITAL_LETTER_G",
    "LATIN_CAPITAL_LETTER_H", "LATIN_CAPITAL_LETTER_I", "LATIN_CAPITAL_LETTER_J", "LATIN_CAPITAL_LETTER_K",
    "LATIN_CAPITAL_LETTER_L", "LATIN_CAPITAL_LETTER_M", "LATIN_CAPITAL_LETTER_N", "LATIN_CAPITAL_LETTER_O",
    "LATIN_CAPITAL_LETTER_P", "LATIN_CAPITAL_LETTER_Q", "LATIN_CAPITAL_LETTER_R", "LATIN_CAPITAL_LETTER_S",
    "LATIN_CAPITAL_LETTER_T", "LATIN_CAPITAL_LETTER_U", "LATIN_CAPITAL_LETTER_V", "LATIN_CAPITAL_LETTER_W",
    "LATIN_CAPITAL_LETTER_X", "LATIN_CAPITAL_LETTER_Y", "LATIN_CAPITAL_LETTER_Z", "LEFT_SQUARE_BRACKET",
    "REVERSE_SOLIDUS", "RIGHT_SQUARE_BRACKET", "CIRCUMFLEX_ACCENT", "LOW_LINE",
    "GRAVE_ACCENT", "LATIN_SMALL_LETTER_A", "LATIN_SMALL_LETTER_B", "LATIN_SMALL_LETTER_C",
    "LATIN_SMALL_LETTER_D", "LATIN_SMALL_LETTER_E", "LATIN_SMALL_LETTER_F", "LATIN_SMALL_LETTER_G",
    "LATIN_SMALL_LETTER_H", "LATIN_SMALL_LETTER_I", "LATIN_SMALL_LETTER_J", "LATIN_SMALL_LETTER_K",
    "LATIN_SMALL_LETTER_L", "LATIN_SMALL_LETTER_M", "LATIN_SMALL_LETTER_N", "LATIN_SMALL_LETTER_O",
    "LATIN_SMALL_LETTER_P", "LATIN_SMALL_LETTER_Q", "LATIN_SMALL_LETTER_R", "LATIN_SMALL_LETTER_S",
    "LATIN_SMALL_LETTER_T", "LATIN_SMALL_LETTER_U", "LATIN_SMALL_LETTER_V", "LATIN_SMALL_LETTER_W",
    "LATIN_SMALL_LETTER_X", "LATIN_SMALL_LETTER_Y", "LATIN_SMALL_LETTER_Z", "LEFT_CURLY_BRACKET",
    "VERTICAL_LINE", "RIGHT_CURLY_BRACKET", "TILDE", "Rubout",
    // for the sake of a fast name-char, cover at least until #\UFF
    "U80", "U81", "U82", "U83", "U84", "U85", "U86", "U87", "U88", "U89", "U8A", "U8B", "U8C", "U8D", "U8E", "U8F",
    "U90", "U91", "U92", "U93", "U94", "U95", "U96", "U97", "U98", "U99", "U9A", "U9B", "U9C", "U9D", "U9E", "U9F",
    "NO-BREAK_SPACE",
    "INVERTED_EXCLAMATION_MARK",
    "CENT_SIGN",
    "POUND_SIGN",
    "CURRENCY_SIGN",
    "YEN_SIGN",
    "BROKEN_BAR",
    "SECTION_SIGN",
    "DIAERESIS",
    "COPYRIGHT_SIGN",
    "FEMININE_ORDINAL_INDICATOR",
    "LEFT-POINTING_DOUBLE_ANGLE_QUOTATION_MARK",
    "NOT_SIGN",
    "SOFT_HYPHEN",
    "REGISTERED_SIGN",
    "MACRON",
    "DEGREE_SIGN",
    "PLUS-MINUS_SIGN",
    "SUPERSCRIPT_TWO",
    "SUPERSCRIPT_THREE",
    "ACUTE_ACCENT",
    "MICRO_SIGN",
    "PILCROW_SIGN",
    "MIDDLE_DOT",
    "CEDILLA",
    "SUPERSCRIPT_ONE",
    "MASCULINE_ORDINAL_INDICATOR",
    "RIGHT-POINTING_DOUBLE_ANGLE_QUOTATION_MARK",
    "VULGAR_FRACTION_ONE_QUARTER",
    "VULGAR_FRACTION_ONE_HALF",
    "VULGAR_FRACTION_THREE_QUARTERS",
    "INVERTED_QUESTION_MARK",
    "LATIN_CAPITAL_LETTER_A_WITH_GRAVE",
    "LATIN_CAPITAL_LETTER_A_WITH_ACUTE",
    "LATIN_CAPITAL_LETTER_A_WITH_CIRCUMFLEX",
    "LATIN_CAPITAL_LETTER_A_WITH_TILDE",
    "LATIN_CAPITAL_LETTER_A_WITH_DIAERESIS",
    "LATIN_CAPITAL_LETTER_A_WITH_RING_ABOVE",
    "LATIN_CAPITAL_LETTER_AE",
    "LATIN_CAPITAL_LETTER_C_WITH_CEDILLA",
    "LATIN_CAPITAL_LETTER_E_WITH_GRAVE",
    "LATIN_CAPITAL_LETTER_E_WITH_ACUTE",
    "LATIN_CAPITAL_LETTER_E_WITH_CIRCUMFLEX",
    "LATIN_CAPITAL_LETTER_E_WITH_DIAERESIS",
    "LATIN_CAPITAL_LETTER_I_WITH_GRAVE",
    "LATIN_CAPITAL_LETTER_I_WITH_ACUTE",
    "LATIN_CAPITAL_LETTER_I_WITH_CIRCUMFLEX",
    "LATIN_CAPITAL_LETTER_I_WITH_DIAERESIS",
    "LATIN_CAPITAL_LETTER_ETH",
    "LATIN_CAPITAL_LETTER_N_WITH_TILDE",
    "LATIN_CAPITAL_LETTER_O_WITH_GRAVE",
    "LATIN_CAPITAL_LETTER_O_WITH_ACUTE",
    "LATIN_CAPITAL_LETTER_O_WITH_CIRCUMFLEX",
    "LATIN_CAPITAL_LETTER_O_WITH_TILDE",
    "LATIN_CAPITAL_LETTER_O_WITH_DIAERESIS",
    "MULTIPLICATION_SIGN",
    "LATIN_CAPITAL_LETTER_O_WITH_STROKE",
    "LATIN_CAPITAL_LETTER_U_WITH_GRAVE",
    "LATIN_CAPITAL_LETTER_U_WITH_ACUTE",
    "LATIN_CAPITAL_LETTER_U_WITH_CIRCUMFLEX",
    "LATIN_CAPITAL_LETTER_U_WITH_DIAERESIS",
    "LATIN_CAPITAL_LETTER_Y_WITH_ACUTE",
    "LATIN_CAPITAL_LETTER_THORN",
    "LATIN_SMALL_LETTER_SHARP_S",
    "LATIN_SMALL_LETTER_A_WITH_GRAVE",
    "LATIN_SMALL_LETTER_A_WITH_ACUTE",
    "LATIN_SMALL_LETTER_A_WITH_CIRCUMFLEX",
    "LATIN_SMALL_LETTER_A_WITH_TILDE",
    "LATIN_SMALL_LETTER_A_WITH_DIAERESIS",
    "LATIN_SMALL_LETTER_A_WITH_RING_ABOVE",
    "LATIN_SMALL_LETTER_AE",
    "LATIN_SMALL_LETTER_C_WITH_CEDILLA",
    "LATIN_SMALL_LETTER_E_WITH_GRAVE",
    "LATIN_SMALL_LETTER_E_WITH_ACUTE",
    "LATIN_SMALL_LETTER_E_WITH_CIRCUMFLEX",
    "LATIN_SMALL_LETTER_E_WITH_DIAERESIS",
    "LATIN_SMALL_LETTER_I_WITH_GRAVE",
    "LATIN_SMALL_LETTER_I_WITH_ACUTE",
    "LATIN_SMALL_LETTER_I_WITH_CIRCUMFLEX",
    "LATIN_SMALL_LETTER_I_WITH_DIAERESIS",
    "LATIN_SMALL_LETTER_ETH",
    "LATIN_SMALL_LETTER_N_WITH_TILDE",
    "LATIN_SMALL_LETTER_O_WITH_GRAVE",
    "LATIN_SMALL_LETTER_O_WITH_ACUTE",
    "LATIN_SMALL_LETTER_O_WITH_CIRCUMFLEX",
    "LATIN_SMALL_LETTER_O_WITH_TILDE",
    "LATIN_SMALL_LETTER_O_WITH_DIAERESIS",
    "DIVISION_SIGN",
    "LATIN_SMALL_LETTER_O_WITH_STROKE",
    "LATIN_SMALL_LETTER_U_WITH_GRAVE",
    "LATIN_SMALL_LETTER_U_WITH_ACUTE",
    "LATIN_SMALL_LETTER_U_WITH_CIRCUMFLEX",
    "LATIN_SMALL_LETTER_U_WITH_DIAERESIS",
    "LATIN_SMALL_LETTER_Y_WITH_ACUTE",
    "LATIN_SMALL_LETTER_THORN",
    "LATIN_SMALL_LETTER_Y_WITH_DIAERESIS"
};

void CharacterInfo::initialize() {
  int num_chars = sizeof(OrderedCharacterNames)/sizeof(OrderedCharacterNames[0]);
  this->_NamesToCharacterIndex = HashTableEqual_O::create_default();
  this->gCharacterNames.resize(num_chars, nil<T_O>());
  this->gIndexedCharacters.resize(num_chars, nil<T_O>());
  for (size_t fci=0; fci<num_chars; ++fci) {
    const char* name = OrderedCharacterNames[fci];
    
    //printf("%s:%d Adding char: %s  at: %d\n", __FILE__, __LINE__, name,(int) fci);
    // we later compare with Uppercase
    SimpleBaseString_sp sname = SimpleBaseString_O::make(stringUpper(name));
    this->_NamesToCharacterIndex->setf_gethash(sname,make_fixnum(fci));
    // If fci is cast to char, the following code fails from fci = 128
    this->gIndexedCharacters[fci] = clasp_make_standard_character((claspCharacter)fci);
     // but want the names in the correct case
    this->gCharacterNames[fci] = SimpleBaseString_O::make(std::string(name));
  }
  // we later compare with Uppercase
  this->_NamesToCharacterIndex->setf_gethash(SimpleBaseString_O::make("NULL"),make_fixnum(NULL_CHAR));
  this->_NamesToCharacterIndex->setf_gethash(SimpleBaseString_O::make("BELL"),make_fixnum(BELL_CHAR));
  this->_NamesToCharacterIndex->setf_gethash(SimpleBaseString_O::make("BS"),make_fixnum(BACKSPACE_CHAR));
  this->_NamesToCharacterIndex->setf_gethash(SimpleBaseString_O::make("HT"),make_fixnum(TAB_CHAR));
  this->_NamesToCharacterIndex->setf_gethash(SimpleBaseString_O::make("LF"),make_fixnum(LINE_FEED_CHAR));
  this->_NamesToCharacterIndex->setf_gethash(SimpleBaseString_O::make("LINEFEED"),make_fixnum(LINE_FEED_CHAR));
  this->_NamesToCharacterIndex->setf_gethash(SimpleBaseString_O::make("FF"),make_fixnum(PAGE_CHAR));
  this->_NamesToCharacterIndex->setf_gethash(SimpleBaseString_O::make("CR"),make_fixnum(RETURN_CHAR));
  this->_NamesToCharacterIndex->setf_gethash(SimpleBaseString_O::make("ESCAPE"),make_fixnum(ESCAPE_CHAR));
  this->_NamesToCharacterIndex->setf_gethash(SimpleBaseString_O::make("SP"),make_fixnum(SPACE_CHAR));
  this->_NamesToCharacterIndex->setf_gethash(SimpleBaseString_O::make("DEL"),make_fixnum(RUBOUT_CHAR));
}

CL_LAMBDA(ch)
CL_DECLARE();
CL_DOCSTRING(R"dx(See CLHS: standard_char_p)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__standard_char_p(Character_sp ch) {
  // Complete list is laid out in CLHS 2.1.3: Standard Characters.
  claspCharacter c = clasp_as_claspCharacter(ch);
  if (c>127) return false;
  if (c == 10)
    return true; // NEWLINE
  if (c == ' ')
    return true;
  if (c >= 'a' && c <= 'z')
    return true;
  if (c >= 'A' && c <= 'Z')
    return true;
  if (c >= '0' && c <= '9')
    return true;
  if (c == '!'                                                  //      exclamation mark
      || c == '$'                                               //      dollar sign
      || c == '"'                                               //      quotation mark, or double quote
      || c == '\''                                              //      apostrophe, or [single] quote
      || c == '('                                               //      left parenthesis, or open parenthesis
      || c == ')'                                               //      right parenthesis, or close parenthesis
      || c == ','                                               //      comma
      || c == '_'                                               //      low line, or underscore
      || c == '-'                                               //      hyphen, or minus [sign]
      || c == '.'                                               //      full stop, period, or dot
      || c == '/'                                               //      solidus, or slash
      || c == ':'                                               //      colon
      || c == ';'                                               //      semicolon
      || c == '?'                                               //      question mark
      || c == '+'                                               //      plus [sign]
      || c == '<'                                               //      less-than [sign]
      || c == '='                                               //      equals [sign]
      || c == '>'                                               //      greater-than [sign]
      || c == '#'                                               //      number sign, or sharp[sign]
      || c == '%'                                               //      percent [sign]
      || c == '&'                                               //      ampersand
      || c == '*'                                               //      asterisk, or star
      || c == '@'                                               //      commercial at, or at-sign
      || c == '['                                               //      left [square] bracket
      || c == '\\'                                              //      reverse solidus, or backslash
      || c == ']'                                               //      right [square] bracket
      || c == '{'                                               //      left curly bracket, or left brace
      || c == '|'                                               //      vertical bar
      || c == '}'                                               //      right curly bracket, or right brace
      || c == '`'                                               //      grave accent, or backquote
      || c == '^'                                               //      circumflex accent
      || c == '~'                                               //      tilde
      )
    return true;
  return false;
};

CL_LAMBDA(ch)
CL_DECLARE();
CL_DOCSTRING(R"dx(alpha_char_p)dx")
DOCGROUP(clasp)
CL_DEFUN bool cl__alpha_char_p(Character_sp ch) {
  claspCharacter x = clasp_as_claspCharacter(ch);
  if (x < 128) {
    return isalpha(x);
  }
  return false;
};

Fixnum clasp_digitp(claspCharacter ch, int basis) {
  if (('0' <= ch) && (ch <= '9') && (ch < '0' + basis))
    return ch - '0';
  if (('A' <= ch) && (10 < basis) && (ch < 'A' + (basis - 10)))
    return ch - 'A' + 10;
  if (('a' <= ch) && (10 < basis) && (ch < 'a' + (basis - 10)))
    return ch - 'a' + 10;
  return -1;
}

// This is generated from unicodedata.txt, select all chars with a Simple_Lowercase_Mapping
bool clasp_isupper_wide(claspCharacter code) {
  bool result = false;
  switch(code) {
  case 256 : result = true;break;
  case 258 : result = true;break;
  case 260 : result = true;break;
  case 262 : result = true;break;
  case 264 : result = true;break;
  case 266 : result = true;break;
  case 268 : result = true;break;
  case 270 : result = true;break;
  case 272 : result = true;break;
  case 274 : result = true;break;
  case 276 : result = true;break;
  case 278 : result = true;break;
  case 280 : result = true;break;
  case 282 : result = true;break;
  case 284 : result = true;break;
  case 286 : result = true;break;
  case 288 : result = true;break;
  case 290 : result = true;break;
  case 292 : result = true;break;
  case 294 : result = true;break;
  case 296 : result = true;break;
  case 298 : result = true;break;
  case 300 : result = true;break;
  case 302 : result = true;break;
  case 304 : result = true;break;
  case 306 : result = true;break;
  case 308 : result = true;break;
  case 310 : result = true;break;
  case 313 : result = true;break;
  case 315 : result = true;break;
  case 317 : result = true;break;
  case 319 : result = true;break;
  case 321 : result = true;break;
  case 323 : result = true;break;
  case 325 : result = true;break;
  case 327 : result = true;break;
  case 330 : result = true;break;
  case 332 : result = true;break;
  case 334 : result = true;break;
  case 336 : result = true;break;
  case 338 : result = true;break;
  case 340 : result = true;break;
  case 342 : result = true;break;
  case 344 : result = true;break;
  case 346 : result = true;break;
  case 348 : result = true;break;
  case 350 : result = true;break;
  case 352 : result = true;break;
  case 354 : result = true;break;
  case 356 : result = true;break;
  case 358 : result = true;break;
  case 360 : result = true;break;
  case 362 : result = true;break;
  case 364 : result = true;break;
  case 366 : result = true;break;
  case 368 : result = true;break;
  case 370 : result = true;break;
  case 372 : result = true;break;
  case 374 : result = true;break;
  case 376 : result = true;break;
  case 377 : result = true;break;
  case 379 : result = true;break;
  case 381 : result = true;break;
  case 385 : result = true;break;
  case 386 : result = true;break;
  case 388 : result = true;break;
  case 390 : result = true;break;
  case 391 : result = true;break;
  case 393 : result = true;break;
  case 394 : result = true;break;
  case 395 : result = true;break;
  case 398 : result = true;break;
  case 399 : result = true;break;
  case 400 : result = true;break;
  case 401 : result = true;break;
  case 403 : result = true;break;
  case 404 : result = true;break;
  case 406 : result = true;break;
  case 407 : result = true;break;
  case 408 : result = true;break;
  case 412 : result = true;break;
  case 413 : result = true;break;
  case 415 : result = true;break;
  case 416 : result = true;break;
  case 418 : result = true;break;
  case 420 : result = true;break;
  case 422 : result = true;break;
  case 423 : result = true;break;
  case 425 : result = true;break;
  case 428 : result = true;break;
  case 430 : result = true;break;
  case 431 : result = true;break;
  case 433 : result = true;break;
  case 434 : result = true;break;
  case 435 : result = true;break;
  case 437 : result = true;break;
  case 439 : result = true;break;
  case 440 : result = true;break;
  case 444 : result = true;break;
  case 452 : result = true;break;
  case 453 : result = true;break;
  case 455 : result = true;break;
  case 456 : result = true;break;
  case 458 : result = true;break;
  case 459 : result = true;break;
  case 461 : result = true;break;
  case 463 : result = true;break;
  case 465 : result = true;break;
  case 467 : result = true;break;
  case 469 : result = true;break;
  case 471 : result = true;break;
  case 473 : result = true;break;
  case 475 : result = true;break;
  case 478 : result = true;break;
  case 480 : result = true;break;
  case 482 : result = true;break;
  case 484 : result = true;break;
  case 486 : result = true;break;
  case 488 : result = true;break;
  case 490 : result = true;break;
  case 492 : result = true;break;
  case 494 : result = true;break;
  case 497 : result = true;break;
  case 498 : result = true;break;
  case 500 : result = true;break;
  case 502 : result = true;break;
  case 503 : result = true;break;
  case 504 : result = true;break;
  case 506 : result = true;break;
  case 508 : result = true;break;
  case 510 : result = true;break;
  case 512 : result = true;break;
  case 514 : result = true;break;
  case 516 : result = true;break;
  case 518 : result = true;break;
  case 520 : result = true;break;
  case 522 : result = true;break;
  case 524 : result = true;break;
  case 526 : result = true;break;
  case 528 : result = true;break;
  case 530 : result = true;break;
  case 532 : result = true;break;
  case 534 : result = true;break;
  case 536 : result = true;break;
  case 538 : result = true;break;
  case 540 : result = true;break;
  case 542 : result = true;break;
  case 544 : result = true;break;
  case 546 : result = true;break;
  case 548 : result = true;break;
  case 550 : result = true;break;
  case 552 : result = true;break;
  case 554 : result = true;break;
  case 556 : result = true;break;
  case 558 : result = true;break;
  case 560 : result = true;break;
  case 562 : result = true;break;
  case 570 : result = true;break;
  case 571 : result = true;break;
  case 573 : result = true;break;
  case 574 : result = true;break;
  case 577 : result = true;break;
  case 579 : result = true;break;
  case 580 : result = true;break;
  case 581 : result = true;break;
  case 582 : result = true;break;
  case 584 : result = true;break;
  case 586 : result = true;break;
  case 588 : result = true;break;
  case 590 : result = true;break;
  case 880 : result = true;break;
  case 882 : result = true;break;
  case 886 : result = true;break;
  case 895 : result = true;break;
  case 902 : result = true;break;
  case 904 : result = true;break;
  case 905 : result = true;break;
  case 906 : result = true;break;
  case 908 : result = true;break;
  case 910 : result = true;break;
  case 911 : result = true;break;
  case 913 : result = true;break;
  case 914 : result = true;break;
  case 915 : result = true;break;
  case 916 : result = true;break;
  case 917 : result = true;break;
  case 918 : result = true;break;
  case 919 : result = true;break;
  case 920 : result = true;break;
  case 921 : result = true;break;
  case 922 : result = true;break;
  case 923 : result = true;break;
  case 924 : result = true;break;
  case 925 : result = true;break;
  case 926 : result = true;break;
  case 927 : result = true;break;
  case 928 : result = true;break;
  case 929 : result = true;break;
  case 931 : result = true;break;
  case 932 : result = true;break;
  case 933 : result = true;break;
  case 934 : result = true;break;
  case 935 : result = true;break;
  case 936 : result = true;break;
  case 937 : result = true;break;
  case 938 : result = true;break;
  case 939 : result = true;break;
  case 975 : result = true;break;
  case 984 : result = true;break;
  case 986 : result = true;break;
  case 988 : result = true;break;
  case 990 : result = true;break;
  case 992 : result = true;break;
  case 994 : result = true;break;
  case 996 : result = true;break;
  case 998 : result = true;break;
  case 1000 : result = true;break;
  case 1002 : result = true;break;
  case 1004 : result = true;break;
  case 1006 : result = true;break;
  case 1012 : result = true;break;
  case 1015 : result = true;break;
  case 1017 : result = true;break;
  case 1018 : result = true;break;
  case 1021 : result = true;break;
  case 1022 : result = true;break;
  case 1023 : result = true;break;
  case 1024 : result = true;break;
  case 1025 : result = true;break;
  case 1026 : result = true;break;
  case 1027 : result = true;break;
  case 1028 : result = true;break;
  case 1029 : result = true;break;
  case 1030 : result = true;break;
  case 1031 : result = true;break;
  case 1032 : result = true;break;
  case 1033 : result = true;break;
  case 1034 : result = true;break;
  case 1035 : result = true;break;
  case 1036 : result = true;break;
  case 1037 : result = true;break;
  case 1038 : result = true;break;
  case 1039 : result = true;break;
  case 1040 : result = true;break;
  case 1041 : result = true;break;
  case 1042 : result = true;break;
  case 1043 : result = true;break;
  case 1044 : result = true;break;
  case 1045 : result = true;break;
  case 1046 : result = true;break;
  case 1047 : result = true;break;
  case 1048 : result = true;break;
  case 1049 : result = true;break;
  case 1050 : result = true;break;
  case 1051 : result = true;break;
  case 1052 : result = true;break;
  case 1053 : result = true;break;
  case 1054 : result = true;break;
  case 1055 : result = true;break;
  case 1056 : result = true;break;
  case 1057 : result = true;break;
  case 1058 : result = true;break;
  case 1059 : result = true;break;
  case 1060 : result = true;break;
  case 1061 : result = true;break;
  case 1062 : result = true;break;
  case 1063 : result = true;break;
  case 1064 : result = true;break;
  case 1065 : result = true;break;
  case 1066 : result = true;break;
  case 1067 : result = true;break;
  case 1068 : result = true;break;
  case 1069 : result = true;break;
  case 1070 : result = true;break;
  case 1071 : result = true;break;
  case 1120 : result = true;break;
  case 1122 : result = true;break;
  case 1124 : result = true;break;
  case 1126 : result = true;break;
  case 1128 : result = true;break;
  case 1130 : result = true;break;
  case 1132 : result = true;break;
  case 1134 : result = true;break;
  case 1136 : result = true;break;
  case 1138 : result = true;break;
  case 1140 : result = true;break;
  case 1142 : result = true;break;
  case 1144 : result = true;break;
  case 1146 : result = true;break;
  case 1148 : result = true;break;
  case 1150 : result = true;break;
  case 1152 : result = true;break;
  case 1162 : result = true;break;
  case 1164 : result = true;break;
  case 1166 : result = true;break;
  case 1168 : result = true;break;
  case 1170 : result = true;break;
  case 1172 : result = true;break;
  case 1174 : result = true;break;
  case 1176 : result = true;break;
  case 1178 : result = true;break;
  case 1180 : result = true;break;
  case 1182 : result = true;break;
  case 1184 : result = true;break;
  case 1186 : result = true;break;
  case 1188 : result = true;break;
  case 1190 : result = true;break;
  case 1192 : result = true;break;
  case 1194 : result = true;break;
  case 1196 : result = true;break;
  case 1198 : result = true;break;
  case 1200 : result = true;break;
  case 1202 : result = true;break;
  case 1204 : result = true;break;
  case 1206 : result = true;break;
  case 1208 : result = true;break;
  case 1210 : result = true;break;
  case 1212 : result = true;break;
  case 1214 : result = true;break;
  case 1216 : result = true;break;
  case 1217 : result = true;break;
  case 1219 : result = true;break;
  case 1221 : result = true;break;
  case 1223 : result = true;break;
  case 1225 : result = true;break;
  case 1227 : result = true;break;
  case 1229 : result = true;break;
  case 1232 : result = true;break;
  case 1234 : result = true;break;
  case 1236 : result = true;break;
  case 1238 : result = true;break;
  case 1240 : result = true;break;
  case 1242 : result = true;break;
  case 1244 : result = true;break;
  case 1246 : result = true;break;
  case 1248 : result = true;break;
  case 1250 : result = true;break;
  case 1252 : result = true;break;
  case 1254 : result = true;break;
  case 1256 : result = true;break;
  case 1258 : result = true;break;
  case 1260 : result = true;break;
  case 1262 : result = true;break;
  case 1264 : result = true;break;
  case 1266 : result = true;break;
  case 1268 : result = true;break;
  case 1270 : result = true;break;
  case 1272 : result = true;break;
  case 1274 : result = true;break;
  case 1276 : result = true;break;
  case 1278 : result = true;break;
  case 1280 : result = true;break;
  case 1282 : result = true;break;
  case 1284 : result = true;break;
  case 1286 : result = true;break;
  case 1288 : result = true;break;
  case 1290 : result = true;break;
  case 1292 : result = true;break;
  case 1294 : result = true;break;
  case 1296 : result = true;break;
  case 1298 : result = true;break;
  case 1300 : result = true;break;
  case 1302 : result = true;break;
  case 1304 : result = true;break;
  case 1306 : result = true;break;
  case 1308 : result = true;break;
  case 1310 : result = true;break;
  case 1312 : result = true;break;
  case 1314 : result = true;break;
  case 1316 : result = true;break;
  case 1318 : result = true;break;
  case 1320 : result = true;break;
  case 1322 : result = true;break;
  case 1324 : result = true;break;
  case 1326 : result = true;break;
  case 1329 : result = true;break;
  case 1330 : result = true;break;
  case 1331 : result = true;break;
  case 1332 : result = true;break;
  case 1333 : result = true;break;
  case 1334 : result = true;break;
  case 1335 : result = true;break;
  case 1336 : result = true;break;
  case 1337 : result = true;break;
  case 1338 : result = true;break;
  case 1339 : result = true;break;
  case 1340 : result = true;break;
  case 1341 : result = true;break;
  case 1342 : result = true;break;
  case 1343 : result = true;break;
  case 1344 : result = true;break;
  case 1345 : result = true;break;
  case 1346 : result = true;break;
  case 1347 : result = true;break;
  case 1348 : result = true;break;
  case 1349 : result = true;break;
  case 1350 : result = true;break;
  case 1351 : result = true;break;
  case 1352 : result = true;break;
  case 1353 : result = true;break;
  case 1354 : result = true;break;
  case 1355 : result = true;break;
  case 1356 : result = true;break;
  case 1357 : result = true;break;
  case 1358 : result = true;break;
  case 1359 : result = true;break;
  case 1360 : result = true;break;
  case 1361 : result = true;break;
  case 1362 : result = true;break;
  case 1363 : result = true;break;
  case 1364 : result = true;break;
  case 1365 : result = true;break;
  case 1366 : result = true;break;
  case 4256 : result = true;break;
  case 4257 : result = true;break;
  case 4258 : result = true;break;
  case 4259 : result = true;break;
  case 4260 : result = true;break;
  case 4261 : result = true;break;
  case 4262 : result = true;break;
  case 4263 : result = true;break;
  case 4264 : result = true;break;
  case 4265 : result = true;break;
  case 4266 : result = true;break;
  case 4267 : result = true;break;
  case 4268 : result = true;break;
  case 4269 : result = true;break;
  case 4270 : result = true;break;
  case 4271 : result = true;break;
  case 4272 : result = true;break;
  case 4273 : result = true;break;
  case 4274 : result = true;break;
  case 4275 : result = true;break;
  case 4276 : result = true;break;
  case 4277 : result = true;break;
  case 4278 : result = true;break;
  case 4279 : result = true;break;
  case 4280 : result = true;break;
  case 4281 : result = true;break;
  case 4282 : result = true;break;
  case 4283 : result = true;break;
  case 4284 : result = true;break;
  case 4285 : result = true;break;
  case 4286 : result = true;break;
  case 4287 : result = true;break;
  case 4288 : result = true;break;
  case 4289 : result = true;break;
  case 4290 : result = true;break;
  case 4291 : result = true;break;
  case 4292 : result = true;break;
  case 4293 : result = true;break;
  case 4295 : result = true;break;
  case 4301 : result = true;break;
  case 5024 : result = true;break;
  case 5025 : result = true;break;
  case 5026 : result = true;break;
  case 5027 : result = true;break;
  case 5028 : result = true;break;
  case 5029 : result = true;break;
  case 5030 : result = true;break;
  case 5031 : result = true;break;
  case 5032 : result = true;break;
  case 5033 : result = true;break;
  case 5034 : result = true;break;
  case 5035 : result = true;break;
  case 5036 : result = true;break;
  case 5037 : result = true;break;
  case 5038 : result = true;break;
  case 5039 : result = true;break;
  case 5040 : result = true;break;
  case 5041 : result = true;break;
  case 5042 : result = true;break;
  case 5043 : result = true;break;
  case 5044 : result = true;break;
  case 5045 : result = true;break;
  case 5046 : result = true;break;
  case 5047 : result = true;break;
  case 5048 : result = true;break;
  case 5049 : result = true;break;
  case 5050 : result = true;break;
  case 5051 : result = true;break;
  case 5052 : result = true;break;
  case 5053 : result = true;break;
  case 5054 : result = true;break;
  case 5055 : result = true;break;
  case 5056 : result = true;break;
  case 5057 : result = true;break;
  case 5058 : result = true;break;
  case 5059 : result = true;break;
  case 5060 : result = true;break;
  case 5061 : result = true;break;
  case 5062 : result = true;break;
  case 5063 : result = true;break;
  case 5064 : result = true;break;
  case 5065 : result = true;break;
  case 5066 : result = true;break;
  case 5067 : result = true;break;
  case 5068 : result = true;break;
  case 5069 : result = true;break;
  case 5070 : result = true;break;
  case 5071 : result = true;break;
  case 5072 : result = true;break;
  case 5073 : result = true;break;
  case 5074 : result = true;break;
  case 5075 : result = true;break;
  case 5076 : result = true;break;
  case 5077 : result = true;break;
  case 5078 : result = true;break;
  case 5079 : result = true;break;
  case 5080 : result = true;break;
  case 5081 : result = true;break;
  case 5082 : result = true;break;
  case 5083 : result = true;break;
  case 5084 : result = true;break;
  case 5085 : result = true;break;
  case 5086 : result = true;break;
  case 5087 : result = true;break;
  case 5088 : result = true;break;
  case 5089 : result = true;break;
  case 5090 : result = true;break;
  case 5091 : result = true;break;
  case 5092 : result = true;break;
  case 5093 : result = true;break;
  case 5094 : result = true;break;
  case 5095 : result = true;break;
  case 5096 : result = true;break;
  case 5097 : result = true;break;
  case 5098 : result = true;break;
  case 5099 : result = true;break;
  case 5100 : result = true;break;
  case 5101 : result = true;break;
  case 5102 : result = true;break;
  case 5103 : result = true;break;
  case 5104 : result = true;break;
  case 5105 : result = true;break;
  case 5106 : result = true;break;
  case 5107 : result = true;break;
  case 5108 : result = true;break;
  case 5109 : result = true;break;
  case 7312 : result = true;break;
  case 7313 : result = true;break;
  case 7314 : result = true;break;
  case 7315 : result = true;break;
  case 7316 : result = true;break;
  case 7317 : result = true;break;
  case 7318 : result = true;break;
  case 7319 : result = true;break;
  case 7320 : result = true;break;
  case 7321 : result = true;break;
  case 7322 : result = true;break;
  case 7323 : result = true;break;
  case 7324 : result = true;break;
  case 7325 : result = true;break;
  case 7326 : result = true;break;
  case 7327 : result = true;break;
  case 7328 : result = true;break;
  case 7329 : result = true;break;
  case 7330 : result = true;break;
  case 7331 : result = true;break;
  case 7332 : result = true;break;
  case 7333 : result = true;break;
  case 7334 : result = true;break;
  case 7335 : result = true;break;
  case 7336 : result = true;break;
  case 7337 : result = true;break;
  case 7338 : result = true;break;
  case 7339 : result = true;break;
  case 7340 : result = true;break;
  case 7341 : result = true;break;
  case 7342 : result = true;break;
  case 7343 : result = true;break;
  case 7344 : result = true;break;
  case 7345 : result = true;break;
  case 7346 : result = true;break;
  case 7347 : result = true;break;
  case 7348 : result = true;break;
  case 7349 : result = true;break;
  case 7350 : result = true;break;
  case 7351 : result = true;break;
  case 7352 : result = true;break;
  case 7353 : result = true;break;
  case 7354 : result = true;break;
  case 7357 : result = true;break;
  case 7358 : result = true;break;
  case 7359 : result = true;break;
  case 7680 : result = true;break;
  case 7682 : result = true;break;
  case 7684 : result = true;break;
  case 7686 : result = true;break;
  case 7688 : result = true;break;
  case 7690 : result = true;break;
  case 7692 : result = true;break;
  case 7694 : result = true;break;
  case 7696 : result = true;break;
  case 7698 : result = true;break;
  case 7700 : result = true;break;
  case 7702 : result = true;break;
  case 7704 : result = true;break;
  case 7706 : result = true;break;
  case 7708 : result = true;break;
  case 7710 : result = true;break;
  case 7712 : result = true;break;
  case 7714 : result = true;break;
  case 7716 : result = true;break;
  case 7718 : result = true;break;
  case 7720 : result = true;break;
  case 7722 : result = true;break;
  case 7724 : result = true;break;
  case 7726 : result = true;break;
  case 7728 : result = true;break;
  case 7730 : result = true;break;
  case 7732 : result = true;break;
  case 7734 : result = true;break;
  case 7736 : result = true;break;
  case 7738 : result = true;break;
  case 7740 : result = true;break;
  case 7742 : result = true;break;
  case 7744 : result = true;break;
  case 7746 : result = true;break;
  case 7748 : result = true;break;
  case 7750 : result = true;break;
  case 7752 : result = true;break;
  case 7754 : result = true;break;
  case 7756 : result = true;break;
  case 7758 : result = true;break;
  case 7760 : result = true;break;
  case 7762 : result = true;break;
  case 7764 : result = true;break;
  case 7766 : result = true;break;
  case 7768 : result = true;break;
  case 7770 : result = true;break;
  case 7772 : result = true;break;
  case 7774 : result = true;break;
  case 7776 : result = true;break;
  case 7778 : result = true;break;
  case 7780 : result = true;break;
  case 7782 : result = true;break;
  case 7784 : result = true;break;
  case 7786 : result = true;break;
  case 7788 : result = true;break;
  case 7790 : result = true;break;
  case 7792 : result = true;break;
  case 7794 : result = true;break;
  case 7796 : result = true;break;
  case 7798 : result = true;break;
  case 7800 : result = true;break;
  case 7802 : result = true;break;
  case 7804 : result = true;break;
  case 7806 : result = true;break;
  case 7808 : result = true;break;
  case 7810 : result = true;break;
  case 7812 : result = true;break;
  case 7814 : result = true;break;
  case 7816 : result = true;break;
  case 7818 : result = true;break;
  case 7820 : result = true;break;
  case 7822 : result = true;break;
  case 7824 : result = true;break;
  case 7826 : result = true;break;
  case 7828 : result = true;break;
  case 7838 : result = true;break;
  case 7840 : result = true;break;
  case 7842 : result = true;break;
  case 7844 : result = true;break;
  case 7846 : result = true;break;
  case 7848 : result = true;break;
  case 7850 : result = true;break;
  case 7852 : result = true;break;
  case 7854 : result = true;break;
  case 7856 : result = true;break;
  case 7858 : result = true;break;
  case 7860 : result = true;break;
  case 7862 : result = true;break;
  case 7864 : result = true;break;
  case 7866 : result = true;break;
  case 7868 : result = true;break;
  case 7870 : result = true;break;
  case 7872 : result = true;break;
  case 7874 : result = true;break;
  case 7876 : result = true;break;
  case 7878 : result = true;break;
  case 7880 : result = true;break;
  case 7882 : result = true;break;
  case 7884 : result = true;break;
  case 7886 : result = true;break;
  case 7888 : result = true;break;
  case 7890 : result = true;break;
  case 7892 : result = true;break;
  case 7894 : result = true;break;
  case 7896 : result = true;break;
  case 7898 : result = true;break;
  case 7900 : result = true;break;
  case 7902 : result = true;break;
  case 7904 : result = true;break;
  case 7906 : result = true;break;
  case 7908 : result = true;break;
  case 7910 : result = true;break;
  case 7912 : result = true;break;
  case 7914 : result = true;break;
  case 7916 : result = true;break;
  case 7918 : result = true;break;
  case 7920 : result = true;break;
  case 7922 : result = true;break;
  case 7924 : result = true;break;
  case 7926 : result = true;break;
  case 7928 : result = true;break;
  case 7930 : result = true;break;
  case 7932 : result = true;break;
  case 7934 : result = true;break;
  case 7944 : result = true;break;
  case 7945 : result = true;break;
  case 7946 : result = true;break;
  case 7947 : result = true;break;
  case 7948 : result = true;break;
  case 7949 : result = true;break;
  case 7950 : result = true;break;
  case 7951 : result = true;break;
  case 7960 : result = true;break;
  case 7961 : result = true;break;
  case 7962 : result = true;break;
  case 7963 : result = true;break;
  case 7964 : result = true;break;
  case 7965 : result = true;break;
  case 7976 : result = true;break;
  case 7977 : result = true;break;
  case 7978 : result = true;break;
  case 7979 : result = true;break;
  case 7980 : result = true;break;
  case 7981 : result = true;break;
  case 7982 : result = true;break;
  case 7983 : result = true;break;
  case 7992 : result = true;break;
  case 7993 : result = true;break;
  case 7994 : result = true;break;
  case 7995 : result = true;break;
  case 7996 : result = true;break;
  case 7997 : result = true;break;
  case 7998 : result = true;break;
  case 7999 : result = true;break;
  case 8008 : result = true;break;
  case 8009 : result = true;break;
  case 8010 : result = true;break;
  case 8011 : result = true;break;
  case 8012 : result = true;break;
  case 8013 : result = true;break;
  case 8025 : result = true;break;
  case 8027 : result = true;break;
  case 8029 : result = true;break;
  case 8031 : result = true;break;
  case 8040 : result = true;break;
  case 8041 : result = true;break;
  case 8042 : result = true;break;
  case 8043 : result = true;break;
  case 8044 : result = true;break;
  case 8045 : result = true;break;
  case 8046 : result = true;break;
  case 8047 : result = true;break;
  case 8072 : result = true;break;
  case 8073 : result = true;break;
  case 8074 : result = true;break;
  case 8075 : result = true;break;
  case 8076 : result = true;break;
  case 8077 : result = true;break;
  case 8078 : result = true;break;
  case 8079 : result = true;break;
  case 8088 : result = true;break;
  case 8089 : result = true;break;
  case 8090 : result = true;break;
  case 8091 : result = true;break;
  case 8092 : result = true;break;
  case 8093 : result = true;break;
  case 8094 : result = true;break;
  case 8095 : result = true;break;
  case 8104 : result = true;break;
  case 8105 : result = true;break;
  case 8106 : result = true;break;
  case 8107 : result = true;break;
  case 8108 : result = true;break;
  case 8109 : result = true;break;
  case 8110 : result = true;break;
  case 8111 : result = true;break;
  case 8120 : result = true;break;
  case 8121 : result = true;break;
  case 8122 : result = true;break;
  case 8123 : result = true;break;
  case 8124 : result = true;break;
  case 8136 : result = true;break;
  case 8137 : result = true;break;
  case 8138 : result = true;break;
  case 8139 : result = true;break;
  case 8140 : result = true;break;
  case 8152 : result = true;break;
  case 8153 : result = true;break;
  case 8154 : result = true;break;
  case 8155 : result = true;break;
  case 8168 : result = true;break;
  case 8169 : result = true;break;
  case 8170 : result = true;break;
  case 8171 : result = true;break;
  case 8172 : result = true;break;
  case 8184 : result = true;break;
  case 8185 : result = true;break;
  case 8186 : result = true;break;
  case 8187 : result = true;break;
  case 8188 : result = true;break;
  case 8486 : result = true;break;
  case 8490 : result = true;break;
  case 8491 : result = true;break;
  case 8498 : result = true;break;
  case 8544 : result = true;break;
  case 8545 : result = true;break;
  case 8546 : result = true;break;
  case 8547 : result = true;break;
  case 8548 : result = true;break;
  case 8549 : result = true;break;
  case 8550 : result = true;break;
  case 8551 : result = true;break;
  case 8552 : result = true;break;
  case 8553 : result = true;break;
  case 8554 : result = true;break;
  case 8555 : result = true;break;
  case 8556 : result = true;break;
  case 8557 : result = true;break;
  case 8558 : result = true;break;
  case 8559 : result = true;break;
  case 8579 : result = true;break;
  case 9398 : result = true;break;
  case 9399 : result = true;break;
  case 9400 : result = true;break;
  case 9401 : result = true;break;
  case 9402 : result = true;break;
  case 9403 : result = true;break;
  case 9404 : result = true;break;
  case 9405 : result = true;break;
  case 9406 : result = true;break;
  case 9407 : result = true;break;
  case 9408 : result = true;break;
  case 9409 : result = true;break;
  case 9410 : result = true;break;
  case 9411 : result = true;break;
  case 9412 : result = true;break;
  case 9413 : result = true;break;
  case 9414 : result = true;break;
  case 9415 : result = true;break;
  case 9416 : result = true;break;
  case 9417 : result = true;break;
  case 9418 : result = true;break;
  case 9419 : result = true;break;
  case 9420 : result = true;break;
  case 9421 : result = true;break;
  case 9422 : result = true;break;
  case 9423 : result = true;break;
  case 11264 : result = true;break;
  case 11265 : result = true;break;
  case 11266 : result = true;break;
  case 11267 : result = true;break;
  case 11268 : result = true;break;
  case 11269 : result = true;break;
  case 11270 : result = true;break;
  case 11271 : result = true;break;
  case 11272 : result = true;break;
  case 11273 : result = true;break;
  case 11274 : result = true;break;
  case 11275 : result = true;break;
  case 11276 : result = true;break;
  case 11277 : result = true;break;
  case 11278 : result = true;break;
  case 11279 : result = true;break;
  case 11280 : result = true;break;
  case 11281 : result = true;break;
  case 11282 : result = true;break;
  case 11283 : result = true;break;
  case 11284 : result = true;break;
  case 11285 : result = true;break;
  case 11286 : result = true;break;
  case 11287 : result = true;break;
  case 11288 : result = true;break;
  case 11289 : result = true;break;
  case 11290 : result = true;break;
  case 11291 : result = true;break;
  case 11292 : result = true;break;
  case 11293 : result = true;break;
  case 11294 : result = true;break;
  case 11295 : result = true;break;
  case 11296 : result = true;break;
  case 11297 : result = true;break;
  case 11298 : result = true;break;
  case 11299 : result = true;break;
  case 11300 : result = true;break;
  case 11301 : result = true;break;
  case 11302 : result = true;break;
  case 11303 : result = true;break;
  case 11304 : result = true;break;
  case 11305 : result = true;break;
  case 11306 : result = true;break;
  case 11307 : result = true;break;
  case 11308 : result = true;break;
  case 11309 : result = true;break;
  case 11310 : result = true;break;
  case 11360 : result = true;break;
  case 11362 : result = true;break;
  case 11363 : result = true;break;
  case 11364 : result = true;break;
  case 11367 : result = true;break;
  case 11369 : result = true;break;
  case 11371 : result = true;break;
  case 11373 : result = true;break;
  case 11374 : result = true;break;
  case 11375 : result = true;break;
  case 11376 : result = true;break;
  case 11378 : result = true;break;
  case 11381 : result = true;break;
  case 11390 : result = true;break;
  case 11391 : result = true;break;
  case 11392 : result = true;break;
  case 11394 : result = true;break;
  case 11396 : result = true;break;
  case 11398 : result = true;break;
  case 11400 : result = true;break;
  case 11402 : result = true;break;
  case 11404 : result = true;break;
  case 11406 : result = true;break;
  case 11408 : result = true;break;
  case 11410 : result = true;break;
  case 11412 : result = true;break;
  case 11414 : result = true;break;
  case 11416 : result = true;break;
  case 11418 : result = true;break;
  case 11420 : result = true;break;
  case 11422 : result = true;break;
  case 11424 : result = true;break;
  case 11426 : result = true;break;
  case 11428 : result = true;break;
  case 11430 : result = true;break;
  case 11432 : result = true;break;
  case 11434 : result = true;break;
  case 11436 : result = true;break;
  case 11438 : result = true;break;
  case 11440 : result = true;break;
  case 11442 : result = true;break;
  case 11444 : result = true;break;
  case 11446 : result = true;break;
  case 11448 : result = true;break;
  case 11450 : result = true;break;
  case 11452 : result = true;break;
  case 11454 : result = true;break;
  case 11456 : result = true;break;
  case 11458 : result = true;break;
  case 11460 : result = true;break;
  case 11462 : result = true;break;
  case 11464 : result = true;break;
  case 11466 : result = true;break;
  case 11468 : result = true;break;
  case 11470 : result = true;break;
  case 11472 : result = true;break;
  case 11474 : result = true;break;
  case 11476 : result = true;break;
  case 11478 : result = true;break;
  case 11480 : result = true;break;
  case 11482 : result = true;break;
  case 11484 : result = true;break;
  case 11486 : result = true;break;
  case 11488 : result = true;break;
  case 11490 : result = true;break;
  case 11499 : result = true;break;
  case 11501 : result = true;break;
  case 11506 : result = true;break;
  case 42560 : result = true;break;
  case 42562 : result = true;break;
  case 42564 : result = true;break;
  case 42566 : result = true;break;
  case 42568 : result = true;break;
  case 42570 : result = true;break;
  case 42572 : result = true;break;
  case 42574 : result = true;break;
  case 42576 : result = true;break;
  case 42578 : result = true;break;
  case 42580 : result = true;break;
  case 42582 : result = true;break;
  case 42584 : result = true;break;
  case 42586 : result = true;break;
  case 42588 : result = true;break;
  case 42590 : result = true;break;
  case 42592 : result = true;break;
  case 42594 : result = true;break;
  case 42596 : result = true;break;
  case 42598 : result = true;break;
  case 42600 : result = true;break;
  case 42602 : result = true;break;
  case 42604 : result = true;break;
  case 42624 : result = true;break;
  case 42626 : result = true;break;
  case 42628 : result = true;break;
  case 42630 : result = true;break;
  case 42632 : result = true;break;
  case 42634 : result = true;break;
  case 42636 : result = true;break;
  case 42638 : result = true;break;
  case 42640 : result = true;break;
  case 42642 : result = true;break;
  case 42644 : result = true;break;
  case 42646 : result = true;break;
  case 42648 : result = true;break;
  case 42650 : result = true;break;
  case 42786 : result = true;break;
  case 42788 : result = true;break;
  case 42790 : result = true;break;
  case 42792 : result = true;break;
  case 42794 : result = true;break;
  case 42796 : result = true;break;
  case 42798 : result = true;break;
  case 42802 : result = true;break;
  case 42804 : result = true;break;
  case 42806 : result = true;break;
  case 42808 : result = true;break;
  case 42810 : result = true;break;
  case 42812 : result = true;break;
  case 42814 : result = true;break;
  case 42816 : result = true;break;
  case 42818 : result = true;break;
  case 42820 : result = true;break;
  case 42822 : result = true;break;
  case 42824 : result = true;break;
  case 42826 : result = true;break;
  case 42828 : result = true;break;
  case 42830 : result = true;break;
  case 42832 : result = true;break;
  case 42834 : result = true;break;
  case 42836 : result = true;break;
  case 42838 : result = true;break;
  case 42840 : result = true;break;
  case 42842 : result = true;break;
  case 42844 : result = true;break;
  case 42846 : result = true;break;
  case 42848 : result = true;break;
  case 42850 : result = true;break;
  case 42852 : result = true;break;
  case 42854 : result = true;break;
  case 42856 : result = true;break;
  case 42858 : result = true;break;
  case 42860 : result = true;break;
  case 42862 : result = true;break;
  case 42873 : result = true;break;
  case 42875 : result = true;break;
  case 42877 : result = true;break;
  case 42878 : result = true;break;
  case 42880 : result = true;break;
  case 42882 : result = true;break;
  case 42884 : result = true;break;
  case 42886 : result = true;break;
  case 42891 : result = true;break;
  case 42893 : result = true;break;
  case 42896 : result = true;break;
  case 42898 : result = true;break;
  case 42902 : result = true;break;
  case 42904 : result = true;break;
  case 42906 : result = true;break;
  case 42908 : result = true;break;
  case 42910 : result = true;break;
  case 42912 : result = true;break;
  case 42914 : result = true;break;
  case 42916 : result = true;break;
  case 42918 : result = true;break;
  case 42920 : result = true;break;
  case 42922 : result = true;break;
  case 42923 : result = true;break;
  case 42924 : result = true;break;
  case 42925 : result = true;break;
  case 42926 : result = true;break;
  case 42928 : result = true;break;
  case 42929 : result = true;break;
  case 42930 : result = true;break;
  case 42931 : result = true;break;
  case 42932 : result = true;break;
  case 42934 : result = true;break;
  case 42936 : result = true;break;
  case 42938 : result = true;break;
  case 42940 : result = true;break;
  case 42942 : result = true;break;
  case 42946 : result = true;break;
  case 42948 : result = true;break;
  case 42949 : result = true;break;
  case 42950 : result = true;break;
  case 42951 : result = true;break;
  case 42953 : result = true;break;
  case 42997 : result = true;break;
  case 65313 : result = true;break;
  case 65314 : result = true;break;
  case 65315 : result = true;break;
  case 65316 : result = true;break;
  case 65317 : result = true;break;
  case 65318 : result = true;break;
  case 65319 : result = true;break;
  case 65320 : result = true;break;
  case 65321 : result = true;break;
  case 65322 : result = true;break;
  case 65323 : result = true;break;
  case 65324 : result = true;break;
  case 65325 : result = true;break;
  case 65326 : result = true;break;
  case 65327 : result = true;break;
  case 65328 : result = true;break;
  case 65329 : result = true;break;
  case 65330 : result = true;break;
  case 65331 : result = true;break;
  case 65332 : result = true;break;
  case 65333 : result = true;break;
  case 65334 : result = true;break;
  case 65335 : result = true;break;
  case 65336 : result = true;break;
  case 65337 : result = true;break;
  case 65338 : result = true;break;
  case 66560 : result = true;break;
  case 66561 : result = true;break;
  case 66562 : result = true;break;
  case 66563 : result = true;break;
  case 66564 : result = true;break;
  case 66565 : result = true;break;
  case 66566 : result = true;break;
  case 66567 : result = true;break;
  case 66568 : result = true;break;
  case 66569 : result = true;break;
  case 66570 : result = true;break;
  case 66571 : result = true;break;
  case 66572 : result = true;break;
  case 66573 : result = true;break;
  case 66574 : result = true;break;
  case 66575 : result = true;break;
  case 66576 : result = true;break;
  case 66577 : result = true;break;
  case 66578 : result = true;break;
  case 66579 : result = true;break;
  case 66580 : result = true;break;
  case 66581 : result = true;break;
  case 66582 : result = true;break;
  case 66583 : result = true;break;
  case 66584 : result = true;break;
  case 66585 : result = true;break;
  case 66586 : result = true;break;
  case 66587 : result = true;break;
  case 66588 : result = true;break;
  case 66589 : result = true;break;
  case 66590 : result = true;break;
  case 66591 : result = true;break;
  case 66592 : result = true;break;
  case 66593 : result = true;break;
  case 66594 : result = true;break;
  case 66595 : result = true;break;
  case 66596 : result = true;break;
  case 66597 : result = true;break;
  case 66598 : result = true;break;
  case 66599 : result = true;break;
  case 66736 : result = true;break;
  case 66737 : result = true;break;
  case 66738 : result = true;break;
  case 66739 : result = true;break;
  case 66740 : result = true;break;
  case 66741 : result = true;break;
  case 66742 : result = true;break;
  case 66743 : result = true;break;
  case 66744 : result = true;break;
  case 66745 : result = true;break;
  case 66746 : result = true;break;
  case 66747 : result = true;break;
  case 66748 : result = true;break;
  case 66749 : result = true;break;
  case 66750 : result = true;break;
  case 66751 : result = true;break;
  case 66752 : result = true;break;
  case 66753 : result = true;break;
  case 66754 : result = true;break;
  case 66755 : result = true;break;
  case 66756 : result = true;break;
  case 66757 : result = true;break;
  case 66758 : result = true;break;
  case 66759 : result = true;break;
  case 66760 : result = true;break;
  case 66761 : result = true;break;
  case 66762 : result = true;break;
  case 66763 : result = true;break;
  case 66764 : result = true;break;
  case 66765 : result = true;break;
  case 66766 : result = true;break;
  case 66767 : result = true;break;
  case 66768 : result = true;break;
  case 66769 : result = true;break;
  case 66770 : result = true;break;
  case 66771 : result = true;break;
  case 68736 : result = true;break;
  case 68737 : result = true;break;
  case 68738 : result = true;break;
  case 68739 : result = true;break;
  case 68740 : result = true;break;
  case 68741 : result = true;break;
  case 68742 : result = true;break;
  case 68743 : result = true;break;
  case 68744 : result = true;break;
  case 68745 : result = true;break;
  case 68746 : result = true;break;
  case 68747 : result = true;break;
  case 68748 : result = true;break;
  case 68749 : result = true;break;
  case 68750 : result = true;break;
  case 68751 : result = true;break;
  case 68752 : result = true;break;
  case 68753 : result = true;break;
  case 68754 : result = true;break;
  case 68755 : result = true;break;
  case 68756 : result = true;break;
  case 68757 : result = true;break;
  case 68758 : result = true;break;
  case 68759 : result = true;break;
  case 68760 : result = true;break;
  case 68761 : result = true;break;
  case 68762 : result = true;break;
  case 68763 : result = true;break;
  case 68764 : result = true;break;
  case 68765 : result = true;break;
  case 68766 : result = true;break;
  case 68767 : result = true;break;
  case 68768 : result = true;break;
  case 68769 : result = true;break;
  case 68770 : result = true;break;
  case 68771 : result = true;break;
  case 68772 : result = true;break;
  case 68773 : result = true;break;
  case 68774 : result = true;break;
  case 68775 : result = true;break;
  case 68776 : result = true;break;
  case 68777 : result = true;break;
  case 68778 : result = true;break;
  case 68779 : result = true;break;
  case 68780 : result = true;break;
  case 68781 : result = true;break;
  case 68782 : result = true;break;
  case 68783 : result = true;break;
  case 68784 : result = true;break;
  case 68785 : result = true;break;
  case 68786 : result = true;break;
  case 71840 : result = true;break;
  case 71841 : result = true;break;
  case 71842 : result = true;break;
  case 71843 : result = true;break;
  case 71844 : result = true;break;
  case 71845 : result = true;break;
  case 71846 : result = true;break;
  case 71847 : result = true;break;
  case 71848 : result = true;break;
  case 71849 : result = true;break;
  case 71850 : result = true;break;
  case 71851 : result = true;break;
  case 71852 : result = true;break;
  case 71853 : result = true;break;
  case 71854 : result = true;break;
  case 71855 : result = true;break;
  case 71856 : result = true;break;
  case 71857 : result = true;break;
  case 71858 : result = true;break;
  case 71859 : result = true;break;
  case 71860 : result = true;break;
  case 71861 : result = true;break;
  case 71862 : result = true;break;
  case 71863 : result = true;break;
  case 71864 : result = true;break;
  case 71865 : result = true;break;
  case 71866 : result = true;break;
  case 71867 : result = true;break;
  case 71868 : result = true;break;
  case 71869 : result = true;break;
  case 71870 : result = true;break;
  case 71871 : result = true;break;
  case 93760 : result = true;break;
  case 93761 : result = true;break;
  case 93762 : result = true;break;
  case 93763 : result = true;break;
  case 93764 : result = true;break;
  case 93765 : result = true;break;
  case 93766 : result = true;break;
  case 93767 : result = true;break;
  case 93768 : result = true;break;
  case 93769 : result = true;break;
  case 93770 : result = true;break;
  case 93771 : result = true;break;
  case 93772 : result = true;break;
  case 93773 : result = true;break;
  case 93774 : result = true;break;
  case 93775 : result = true;break;
  case 93776 : result = true;break;
  case 93777 : result = true;break;
  case 93778 : result = true;break;
  case 93779 : result = true;break;
  case 93780 : result = true;break;
  case 93781 : result = true;break;
  case 93782 : result = true;break;
  case 93783 : result = true;break;
  case 93784 : result = true;break;
  case 93785 : result = true;break;
  case 93786 : result = true;break;
  case 93787 : result = true;break;
  case 93788 : result = true;break;
  case 93789 : result = true;break;
  case 93790 : result = true;break;
  case 93791 : result = true;break;
  case 125184 : result = true;break;
  case 125185 : result = true;break;
  case 125186 : result = true;break;
  case 125187 : result = true;break;
  case 125188 : result = true;break;
  case 125189 : result = true;break;
  case 125190 : result = true;break;
  case 125191 : result = true;break;
  case 125192 : result = true;break;
  case 125193 : result = true;break;
  case 125194 : result = true;break;
  case 125195 : result = true;break;
  case 125196 : result = true;break;
  case 125197 : result = true;break;
  case 125198 : result = true;break;
  case 125199 : result = true;break;
  case 125200 : result = true;break;
  case 125201 : result = true;break;
  case 125202 : result = true;break;
  case 125203 : result = true;break;
  case 125204 : result = true;break;
  case 125205 : result = true;break;
  case 125206 : result = true;break;
  case 125207 : result = true;break;
  case 125208 : result = true;break;
  case 125209 : result = true;break;
  case 125210 : result = true;break;
  case 125211 : result = true;break;
  case 125212 : result = true;break;
  case 125213 : result = true;break;
  case 125214 : result = true;break;
  case 125215 : result = true;break;
  case 125216 : result = true;break;
  case 125217 : result = true;break;
  }
  return result;
}

// // This is generated from unicodedata.txt, select all chars with a Simple_Uppercase_Mapping
bool clasp_islower_wide(claspCharacter code) {
  bool result = false;
  switch(code) {
  case 257 : result = true;break;
  case 259 : result = true;break;
  case 261 : result = true;break;
  case 263 : result = true;break;
  case 265 : result = true;break;
  case 267 : result = true;break;
  case 269 : result = true;break;
  case 271 : result = true;break;
  case 273 : result = true;break;
  case 275 : result = true;break;
  case 277 : result = true;break;
  case 279 : result = true;break;
  case 281 : result = true;break;
  case 283 : result = true;break;
  case 285 : result = true;break;
  case 287 : result = true;break;
  case 289 : result = true;break;
  case 291 : result = true;break;
  case 293 : result = true;break;
  case 295 : result = true;break;
  case 297 : result = true;break;
  case 299 : result = true;break;
  case 301 : result = true;break;
  case 303 : result = true;break;
  case 305 : result = true;break;
  case 307 : result = true;break;
  case 309 : result = true;break;
  case 311 : result = true;break;
  case 314 : result = true;break;
  case 316 : result = true;break;
  case 318 : result = true;break;
  case 320 : result = true;break;
  case 322 : result = true;break;
  case 324 : result = true;break;
  case 326 : result = true;break;
  case 328 : result = true;break;
  case 331 : result = true;break;
  case 333 : result = true;break;
  case 335 : result = true;break;
  case 337 : result = true;break;
  case 339 : result = true;break;
  case 341 : result = true;break;
  case 343 : result = true;break;
  case 345 : result = true;break;
  case 347 : result = true;break;
  case 349 : result = true;break;
  case 351 : result = true;break;
  case 353 : result = true;break;
  case 355 : result = true;break;
  case 357 : result = true;break;
  case 359 : result = true;break;
  case 361 : result = true;break;
  case 363 : result = true;break;
  case 365 : result = true;break;
  case 367 : result = true;break;
  case 369 : result = true;break;
  case 371 : result = true;break;
  case 373 : result = true;break;
  case 375 : result = true;break;
  case 378 : result = true;break;
  case 380 : result = true;break;
  case 382 : result = true;break;
  case 383 : result = true;break;
  case 384 : result = true;break;
  case 387 : result = true;break;
  case 389 : result = true;break;
  case 392 : result = true;break;
  case 396 : result = true;break;
  case 402 : result = true;break;
  case 405 : result = true;break;
  case 409 : result = true;break;
  case 410 : result = true;break;
  case 414 : result = true;break;
  case 417 : result = true;break;
  case 419 : result = true;break;
  case 421 : result = true;break;
  case 424 : result = true;break;
  case 429 : result = true;break;
  case 432 : result = true;break;
  case 436 : result = true;break;
  case 438 : result = true;break;
  case 441 : result = true;break;
  case 445 : result = true;break;
  case 447 : result = true;break;
  case 453 : result = true;break;
  case 454 : result = true;break;
  case 456 : result = true;break;
  case 457 : result = true;break;
  case 459 : result = true;break;
  case 460 : result = true;break;
  case 462 : result = true;break;
  case 464 : result = true;break;
  case 466 : result = true;break;
  case 468 : result = true;break;
  case 470 : result = true;break;
  case 472 : result = true;break;
  case 474 : result = true;break;
  case 476 : result = true;break;
  case 477 : result = true;break;
  case 479 : result = true;break;
  case 481 : result = true;break;
  case 483 : result = true;break;
  case 485 : result = true;break;
  case 487 : result = true;break;
  case 489 : result = true;break;
  case 491 : result = true;break;
  case 493 : result = true;break;
  case 495 : result = true;break;
  case 498 : result = true;break;
  case 499 : result = true;break;
  case 501 : result = true;break;
  case 505 : result = true;break;
  case 507 : result = true;break;
  case 509 : result = true;break;
  case 511 : result = true;break;
  case 513 : result = true;break;
  case 515 : result = true;break;
  case 517 : result = true;break;
  case 519 : result = true;break;
  case 521 : result = true;break;
  case 523 : result = true;break;
  case 525 : result = true;break;
  case 527 : result = true;break;
  case 529 : result = true;break;
  case 531 : result = true;break;
  case 533 : result = true;break;
  case 535 : result = true;break;
  case 537 : result = true;break;
  case 539 : result = true;break;
  case 541 : result = true;break;
  case 543 : result = true;break;
  case 547 : result = true;break;
  case 549 : result = true;break;
  case 551 : result = true;break;
  case 553 : result = true;break;
  case 555 : result = true;break;
  case 557 : result = true;break;
  case 559 : result = true;break;
  case 561 : result = true;break;
  case 563 : result = true;break;
  case 572 : result = true;break;
  case 575 : result = true;break;
  case 576 : result = true;break;
  case 578 : result = true;break;
  case 583 : result = true;break;
  case 585 : result = true;break;
  case 587 : result = true;break;
  case 589 : result = true;break;
  case 591 : result = true;break;
  case 592 : result = true;break;
  case 593 : result = true;break;
  case 594 : result = true;break;
  case 595 : result = true;break;
  case 596 : result = true;break;
  case 598 : result = true;break;
  case 599 : result = true;break;
  case 601 : result = true;break;
  case 603 : result = true;break;
  case 604 : result = true;break;
  case 608 : result = true;break;
  case 609 : result = true;break;
  case 611 : result = true;break;
  case 613 : result = true;break;
  case 614 : result = true;break;
  case 616 : result = true;break;
  case 617 : result = true;break;
  case 618 : result = true;break;
  case 619 : result = true;break;
  case 620 : result = true;break;
  case 623 : result = true;break;
  case 625 : result = true;break;
  case 626 : result = true;break;
  case 629 : result = true;break;
  case 637 : result = true;break;
  case 640 : result = true;break;
  case 642 : result = true;break;
  case 643 : result = true;break;
  case 647 : result = true;break;
  case 648 : result = true;break;
  case 649 : result = true;break;
  case 650 : result = true;break;
  case 651 : result = true;break;
  case 652 : result = true;break;
  case 658 : result = true;break;
  case 669 : result = true;break;
  case 670 : result = true;break;
  case 837 : result = true;break;
  case 881 : result = true;break;
  case 883 : result = true;break;
  case 887 : result = true;break;
  case 891 : result = true;break;
  case 892 : result = true;break;
  case 893 : result = true;break;
  case 940 : result = true;break;
  case 941 : result = true;break;
  case 942 : result = true;break;
  case 943 : result = true;break;
  case 945 : result = true;break;
  case 946 : result = true;break;
  case 947 : result = true;break;
  case 948 : result = true;break;
  case 949 : result = true;break;
  case 950 : result = true;break;
  case 951 : result = true;break;
  case 952 : result = true;break;
  case 953 : result = true;break;
  case 954 : result = true;break;
  case 955 : result = true;break;
  case 956 : result = true;break;
  case 957 : result = true;break;
  case 958 : result = true;break;
  case 959 : result = true;break;
  case 960 : result = true;break;
  case 961 : result = true;break;
  case 962 : result = true;break;
  case 963 : result = true;break;
  case 964 : result = true;break;
  case 965 : result = true;break;
  case 966 : result = true;break;
  case 967 : result = true;break;
  case 968 : result = true;break;
  case 969 : result = true;break;
  case 970 : result = true;break;
  case 971 : result = true;break;
  case 972 : result = true;break;
  case 973 : result = true;break;
  case 974 : result = true;break;
  case 976 : result = true;break;
  case 977 : result = true;break;
  case 981 : result = true;break;
  case 982 : result = true;break;
  case 983 : result = true;break;
  case 985 : result = true;break;
  case 987 : result = true;break;
  case 989 : result = true;break;
  case 991 : result = true;break;
  case 993 : result = true;break;
  case 995 : result = true;break;
  case 997 : result = true;break;
  case 999 : result = true;break;
  case 1001 : result = true;break;
  case 1003 : result = true;break;
  case 1005 : result = true;break;
  case 1007 : result = true;break;
  case 1008 : result = true;break;
  case 1009 : result = true;break;
  case 1010 : result = true;break;
  case 1011 : result = true;break;
  case 1013 : result = true;break;
  case 1016 : result = true;break;
  case 1019 : result = true;break;
  case 1072 : result = true;break;
  case 1073 : result = true;break;
  case 1074 : result = true;break;
  case 1075 : result = true;break;
  case 1076 : result = true;break;
  case 1077 : result = true;break;
  case 1078 : result = true;break;
  case 1079 : result = true;break;
  case 1080 : result = true;break;
  case 1081 : result = true;break;
  case 1082 : result = true;break;
  case 1083 : result = true;break;
  case 1084 : result = true;break;
  case 1085 : result = true;break;
  case 1086 : result = true;break;
  case 1087 : result = true;break;
  case 1088 : result = true;break;
  case 1089 : result = true;break;
  case 1090 : result = true;break;
  case 1091 : result = true;break;
  case 1092 : result = true;break;
  case 1093 : result = true;break;
  case 1094 : result = true;break;
  case 1095 : result = true;break;
  case 1096 : result = true;break;
  case 1097 : result = true;break;
  case 1098 : result = true;break;
  case 1099 : result = true;break;
  case 1100 : result = true;break;
  case 1101 : result = true;break;
  case 1102 : result = true;break;
  case 1103 : result = true;break;
  case 1104 : result = true;break;
  case 1105 : result = true;break;
  case 1106 : result = true;break;
  case 1107 : result = true;break;
  case 1108 : result = true;break;
  case 1109 : result = true;break;
  case 1110 : result = true;break;
  case 1111 : result = true;break;
  case 1112 : result = true;break;
  case 1113 : result = true;break;
  case 1114 : result = true;break;
  case 1115 : result = true;break;
  case 1116 : result = true;break;
  case 1117 : result = true;break;
  case 1118 : result = true;break;
  case 1119 : result = true;break;
  case 1121 : result = true;break;
  case 1123 : result = true;break;
  case 1125 : result = true;break;
  case 1127 : result = true;break;
  case 1129 : result = true;break;
  case 1131 : result = true;break;
  case 1133 : result = true;break;
  case 1135 : result = true;break;
  case 1137 : result = true;break;
  case 1139 : result = true;break;
  case 1141 : result = true;break;
  case 1143 : result = true;break;
  case 1145 : result = true;break;
  case 1147 : result = true;break;
  case 1149 : result = true;break;
  case 1151 : result = true;break;
  case 1153 : result = true;break;
  case 1163 : result = true;break;
  case 1165 : result = true;break;
  case 1167 : result = true;break;
  case 1169 : result = true;break;
  case 1171 : result = true;break;
  case 1173 : result = true;break;
  case 1175 : result = true;break;
  case 1177 : result = true;break;
  case 1179 : result = true;break;
  case 1181 : result = true;break;
  case 1183 : result = true;break;
  case 1185 : result = true;break;
  case 1187 : result = true;break;
  case 1189 : result = true;break;
  case 1191 : result = true;break;
  case 1193 : result = true;break;
  case 1195 : result = true;break;
  case 1197 : result = true;break;
  case 1199 : result = true;break;
  case 1201 : result = true;break;
  case 1203 : result = true;break;
  case 1205 : result = true;break;
  case 1207 : result = true;break;
  case 1209 : result = true;break;
  case 1211 : result = true;break;
  case 1213 : result = true;break;
  case 1215 : result = true;break;
  case 1218 : result = true;break;
  case 1220 : result = true;break;
  case 1222 : result = true;break;
  case 1224 : result = true;break;
  case 1226 : result = true;break;
  case 1228 : result = true;break;
  case 1230 : result = true;break;
  case 1231 : result = true;break;
  case 1233 : result = true;break;
  case 1235 : result = true;break;
  case 1237 : result = true;break;
  case 1239 : result = true;break;
  case 1241 : result = true;break;
  case 1243 : result = true;break;
  case 1245 : result = true;break;
  case 1247 : result = true;break;
  case 1249 : result = true;break;
  case 1251 : result = true;break;
  case 1253 : result = true;break;
  case 1255 : result = true;break;
  case 1257 : result = true;break;
  case 1259 : result = true;break;
  case 1261 : result = true;break;
  case 1263 : result = true;break;
  case 1265 : result = true;break;
  case 1267 : result = true;break;
  case 1269 : result = true;break;
  case 1271 : result = true;break;
  case 1273 : result = true;break;
  case 1275 : result = true;break;
  case 1277 : result = true;break;
  case 1279 : result = true;break;
  case 1281 : result = true;break;
  case 1283 : result = true;break;
  case 1285 : result = true;break;
  case 1287 : result = true;break;
  case 1289 : result = true;break;
  case 1291 : result = true;break;
  case 1293 : result = true;break;
  case 1295 : result = true;break;
  case 1297 : result = true;break;
  case 1299 : result = true;break;
  case 1301 : result = true;break;
  case 1303 : result = true;break;
  case 1305 : result = true;break;
  case 1307 : result = true;break;
  case 1309 : result = true;break;
  case 1311 : result = true;break;
  case 1313 : result = true;break;
  case 1315 : result = true;break;
  case 1317 : result = true;break;
  case 1319 : result = true;break;
  case 1321 : result = true;break;
  case 1323 : result = true;break;
  case 1325 : result = true;break;
  case 1327 : result = true;break;
  case 1377 : result = true;break;
  case 1378 : result = true;break;
  case 1379 : result = true;break;
  case 1380 : result = true;break;
  case 1381 : result = true;break;
  case 1382 : result = true;break;
  case 1383 : result = true;break;
  case 1384 : result = true;break;
  case 1385 : result = true;break;
  case 1386 : result = true;break;
  case 1387 : result = true;break;
  case 1388 : result = true;break;
  case 1389 : result = true;break;
  case 1390 : result = true;break;
  case 1391 : result = true;break;
  case 1392 : result = true;break;
  case 1393 : result = true;break;
  case 1394 : result = true;break;
  case 1395 : result = true;break;
  case 1396 : result = true;break;
  case 1397 : result = true;break;
  case 1398 : result = true;break;
  case 1399 : result = true;break;
  case 1400 : result = true;break;
  case 1401 : result = true;break;
  case 1402 : result = true;break;
  case 1403 : result = true;break;
  case 1404 : result = true;break;
  case 1405 : result = true;break;
  case 1406 : result = true;break;
  case 1407 : result = true;break;
  case 1408 : result = true;break;
  case 1409 : result = true;break;
  case 1410 : result = true;break;
  case 1411 : result = true;break;
  case 1412 : result = true;break;
  case 1413 : result = true;break;
  case 1414 : result = true;break;
  case 4304 : result = true;break;
  case 4305 : result = true;break;
  case 4306 : result = true;break;
  case 4307 : result = true;break;
  case 4308 : result = true;break;
  case 4309 : result = true;break;
  case 4310 : result = true;break;
  case 4311 : result = true;break;
  case 4312 : result = true;break;
  case 4313 : result = true;break;
  case 4314 : result = true;break;
  case 4315 : result = true;break;
  case 4316 : result = true;break;
  case 4317 : result = true;break;
  case 4318 : result = true;break;
  case 4319 : result = true;break;
  case 4320 : result = true;break;
  case 4321 : result = true;break;
  case 4322 : result = true;break;
  case 4323 : result = true;break;
  case 4324 : result = true;break;
  case 4325 : result = true;break;
  case 4326 : result = true;break;
  case 4327 : result = true;break;
  case 4328 : result = true;break;
  case 4329 : result = true;break;
  case 4330 : result = true;break;
  case 4331 : result = true;break;
  case 4332 : result = true;break;
  case 4333 : result = true;break;
  case 4334 : result = true;break;
  case 4335 : result = true;break;
  case 4336 : result = true;break;
  case 4337 : result = true;break;
  case 4338 : result = true;break;
  case 4339 : result = true;break;
  case 4340 : result = true;break;
  case 4341 : result = true;break;
  case 4342 : result = true;break;
  case 4343 : result = true;break;
  case 4344 : result = true;break;
  case 4345 : result = true;break;
  case 4346 : result = true;break;
  case 4349 : result = true;break;
  case 4350 : result = true;break;
  case 4351 : result = true;break;
  case 5112 : result = true;break;
  case 5113 : result = true;break;
  case 5114 : result = true;break;
  case 5115 : result = true;break;
  case 5116 : result = true;break;
  case 5117 : result = true;break;
  case 7296 : result = true;break;
  case 7297 : result = true;break;
  case 7298 : result = true;break;
  case 7299 : result = true;break;
  case 7300 : result = true;break;
  case 7301 : result = true;break;
  case 7302 : result = true;break;
  case 7303 : result = true;break;
  case 7304 : result = true;break;
  case 7545 : result = true;break;
  case 7549 : result = true;break;
  case 7566 : result = true;break;
  case 7681 : result = true;break;
  case 7683 : result = true;break;
  case 7685 : result = true;break;
  case 7687 : result = true;break;
  case 7689 : result = true;break;
  case 7691 : result = true;break;
  case 7693 : result = true;break;
  case 7695 : result = true;break;
  case 7697 : result = true;break;
  case 7699 : result = true;break;
  case 7701 : result = true;break;
  case 7703 : result = true;break;
  case 7705 : result = true;break;
  case 7707 : result = true;break;
  case 7709 : result = true;break;
  case 7711 : result = true;break;
  case 7713 : result = true;break;
  case 7715 : result = true;break;
  case 7717 : result = true;break;
  case 7719 : result = true;break;
  case 7721 : result = true;break;
  case 7723 : result = true;break;
  case 7725 : result = true;break;
  case 7727 : result = true;break;
  case 7729 : result = true;break;
  case 7731 : result = true;break;
  case 7733 : result = true;break;
  case 7735 : result = true;break;
  case 7737 : result = true;break;
  case 7739 : result = true;break;
  case 7741 : result = true;break;
  case 7743 : result = true;break;
  case 7745 : result = true;break;
  case 7747 : result = true;break;
  case 7749 : result = true;break;
  case 7751 : result = true;break;
  case 7753 : result = true;break;
  case 7755 : result = true;break;
  case 7757 : result = true;break;
  case 7759 : result = true;break;
  case 7761 : result = true;break;
  case 7763 : result = true;break;
  case 7765 : result = true;break;
  case 7767 : result = true;break;
  case 7769 : result = true;break;
  case 7771 : result = true;break;
  case 7773 : result = true;break;
  case 7775 : result = true;break;
  case 7777 : result = true;break;
  case 7779 : result = true;break;
  case 7781 : result = true;break;
  case 7783 : result = true;break;
  case 7785 : result = true;break;
  case 7787 : result = true;break;
  case 7789 : result = true;break;
  case 7791 : result = true;break;
  case 7793 : result = true;break;
  case 7795 : result = true;break;
  case 7797 : result = true;break;
  case 7799 : result = true;break;
  case 7801 : result = true;break;
  case 7803 : result = true;break;
  case 7805 : result = true;break;
  case 7807 : result = true;break;
  case 7809 : result = true;break;
  case 7811 : result = true;break;
  case 7813 : result = true;break;
  case 7815 : result = true;break;
  case 7817 : result = true;break;
  case 7819 : result = true;break;
  case 7821 : result = true;break;
  case 7823 : result = true;break;
  case 7825 : result = true;break;
  case 7827 : result = true;break;
  case 7829 : result = true;break;
  case 7835 : result = true;break;
  case 7841 : result = true;break;
  case 7843 : result = true;break;
  case 7845 : result = true;break;
  case 7847 : result = true;break;
  case 7849 : result = true;break;
  case 7851 : result = true;break;
  case 7853 : result = true;break;
  case 7855 : result = true;break;
  case 7857 : result = true;break;
  case 7859 : result = true;break;
  case 7861 : result = true;break;
  case 7863 : result = true;break;
  case 7865 : result = true;break;
  case 7867 : result = true;break;
  case 7869 : result = true;break;
  case 7871 : result = true;break;
  case 7873 : result = true;break;
  case 7875 : result = true;break;
  case 7877 : result = true;break;
  case 7879 : result = true;break;
  case 7881 : result = true;break;
  case 7883 : result = true;break;
  case 7885 : result = true;break;
  case 7887 : result = true;break;
  case 7889 : result = true;break;
  case 7891 : result = true;break;
  case 7893 : result = true;break;
  case 7895 : result = true;break;
  case 7897 : result = true;break;
  case 7899 : result = true;break;
  case 7901 : result = true;break;
  case 7903 : result = true;break;
  case 7905 : result = true;break;
  case 7907 : result = true;break;
  case 7909 : result = true;break;
  case 7911 : result = true;break;
  case 7913 : result = true;break;
  case 7915 : result = true;break;
  case 7917 : result = true;break;
  case 7919 : result = true;break;
  case 7921 : result = true;break;
  case 7923 : result = true;break;
  case 7925 : result = true;break;
  case 7927 : result = true;break;
  case 7929 : result = true;break;
  case 7931 : result = true;break;
  case 7933 : result = true;break;
  case 7935 : result = true;break;
  case 7936 : result = true;break;
  case 7937 : result = true;break;
  case 7938 : result = true;break;
  case 7939 : result = true;break;
  case 7940 : result = true;break;
  case 7941 : result = true;break;
  case 7942 : result = true;break;
  case 7943 : result = true;break;
  case 7952 : result = true;break;
  case 7953 : result = true;break;
  case 7954 : result = true;break;
  case 7955 : result = true;break;
  case 7956 : result = true;break;
  case 7957 : result = true;break;
  case 7968 : result = true;break;
  case 7969 : result = true;break;
  case 7970 : result = true;break;
  case 7971 : result = true;break;
  case 7972 : result = true;break;
  case 7973 : result = true;break;
  case 7974 : result = true;break;
  case 7975 : result = true;break;
  case 7984 : result = true;break;
  case 7985 : result = true;break;
  case 7986 : result = true;break;
  case 7987 : result = true;break;
  case 7988 : result = true;break;
  case 7989 : result = true;break;
  case 7990 : result = true;break;
  case 7991 : result = true;break;
  case 8000 : result = true;break;
  case 8001 : result = true;break;
  case 8002 : result = true;break;
  case 8003 : result = true;break;
  case 8004 : result = true;break;
  case 8005 : result = true;break;
  case 8017 : result = true;break;
  case 8019 : result = true;break;
  case 8021 : result = true;break;
  case 8023 : result = true;break;
  case 8032 : result = true;break;
  case 8033 : result = true;break;
  case 8034 : result = true;break;
  case 8035 : result = true;break;
  case 8036 : result = true;break;
  case 8037 : result = true;break;
  case 8038 : result = true;break;
  case 8039 : result = true;break;
  case 8048 : result = true;break;
  case 8049 : result = true;break;
  case 8050 : result = true;break;
  case 8051 : result = true;break;
  case 8052 : result = true;break;
  case 8053 : result = true;break;
  case 8054 : result = true;break;
  case 8055 : result = true;break;
  case 8056 : result = true;break;
  case 8057 : result = true;break;
  case 8058 : result = true;break;
  case 8059 : result = true;break;
  case 8060 : result = true;break;
  case 8061 : result = true;break;
  case 8064 : result = true;break;
  case 8065 : result = true;break;
  case 8066 : result = true;break;
  case 8067 : result = true;break;
  case 8068 : result = true;break;
  case 8069 : result = true;break;
  case 8070 : result = true;break;
  case 8071 : result = true;break;
  case 8080 : result = true;break;
  case 8081 : result = true;break;
  case 8082 : result = true;break;
  case 8083 : result = true;break;
  case 8084 : result = true;break;
  case 8085 : result = true;break;
  case 8086 : result = true;break;
  case 8087 : result = true;break;
  case 8096 : result = true;break;
  case 8097 : result = true;break;
  case 8098 : result = true;break;
  case 8099 : result = true;break;
  case 8100 : result = true;break;
  case 8101 : result = true;break;
  case 8102 : result = true;break;
  case 8103 : result = true;break;
  case 8112 : result = true;break;
  case 8113 : result = true;break;
  case 8115 : result = true;break;
  case 8126 : result = true;break;
  case 8131 : result = true;break;
  case 8144 : result = true;break;
  case 8145 : result = true;break;
  case 8160 : result = true;break;
  case 8161 : result = true;break;
  case 8165 : result = true;break;
  case 8179 : result = true;break;
  case 8526 : result = true;break;
  case 8560 : result = true;break;
  case 8561 : result = true;break;
  case 8562 : result = true;break;
  case 8563 : result = true;break;
  case 8564 : result = true;break;
  case 8565 : result = true;break;
  case 8566 : result = true;break;
  case 8567 : result = true;break;
  case 8568 : result = true;break;
  case 8569 : result = true;break;
  case 8570 : result = true;break;
  case 8571 : result = true;break;
  case 8572 : result = true;break;
  case 8573 : result = true;break;
  case 8574 : result = true;break;
  case 8575 : result = true;break;
  case 8580 : result = true;break;
  case 9424 : result = true;break;
  case 9425 : result = true;break;
  case 9426 : result = true;break;
  case 9427 : result = true;break;
  case 9428 : result = true;break;
  case 9429 : result = true;break;
  case 9430 : result = true;break;
  case 9431 : result = true;break;
  case 9432 : result = true;break;
  case 9433 : result = true;break;
  case 9434 : result = true;break;
  case 9435 : result = true;break;
  case 9436 : result = true;break;
  case 9437 : result = true;break;
  case 9438 : result = true;break;
  case 9439 : result = true;break;
  case 9440 : result = true;break;
  case 9441 : result = true;break;
  case 9442 : result = true;break;
  case 9443 : result = true;break;
  case 9444 : result = true;break;
  case 9445 : result = true;break;
  case 9446 : result = true;break;
  case 9447 : result = true;break;
  case 9448 : result = true;break;
  case 9449 : result = true;break;
  case 11312 : result = true;break;
  case 11313 : result = true;break;
  case 11314 : result = true;break;
  case 11315 : result = true;break;
  case 11316 : result = true;break;
  case 11317 : result = true;break;
  case 11318 : result = true;break;
  case 11319 : result = true;break;
  case 11320 : result = true;break;
  case 11321 : result = true;break;
  case 11322 : result = true;break;
  case 11323 : result = true;break;
  case 11324 : result = true;break;
  case 11325 : result = true;break;
  case 11326 : result = true;break;
  case 11327 : result = true;break;
  case 11328 : result = true;break;
  case 11329 : result = true;break;
  case 11330 : result = true;break;
  case 11331 : result = true;break;
  case 11332 : result = true;break;
  case 11333 : result = true;break;
  case 11334 : result = true;break;
  case 11335 : result = true;break;
  case 11336 : result = true;break;
  case 11337 : result = true;break;
  case 11338 : result = true;break;
  case 11339 : result = true;break;
  case 11340 : result = true;break;
  case 11341 : result = true;break;
  case 11342 : result = true;break;
  case 11343 : result = true;break;
  case 11344 : result = true;break;
  case 11345 : result = true;break;
  case 11346 : result = true;break;
  case 11347 : result = true;break;
  case 11348 : result = true;break;
  case 11349 : result = true;break;
  case 11350 : result = true;break;
  case 11351 : result = true;break;
  case 11352 : result = true;break;
  case 11353 : result = true;break;
  case 11354 : result = true;break;
  case 11355 : result = true;break;
  case 11356 : result = true;break;
  case 11357 : result = true;break;
  case 11358 : result = true;break;
  case 11361 : result = true;break;
  case 11365 : result = true;break;
  case 11366 : result = true;break;
  case 11368 : result = true;break;
  case 11370 : result = true;break;
  case 11372 : result = true;break;
  case 11379 : result = true;break;
  case 11382 : result = true;break;
  case 11393 : result = true;break;
  case 11395 : result = true;break;
  case 11397 : result = true;break;
  case 11399 : result = true;break;
  case 11401 : result = true;break;
  case 11403 : result = true;break;
  case 11405 : result = true;break;
  case 11407 : result = true;break;
  case 11409 : result = true;break;
  case 11411 : result = true;break;
  case 11413 : result = true;break;
  case 11415 : result = true;break;
  case 11417 : result = true;break;
  case 11419 : result = true;break;
  case 11421 : result = true;break;
  case 11423 : result = true;break;
  case 11425 : result = true;break;
  case 11427 : result = true;break;
  case 11429 : result = true;break;
  case 11431 : result = true;break;
  case 11433 : result = true;break;
  case 11435 : result = true;break;
  case 11437 : result = true;break;
  case 11439 : result = true;break;
  case 11441 : result = true;break;
  case 11443 : result = true;break;
  case 11445 : result = true;break;
  case 11447 : result = true;break;
  case 11449 : result = true;break;
  case 11451 : result = true;break;
  case 11453 : result = true;break;
  case 11455 : result = true;break;
  case 11457 : result = true;break;
  case 11459 : result = true;break;
  case 11461 : result = true;break;
  case 11463 : result = true;break;
  case 11465 : result = true;break;
  case 11467 : result = true;break;
  case 11469 : result = true;break;
  case 11471 : result = true;break;
  case 11473 : result = true;break;
  case 11475 : result = true;break;
  case 11477 : result = true;break;
  case 11479 : result = true;break;
  case 11481 : result = true;break;
  case 11483 : result = true;break;
  case 11485 : result = true;break;
  case 11487 : result = true;break;
  case 11489 : result = true;break;
  case 11491 : result = true;break;
  case 11500 : result = true;break;
  case 11502 : result = true;break;
  case 11507 : result = true;break;
  case 11520 : result = true;break;
  case 11521 : result = true;break;
  case 11522 : result = true;break;
  case 11523 : result = true;break;
  case 11524 : result = true;break;
  case 11525 : result = true;break;
  case 11526 : result = true;break;
  case 11527 : result = true;break;
  case 11528 : result = true;break;
  case 11529 : result = true;break;
  case 11530 : result = true;break;
  case 11531 : result = true;break;
  case 11532 : result = true;break;
  case 11533 : result = true;break;
  case 11534 : result = true;break;
  case 11535 : result = true;break;
  case 11536 : result = true;break;
  case 11537 : result = true;break;
  case 11538 : result = true;break;
  case 11539 : result = true;break;
  case 11540 : result = true;break;
  case 11541 : result = true;break;
  case 11542 : result = true;break;
  case 11543 : result = true;break;
  case 11544 : result = true;break;
  case 11545 : result = true;break;
  case 11546 : result = true;break;
  case 11547 : result = true;break;
  case 11548 : result = true;break;
  case 11549 : result = true;break;
  case 11550 : result = true;break;
  case 11551 : result = true;break;
  case 11552 : result = true;break;
  case 11553 : result = true;break;
  case 11554 : result = true;break;
  case 11555 : result = true;break;
  case 11556 : result = true;break;
  case 11557 : result = true;break;
  case 11559 : result = true;break;
  case 11565 : result = true;break;
  case 42561 : result = true;break;
  case 42563 : result = true;break;
  case 42565 : result = true;break;
  case 42567 : result = true;break;
  case 42569 : result = true;break;
  case 42571 : result = true;break;
  case 42573 : result = true;break;
  case 42575 : result = true;break;
  case 42577 : result = true;break;
  case 42579 : result = true;break;
  case 42581 : result = true;break;
  case 42583 : result = true;break;
  case 42585 : result = true;break;
  case 42587 : result = true;break;
  case 42589 : result = true;break;
  case 42591 : result = true;break;
  case 42593 : result = true;break;
  case 42595 : result = true;break;
  case 42597 : result = true;break;
  case 42599 : result = true;break;
  case 42601 : result = true;break;
  case 42603 : result = true;break;
  case 42605 : result = true;break;
  case 42625 : result = true;break;
  case 42627 : result = true;break;
  case 42629 : result = true;break;
  case 42631 : result = true;break;
  case 42633 : result = true;break;
  case 42635 : result = true;break;
  case 42637 : result = true;break;
  case 42639 : result = true;break;
  case 42641 : result = true;break;
  case 42643 : result = true;break;
  case 42645 : result = true;break;
  case 42647 : result = true;break;
  case 42649 : result = true;break;
  case 42651 : result = true;break;
  case 42787 : result = true;break;
  case 42789 : result = true;break;
  case 42791 : result = true;break;
  case 42793 : result = true;break;
  case 42795 : result = true;break;
  case 42797 : result = true;break;
  case 42799 : result = true;break;
  case 42803 : result = true;break;
  case 42805 : result = true;break;
  case 42807 : result = true;break;
  case 42809 : result = true;break;
  case 42811 : result = true;break;
  case 42813 : result = true;break;
  case 42815 : result = true;break;
  case 42817 : result = true;break;
  case 42819 : result = true;break;
  case 42821 : result = true;break;
  case 42823 : result = true;break;
  case 42825 : result = true;break;
  case 42827 : result = true;break;
  case 42829 : result = true;break;
  case 42831 : result = true;break;
  case 42833 : result = true;break;
  case 42835 : result = true;break;
  case 42837 : result = true;break;
  case 42839 : result = true;break;
  case 42841 : result = true;break;
  case 42843 : result = true;break;
  case 42845 : result = true;break;
  case 42847 : result = true;break;
  case 42849 : result = true;break;
  case 42851 : result = true;break;
  case 42853 : result = true;break;
  case 42855 : result = true;break;
  case 42857 : result = true;break;
  case 42859 : result = true;break;
  case 42861 : result = true;break;
  case 42863 : result = true;break;
  case 42874 : result = true;break;
  case 42876 : result = true;break;
  case 42879 : result = true;break;
  case 42881 : result = true;break;
  case 42883 : result = true;break;
  case 42885 : result = true;break;
  case 42887 : result = true;break;
  case 42892 : result = true;break;
  case 42897 : result = true;break;
  case 42899 : result = true;break;
  case 42900 : result = true;break;
  case 42903 : result = true;break;
  case 42905 : result = true;break;
  case 42907 : result = true;break;
  case 42909 : result = true;break;
  case 42911 : result = true;break;
  case 42913 : result = true;break;
  case 42915 : result = true;break;
  case 42917 : result = true;break;
  case 42919 : result = true;break;
  case 42921 : result = true;break;
  case 42933 : result = true;break;
  case 42935 : result = true;break;
  case 42937 : result = true;break;
  case 42939 : result = true;break;
  case 42941 : result = true;break;
  case 42943 : result = true;break;
  case 42947 : result = true;break;
  case 42952 : result = true;break;
  case 42954 : result = true;break;
  case 42998 : result = true;break;
  case 43859 : result = true;break;
  case 43888 : result = true;break;
  case 43889 : result = true;break;
  case 43890 : result = true;break;
  case 43891 : result = true;break;
  case 43892 : result = true;break;
  case 43893 : result = true;break;
  case 43894 : result = true;break;
  case 43895 : result = true;break;
  case 43896 : result = true;break;
  case 43897 : result = true;break;
  case 43898 : result = true;break;
  case 43899 : result = true;break;
  case 43900 : result = true;break;
  case 43901 : result = true;break;
  case 43902 : result = true;break;
  case 43903 : result = true;break;
  case 43904 : result = true;break;
  case 43905 : result = true;break;
  case 43906 : result = true;break;
  case 43907 : result = true;break;
  case 43908 : result = true;break;
  case 43909 : result = true;break;
  case 43910 : result = true;break;
  case 43911 : result = true;break;
  case 43912 : result = true;break;
  case 43913 : result = true;break;
  case 43914 : result = true;break;
  case 43915 : result = true;break;
  case 43916 : result = true;break;
  case 43917 : result = true;break;
  case 43918 : result = true;break;
  case 43919 : result = true;break;
  case 43920 : result = true;break;
  case 43921 : result = true;break;
  case 43922 : result = true;break;
  case 43923 : result = true;break;
  case 43924 : result = true;break;
  case 43925 : result = true;break;
  case 43926 : result = true;break;
  case 43927 : result = true;break;
  case 43928 : result = true;break;
  case 43929 : result = true;break;
  case 43930 : result = true;break;
  case 43931 : result = true;break;
  case 43932 : result = true;break;
  case 43933 : result = true;break;
  case 43934 : result = true;break;
  case 43935 : result = true;break;
  case 43936 : result = true;break;
  case 43937 : result = true;break;
  case 43938 : result = true;break;
  case 43939 : result = true;break;
  case 43940 : result = true;break;
  case 43941 : result = true;break;
  case 43942 : result = true;break;
  case 43943 : result = true;break;
  case 43944 : result = true;break;
  case 43945 : result = true;break;
  case 43946 : result = true;break;
  case 43947 : result = true;break;
  case 43948 : result = true;break;
  case 43949 : result = true;break;
  case 43950 : result = true;break;
  case 43951 : result = true;break;
  case 43952 : result = true;break;
  case 43953 : result = true;break;
  case 43954 : result = true;break;
  case 43955 : result = true;break;
  case 43956 : result = true;break;
  case 43957 : result = true;break;
  case 43958 : result = true;break;
  case 43959 : result = true;break;
  case 43960 : result = true;break;
  case 43961 : result = true;break;
  case 43962 : result = true;break;
  case 43963 : result = true;break;
  case 43964 : result = true;break;
  case 43965 : result = true;break;
  case 43966 : result = true;break;
  case 43967 : result = true;break;
  case 65345 : result = true;break;
  case 65346 : result = true;break;
  case 65347 : result = true;break;
  case 65348 : result = true;break;
  case 65349 : result = true;break;
  case 65350 : result = true;break;
  case 65351 : result = true;break;
  case 65352 : result = true;break;
  case 65353 : result = true;break;
  case 65354 : result = true;break;
  case 65355 : result = true;break;
  case 65356 : result = true;break;
  case 65357 : result = true;break;
  case 65358 : result = true;break;
  case 65359 : result = true;break;
  case 65360 : result = true;break;
  case 65361 : result = true;break;
  case 65362 : result = true;break;
  case 65363 : result = true;break;
  case 65364 : result = true;break;
  case 65365 : result = true;break;
  case 65366 : result = true;break;
  case 65367 : result = true;break;
  case 65368 : result = true;break;
  case 65369 : result = true;break;
  case 65370 : result = true;break;
  case 66600 : result = true;break;
  case 66601 : result = true;break;
  case 66602 : result = true;break;
  case 66603 : result = true;break;
  case 66604 : result = true;break;
  case 66605 : result = true;break;
  case 66606 : result = true;break;
  case 66607 : result = true;break;
  case 66608 : result = true;break;
  case 66609 : result = true;break;
  case 66610 : result = true;break;
  case 66611 : result = true;break;
  case 66612 : result = true;break;
  case 66613 : result = true;break;
  case 66614 : result = true;break;
  case 66615 : result = true;break;
  case 66616 : result = true;break;
  case 66617 : result = true;break;
  case 66618 : result = true;break;
  case 66619 : result = true;break;
  case 66620 : result = true;break;
  case 66621 : result = true;break;
  case 66622 : result = true;break;
  case 66623 : result = true;break;
  case 66624 : result = true;break;
  case 66625 : result = true;break;
  case 66626 : result = true;break;
  case 66627 : result = true;break;
  case 66628 : result = true;break;
  case 66629 : result = true;break;
  case 66630 : result = true;break;
  case 66631 : result = true;break;
  case 66632 : result = true;break;
  case 66633 : result = true;break;
  case 66634 : result = true;break;
  case 66635 : result = true;break;
  case 66636 : result = true;break;
  case 66637 : result = true;break;
  case 66638 : result = true;break;
  case 66639 : result = true;break;
  case 66776 : result = true;break;
  case 66777 : result = true;break;
  case 66778 : result = true;break;
  case 66779 : result = true;break;
  case 66780 : result = true;break;
  case 66781 : result = true;break;
  case 66782 : result = true;break;
  case 66783 : result = true;break;
  case 66784 : result = true;break;
  case 66785 : result = true;break;
  case 66786 : result = true;break;
  case 66787 : result = true;break;
  case 66788 : result = true;break;
  case 66789 : result = true;break;
  case 66790 : result = true;break;
  case 66791 : result = true;break;
  case 66792 : result = true;break;
  case 66793 : result = true;break;
  case 66794 : result = true;break;
  case 66795 : result = true;break;
  case 66796 : result = true;break;
  case 66797 : result = true;break;
  case 66798 : result = true;break;
  case 66799 : result = true;break;
  case 66800 : result = true;break;
  case 66801 : result = true;break;
  case 66802 : result = true;break;
  case 66803 : result = true;break;
  case 66804 : result = true;break;
  case 66805 : result = true;break;
  case 66806 : result = true;break;
  case 66807 : result = true;break;
  case 66808 : result = true;break;
  case 66809 : result = true;break;
  case 66810 : result = true;break;
  case 66811 : result = true;break;
  case 68800 : result = true;break;
  case 68801 : result = true;break;
  case 68802 : result = true;break;
  case 68803 : result = true;break;
  case 68804 : result = true;break;
  case 68805 : result = true;break;
  case 68806 : result = true;break;
  case 68807 : result = true;break;
  case 68808 : result = true;break;
  case 68809 : result = true;break;
  case 68810 : result = true;break;
  case 68811 : result = true;break;
  case 68812 : result = true;break;
  case 68813 : result = true;break;
  case 68814 : result = true;break;
  case 68815 : result = true;break;
  case 68816 : result = true;break;
  case 68817 : result = true;break;
  case 68818 : result = true;break;
  case 68819 : result = true;break;
  case 68820 : result = true;break;
  case 68821 : result = true;break;
  case 68822 : result = true;break;
  case 68823 : result = true;break;
  case 68824 : result = true;break;
  case 68825 : result = true;break;
  case 68826 : result = true;break;
  case 68827 : result = true;break;
  case 68828 : result = true;break;
  case 68829 : result = true;break;
  case 68830 : result = true;break;
  case 68831 : result = true;break;
  case 68832 : result = true;break;
  case 68833 : result = true;break;
  case 68834 : result = true;break;
  case 68835 : result = true;break;
  case 68836 : result = true;break;
  case 68837 : result = true;break;
  case 68838 : result = true;break;
  case 68839 : result = true;break;
  case 68840 : result = true;break;
  case 68841 : result = true;break;
  case 68842 : result = true;break;
  case 68843 : result = true;break;
  case 68844 : result = true;break;
  case 68845 : result = true;break;
  case 68846 : result = true;break;
  case 68847 : result = true;break;
  case 68848 : result = true;break;
  case 68849 : result = true;break;
  case 68850 : result = true;break;
  case 71872 : result = true;break;
  case 71873 : result = true;break;
  case 71874 : result = true;break;
  case 71875 : result = true;break;
  case 71876 : result = true;break;
  case 71877 : result = true;break;
  case 71878 : result = true;break;
  case 71879 : result = true;break;
  case 71880 : result = true;break;
  case 71881 : result = true;break;
  case 71882 : result = true;break;
  case 71883 : result = true;break;
  case 71884 : result = true;break;
  case 71885 : result = true;break;
  case 71886 : result = true;break;
  case 71887 : result = true;break;
  case 71888 : result = true;break;
  case 71889 : result = true;break;
  case 71890 : result = true;break;
  case 71891 : result = true;break;
  case 71892 : result = true;break;
  case 71893 : result = true;break;
  case 71894 : result = true;break;
  case 71895 : result = true;break;
  case 71896 : result = true;break;
  case 71897 : result = true;break;
  case 71898 : result = true;break;
  case 71899 : result = true;break;
  case 71900 : result = true;break;
  case 71901 : result = true;break;
  case 71902 : result = true;break;
  case 71903 : result = true;break;
  case 93792 : result = true;break;
  case 93793 : result = true;break;
  case 93794 : result = true;break;
  case 93795 : result = true;break;
  case 93796 : result = true;break;
  case 93797 : result = true;break;
  case 93798 : result = true;break;
  case 93799 : result = true;break;
  case 93800 : result = true;break;
  case 93801 : result = true;break;
  case 93802 : result = true;break;
  case 93803 : result = true;break;
  case 93804 : result = true;break;
  case 93805 : result = true;break;
  case 93806 : result = true;break;
  case 93807 : result = true;break;
  case 93808 : result = true;break;
  case 93809 : result = true;break;
  case 93810 : result = true;break;
  case 93811 : result = true;break;
  case 93812 : result = true;break;
  case 93813 : result = true;break;
  case 93814 : result = true;break;
  case 93815 : result = true;break;
  case 93816 : result = true;break;
  case 93817 : result = true;break;
  case 93818 : result = true;break;
  case 93819 : result = true;break;
  case 93820 : result = true;break;
  case 93821 : result = true;break;
  case 93822 : result = true;break;
  case 93823 : result = true;break;
  case 125218 : result = true;break;
  case 125219 : result = true;break;
  case 125220 : result = true;break;
  case 125221 : result = true;break;
  case 125222 : result = true;break;
  case 125223 : result = true;break;
  case 125224 : result = true;break;
  case 125225 : result = true;break;
  case 125226 : result = true;break;
  case 125227 : result = true;break;
  case 125228 : result = true;break;
  case 125229 : result = true;break;
  case 125230 : result = true;break;
  case 125231 : result = true;break;
  case 125232 : result = true;break;
  case 125233 : result = true;break;
  case 125234 : result = true;break;
  case 125235 : result = true;break;
  case 125236 : result = true;break;
  case 125237 : result = true;break;
  case 125238 : result = true;break;
  case 125239 : result = true;break;
  case 125240 : result = true;break;
  case 125241 : result = true;break;
  case 125242 : result = true;break;
  case 125243 : result = true;break;
  case 125244 : result = true;break;
  case 125245 : result = true;break;
  case 125246 : result = true;break;
  case 125247 : result = true;break;
  case 125248 : result = true;break;
  case 125249 : result = true;break;
  case 125250 : result = true;break;
  case 125251 : result = true;break;
  }
  return result;
}

CL_LAMBDA(c &optional (radix 10))
CL_DECLARE();
CL_DOCSTRING(R"dx(digitCharP)dx")
DOCGROUP(clasp)
CL_DEFUN T_sp cl__digit_char_p(Character_sp c, Fixnum_sp radix) {
  Fixnum basis = unbox_fixnum(radix);
  if (basis < 2 || basis > 36) {
    QERROR_WRONG_TYPE_NTH_ARG(2, radix, Integer_O::makeIntegerType(2, 36));
  }
  Fixnum value = clasp_digitp(clasp_as_claspCharacter(c), basis);
  if (value < 0) return nil<T_O>();
  return make_fixnum(value);
};

int unicodeHex2int (std::string aString){
    // parses "<U>(HexDigits)+"
    // Does not fail on "U(HexDigits)+<Space> [any Garbage]", e.g. "U100 Garbage"
    unsigned long sizeInput = aString.size();
    if (sizeInput <= 1)
        return -1;
    if (aString.at(0) == 'U') {
        std::string bString = aString.substr(1,sizeInput-1);
        long n = strtol(bString.c_str(), NULL, 16 );
        if ((n == 0) || (n == LONG_MAX) || (n == LONG_MIN)) {
            return -1;
        }
        else {
            return (int) n;
        }
    }
    else return -1;
}

CL_LAMBDA(sname)
CL_DECLARE();
CL_DOCSTRING(R"dx(name_char)dx")
DOCGROUP(clasp)
CL_DEFUN T_sp cl__name_char(T_sp sname) {
  String_sp name = coerce::stringDesignator(sname);
  String_sp upname = cl__string_upcase(name);
  T_sp it = _lisp->characterInfo()._NamesToCharacterIndex->gethash(upname);
  if (it.fixnump()) {
    return _lisp->characterInfo().gIndexedCharacters[it.unsafe_fixnum()];
  }
  // The upper exclusive bound on the value returned by the function char-code.
  // Treat U100 until U110000 -1 to be consistent with char-name
  claspCharacter conversion = unicodeHex2int(upname->get_std_string());
  if ((conversion >= 0) && (conversion < CHAR_CODE_LIMIT))
    return (Values (clasp_make_standard_character(conversion)));
    else return nil<T_O>();
};

CL_LAMBDA(och)
CL_DECLARE();
CL_DOCSTRING(R"dx(char_name)dx")
DOCGROUP(clasp)
CL_DEFUN SimpleBaseString_sp cl__char_name(Character_sp och) {
  claspCharacter ch = clasp_as_claspCharacter(och);
  if (ch<_lisp->characterInfo().gCharacterNames.size()) {
    return gc::As<SimpleBaseString_sp>(_lisp->characterInfo().gCharacterNames[ch]);
  }
  SafeBufferStr8Ns buffer;
  buffer._Buffer->fillPointerSet(0);
  buffer._Buffer->vectorPushExtend('U');
  core__integer_to_string(buffer._Buffer,Integer_O::create((Fixnum)ch),clasp_make_fixnum(16));
  auto ret = SimpleBaseString_O::make(buffer._Buffer->length(),'\0',false,buffer._Buffer->length(), &(*buffer._Buffer)[0]);
  return ret;
};

DOCGROUP(clasp)
CL_DEFUN T_sp core__all_characters() {
  return _lisp->characterInfo()._NamesToCharacterIndex->keysAsCons();
}
CL_LAMBDA(och)
CL_DECLARE();
CL_DOCSTRING(R"dx(char_code)dx")
DOCGROUP(clasp)
CL_DEFUN Fixnum_sp cl__char_code(Character_sp och) {
  claspCharacter ch = clasp_as_claspCharacter(och);
  return make_fixnum((Fixnum)ch);
};

CL_LAMBDA(och)
CL_DECLARE();
CL_DOCSTRING(R"dx(char_int)dx")
DOCGROUP(clasp)
CL_DEFUN Fixnum_sp cl__char_int(Character_sp och) {
  claspCharacter ch = clasp_as_claspCharacter(och);
  return make_fixnum((Fixnum)ch);
};

CL_LAMBDA(och)
CL_DECLARE();
CL_DOCSTRING(R"dx(code_char)dx")
DOCGROUP(clasp)
CL_DEFUN Character_sp cl__code_char(Integer_sp ich) {
  int ii = clasp_to_int(ich);
  if (ii >= 0 && ii < CHAR_CODE_LIMIT) {
    return clasp_make_character(ii);
  }
  return nil<Character_O>();
};


// ----------------------------------------------------------------------
//



  SYMBOL_EXPORT_SC_(ClPkg, char_code);
  SYMBOL_EXPORT_SC_(ClPkg, code_char);
  SYMBOL_EXPORT_SC_(ClPkg, char_int);

  SYMBOL_EXPORT_SC_(ClPkg, name_char);
  SYMBOL_EXPORT_SC_(ClPkg, char_name);
  SYMBOL_EXPORT_SC_(ClPkg, alpha_char_p);
  SYMBOL_EXPORT_SC_(ClPkg, standard_char_p);
  SYMBOL_EXPORT_SC_(ClPkg, charUpcase);
  SYMBOL_EXPORT_SC_(ClPkg, charDowncase);
  SYMBOL_EXPORT_SC_(ClPkg, char_LT_);
  SYMBOL_EXPORT_SC_(ClPkg, char_GT_);
  SYMBOL_EXPORT_SC_(ClPkg, char_LE_);
  SYMBOL_EXPORT_SC_(ClPkg, char_GE_);
  SYMBOL_EXPORT_SC_(ClPkg, char_NE_);
  SYMBOL_EXPORT_SC_(ClPkg, char_EQ_);

  SYMBOL_EXPORT_SC_(ClPkg, charLessp);
  SYMBOL_EXPORT_SC_(ClPkg, charGreaterp);
  SYMBOL_EXPORT_SC_(ClPkg, charNotGreaterp);
  SYMBOL_EXPORT_SC_(ClPkg, charNotLessp);
  SYMBOL_EXPORT_SC_(ClPkg, charNotEqual);
  SYMBOL_EXPORT_SC_(ClPkg, charEqual);
  SYMBOL_EXPORT_SC_(ClPkg, digitCharP);



}; /* core */
