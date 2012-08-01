%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2001, 2007 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% Module: posix.kill.
% Main author: Michael Day <miked@lendtech.com.au>
%
%-----------------------------------------------------------------------------%

:- module posix.kill.
:- interface.

:- import_module int.

:- pred kill(pid_t::in, int::in, posix.result::out, io::di, io::uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- pragma foreign_decl("C", "
    #include <sys/types.h>
    #include <signal.h>
").

%-----------------------------------------------------------------------------%

kill(Pid, Sig, Result, !IO) :-
    kill0(Pid, Sig, Res, !IO),
    ( if Res \= 0 then
        errno(Err, !IO),
        Result = error(Err)
    else
        Result = ok
    ).

:- pred kill0(pid_t::in, int::in, int::out, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    kill0(Pid::in, Sig::in, Res::out, IO0::di, IO::uo),
    [promise_pure, will_not_call_mercury, tabled_for_io],
"
    Res = kill(Pid, Sig);
    IO = IO0;
").

%-----------------------------------------------------------------------------%
:- end_module posix.kill.
%-----------------------------------------------------------------------------%