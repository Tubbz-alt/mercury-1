%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module prog_io.
:- import_module string, list, varset, term, io.

	% This module defines a data structure for representing Mercury
	% programs.
	%
	% In some ways the representation of programs is considerably
	% more complex than is necessary for the compiler.
	% The basic reason for this is that it was designed to preserve
	% as much information about the source code as possible, so that
	% this representation could also be used for other tools such
	% as Mercury-to-Goedel converters, pretty-printers, etc.
	% Currently the only information that is lost is the comments,
	% whitespace and indentation, and any redundant parenthesization.
	% It would be a good idea to preserve those too (well, maybe not
	% the redundant parentheses), but right now it's not worth the effort.
	%
	% So that means that this phase of compilation is purely parsing.
	% No simplifications are done.  The results of this phase specify
	% basically the same information as is contained in the source code,
	% but in a parse tree rather than a flat file.
	%
	% Some of this code is a nightmare of cut-and-paste style reuse.
	% It should be cleaned up to eliminate most of the duplication.
	% But that task really needs to wait until we implement higher-order
	% predicates.  For the moment, just be careful that any changes
	% you make are reflected correctly in all similar parts of this
	% file.

	% XXX todo:
	%
	% 1.  implement importing/exporting operators with a particular fixity
	%     eg. :- import_op prefix(+). % only prefix +, not infix
	%     (not important, but should be there for reasons of symmetry.)
	% 2.  improve the handling of type and inst parameters 
	%     (see XXX's below)
	% 3.  improve the error reporting
	%
	% Question: should we allow `:- rule' declarations???

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- interface.

%-----------------------------------------------------------------------------%

:- type int		==	integer. % XXX put this somewhere central

%-----------------------------------------------------------------------------%

	% This is how programs (and parse errors) are represented.

:- type maybe_program	--->	ok(message_list, program)
			;	error(message_list).
:- type message_list	==	list(pair(string, term)).
				% the error/warning message, and the
				% term to which it relates
:- type program		--->	module(module_name, list(item)).
:- type item		--->	clause(varset, sym_name, list(term), goal)
				%      VarNames, PredName, HeadArgs, ClauseBody
			; 	type_defn(varset, type_defn, condition)
			; 	inst_defn(varset, inst_defn, condition)
			; 	mode_defn(varset, mode_defn, condition)
			; 	module_defn(varset, module_defn)
			; 	pred(varset, sym_name, list(type_and_mode),
					condition)
				%      VarNames, PredName, ArgTypes, Cond
			; 	rule(varset, sym_name, list(type), condition)
				%      VarNames, PredName, ArgTypes, Cond
			; 	mode(varset, sym_name, list(mode), condition)
				%      VarNames, PredName, ArgModes, Cond
			;	unimplemented	% XXX
			; 	error.

:- type type_and_mode	--->	type_only(type)
			;	type_and_mode(type, mode).

%-----------------------------------------------------------------------------%

	% Here's how clauses and goals are represented.
	% (Constructs like "=>", "<=", and "<=>" are considered to be
	% just higher-order predicates, and so aren't represented
	% specially here.)

% clause/4 defined above

:- type goal		--->	(goal,goal)
			;	fail	
					% could use conj(goals) instead 
			;	{goal;goal}	% {...} quotes ';'/2.
			;	true	
					% could use disj(goals) instead
			;	not(vars,goal)
			;	some(vars,goal)
			;	all(vars,goal)
			;	if_then(vars,goal,goal)
			;	if_then_else(vars,goal,goal,goal)
			;	call(term).

:- type goals		==	list(goal).
:- type vars		==	list(variable).

%-----------------------------------------------------------------------------%

	% This is how types are represented.

			% one day we might allow types to take
			% value parameters as well as type parameters.

% type_defn/3 define above

:- type type_defn	--->	du_type(sym_name, list(type_param),
						list(constructor))
			;	uu_type(sym_name, list(type_param), list(type))
			;	eqv_type(sym_name, list(type_param), type).

	% XXX constructor should be pair(sym_name, list(type)) not term.
:- type constructor	==	term.

	% XXX type parameters should be variables not terms
:- type type_param	=	term.

:- type (type)		=	term.

	% Types may have arbitrary assertions associated with them
	% (eg. you can define a type which represents sorted lists).
	% The compiler will ignore these assertions - they are intended
	% to be used by other tools, such as the debugger.

:- type condition	--->	true
			;	where(term).

%-----------------------------------------------------------------------------%

	% This is how instantiatednesses and modes are represented.
	% Note that while we use the normal term data structure to represent 
	% type terms (see above), we need a separate data structure for inst 
	% terms.

% inst_defn/3 defined above

:- type inst_defn	--->	inst_defn(sym_name, list(inst_param), inst).

	% XXX inst parameters should be variables not terms.
:- type inst_param	==	term.

:- type (inst)		--->	free
			;	bound(list(bound_inst))
			;	ground
			;	inst_var(var)
			;	user_defined_inst(sym_name, list(inst)).

:- type bound_inst	--->	functor(const, list(inst)).


% mode_defn/3 defined above

:- type mode_defn	--->	mode_defn(sym_name, list(inst_param), mode).

:- type (mode)		--->	((inst) -> (inst))
			;	user_defined_mode(sym_name, list(inst)).

% mode/4 defined above

%-----------------------------------------------------------------------------%
	
	% This is how module-system declarations (such as imports
	% and exports) are represented.

:- type module_defn	--->	module(module_name)
			;	interface
			;	implementation
			;	end_module(module_name)
			;	export(sym_list)
			;	import(sym_list)
			;	use(sym_list).
:- type sym_list	--->	sym(list(sym_specifier))
			;	pred(list(pred_specifier))
			;	cons(list(pred_specifier))
			;	op(list(op_specifier))
			;	adt(list(sym_name_specifier))
	 		;	type(list(sym_name_specifier))
	 		;	module(list(module_specifier)).
:- type sym_specifier	--->	sym(sym_name_specifier)
			;	typed_sym(typed_cons_specifier)
			;	pred(pred_specifier)
			;	cons(cons_specifier)
			;	op(op_specifier)
			;	adt(sym_name_specifier)
	 		;	type(sym_name_specifier)
	 		;	module(module_specifier).
:- type pred_specifier	--->	sym(sym_name_specifier)
			;	name_args(sym_name, list(type)).
:- type cons_specifier	--->	sym(sym_name_specifier)
			;	typed(typed_cons_specifier).
:- type typed_cons_specifier --->	
				name_args(sym_name, list(type))
			;	name_res(sym_name_specifier, type)
			;	name_args_res(sym_name,
						list(type), type).
:- type op_specifier	--->	sym(sym_name_specifier)
			% XXX operator fixity specifiers not yet implemented
			;	fixity(sym_name_specifier, fixity).
:- type fixity		--->	infix ; prefix ; postfix.
:- type sym_name_specifier ---> name(sym_name)
			;	name_arity(sym_name, integer).
:- type sym_name 	--->	unqualified(string)
			;	qualified(module_specifier, string).

:- type module_specifier ==	string.
:- type module_name 	== 	string.

%-----------------------------------------------------------------------------%

% This module (prog_io) exports the following predicate:

:- pred prog_io__read_program(string, maybe_program, io__state, io__state).
:- mode prog_io__read_program(input, output, di, uo).

% 	read_program(FileName, Result)
%	- reads and parses file 'FileName'. Result is either
%	  ok(Warnings,Program) or error(Messages) where Warnings
%	  is a list of warning messages, Program is the parse tree,
%	  and Messages is a list of warning/error messages.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

	% When actually reading in type declarations, we need to
	% check for errors.

:- type maybe(T)	--->	error(string, term)
			;	ok(T).
:- type maybe2(T1, T2)	--->	error(string, term)
			;	ok(T1, T2).
:- type maybe_functor	== 	maybe2(sym_name, list(term)).
:- type maybe_constructor ==	maybe2(sym_name, list(type)).

% This implementation uses io__read_term to read in the program
% term at a time, and then converts those terms into clauses and
% declarations, checking for errors as it goes.
% Note that rather than using difference lists, we just
% build up the lists of items and messages in reverse order
% and then reverse them afterwards.  (Using difference lists would require
% late-input modes.)

prog_io__read_program(FileName, Result) -->
	io__op(1199, fx, "rule"),
	io__op(1179, xfy, "--->"),		% XXX should be automatic
	io__see(FileName, R),
	(if { R = ok } then
		read_program_3(RevMessages, RevItems0, Error),
		{
		  get_end_module(RevItems0, RevItems, EndModule),

		  reverse(RevMessages, Messages),
		  reverse(RevItems, Items),

		  check_begin_module(Messages, Items, Error, EndModule,
				     Result)
		},
		io__seen
	else
		{ io__progname(Progname),
		  string__append(Progname, ": can't open file '", Message1),
		  string__append(Message1, FileName, Message2),
		  string__append(Message2, "'.\n", Message),
		  Term = term_functor(term_atom("<end of file>"), [])
		}
	).


%-----------------------------------------------------------------------------%

	% extract the final `:- end_module' declaration if any

:- type module_end ---> no ; yes(module_name).

:- pred get_end_module(message_list, message_list, module_end).
:- mode get_end_module(input, output, output).

get_end_module(RevItems0, RevItems, EndModule) :-
	(if some [VarSet, ModuleName, RevItems1]
		RevItems0 = [module_defn(VarSet, end_module(ModuleName))
			    | RevItems1]
	then
		RevItems = RevItems1,
		EndModule = yes(ModuleName)
	else
		RevItems = RevItems0,
		EndModule = no
	).

%-----------------------------------------------------------------------------%

	% check that the module starts with a :- module declaration,
	% and that the end_module declaration (if any) is correct,
	% and construct the final parsing result.

:- pred check_begin_module(message_list, list(item), yes_or_no,
			   module_end, maybe_program).
:- mode check_begin_module(input, input, input, input, output).

check_begin_module(Messages0, Items0, Error, EndModule, Result) :-

    % check that the first item is a `:- module ModuleName'
    % declaration

    (if some [VarSet, ModuleName1, Items1]
        Items0 = [module_defn(VarSet, module(ModuleName1))
              | Items1]
    then
        % check that the end module declaration (if any)
        % matches the begin module declaration 

        (if some [ModuleName2] (
            EndModule = yes(ModuleName2),
            ModuleName1 \= ModuleName2
            )
        then
            ThisError = error(
"`:- end_module' declaration doesn't match `:- module' declaration",
			term_functor(term_atom("<end of file>"), []) ),
            append([ThisError], Messages0, Messages),
            Program = error(Messages)
        else
            (if Error = yes then
                Program = error(Messages0)
            else
                Program = ok(Messages0, module(ModuleName1,Items1))
            )
        )
    else
        ThisError = error("module should start with a ':- module' declaration",
            		   term_functor(term_atom("<start of file>"), []) ),
        Program = error([ThisError | Messages])
    ).

%-----------------------------------------------------------------------------%
 	% Read a source file from standard input, first reading in
	% the input term by term and then parsing those terms and producing
	% a high-level representation.
	% Parsing is actually a 3-stage process instead of the
	% normal two-stage process:
	%	lexical analysis (chars -> tokens),
	% 	parsing stage 1 (tokens -> terms),
	%	parsing stage 2 (terms -> items).
	% The final stage produces a list of program items, each of
	% which may be a declaration or a clause.

:- type yes_or_no ---> yes ; no.

:- pred read_program_3(message_list, program, yes_or_no, io__state, io__state).
:- mode read_program_3(output, output, output, di, uo).
read_program_3(Messages, Items, Error) -->
	io__read_term(MaybeTerm),
	read_program_4(MaybeTerm, [], [], no, Messages, Items, Error).

:- pred read_program_4(read_term, message_list, program, yes_or_no,
			message_list, program, yes_or_no,
			io__state,io__state).
:- mode read_program_4(input, input, input, input,
			output, output, output, di, uo).

read_program_4(eof, Msgs, Items, Error, Msgs, Items, Error) --> []. 

read_program_4(error(ErrorMsg), Msgs0, Items, _, Msgs, Items, yes) -->
	{
	  Error = error(Msg, term_functor(term_atom(""), [])),
	  Msgs = [Error | Msgs]
	}.

read_program_4(term(VarSet, Term), Msgs0, Items0,
		Error0, Msgs, Items, Error) -->
	{ 
	  parse_item(VarSet, Term, MaybeItem),
	  process_item(MaybeItem, Msgs0, Items0, Error0,
				  Msgs1, Items1, Error1)
	},
	io__read_term(MaybeTerm),
 	read_program_4(MaybeTerm, Messages1, Items1, Error1,
			Msgs, Items, Error).

:- pred process_item(maybe(item),  message_list, program, yes_or_no,
		       message_list, program, yes_or_no). 
:- mode process_item(input, input, input, input,
			output, output, output).
process_item(ok(Item), Msgs, Items0, Error, Msgs, [Item|Items0], Error).
process_item(error(M,T), Msgs0, Items, _, Msgs, Items0, yes) :-
	add_error(M, T, Msgs0, Msgs).

:- pred parse_item(varset, term, maybe(item)).
:- mode parse_item(input, input, output).
parse_item(VarSet, Term, Result) :-
 	(if some [Decl]
		Term = term_functor(term_atom(":-"), [Decl])
	then
		parse_decl(VarSet, Decl, Result)
	else
			% OK, it's not a declaration. Is it a fact, or a rule?
		(if some [H,B]
			Term = term_functor(term_atom(":-"), [H,B])
		then		% it's a fact
			Head = H,
			Body = B
		else		% it's a rule
			Head = Term,
			Body = term_functor(term_atom("true"), [])
		),
		parse_goal(Body, Body2),
		parse_qualified_term(Head, "clause head", Result),
		process_clause(Result, VarSet, Body2, Msgs0, Error0,
				Item, Msgs1, Error)
	).

:- pred process_clause(maybe_functor, varset, term, maybe(item)).
:- mode process_clause(input, input, input, input, output).
process_clause(ok(Name, Args), VarSet, Body,
		ok(clause(VarSet, Name, Args, Body))).
process_clause(error(ErrMessage, Term), _, _, error(ErrMessage, Term)).

:- pred join_error(yes_or_no, yes_or_no, yes_or_no).
:- mode join_error(input, input, output).
join_error(yes, _, yes).
join_error(no, Error, Error).

%-----------------------------------------------------------------------------%

	% parse a goal

:- pred parse_goal(term, goal).
:- mode parse_goal(input, output).
parse_goal(Term, Goal) :-
	(if some [Goal2]
		parse_goal_2(Term, Goal2)
	then
		Goal = Goal2
	else
		Goal = call(Term)
	).

:- pred parse_goal_2(term, goal).
:- mode parse_goal_2(input, output).
parse_goal_2(term_functor(term_atom("true"),[]), true).
parse_goal_2(term_functor(term_atom("fail"),[]), fail).
parse_goal_2(term_functor(term_atom(","),[A0,B0]), (A,B)) :-
	parse_goal(A0, A),
	parse_goal(B0, B).
parse_goal_2(term_functor(term_atom(";"),[A0,B0]), (A;B)) :-
	parse_goal(A0, A),
	parse_goal(B0, B).
parse_goal_2(term_functor(term_atom("if"),
		[term_functor(term_atom("then"),[A0,B0])]),
		if_then(Vars,A,B)) :-
	parse_some_vars_goal(A0, Vars, A),
	parse_goal(B0, B).
parse_goal_2( term_functor(term_atom("else"),[
		    term_functor(term_atom("if"),[
			term_functor(term_atom("then"),[A0,B0])
		    ]),
		    C0
		]),
		if_then_else(Vars,A,B,C)) :-
	parse_some_vars_goal(A0, Vars, A),
	parse_goal(B0, B),
	parse_goal(C0, C).
parse_goal_2( term_functor(term_atom("not"), [A0]), not([],A) ) :-
	parse_goal(A0, A).
parse_goal_2( term_functor(term_atom("all"),[Vars0,A0]),all(Vars,A) ):-
	term_vars(Vars0, Vars),
	parse_goal(A0, A).

:- pred parse_some_vars_goal(term, vars, goal).
:- mode parse_some_vars_goal(input, output, output).
parse_some_vars_goal(A0, Vars, A) :-
	(if some [Vars0, A1]
		A0 = term_functor(term_atom("some"), [Vars0,A1])
	then
		term_vars(Vars0, Vars),
		parse_goal(A1, A)
	else
		Vars = [],
		parse_goal(A0, A)
	).

%-----------------------------------------------------------------------------%

	% parse a declaration

:- pred parse_decl(varset, term, maybe_item).
:- mode parse_decl(input, input, output).
parse_decl(VarSet, F, Result) :-
	(if some [Atom, As]
		F = term_functor(term_atom(Atom), As)
	then
		(if some [R]
			process_decl(VarSet, Atom, As, R)
		then
			Result = R
		else
			Result = error("unrecognized declaration", F)
		)
	else
		Result = error("atom expected after `:-'", F)
	).

	% process_decl(VarSet, Atom, Args, Result) succeeds if Atom(Args)
	% is a declaration and binds Result to a representation of that
	% declaration.
