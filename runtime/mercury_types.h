/*
** Copyright (C) 1995-2000 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_types.h - definitions of some basic types used by the
** code generated by the Mercury compiler and by the Mercury runtime.
*/

/*
** IMPORTANT NOTE:
** This file must not contain any #include statements,
** other than the #include of "mercury_conf.h",
** for reasons explained in mercury_imp.h.
*/

#ifndef MERCURY_TYPES_H
#define MERCURY_TYPES_H

#include "mercury_conf.h"

/*
** This section defines types similar to C9X's <stdint.h> header.
** We do not use <stdint.h>, or the <inttypes.h> or <sys/types.h> files
** that substitute for it on some systems because (a) some such files
** do not define the types we need, and (b) some such files include
** inline function definitions. The latter is a problem because we want to
** reserve some real machine registers for Mercury abstract machine registers.
** To be effective, the definitions of these global register variables
** must precede all function definitions, and we want to put their
** definitions after mercury_types.h.
*/

typedef unsigned MR_WORD_TYPE		MR_uintptr_t;
typedef MR_WORD_TYPE			MR_intptr_t;

#ifdef	MR_INT_LEAST64_TYPE
typedef unsigned MR_INT_LEAST64_TYPE	MR_uint_least64_t;
typedef MR_INT_LEAST64_TYPE		MR_int_least64_t;
#endif

typedef unsigned MR_INT_LEAST32_TYPE	MR_uint_least32_t;
typedef MR_INT_LEAST32_TYPE		MR_int_least32_t;
typedef unsigned MR_INT_LEAST16_TYPE	MR_uint_least16_t;
typedef MR_INT_LEAST16_TYPE		MR_int_least16_t;
typedef unsigned char			MR_uint_least8_t;
typedef signed char			MR_int_least8_t;

/* 
** This section defines the basic types that we use.
** Note that we require 
** 	sizeof(MR_Word) == sizeof(MR_Integer) == sizeof(MR_Code*).
*/

typedef	MR_uintptr_t		MR_Word;
typedef	MR_intptr_t		MR_Integer;
typedef	MR_uintptr_t		MR_Unsigned;
typedef	MR_intptr_t		MR_Bool;

/*
** `MR_Code *' is used as a generic pointer-to-label type that can point
** to any label defined using the Define_* macros in mercury_goto.h.
*/
typedef void			MR_Code;

/*
** MR_Float64 is required for the bytecode.
** XXX: We should also check for IEEE-754 compliance.
*/

#if	MR_FLOAT_IS_64_BIT
	typedef	float			MR_Float64;
#elif	MR_DOUBLE_IS_64_BIT
	typedef	double			MR_Float64;
#elif	MR_LONG_DOUBLE_IS_64_BIT
	typedef	long double		MR_Float64;
#else
	#error	"For Mercury bytecode, we require 64-bit IEEE-754 floating point"
#endif

/*
** The following four typedefs logically belong in mercury_string.h.
** They are defined here to avoid problems with circular #includes.
** If you modify them, you will need to modify mercury_string.h as well.
*/

typedef char MR_Char;
typedef unsigned char MR_UnsignedChar;

typedef MR_Char *MR_String;
typedef const MR_Char *MR_ConstString;

#ifndef MR_HIGHLEVEL_CODE
  /*
  ** semidet predicates indicate success or failure by leaving nonzero or zero
  ** respectively in register MR_r1
  ** (should this #define go in some other header file?)
  */
  #define SUCCESS_INDICATOR MR_r1
#endif

/*
** The MR_Box type is used for representing polymorphic types.
** Currently this is only used in the MLDS C backend.
**
** Since it is used in some C code fragments, we define it as MR_Word
** in the low-level backend.
*/
#ifdef MR_HIGHLEVEL_CODE
typedef void 	*MR_Box;
#else
typedef MR_Word MR_Box;
#endif



#endif /* not MERCURY_TYPES_H */
