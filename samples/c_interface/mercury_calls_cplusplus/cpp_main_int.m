% This module cpp_main_int defines a Mercury predicate cpp_main which acts as an
% interface to the C++ function cpp_main(), which is defined in cpp_main.c.

:- module cpp_main_int.

:- interface.
:- import_module io.

% Since the cpp_main() function has side effects, we declare the corresponding
% Mercury predicate as one that takes an io__state pair.  If we didn't do
% this, the Mercury compiler might optimize away calls to it!

:- pred cpp_main(io__state::di, io__state::uo) is det.

:- implementation.

	% #include the header file containing the function prototype
	% for cpp_main(), using a `pragma c_header_code' declaration.
	% Note that any double quotes or backslashes in the C code for
	% the `#include' line must be escaped, since the C code is
	% given as a Mercury string.
:- pragma c_header_code("#include \"cpp_main.h\"").

	% Define the Mercury predicate cpp_main to call the C++ function
	% cpp_main.
:- pragma c_code(cpp_main(IO0::di, IO::uo), "cpp_main(); IO = IO0;").