:- pred process_decl(varset, string, list(term), maybe(item)).
:- mode process_decl(input, input, input, output).

process_decl(VarSet, "type", [TypeDecl], Result) :-
	parse_type_decl(VarSet, TypeDecl, Result).

process_decl(VarSet, "pred", [PredDecl], Result) :-
	parse_type_decl_pred(VarSet, PredDecl, Result).

/*** OBSOLETE
process_decl(VarSet, "rule", [RuleDecl], Result) :-
	parse_type_decl_rule(VarSet, RuleDecl, Result).
***/

process_decl(VarSet, "mode", [ModeDecl], Result) :-
	parse_mode_decl(VarSet, ModeDecl, Result).

process_decl(VarSet, "inst", [InstDecl], Result) :-
	parse_inst_decl(VarSet, InstDecl, Result).

process_decl(VarSet, "import_module", [ModuleSpec], Result) :-
	parse_import_module_decl(VarSet, ModuleSpec, Result).

process_decl(VarSet, "use_module", [ModuleSpec], Result) :-
	parse_use_module_decl(VarSet, ModuleSpec, Result).

process_decl(VarSet, "export_module", [ModuleSpec], Result) :-
	parse_export_module_decl(VarSet, ModuleSpec, Result).

process_decl(VarSet, "import_sym", [SymSpec], Result) :-
	parse_import_sym_decl(VarSet, SymSpec, Result).

process_decl(VarSet, "use_sym", [SymSpec], Result) :-
	parse_use_sym_decl(VarSet, SymSpec, Result).

process_decl(VarSet, "export_sym", [SymSpec], Result) :-
	parse_export_sym_decl(VarSet, SymSpec, Result).

