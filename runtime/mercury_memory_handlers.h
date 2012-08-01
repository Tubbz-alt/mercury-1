/*
** Copyright (C) 1998,2000, 2011 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_memory_handlers.h - signal handlers for the memory zones.
**
** This defines various signal handlers for memory access violations,
** including accesses to the redzones at the end of each zone.
*/

#ifndef	MERCURY_MEMORY_HANDLERS_H
#define	MERCURY_MEMORY_HANDLERS_H

#include "mercury_memory_zones.h"

/*
** MR_default_handler is a function that can be passed to MR_create_zone to
** unprotect enough of the redzone to allow the access to succeed, or
** fail if there is no space left in the zone.
*/

extern	MR_ZoneHandler MR_default_handler;

/*
** MR_null_handler is a function that can be passed to MR_create_zone
** which always fails.
*/

extern	MR_ZoneHandler MR_null_handler;

/*
**
** setup_signals() will setup the default signal handlers.
**
*/

extern	void	MR_setup_signals(void);

#ifdef MR_MSVC_STRUCTURED_EXCEPTIONS
/*
** Filter a Win32 exception (to be called in the __except filter
** part).
** Possible return values are:
**
** EXCEPTION_CONTINUE_EXECUTION (-1)
**  Exception is dismissed. Continue execution at the point where
**  the exception occurred.
**
** EXCEPTION_CONTINUE_SEARCH (0)
**  Exception is not recognized. Continue to search up the stack for
**  a handler, first for containing try-except statements, then for
**  handlers with the next highest precedence.
**
** EXCEPTION_EXECUTE_HANDLER (1)
**  Exception is recognized. Transfer control to the exception handler
**  by executing the __except compound statement, then continue
**  execution at the assembly instruction that was executing
**  when the exception was raised. 
*/
#include "mercury_windows.h"

int MR_filter_win32_exception(LPEXCEPTION_POINTERS exception_ptrs);
#endif

#endif /* not MERCURY_MEMORY_HANDLERS_H */