process_decl(VarSet, "import_pred", [PredSpec], Result) :-
	parse_import_pred_decl(VarSet, PredSpec, Result).

process_decl(VarSet, "use_pred", [PredSpec], Result) :-
	parse_use_pred_decl(VarSet, PredSpec, Result).

process_decl(VarSet, "export_pred", [PredSpec], Result) :-
	parse_export_pred_decl(VarSet, PredSpec, Result).

process_decl(VarSet, "import_cons", [ConsSpec], Result) :-
	parse_import_cons_decl(VarSet, ConsSpec, Result).

process_decl(VarSet, "use_cons", [ConsSpec], Result) :-
	parse_use_cons_decl(VarSet, ConsSpec, Result).

process_decl(VarSet, "export_cons", [ConsSpec], Result) :-
	parse_export_cons_decl(VarSet, ConsSpec, Result).

process_decl(VarSet, "import_type", [TypeSpec], Result) :-
	parse_import_type_decl(VarSet, TypeSpec, Result).

process_decl(VarSet, "use_type", [TypeSpec], Result) :-
	parse_use_type_decl(VarSet, TypeSpec, Result).

process_decl(VarSet, "export_type", [TypeSpec], Result) :-
	parse_export_type_decl(VarSet, TypeSpec, Result).

process_decl(VarSet, "import_adt", [ADT_Spec], Result) :-
	parse_import_adt_decl(VarSet, ADT_Spec, Result).

process_decl(VarSet, "use_adt", [ADT_Spec], Result) :-
	parse_use_adt_decl(VarSet, ADT_Spec, Result).

process_decl(VarSet, "export_adt", [ADT_Spec], Result) :-
	parse_export_adt_decl(VarSet, ADT_Spec, Result).

process_decl(VarSet, "import_op", [OpSpec], Result) :-
	parse_import_op_decl(VarSet, OpSpec, Result).

process_decl(VarSet, "use_op", [OpSpec], Result) :-
	parse_use_op_decl(VarSet, OpSpec, Result).

process_decl(VarSet, "export_op", [OpSpec], Result) :-
	parse_export_op_decl(VarSet, OpSpec, Result).

process_decl(VarSet, "interface", [], ok(module_defn(VarSet, interface))).
process_decl(VarSet, "implementation", [],
				ok(module_defn(VarSet, implementation))).

	% XXX

process_decl(VarSet, "module", [_ModuleName], ok(unimplemented)).
process_decl(VarSet, "end_module", [_ModuleName], ok(unimplemented)).

:- pred parse_type_decl(varset, term, maybe(item)).
:- mode parse_type_decl(input, input, output).
parse_type_decl(VarSet, TypeDecl, Result) :-
    (if some [R, Cond]
	parse_type_decl_type(TypeDecl, Cond, R) 
    then
	parse_type_decl_2(R, VarSet, Cond, Result)
    else
	Result = error("Invalid type declaration (need =, == or --->)", TypeDecl)
    ).

:- pred parse_type_decl_2(maybe(type_defn), varset, condition, maybe(item)).
:- mode parse_type_decl_2(input, input, input, output).
parse_type_decl_2(error(Error, Term), _, _, error(Error, Term)).
parse_type_decl_2(ok(TypeDefn), VarSet, Cond,
					ok(type_defn(VarSet, TypeDefn, Cond))).
		% XXX we should check the condition for errs
		%    (don't bother at the moment, since we ignore
		%     conditions anyhow :-)

%-----------------------------------------------------------------------------%

	% add a warning message to the list of messages

:- pred add_warning(string, term, message_list, message_list).
:- mode add_warning(input, input, output, input).
add_warning(Warning, Term, [Msg - Term | Msgs], Msgs) :-
	string__append("warning: ", Warning, Msg).

	% add an error message to the list of messages

:- pred add_error(string, term, message_list, message_list).
:- mode add_error(input, input, input, output).
add_error(Error, Term, Msgs, [Msg - Term | Msgs]) :-
	string__append("error: ", Error, Msg).

%-----------------------------------------------------------------------------%
	% parse_type_decl_type(Term, Condition, Result) succeeds
	% if Term is a "type" type declaration, and binds Condition
	% to the condition for that declaration (if any), and Result to
	% a representation of the declaration.

:- pred parse_type_decl_type(term, condition, maybe(type_defn)).
:- mode parse_type_decl_type(input, input, output).

parse_type_decl_type(term_functor(term_atom("--->"),[H,B]), Condition, R) :-
	get_condition(B, Body, Condition),
	process_du_type(H, Body, R).

parse_type_decl_type(term_functor(term_atom("="),[H,B]), Condition, R) :-
	get_condition(B, Body, Condition),
	process_uu_type(H, Body, R).
	
parse_type_decl_type(term_functor(term_atom("=="),[H,B]), Condition, R) :-
	get_condition(B, Body, Condition),
	process_eqv_type(H, Body, R).

%-----------------------------------------------------------------------------%
	% parse_type_decl_pred(Pred, Condition, Result) succeeds
	% if Pred is a "pred" type declaration, and binds Condition
	% to the condition for that declaration (if any), and Result to
	% a representation of the declaration.
:- pred parse_type_decl_pred(varset, term, maybe(item)).
:- mode parse_type_decl_pred(input, input, output).
parse_type_decl_pred(VarSet, Pred, R) :-
	get_condition(Pred, Body, Condition),
	process_pred(VarSet, Body, Condition, R).

%-----------------------------------------------------------------------------%

/*** OBSOLETE
	% parse_type_decl_rule(VarSet, Rule, Result) succeeds
	% if Rule is a "rule" type declaration, and binds Result to
	% a representation of the declaration.
	% ("rule" here means DCG predicate, not horn clause.)
:- pred parse_type_decl_rule(varset, term, maybe(item)).
:- mode parse_type_decl_rule(input, input, output).
parse_type_decl_rule(VarSet, Rule, R) :-
	get_condition(Rule, Body, Condition),
	process_mode(VarSet, Body, Condition, R).
****/

%-----------------------------------------------------------------------------%
	% parse_mode_decl_pred(Pred, Condition, Result) succeeds
	% if Pred is a "pred" mode declaration, and binds Condition
	% to the condition for that declaration (if any), and Result to
	% a representation of the declaration.
:- pred parse_mode_decl_pred(varset, term, maybe(item)).
:- mode parse_mode_decl_pred(input, input, output).
parse_mode_decl_pred(VarSet, Pred, R) :-
	get_condition(Pred, Body, Condition),
	process_mode(VarSet, Body, Condition, R).

%-----------------------------------------------------------------------------%
	% get_condition(Term0, Term, Condition) binds Condition
	% to a representation of the 'where' condition of Term0, if any,
	% and binds Term to the other part of Term0. If Term0 does not
	% contain a condition, then Condition is bound to true.
:- pred get_condition(term, term, condition).
:- mode get_condition(input, output, output).
get_condition(B, Body, Condition) :-
	(if some [Body1, Condition1]
		B = term_functor(term_atom("where"), [Body1, Condition1])
	then
		Body = Body1,
		Condition = where(Condition1)
	else
		Body = B,
		Condition = true
	).

%-----------------------------------------------------------------------------%

	% This is for "Head = Body" (undiscriminated union) definitions.
:- pred process_uu_type(term, term, maybe(type_defn)).
:- mode process_uu_type(input, input, output).
process_uu_type(Head, Body, Result) :-
	check_for_errors(Head, Body, Result0),
	process_uu_type_2(Result0, Body, Result).

:- pred process_uu_type_2(maybe_functor, term, maybe(type_defn)).
:- mode process_uu_type_2(input, input, output).
process_uu_type_2(error(Error, Term), _, error(Error, Term)).
process_uu_type_2(ok(Name, Args), Body, ok(uu_type(Name,Args,List))) :-
		sum_to_list(Body, List).

%-----------------------------------------------------------------------------%

	% This is for "Head == Body" (equivalence) definitions.
:- pred process_eqv_type(term, term, maybe(type_defn)).
:- mode process_eqv_type(input, input, output).
process_eqv_type(Head, Body, Result) :-
	check_for_errors(Head, Body, Result0),
	process_eqv_type_2(Result0, Body, Result).

:- pred process_eqv_type_2(maybe_functor, term, maybe(type_defn)).
:- mode process_eqv_type_2(input, input, output).
process_eqv_type_2(error(Error, Term), _, error(Error, Term)).
process_eqv_type_2(ok(Name, Args), Body, ok(eqv_type(Name,Args,Body))).

%-----------------------------------------------------------------------------%

	% process_du_type(TypeHead, TypeBody, Result)
	% checks that its arguments are well formed, and if they are,
	% binds Result to a representation of the type information about the
	% TypeHead.
	% This is for "Head ---> Body" (constructor) definitions.
:- pred process_du_type(term, term, maybe(type_defn)).
:- mode process_du_type(input, input, output).
process_du_type(Head, Body, Result) :-
	check_for_errors(Head, Body, Result0),
	process_du_type_2(Result0, Body, Result).

:- pred process_du_type_2(maybe_functor, term, maybe(type_defn)).
:- mode process_du_type_2(input, input, output).
process_du_type_2(error(Error, Term), _, error(Error, Term)).
process_du_type_2(ok(Functor,Args), Body, Result) :-
	% check that body is a disjunction of constructors
	(if some [Constrs] 
		convert_constructors(Body, Constrs)
	then
		Result = ok(du_type(Functor, Args, Constrs))
	else
		Result = error("Invalid RHS of type definition", Body)
	).

%-----------------------------------------------------------------------------%

	%  check a type definition for errors
	
:- pred check_for_errors(term, term, maybe_functor).
:- mode check_for_errors(input, input, output).
check_for_errors(Term, _, error("variable on LHS of type definition", Term)) :-
	Term = term_variable(_).
check_for_errors(Term, Body, Result) :-
	Term = term_functor(_,_),
	parse_qualified_term(Term, "type definition", R),
	check_for_errors_2(R, Body, Term, Result).

:- pred check_for_errors_2(maybe_functor, term, term, maybe_functor).
:- mode check_for_errors_2(input, input, input, output).
check_for_errors_2(error(Msg, Term), _, _, error(Msg, Term)).
check_for_errors_2(ok(Name, Args), Body, Term, Result) :-
	check_for_errors_3(Name, Args, Body, Term, Result).

:- pred check_for_errors_3(sym_name, list(term), term, term, maybe_functor).
:- mode check_for_errors_3(input, input, input, input, output).
check_for_errors_3(Name, Args, Body, Term, Result) :-
	% check that all the head args are variables
	(if	some [Arg] (
			member(Arg, Args),
			all [Var] Arg ~= term_variable(Var)
		)
	then
		Result = error("Type parameters must be variables", Arg)
	else
	% check that all the head arg variables are distinct
	if	some [Arg2, OtherArgs] (
			member(Arg2, Args, Arg2.OtherArgs),
			member(Arg2, OtherArgs)
		)
	then
		Result = error("Repeated type parameters in LHS of type defn", Term)
	else
	% check that all the variables in the body occur in the head
	if	some [Var2] (
			term_contains_var(Body, Var2),
			not term_contains_var_list(Args, Var2)
		)
	then
		Result = error("Free type parameter in RHS of type definition",
				Var2)
	else
		Result = ok(Name, Args)
	).

%-----------------------------------------------------------------------------%

	% Convert a list of terms separated by semi-colons
	% (known as a "disjunction", even thought the terms aren't goals
	% in this case) into a list of constructors

:- pred convert_constructors(term, list(constructor)).
:- mode convert_constructors(input, output).
convert_constructors(Body,Constrs) :-
	disjunction_to_list(Body, List),
	convert_constructors_2(List, Constrs).

	% true if input argument is a valid list of constructors

:- pred convert_constructors_2(list(term), list(constructor)).
:- mode convert_constructors_2(input, output).
convert_constructors_2([], []).
convert_constructors_2(Term.Terms, Constr.Constrs) :-
	convert_constructor(Term, Constr),
	convert_constructors_2(Terms, Constrs).

	% true if input argument is a valid constructor

:- pred convert_constructor(term, constructor).
:- mode convert_constructor(input, output).
convert_constructor(term_functor(Functor,Args), term_functor(Functor,Args)).

%-----------------------------------------------------------------------------%

	% convert a "disjunction" (bunch of terms separated by ';'s) to a list

:- pred disjunction_to_list(term, list(term)).
:- mode disjunction_to_list(input, output).
disjunction_to_list(Term, List) :-
	binop_term_to_list(";", Term, List).

	% convert a "conjunction" (bunch of terms separated by ','s) to a list

:- pred conjunction_to_list(term, list(term)).
:- mode conjunction_to_list(input, output).
conjunction_to_list(Term, List) :-
	binop_term_to_list(",", Term, List).

	% convert a "sum" (bunch of terms separated by '+' operators) to a list

:- pred sum_to_list(term, list(term)).
:- mode sum_to_list(input, output).
sum_to_list(Term, List) :-
	binop_term_to_list("+", Term, List).

	% general predicate to convert terms separated by any specified
	% operator into a list

:- pred binop_term_to_list(string, term, list(term)).
:- mode binop_term_to_list(input, input, output).
binop_term_to_list(Op, Term, List) :-
	binop_term_to_list_2(Op, Term, [], List).

:- pred binop_term_to_list_2(string, term, list(term), list(term)).
:- mode binop_term_to_list_2(input, input, input, output).
binop_term_to_list_2(Op, Term, List0, List) :-
	(if some [L, R]
		Term = term_functor(term_atom(Op), [L, R])
	then
		binop_term_to_list_2(Op, L, List0, List1),
		binop_term_to_list_2(Op, R, List1, List)
	else
		List = [Term|List0]
	).

%-----------------------------------------------------------------------------%

	% parse a `:- pred p(...)' declaration

:- pred process_pred(varset, term, condition, maybe(item)).
:- mode process_pred(input, input, input, output).
process_pred(VarSet, PredType, Cond, Result) :-
	parse_qualified_term(PredType, "`:- pred' declaration", R),
	process_pred_2(R, PredType, VarSet, Cond, Result).

:- pred process_pred_2(maybe_functor, term, varset, condition, maybe(item)).
:- mode process_pred_2(input, input, input, input, output).
process_pred_2(ok(F, As0), PredType, VarSet, Cond, Result) :-
	(if some [As]
		convert_type_and_mode_list(As0, As)
	then
		Result = ok(pred(VarSet, F, As, Cond))
	else
		Result = error("syntax error in :- pred declaration", PredType)
	).
process_pred_2(error(M, T), _, _, _, error(M, T)).

	% parse a `:- mode p(...)' declaration

:- pred process_mode(varset, term, condition, maybe(item)).
:- mode process_mode(input, input, input, output).
process_mode(VarSet, PredMode, Cond, Result) :-
	parse_qualified_term(PredMode, "`:- mode' declaration", R),
	process_mode_2(R, PredMode, VarSet, Cond, Result).

:- pred process_mode_2(maybe_functor, term, varset, condition, maybe(item)).
:- mode process_mode_2(input, input, input, input, output).
process_mode_2(ok(F, As0), PredMode, VarSet, Cond, Result) :-
	(if some [As]
		convert_mode_list(As0, As)
	then
		Result = ok(mode(VarSet, F, As, Cond))
	else
		Result = error("syntax error in predicate mode declaration",
				PredMode)
	).
process_mode_2(error(M, T), _, _, _, error(M, T)).

/*** OBSOLETE
	% A rule declaration is just the same as a pred declaration,
	% except that it is for DCG rules, so there are two hidden arguments. 

:- pred process_rule(varset, term, condition, maybe(item)).
:- mode process_rule(input, input, input, output).
process_rule(VarSet, RuleType, Cond, Result) :-
	parse_qualified_term(RuleType, "`:- rule' declaration", R),
	process_rule_2(R, VarSet, Cond, Result).

:- pred process_rule_2(maybe_functor, varset, condition, maybe(item)).
:- mode process_rule_2(input, input, input, output).
process_rule_2(ok(F, As), VarSet, Cond, ok(rule(VarSet, F, As, Cond))).
process_rule_2(error(M, T), _, _, error(M, T)).
***/

/*** JUNK
process_rule(VarSet, RuleType, Cond, Result) :-
	varset__new_var(VarSet, Var, VarSet1),
	RuleType = term_functor(F, RuleArgs),
	append(RuleArgs, [Var, Var], PredArgs),
	PredType = term_functor(F, PredArgs),
	process_pred(VarSet1, PredType, Cond, Result).
***/

%-----------------------------------------------------------------------------%

	% parse a `:- inst foo = ...' definition

:- pred parse_inst_decl(varset, term, maybe(item)).
:- mode parse_inst_decl(input, input, output).
parse_inst_decl(VarSet, InstDefn, Result) :-
	(if some [H,B]
		InstDefn = term_functor(term_atom("="),[H,B])
	then
		get_condition(B, Body, Condition),
		convert_inst_defn(H, Body, R),
		process_inst_defn(R, VarSet, Condition, Result)
	else
		Result = error("`=' expected in `:- inst' definition", InstDefn)
	).

		% XXX we should check the condition for errs
		%    (don't bother at the moment, since we ignore
		%     conditions anyhow :-)

:- pred convert_inst_defn(term, term, maybe(inst_defn)).
:- mode convert_inst_defn(input, input, output).
convert_inst_defn(Head, Body, Result) :-
	parse_qualified_term(Head, "inst definition", R),
	convert_inst_defn_2(R, Head, Body, Result).

:- pred convert_inst_defn_2(maybe_functor, term, term, maybe(inst_defn)).
:- mode convert_inst_defn_2(input, input, input, output).
convert_inst_defn_2(error(M,T), _, _, error(M,T)).
convert_inst_defn_2(ok(Name, Args), Head, Body, Result) :-
	% check that all the head args are variables
	(if	some [Arg] (
			member(Arg, Args),
			all [Var] Arg ~= term_variable(Var)
		)
	then
		Result = error("Inst parameters must be variables", Arg)
	else
	% check that all the head arg variables are distinct
	if	some [Arg2, OtherArgs] (
			member(Arg2, Args, Arg2.OtherArgs),
			member(Arg2, OtherArgs)
		)
	then
		Result = error("Repeated inst parameters in LHS of inst defn",
				Head)
	else
	% check that all the variables in the body occur in the head
	if	some [Var2] (
			term_contains_var(Body, Var2),
			not term_contains_var_list(Args, Var2)
		)
	then
		Result = error("Free inst parameter in RHS of inst definition",
				Var2)
	else
		% should improve the error message here

		(if some [ConvertedBody]
			convert_inst(Body, ConvertedBody)
		then
			Result = ok(inst_defn(Name, Args, ConvertedBody))
		else
			Result = error("syntax error in inst body", Body)
		)
	).

:- pred convert_inst_list(list(term), list(inst)).
:- mode convert_inst_list(input, output).
convert_inst_list([], []).
convert_inst_list([H0|T0], [H|T]) :-
	convert_inst(H0, H),
	convert_inst_list(T0, T).

:- pred convert_inst(term, inst).
:- mode convert_inst(input, output).
convert_inst(term_variable(V), inst_var(V)).
convert_inst(term_functor(Name, Args0), Result) :-
	(if Name = term_atom("free"), Args0 = [] then
		Result = free
	else
	if Name = term_atom("ground"), Args0 = [] then
		Result = ground
	else
	if some [Disj] (Name = term_atom("bound"), Args0 = [Disj]) then
		disjunction_to_list(Disj, List),
		convert_bound_inst_list(List, Functors),
		Result = bound(Functors)
	else
		convert_inst_list(Args0, Args),
		Result = user_defined_inst(Name, Args)
	).

:- pred convert_bound_inst_list(list(term), list(bound_inst)).
:- mode convert_bound_inst_list(input, output).
convert_bound_inst_list([], []).
convert_bound_inst_list([H0|T0], [H|T]) :-
	convert_bound_inst(H0, H),
	convert_bound_inst_list(T0, T).

:- pred convert_bound_inst(term, bound_inst).
:- mode convert_bound_inst(input, output).
convert_bound_inst(term_functor(Name, Args0), functor(Name, Args)) :-
	convert_inst_list(Args0, Args).

:- pred process_inst_defn(maybe(inst_defn), varset, condition, maybe(item)).
:- mode process_inst_defn(input, input, input, output).
process_inst_defn(error(Error, Term), _, _, error(Error, Term)).
process_inst_defn(ok(InstDefn), VarSet, Cond,
					ok(inst_defn(VarSet, InstDefn, Cond))).

%-----------------------------------------------------------------------------%

	% parse a `:- mode foo :: ...' or `:- mode foo = ...' definition.

:- pred parse_mode_decl(varset, term, maybe(item)).
:- mode parse_mode_decl(input, input, output).
parse_mode_decl(VarSet, ModeDefn, Result) :-
	(if some [H,B]
		mode_op(ModeDefn, H, B)
	then
		get_condition(B, Body, Condition),
		convert_mode_defn(H, Body, R),
		process_mode_defn(R, VarSet, Condition, Result)
	else
		parse_mode_decl_pred(VarSet, ModeDefn, Result)
	).

:- pred mode_op(term, term, term).
:- mode mode_op(input, input, output).
mode_op(term_functor(term_atom("::"),[H,B]), H, B).
mode_op(term_functor(term_atom("="),[H,B]), H, B).

:- pred convert_mode_defn(term, term, maybe(mode_defn)).
:- mode convert_mode_defn(input, input, output).
convert_mode_defn(Head, Body, Result) :-
	parse_qualified_term(Head, "mode definition", R),
	convert_mode_defn_2(R, Head, Body, Result).

:- pred convert_mode_defn_2(maybe_functor, term, term, maybe(mode_defn)).
:- mode convert_mode_defn_2(input, input, input, output).
convert_mode_defn_2(error(M,T), _, _, error(M,T)).
convert_mode_defn_2(ok(Name, Args), Head, Body, Result) :-
	% check that all the head args are variables
	(if	some [Arg] (
			member(Arg, Args),
			all [Var] Arg ~= term_variable(Var)
		)
	then
		Result = error("Mode parameters must be variables", Arg)
	else
	% check that all the head arg variables are distinct
	if	some [Arg2, OtherArgs] (
			member(Arg2, Args, Arg2.OtherArgs),
			member(Arg2, OtherArgs)
		)
	then
		Result = error("Repeated parameters in LHS of mode defn",
				Head)
	else
	% check that all the variables in the body occur in the head
	if	some [Var2] (
			term_contains_var(Body, Var2),
			not term_contains_var_list(Args, Var2)
		)
	then
		Result = error("Free inst parameter in RHS of mode definition",
				Var2)
	else
		% should improve the error message here

		(if some [ConvertedBody]
			convert_mode(Body, ConvertedBody)
		then
			Result = ok(mode_defn(Name, Args, ConvertedBody))
		else
			% XXX catch-all error message
			Result = error("syntax error in mode definition body",
					Body)
		)
	).

:- pred convert_type_and_mode_list(list(term), list(type_and_mode)).
:- mode convert_type_and_mode_list(input, output).
convert_type_and_mode_list([], []).
convert_type_and_mode_list([H0|T0], [H|T]) :-
	convert_type_and_mode(H0, H),
	convert_type_and_mode_list(T0, T).

:- pred convert_type_and_mode(term, type_and_mode).
:- mode convert_type_and_mode(input, output).
convert_type_and_mode(Term, Result) :-
	(if some [ModeTerm, TypeTerm]
		Term = term_functor(term_atom("::"), [ModeTerm, TypeTerm])
	then
		convert_type(TypeTerm, Type),
		convert_mode(ModeTerm, Mode),
		Result = type_and_mode(Type, Mode)
	else
		convert_type(Term, Type),
		Result = type_only(Type)
	).

:- pred convert_mode_list(list(term), list(mode)).
:- mode convert_mode_list(input, output).
convert_mode_list([], []).
convert_mode_list([H0|T0], [H|T]) :-
	convert_mode(H0, H),
	convert_mode_list(T0, T).

:- pred convert_mode(term, mode).
:- mode convert_mode(input, output).
convert_mode(Term, Mode) :-
	(if some [InstA, InstB]
		Term = term_functor(term_atom("->"), [InstA, InstB])
	then
		convert_inst(InstA, ConvertedInstA),
		convert_inst(InstB, ConvertedInstB),
		Mode = (ConvertedInstA -> ConvertedInstB)
	else
		parse_qualified_term(Term, "mode definition", R),
		R = ok(Name, Args),	% XXX should improve error reporting
		convert_inst_list(Args, ConvertedArgs),
		Mode = user_defined_mode(Name, ConvertedArgs)
	).

:- pred process_mode_defn(maybe(mode_defn), varset, condition, maybe(item)).
:- mode process_mode_defn(input, input, input, output).
process_mode_defn(error(Error, Term), _, _, error(Error, Term)).
process_mode_defn(ok(ModeDefn), VarSet, Cond,
					ok(mode_defn(VarSet, ModeDefn, Cond))).

%-----------------------------------------------------------------------------%

% parse {import,use,export}_module declarations

:- pred parse_import_module_decl(varset, term, maybe(item)).
:- mode parse_import_module_decl(input, input, output).
parse_import_module_decl(VarSet, ModuleSpec, Result) :-
	parse_module_spec_list(ModuleSpec, R),
	process_import(R, VarSet, Result).

:- pred parse_use_module_decl(varset, term, maybe(item)).
:- mode parse_use_module_decl(input, input, output).
parse_use_module_decl(VarSet, ModuleSpec, Result) :-
	parse_module_spec_list(ModuleSpec, R),
	process_use(R, VarSet, Result).

:- pred parse_export_module_decl(varset, term, maybe(item)).
:- mode parse_export_module_decl(input, input, output).
parse_export_module_decl(VarSet, ModuleSpec, Result) :-
	parse_module_spec_list(ModuleSpec, R),
	process_export(R, VarSet, Result).

% parse {import,use,export}_sym declarations

:- pred parse_export_sym_decl(varset, term, maybe(item)).
:- mode parse_export_sym_decl(input, input, output).
parse_export_sym_decl(VarSet, SymSpec, Result) :-
	parse_sym_spec_list(SymSpec, R),
	process_export(R, VarSet, Result).

:- pred parse_import_sym_decl(varset, term, maybe(item)).
:- mode parse_import_sym_decl(input, input, output).
parse_import_sym_decl(VarSet, SymSpec, Result) :-
	parse_sym_spec_list(SymSpec, R),
	process_import(R, VarSet, Result).

:- pred parse_use_sym_decl(varset, term, maybe(item)).
:- mode parse_use_sym_decl(input, input, output).
parse_use_sym_decl(VarSet, SymSpec, Result) :-
	parse_sym_spec_list(SymSpec, R),
	process_use(R, VarSet, Result).

% parse {import,use,export}_pred declarations

:- pred parse_import_pred_decl(varset, term, maybe(item)).
:- mode parse_import_pred_decl(input, input, output).
parse_import_pred_decl(VarSet, PredSpec, Result) :-
	parse_pred_spec_list(PredSpec, R),
	process_import(R, VarSet, Result).

:- pred parse_use_pred_decl(varset, term, maybe(item)).
:- mode parse_use_pred_decl(input, input, output).
parse_use_pred_decl(VarSet, PredSpec, Result) :-
	parse_pred_spec_list(PredSpec, R),
	process_use(R, VarSet, Result).

:- pred parse_export_pred_decl(varset, term, maybe(item)).
:- mode parse_export_pred_decl(input, input, output).
parse_export_pred_decl(VarSet, PredSpec, Result) :-
	parse_pred_spec_list(PredSpec, R),
	process_export(R, VarSet, Result).

% parse {import,use,export}_cons declarations

:- pred parse_import_cons_decl(varset, term, maybe(item)).
:- mode parse_import_cons_decl(input, input, output).
parse_import_cons_decl(VarSet, ConsSpec, Result) :-
	parse_cons_spec_list(ConsSpec, R),
	process_import(R, VarSet, Result).

:- pred parse_use_cons_decl(varset, term, maybe(item)).
:- mode parse_use_cons_decl(input, input, output).
parse_use_cons_decl(VarSet, ConsSpec, Result) :-
	parse_cons_spec_list(ConsSpec, R),
	process_use(R, VarSet, Result).

:- pred parse_export_cons_decl(varset, term, maybe(item)).
:- mode parse_export_cons_decl(input, input, output).
parse_export_cons_decl(VarSet, ConsSpec, Result) :-
	parse_cons_spec_list(ConsSpec, R),
	process_export(R, VarSet, Result).

% parse {import,use,export}_type declarations

:- pred parse_import_type_decl(varset, term, maybe(item)).
:- mode parse_import_type_decl(input, input, output).
parse_import_type_decl(VarSet, TypeSpec, Result) :-
	parse_type_spec_list(TypeSpec, R),
	process_import(R, VarSet, Result).

:- pred parse_use_type_decl(varset, term, maybe(item)).
:- mode parse_use_type_decl(input, input, output).
parse_use_type_decl(VarSet, TypeSpec, Result) :-
	parse_type_spec_list(TypeSpec, R),
	process_use(R, VarSet, Result).

:- pred parse_export_type_decl(varset, term, maybe(item)).
:- mode parse_export_type_decl(input, input, output).
parse_export_type_decl(VarSet, TypeSpec, Result) :-
	parse_type_spec_list(TypeSpec, R),
	process_export(R, VarSet, Result).

% parse {import,use,export}_adt declarations

:- pred parse_import_adt_decl(varset, term, maybe(item)).
:- mode parse_import_adt_decl(input, input, output).
parse_import_adt_decl(VarSet, ADT_Spec, Result) :-
	parse_adt_spec_list(ADT_Spec, R),
	process_import(R, VarSet, Result).

:- pred parse_use_adt_decl(varset, term, maybe(item)).
:- mode parse_use_adt_decl(input, input, output).
parse_use_adt_decl(VarSet, ADT_Spec, Result) :-
	parse_adt_spec_list(ADT_Spec, R),
	process_use(R, VarSet, Result).

:- pred parse_export_adt_decl(varset, term, maybe(item)).
:- mode parse_export_adt_decl(input, input, output).
parse_export_adt_decl(VarSet, ADT_Spec, Result) :-
	parse_adt_spec_list(ADT_Spec, R),
	process_export(R, VarSet, Result).

% parse {import,use,export}_op declarations

:- pred parse_import_op_decl(varset, term, maybe(item)).
:- mode parse_import_op_decl(input, input, output).
parse_import_op_decl(VarSet, OpSpec, Result) :-
	parse_op_spec_list(OpSpec, R),
	process_import(R, VarSet, Result).

:- pred parse_use_op_decl(varset, term, maybe(item)).
:- mode parse_use_op_decl(input, input, output).
parse_use_op_decl(VarSet, OpSpec, Result) :-
	parse_op_spec_list(OpSpec, R),
	process_use(R, VarSet, Result).

:- pred parse_export_op_decl(varset, term, maybe(item)).
:- mode parse_export_op_decl(input, input, output).
parse_export_op_decl(VarSet, OpSpec, Result) :-
	parse_op_spec_list(OpSpec, R),
	process_export(R, VarSet, Result).

%-----------------------------------------------------------------------------%

	% Parse a comma-separated list (misleading described as
	% a "conjunction") of module specifiers.

:- pred parse_module_spec_list(term, maybe(sym_list)).
:- mode parse_module_spec_list(input, output).
parse_module_spec_list(Term, Result) :-
	conjunction_to_list(Term, List),
	parse_module_spec_list_2(List, R),
	process_module_spec_list(R, Result).

:- pred parse_module_spec_list_2(list(term), maybe(list(module_specifier))).
:- mode parse_module_spec_list_2(input, output).
parse_module_spec_list_2([], ok([])).
parse_module_spec_list_2(X.Xs, Result) :-
	parse_module_specifier(X, X_Result),
	parse_module_spec_list_2(Xs, Xs_Result),
	combine_list_results(X_Result, Xs_Result, Result).

:- pred process_module_spec_list(maybe(list(module_specifier)),
				 maybe(sym_list)).
:- mode process_module_spec_list(input, output).
process_module_spec_list(ok(X), ok(module(X))).
process_module_spec_list(error(M, T), error(M, T)).

	% Parse a comma-separated list (misleading described as
	% a "conjunction") of symbol specifiers.

:- pred parse_sym_spec_list(term, maybe(sym_list)).
:- mode parse_sym_spec_list(input, output).
parse_sym_spec_list(Term, Result) :-
	conjunction_to_list(Term, List),
	parse_sym_spec_list_2(List, R),
	process_sym_spec_list(R, Result).

:- pred parse_sym_spec_list_2(list(term), maybe(list(sym_specifier))).
:- mode parse_sym_spec_list_2(input, output).
parse_sym_spec_list_2([], ok([])).
parse_sym_spec_list_2(X.Xs, Result) :-
	parse_symbol_specifier(X, X_Result),
	parse_sym_spec_list_2(Xs, Xs_Result),
	combine_list_results(X_Result, Xs_Result, Result).

:- pred process_sym_spec_list(maybe(list(sym_specifier)),
				 maybe(sym_list)).
:- mode process_sym_spec_list(input, output).
process_sym_spec_list(ok(X), ok(sym(X))).
process_sym_spec_list(error(M, T), error(M, T)).


	% Parse a comma-separated list (misleading described as
	% a "conjunction") of predicate specifiers.

:- pred parse_pred_spec_list(term, maybe(sym_list)).
:- mode parse_pred_spec_list(input, output).
parse_pred_spec_list(Term, Result) :-
	conjunction_to_list(Term, List),
	parse_pred_spec_list_2(List, R),
	process_pred_spec_list(R, Result).

:- pred parse_pred_spec_list_2(list(term), maybe(list(pred_specifier))).
:- mode parse_pred_spec_list_2(input, output).
parse_pred_spec_list_2([], ok([])).
parse_pred_spec_list_2(X.Xs, Result) :-
	parse_predicate_specifier(X, X_Result),
	parse_pred_spec_list_2(Xs, Xs_Result),
	combine_list_results(X_Result, Xs_Result, Result).

:- pred process_pred_spec_list(maybe(list(pred_specifier)),
				 maybe(sym_list)).
:- mode process_pred_spec_list(input, output).
process_pred_spec_list(ok(X), ok(pred(X))).
process_pred_spec_list(error(M, T), error(M, T)).


	% Parse a comma-separated list (misleading described as
	% a "conjunction") of constructor specifiers.

:- pred parse_cons_spec_list(term, maybe(sym_list)).
:- mode parse_cons_spec_list(input, output).
parse_cons_spec_list(Term, Result) :-
	conjunction_to_list(Term, List),
	parse_cons_spec_list_2(List, R),
	process_cons_spec_list(R, Result).

:- pred parse_cons_spec_list_2(list(term), maybe(list(cons_specifier))).
:- mode parse_cons_spec_list_2(input, output).
parse_cons_spec_list_2([], ok([])).
parse_cons_spec_list_2(X.Xs, Result) :-
	parse_constructor_specifier(X, X_Result),
	parse_cons_spec_list_2(Xs, Xs_Result),
	combine_list_results(X_Result, Xs_Result, Result).

:- pred process_cons_spec_list(maybe(list(cons_specifier)),
				 maybe(sym_list)).
:- mode process_cons_spec_list(input, output).
process_cons_spec_list(ok(X), ok(cons(X))).
process_cons_spec_list(error(M, T), error(M, T)).


	% Parse a comma-separated list (misleading described as
	% a "conjunction") of type specifiers.

:- pred parse_type_spec_list(term, maybe(sym_list)).
:- mode parse_type_spec_list(input, output).
parse_type_spec_list(Term, Result) :-
	conjunction_to_list(Term, List),
	parse_type_spec_list_2(List, R),
	process_type_spec_list(R, Result).

:- pred parse_type_spec_list_2(list(term), maybe(list(sym_name_specifier))).
:- mode parse_type_spec_list_2(input, output).
parse_type_spec_list_2([], ok([])).
parse_type_spec_list_2(X.Xs, Result) :-
	parse_type_specifier(X, X_Result),
	parse_type_spec_list_2(Xs, Xs_Result),
	combine_list_results(X_Result, Xs_Result, Result).

:- pred process_type_spec_list(maybe(list(sym_name_specifier)),
				 maybe(sym_list)).
:- mode process_type_spec_list(input, output).
process_type_spec_list(ok(X), ok(type(X))).
process_type_spec_list(error(M, T), error(M, T)).


	% Parse a comma-separated list (misleading described as
	% a "conjunction") of adt specifiers.

:- pred parse_adt_spec_list(term, maybe(sym_list)).
:- mode parse_adt_spec_list(input, output).
parse_adt_spec_list(Term, Result) :-
	conjunction_to_list(Term, List),
	parse_adt_spec_list_2(List, R),
	process_adt_spec_list(R, Result).

:- pred parse_adt_spec_list_2(list(term), maybe(list(sym_name_specifier))).
:- mode parse_adt_spec_list_2(input, output).
parse_adt_spec_list_2([], ok([])).
parse_adt_spec_list_2(X.Xs, Result) :-
	parse_adt_specifier(X, X_Result),
	parse_adt_spec_list_2(Xs, Xs_Result),
	combine_list_results(X_Result, Xs_Result, Result).

:- pred process_adt_spec_list(maybe(list(sym_name_specifier)),
				 maybe(sym_list)).
:- mode process_adt_spec_list(input, output).
process_adt_spec_list(ok(X), ok(adt(X))).
process_adt_spec_list(error(M, T), error(M, T)).


	% Parse a comma-separated list (misleading described as
	% a "conjunction") of operator specifiers.

:- pred parse_op_spec_list(term, maybe(sym_list)).
:- mode parse_op_spec_list(input, output).
parse_op_spec_list(Term, Result) :-
	conjunction_to_list(Term, List),
	parse_op_spec_list_2(List, R),
	process_op_spec_list(R, Result).

:- pred parse_op_spec_list_2(list(term), maybe(list(sym_name_specifier))).
:- mode parse_op_spec_list_2(input, output).
parse_op_spec_list_2([], ok([])).
parse_op_spec_list_2(X.Xs, Result) :-
	parse_op_specifier(X, X_Result),
	parse_op_spec_list_2(Xs, Xs_Result),
	combine_list_results(X_Result, Xs_Result, Result).

:- pred process_op_spec_list(maybe(list(op_specifier)),
				 maybe(sym_list)).
:- mode process_op_spec_list(input, output).
process_op_spec_list(ok(X), ok(op(X))).
process_op_spec_list(error(M, T), error(M, T)).

%-----------------------------------------------------------------------------%

	% If a list of things contains multiple errors, then we only
	% report the first one.

:- pred combine_list_results(maybe(T), maybe(list(T)), maybe(list(T))).
:- mode combine_list_results(input, input, output).
combine_list_results(error(Msg, Term), _, error(Msg, Term)).
combine_list_results(ok(_), error(Msg, Term), error(Msg, Term)).
combine_list_results(ok(X), ok(Xs), ok([X|Xs])).

%-----------------------------------------------------------------------------%
%
%	A symbol specifier is one of
%
%		SymbolNameSpecifier
%			Matches any symbol matched by the SymbolNameSpecifier.
%		TypedConstructorSpecifier
%			Matches any constructors matched by the
%			TypedConstructorSpecifier.
%		cons(ConstructorSpecifier)
%			Matches only constructors.
%		pred(PredSpecifier)
%			Matches only predicates, ie. constructors of type
%			`pred'.
%		adt(SymbolNameSpecifier)
%			Matches only type names.
%		type(SymbolNameSpecifier)
%			Matches type names matched by the SymbolNameSpecifier,
%			and also matches any constructors for the matched type
%			names.
%		op(SymbolNameSpecifier)
%			Matches only operators.
%		module(ModuleSpecifier)
%			Matches all symbols in the specified module.

:- pred parse_symbol_specifier(term, maybe(sym_specifier)).
parse_symbol_specifier(Term, Result) :-
	(if some [ConsSpecTerm]
	    Term = term_functor(term_atom("cons"), [ConsSpecTerm])
	then
	    parse_constructor_specifier(ConsSpecTerm, ConsSpecResult),
	    process_cons_symbol_specifier(ConsSpecResult, Result)
	else if some [PredSpecTerm]
	    Term = term_functor(term_atom("pred"), [PredSpecTerm])
	then
	    parse_predicate_specifier(PredSpecTerm, PredSpecResult),
	    process_pred_symbol_specifier(PredSpecResult, Result)
	else if some [TypeSpecTerm]
	    Term = term_functor(term_atom("type"), [TypeSpecTerm])
	then
	    parse_type_specifier(TypeSpecTerm, TypeSpecResult),
	    process_type_symbol_specifier(TypeSpecResult, Result)
	else if some [AdtSpecTerm]
	    Term = term_functor(term_atom("adt"), [AdtSpecTerm])
	then
	    parse_adt_specifier(AdtSpecTerm, AdtSpecResult),
	    process_adt_symbol_specifier(AdtSpecResult, Result)
	else if some [OpSpecTerm]
	    Term = term_functor(term_atom("op"), [OpSpecTerm])
	then
	    parse_op_specifier(OpSpecTerm, OpSpecResult),
	    process_op_symbol_specifier(OpSpecResult, Result)
	else if some [ModuleSpecTerm]
	    Term = term_functor(term_atom("module"), [ModuleSpecTerm])
	then
	    parse_module_specifier(ModuleSpecTerm, ModuleSpecResult),
	    process_module_symbol_specifier(ModuleSpecResult, Result)
	else
	    parse_constructor_specifier(Term, TermResult),
	    process_any_symbol_specifier(TermResult, Result)
	).

% 	Once we've parsed the appropriate type of symbol specifier, we
%	need to convert it to a sym_specifier, propagating errors upwards.

:- pred process_module_symbol_specifier(maybe(module_specifier),
					maybe(sym_specifier)).
:- mode process_module_symbol_specifier(input, output).
process_module_symbol_specifier(ok(OpSpec), ok(module(OpSpec))).
process_module_symbol_specifier(error(Msg, Term), error(Msg, Term)).

:- pred process_any_symbol_specifier(maybe(cons_specifier),
				     maybe(sym_specifier)).
:- mode process_any_symbol_specifier(input, output).
process_any_symbol_specifier(error(Msg, Term), error(Msg, Term)).
process_any_symbol_specifier(ok(sym(SymSpec)), ok(sym(SymSpec))).
process_any_symbol_specifier(ok(typed(ConsSpec)), ok(typed_sym(ConsSpec))).

:- pred process_pred_symbol_specifier(maybe(pred_specifier),
					maybe(sym_specifier)).
:- mode process_pred_symbol_specifier(input, output).
process_pred_symbol_specifier(error(Msg, Term), error(Msg, Term)).
process_pred_symbol_specifier(ok(PredSpec), ok(pred(PredSpec))).

:- pred process_cons_symbol_specifier(maybe(cons_specifier),
					maybe(sym_specifier)).
:- mode process_cons_symbol_specifier(input, output).
process_cons_symbol_specifier(error(Msg, Term), error(Msg, Term)).
process_cons_symbol_specifier(ok(ConsSpec), ok(cons(ConsSpec))).

:- pred process_type_symbol_specifier(maybe(sym_name_specifier),
					maybe(sym_specifier)).
:- mode process_type_symbol_specifier(input, output).
process_type_symbol_specifier(ok(SymSpec), ok(type(SymSpec))).
process_type_symbol_specifier(error(Msg, Term), error(Msg, Term)).

:- pred process_adt_symbol_specifier(maybe(sym_name_specifier),
					maybe(sym_specifier)).
:- mode process_adt_symbol_specifier(input, output).
process_adt_symbol_specifier(ok(SymSpec), ok(adt(SymSpec))).
process_adt_symbol_specifier(error(Msg, Term), error(Msg, Term)).

:- pred process_op_symbol_specifier(maybe(op_specifier),
					maybe(sym_specifier)).
:- mode process_op_symbol_specifier(input, output).
process_op_symbol_specifier(ok(OpSpec), ok(op(OpSpec))).
process_op_symbol_specifier(error(Msg, Term), error(Msg, Term)).

%-----------------------------------------------------------------------------%

%	A ModuleSpecifier is just an identifier.

:- pred parse_module_specifier(term, maybe(module_specifier)).
:- mode parse_module_specifier(input, output).
parse_module_specifier(Term, Result) :-
	(if some [ModuleName]
		Term = term_functor(term_atom(ModuleName), [])
	then
		Result = ok(ModuleName)
	else
		Result = error("module specifier should be an identifier", Term)
	).

%-----------------------------------------------------------------------------%

%	A ConstructorSpecifier is one of
%		SymbolNameSpecifier
%		TypedConstructorSpecifier
%
%	A TypedConstructorSpecifier is one of
%		SymbolNameSpecifier::Type
%			Matches only constructors with the specified result
%			type.
%		SymbolName(ArgType1, ..., ArgTypeN)
%			Matches only constructors with the specified argument
%			types.
%		SymbolName(ArgType1, ..., ArgTypeN)::Type
%			Matches only constructors with the specified argument
%			and result types.

:- pred parse_constructor_specifier(term, maybe(cons_specifier)).
:- mode parse_constructor_specifier(input, output).
parse_constructor_specifier(Term, Result) :-
    (if some [NameArgsTerm, TypeTerm]
	Term = term_functor(term_atom("::"), [NameArgsTerm, TypeTerm])
    then
	parse_arg_types_specifier(NameArgsTerm, NameArgsResult),
	parse_type(TypeTerm, TypeResult),
	process_typed_constructor_specifier(NameArgsResult, TypeResult, Result)
    else
	parse_arg_types_specifier(Term, TermResult),
	process_untyped_constructor_specifier(TermResult, Result)
    ).

%-----------------------------------------------------------------------------%

%	A PredicateSpecifier is one of
%		SymbolName(ArgType1, ..., ArgTypeN)
%			Matches only predicates with the specified argument
%			types.
%		SymbolNameSpecifier

:- pred parse_predicate_specifier(term, maybe(pred_specifier)).
:- mode parse_predicate_specifier(input, output).
parse_predicate_specifier(Term, Result) :-
    (if some [X, Y] Term = term_functor(term_atom("/"), [X,Y]) then
	parse_symbol_name_specifier(Term, TermResult),
        process_arity_predicate_specifier(TermResult, Result)
    else
	parse_qualified_term(Term, "predicate specifier", TermResult),
	process_typed_predicate_specifier(TermResult, Result)
    ).

:- pred process_typed_predicate_specifier(maybe_functor, maybe(pred_specifier)).
:- mode process_typed_predicate_specifier(input, output).
process_typed_predicate_specifier(ok(Name, Args), ok(Result)) :-
    (if Args = [] then
	Result = sym(name(Name))
    else
	Result = name_args(Name, Args)
    ).
process_typed_predicate_specifier(error(Msg, Term), error(Msg, Term)).

:- pred process_arity_predicate_specifier(maybe(sym_name_specifier),
		maybe(pred_specifier)).
:- mode process_arity_predicate_specifier(input, output).
process_arity_predicate_specifier(ok(Result), ok(sym(Result))).
process_arity_predicate_specifier(error(Msg, Term), error(Msg, Term)).

%-----------------------------------------------------------------------------%

% 	Parsing the name & argument types of a constructor specifier is
% 	exactly the same as parsing a predicate specifier...

:- pred parse_arg_types_specifier(term, maybe(pred_specifier)).
:- mode parse_arg_types_specifier(input, output).
parse_arg_types_specifier(Term, Result) :-
    (if some [X, Y] Term = term_functor(term_atom("/"), [X,Y]) then
	parse_symbol_name_specifier(Term, TermResult),
        process_arity_predicate_specifier(TermResult, Result)
    else
	parse_qualified_term(Term, "constructor specifier", TermResult),
	process_typed_predicate_specifier(TermResult, Result)
    ).

% 	... but we have to convert the result back into the appropriate
% 	format.

:- pred process_typed_constructor_specifier(maybe(pred_specifier), maybe(type),
		maybe(cons_specifier)).
:- mode process_typed_constructor_specifier(input, input, output).
process_typed_constructor_specifier(error(Msg, Term), _, error(Msg, Term)).
process_typed_constructor_specifier(_, error(Msg, Term), error(Msg, Term)).
process_typed_constructor_specifier(ok(NameArgs), ok(ResType), ok(Result)) :-
	process_typed_cons_spec_2(NameArgs, ResType, Result).

:- pred process_typed_cons_spec_2(pred_specifier, type, cons_specifier).
:- mode process_typed_cons_spec_2(input, input, output).
process_typed_cons_spec_2(sym(Name), Res, typed(name_res(Name, Res))).
process_typed_cons_spec_2(name_args(Name, Args), Res,
			  typed(name_args_res(Name, Args, Res))).

:- pred process_untyped_constructor_specifier(maybe(pred_specifier),
		maybe(cons_specifier)).
:- mode process_untyped_constructor_specifier(input, output).
process_untyped_constructor_specifier(error(Msg, Term), error(Msg, Term)).
process_untyped_constructor_specifier(ok(NameArgs), ok(Result)) :-
	process_untyped_cons_spec_2(NameArgs, Result).

:- pred process_untyped_cons_spec_2(pred_specifier, cons_specifier).
:- mode process_untyped_cons_spec_2(input, output).
process_untyped_cons_spec_2(sym(Name), sym(Name)).
process_untyped_cons_spec_2(name_args(Name, Args),
			    typed(name_args(Name, Args))).

%-----------------------------------------------------------------------------%

%	A SymbolNameSpecifier is one of
%		SymbolName
%		SymbolName/Arity
%			Matches only symbols of the specified arity.
%	

:- pred parse_symbol_name_specifier(term, maybe(sym_name_specifier)).
:- mode parse_symbol_name_specifier(input, output).
parse_symbol_name_specifier(Term, Result) :-
    (if some [NameTerm, ArityTerm]
       	Term = term_functor(term_atom("/"), [NameTerm, ArityTerm])
    then
        (if some [Arity]
            ArityTerm = term_functor(term_integer(Arity),[])
	then
            (if Arity >= 0 then
		parse_symbol_name(NameTerm, NameResult),
		process_name_arity_specifier(NameResult, Arity, Result)
	    else
		Result = error("Arity in symbol name specifier must be a non-negative integer", Term)
	    )
        else
	    Result = error("Arity in symbol name specifier must be an integer", Term)
        )
    else
	parse_symbol_name(Term, SymbolNameResult),
	process_name_specifier(SymbolNameResult, Result)
    ).

:- pred process_name_arity_specifier(maybe(sym_name), int,
		maybe(sym_name_specifier)).
:- mode process_name_arity_specifier(input, input, output).
process_name_arity_specifier(ok(Name), Arity, ok(name_arity(Name, Arity))).
process_name_arity_specifier(error(Error, Term), _, error(Error, Term)).

:- pred process_name_specifier(maybe(sym_name), maybe(sym_name_specifier)).
:- mode process_name_specifier(input, output).
process_name_specifier(ok(Name), ok(name(Name))).
process_name_specifier(error(Error, Term), error(Error, Term)).

%-----------------------------------------------------------------------------%

%	A QualifiedTerm is one of
%		Name(Args)
%		Module:Name(Args)
%	(or if Args is empty, one of
%		Name
%		Module:Name)

:- pred parse_qualified_term(term, string, maybe_functor).
:- mode parse_qualified_term(input, input, output).
parse_qualified_term(Term, Msg, Result) :-
    (if some [ModuleTerm, NameArgsTerm]
       	Term = term_functor(term_atom(":"), [ModuleTerm, NameArgsTerm])
    then
        (if some [Name, Args]
            NameArgsTerm = term_functor(term_atom(Name),Args)
        then
            (if some [Module]
                ModuleTerm = term_functor(term_atom(Module),[])
	    then
		Result = ok(qualified(Module, Name), Args)
	    else
		Result = error("module name identifier expected before ':' in qualified symbol name", Term)
            )
        else
            Result = error("identifier expected after ':' in qualified symbol name", Term)
	)
    else
        (if some [Name2, Args2]
            Term = term_functor(term_atom(Name2), Args2)
        then
            Result = ok(unqualified(Name2), Args2)
        else
	    string__append("atom expected in ", Msg, ErrorMsg),
            Result = error(ErrorMsg, Term)
        )
    ).

%-----------------------------------------------------------------------------%

%	A SymbolName is one of
%		Name
%			Matches symbols with the specified name in the
%			current namespace.
%		Module:Name
%			Matches symbols with the specified name exported
%			by the specified module.

:- pred parse_symbol_name(term, maybe(sym_name)).
:- mode parse_symbol_name(input, output).
parse_symbol_name(Term, Result) :-
    (if some [ModuleTerm, NameTerm]
       	Term = term_functor(term_atom(":"), [ModuleTerm, NameTerm])
    then
        (if some [Name]
            NameTerm = term_functor(term_atom(Name),[])
        then
            (if some [Module]
                ModuleTerm = term_functor(term_atom(Module),[])
	    then
		Result = ok(qualified(Module, Name))
	    else
		Result = error("module name identifier expected before ':' in qualified symbol name", Term)
            )
        else
            Result = error("identifier expected after ':' in qualified symbol name", Term)
	)
    else
        (if some [Name2]
            Term = term_functor(term_atom(Name2),[])
        then
            Result = ok(unqualified(Name2))
        else
            Result = error("symbol name specifier expected", Term)
        )
    ).

%-----------------------------------------------------------------------------%

% convert a module definition to a program item,
% propagating errors upwards

:- pred process_import(maybe(module_defn), varset, maybe(item)).
:- mode process_import(input, input, output).
process_import(ok(X), VarSet, ok(module_defn(VarSet, import(X)))).
process_import(error(Msg, Term), _, error(Msg, Term)).

:- pred process_use(maybe(module_defn), varset, maybe(item)).
:- mode process_use(input, input, output).
process_use(ok(X), VarSet, ok(module_defn(VarSet, use(X)))).
process_use(error(Msg, Term), _, error(Msg, Term)).

:- pred process_export(maybe(module_defn), varset, maybe(item)).
:- mode process_export(input, input, output).
process_export(ok(X), VarSet, ok(module_defn(VarSet, export(X)))).
process_export(error(Msg, Term), _, error(Msg, Term)).

%-----------------------------------------------------------------------------%

%	A TypeSpecifier is just a symbol name specifier.

:- pred parse_type_specifier(term, maybe(sym_name_specifier)).
:- mode parse_type_specifier(input, output).
parse_type_specifier(Term, Result) :-
	parse_symbol_name_specifier(Term, Result).

%	An ADT_Specifier is just a symbol name specifier.

:- pred parse_adt_specifier(term, maybe(sym_name_specifier)).
:- mode parse_adt_specifier(input, output).
parse_adt_specifier(Term, Result) :-
	parse_symbol_name_specifier(Term, Result).

%-----------------------------------------------------------------------------%

%	For the moment, an OpSpecifier is just a symbol name specifier.
% 	XXX We should allow specifying the fixity of an operator

:- pred parse_op_specifier(term, maybe(op_specifier)).
:- mode parse_op_specifier(input, output).
parse_op_specifier(Term, Result) :-
	parse_symbol_name_specifier(Term, R),
	process_op_specifier(R, Result).

:- pred process_op_specifier(maybe(sym_name_specifier), maybe(op_specifier)).
:- mode process_op_specifier(input, output).
process_op_specifier(ok(X), ok(sym(X))).
process_op_specifier(error(M,T), error(M,T)).
	
%-----------------------------------------------------------------------------%

	% types are represented just as ordinary terms

:- pred parse_type(term, maybe(type)).
:- mode parse_type(input, output).
parse_type(T, ok(T)).

:- pred convert_type(term, type).
:- mode convert_type(input, output).
convert_type(T, T).

%-----------------------------------------------------------------------------%
