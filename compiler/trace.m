%-----------------------------------------------------------------------------%
% Copyright (C) 1997-2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% Author: zs.
%
% This module handles the generation of traces for the trace analysis system.
%
% For the general basis of trace analysis systems, see the paper
% "Opium: An extendable trace analyser for Prolog" by Mireille Ducasse,
% available from http://www.irisa.fr/lande/ducasse.
%
% We reserve some slots in the stack frame of the traced procedure.
% One contains the call sequence number, which is set in the procedure prologue
% by incrementing a global counter. An other contains the call depth, which
% is also set by incrementing a global variable containing the depth of the
% caller. The caller sets this global variable from its own saved depth
% just before the call.  We also save the event number, and sometimes also
% the redo layout and the from_full flag.
%
% Each event has a label associated with it. The stack layout for that label
% records what variables are live and where they are at the time of the event.
% These labels are generated by the same predicate that generates the code
% for the event, and are initially not used for anything else.
% However, some of these labels may be fallen into from other places,
% and thus optimization may redirect references from labels to one of these
% labels. This cannot happen in the opposite direction, due to the reference
% to each event's label from the event's pragma C code instruction.
% (This prevents labelopt from removing the label.)
%
% We classify events into three kinds: external events (call, exit, fail),
% internal events (switch, disj, ite_then, ite_else), and nondet pragma C
% events (first, later). Code_gen.m, which calls this module to generate
% all external events, checks whether tracing is required before calling us;
% the predicates handing internal and nondet pragma C events must check this
% themselves. The predicates generating internal events need the goal
% following the event as a parameter. For the first and later arms of
% nondet pragma C code, there is no such hlds_goal, which is why these events
% need a bit of special treatment.

%-----------------------------------------------------------------------------%

:- module trace.

:- interface.

:- import_module hlds_goal, hlds_pred, hlds_module.
:- import_module globals, prog_data, llds, code_info.
:- import_module map, std_util, set.

	% The kinds of external ports for which the code we generate will
	% call MR_trace. The redo port is not on this list, because for that
	% port the code that calls MR_trace is not in compiler-generated code,
	% but in the runtime system.  Likewise for the exception port.
	% (The same comment applies to the type `trace_port' in llds.m.)
:- type external_trace_port
	--->	call
	;	exit
	;	fail.

	% These ports are different from other internal ports (even neg_enter)
	% because their goal path identifies not the goal we are about to enter
	% but the goal we have just left.
:- type negation_end_port
	--->	neg_success
	;	neg_failure.

:- type nondet_pragma_trace_port
	--->	nondet_pragma_first
	;	nondet_pragma_later.

:- type trace_info.

:- type trace_slot_info
	--->	trace_slot_info(
			maybe(int),	% If the procedure is shallow traced,
					% this will be yes(N), where stack
					% slot N is the slot that holds the
					% value of the from-full flag at call.
					% Otherwise, it will be no.

			maybe(int),	% If --trace-decl is set, this will
					% be yes(M), where stack slots M
					% and M+1 are reserved for the runtime
					% system to use in building proof
					% trees for the declarative debugger.
					% Otherwise, it will be no.

			maybe(int)	% If --use-trail is set, this will
					% be yes(M), where stack slots M
					% and M+1 are the slots that hold the
					% saved values of the trail pointer
					% and the ticket counter respectively
					% at the time of the call. Otherwise,
					% it will be no.
		).

	% Return the set of input variables whose values should be preserved
	% until the exit and fail ports. This will be all the input variables,
	% except those that can be totally clobbered during the evaluation
	% of the procedure (those partially clobbered may still be of interest,
	% although to handle them properly we need to record insts in stack
	% layouts).
:- pred trace__fail_vars(module_info::in, proc_info::in,
		set(prog_var)::out) is det.

	% Return the number of slots reserved for tracing information.
	% If there are N slots, the reserved slots will be 1 through N.
:- pred trace__reserved_slots(proc_info::in, globals::in, int::out) is det.

	% Construct and return an abstract struct that represents the
	% tracing-specific part of the code generator state. Return also
	% info about the non-fixed slots used by the tracing system,
	% for eventual use in the constructing the procedure's layout
	% structure.
:- pred trace__setup(globals::in, trace_slot_info::out, trace_info::out,
	code_info::in, code_info::out) is det.

	% Generate code to fill in the reserved stack slots.
:- pred trace__generate_slot_fill_code(trace_info::in, code_tree::out,
	code_info::in, code_info::out) is det.

	% If we are doing execution tracing, generate code to prepare for
	% a call.
:- pred trace__prepare_for_call(code_tree::out, code_info::in, code_info::out)
	is det.

	% If we are doing execution tracing, generate code for an internal
	% trace event. This predicate must be called just before generating
	% code for the given goal.
:- pred trace__maybe_generate_internal_event_code(hlds_goal::in,
	code_tree::out, code_info::in, code_info::out) is det.

	% If we are doing execution tracing, generate code for an trace event
	% that represents leaving a negated goal (via success or failure).
:- pred trace__maybe_generate_negated_event_code(hlds_goal::in,
	negation_end_port::in, code_tree::out, code_info::in, code_info::out)
	is det.

	% If we are doing execution tracing, generate code for a nondet
	% pragma C code trace event.
:- pred trace__maybe_generate_pragma_event_code(nondet_pragma_trace_port::in,
	prog_context::in, code_tree::out, code_info::in, code_info::out)
	is det.

	% Generate code for an external trace event.
	% Besides the trace code, we return the label on which we have hung
	% the trace liveness information and data on the type variables in the
	% liveness information, since some of our callers also need this
	% information.
:- pred trace__generate_external_event_code(external_trace_port::in,
	trace_info::in, prog_context::in, label::out,
	map(tvar, set(layout_locn))::out, code_tree::out,
	code_info::in, code_info::out) is det.

	% If the trace level calls for redo events, generate code that pushes
	% a temporary nondet stack frame whose redoip slot contains the
	% address of one of the labels in the runtime that calls MR_trace
	% for a redo event. Otherwise, generate empty code.
:- pred trace__maybe_setup_redo_event(trace_info::in, code_tree::out) is det.

:- pred trace__path_to_string(goal_path::in, string::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module continuation_info, type_util, llds_out, tree, hlds_data.
:- import_module (inst), instmap, inst_table, inst_match, mode_util, options.
:- import_module list, bool, int, string, map, std_util, require, term, varset.

	% Information specific to a trace port.
:- type trace_port_info
	--->	external
	;	internal(
			goal_path,	% The path of the goal whose start
					% this port represents.
			set(prog_var)	% The pre-death set of this goal.
		)
	;	negation_end(
			goal_path	% The path of the goal whose end
					% (one way or another) this port
					% represents.
		)
	;	nondet_pragma.

:- type trace_type
	--->	deep_trace
	;	shallow_trace(lval).	% This holds the saved value of a bool
					% that is true iff we were called from
					% code with full tracing.

trace__fail_vars(ModuleInfo, ProcInfo, FailVars) :-
	proc_info_headvars(ProcInfo, HeadVars),
	proc_info_argmodes(ProcInfo, argument_modes(ArgInstTable, Modes)),
	proc_info_arg_info(ProcInfo, ArgInfos),
	proc_info_get_initial_instmap(ProcInfo, ModuleInfo, InstMap),
	mode_list_get_final_insts(Modes, ModuleInfo, Insts),
	(
		trace__build_fail_vars(HeadVars, Insts, ArgInfos,
			InstMap, ArgInstTable, ModuleInfo, FailVarsList)
	->
		set__list_to_set(FailVarsList, FailVars)
	;
		error("length mismatch in trace__fail_vars")
	).

	% trace__reserved_slots and trace__setup cooperate in the allocation
	% of stack slots for tracing purposes. The allocation is done in five
	% stages.
	%
	% stage 1:	Allocate the fixed slots, slots 1, 2 and 3, to hold
	%		the event number of call, the call sequence number
	%		and the call depth respectively.
	%
	% stage 2:	If the procedure is model_non and --trace-redo is set,
	%		allocate the next available slot (which must be slot 4)
	%		to hold the address of the redo layout structure.
	%
	% stage 3:	If the procedure is shallow traced, allocate the
	%		next available slot to the saved copy of the
	%		from-full flag. The number of this slot is recorded
	%		in the maybe_from_full field in the proc layout;
	%		if there is no such slot, that field will contain -1.
	%
	% stage 4:	If --trace-decl is given, allocate the next two
	%		available slots to hold the pointers to the proof tree
	%		node of the parent and of this call respectively.
	%		The number of the first of these two slots is recorded
	%		in the maybe_decl_debug field in the proc layout;
	%		if there are no such slots, that field will contain -1.
	%
	% stage 5:	If --use-trail is set (given or implied), allocate
	%		two slots to hold the saved value of the trail pointer
	%		and the ticket counter at the point of the call, for
	%		use in implementing retry. The number of the first of
	%		these two slots is recorded in the maybe_trail field
	%		in the proc layout; if there are no such slots, that
	%		field will contain -1.
	%
	% The runtime system cannot know whether the stack frame has a slot
	% that holds the saved from-full flag and whether it has the slots
	% for the proof tree. This is why trace__setup returns TraceSlotInfo,
	% which answers these questions, for later inclusion in the
	% procedure's layout structure.
	%
	% The procedure's layout structure does not need to include
	% information about the presence or absence of the slot holding
	% the address of the redo layout structure. If we generate redo
	% trace events, the runtime will know that this slot exists and
	% what its number must be; if we do not, the runtime will never
	% refer to such a slot.
	%
	% We need two redo labels in the runtime. Deep traced procedures
	% do not have a from-full slot, but their slots 1 through 4 are always
	% valid; the label handling their redos accesses those slots directly.
	% Shallow traced procedures do have a from-full slot, and their slots
	% 1-4 are valid only if the from-full slot is TRUE; the label handling
	% their redos thus checks this slot to see whether it can (or should)
	% access the other slots. In shallow-traced model_non procedures
	% that generate redo events, the from-full flag is always in slot 5.

trace__reserved_slots(ProcInfo, Globals, ReservedSlots) :-
	globals__get_trace_level(Globals, TraceLevel),
	(
		TraceLevel = none
	->
		ReservedSlots = 0
	;
		Fixed = 3, % event#, call#, call depth
		(
			globals__lookup_bool_option(Globals, trace_redo, yes),
			proc_info_interface_code_model(ProcInfo, model_non)
		->
			RedoLayout = 1
		;
			RedoLayout = 0
		),
		( TraceLevel = deep ->
			FromFull = 0
		;
			FromFull = 1
		),
		globals__lookup_bool_option(Globals, trace_decl, TraceDecl),
		( TraceDecl = yes ->
			DeclDebug = 2
		;
			DeclDebug = 0
		),
		globals__lookup_bool_option(Globals, use_trail, UseTrail),
		( UseTrail = yes ->
			Trail = 2
		;
			Trail = 0
		),
		ReservedSlots is Fixed + RedoLayout + FromFull + DeclDebug +
			Trail
	).

trace__setup(Globals, TraceSlotInfo, TraceInfo) -->
	code_info__get_proc_model(CodeModel),
	{ globals__lookup_bool_option(Globals, trace_decl, TraceDecl) },
	{ globals__lookup_bool_option(Globals, trace_redo, TraceRedo) },
	(
		{ TraceRedo = yes },
		{ CodeModel = model_non }
	->
		code_info__get_next_label(RedoLayoutLabel),
		{ MaybeRedoLayout = yes(RedoLayoutLabel) },
		{ NextSlotAfterRedoLayout = 5 }
	;
		{ MaybeRedoLayout = no },
		{ NextSlotAfterRedoLayout = 4 }
	),
	{ globals__get_trace_level(Globals, deep) ->
		TraceType = deep_trace,
		MaybeFromFullSlot = no,
		NextSlotAfterFromFull = NextSlotAfterRedoLayout,
		globals__lookup_bool_option(Globals, trace_internal,
			TraceInternal)
	;
		% Trace level must be shallow.
		MaybeFromFullSlot = yes(NextSlotAfterRedoLayout),
		( CodeModel = model_non ->
			CallFromFullSlot = framevar(NextSlotAfterRedoLayout)
		;
			CallFromFullSlot = stackvar(NextSlotAfterRedoLayout)
		),
		TraceType = shallow_trace(CallFromFullSlot),
		NextSlotAfterFromFull is NextSlotAfterRedoLayout + 1,
		% Shallow traced procs never generate internal events.
		TraceInternal = no
	},
	{ globals__lookup_bool_option(Globals, trace_decl, yes) ->
		MaybeDeclSlots = yes(NextSlotAfterFromFull),
		NextSlotAfterDecl = NextSlotAfterFromFull + 2
	;
		MaybeDeclSlots = no,
		NextSlotAfterDecl = NextSlotAfterFromFull
	},
	{ globals__lookup_bool_option(Globals, use_trail, yes) ->
		MaybeTrailSlot = yes(NextSlotAfterDecl),
		( CodeModel = model_non ->
			TrailLval =  framevar(NextSlotAfterDecl),
			TicketLval = framevar(NextSlotAfterDecl+1)
		;
			TrailLval =  stackvar(NextSlotAfterDecl),
			TicketLval = stackvar(NextSlotAfterDecl+1)
		),
		MaybeTrailLvals = yes(TrailLval - TicketLval)
	;
		MaybeTrailSlot = no,
		MaybeTrailLvals = no
	},
	{ TraceSlotInfo = trace_slot_info(MaybeFromFullSlot,
		MaybeDeclSlots, MaybeTrailSlot) },
	{ init_trace_info(TraceType, TraceInternal, TraceDecl, MaybeTrailLvals,
		MaybeRedoLayout, TraceInfo) }.

trace__generate_slot_fill_code(TraceInfo, TraceCode) -->
	code_info__get_proc_model(CodeModel),
	{
	trace_info_get_trace_type(TraceInfo, TraceType),
	trace_info_get_maybe_redo_layout_slot(TraceInfo, MaybeRedoLayoutSlot),
	trace_info_get_maybe_trail_slots(TraceInfo, MaybeTrailLvals),
	trace__event_num_slot(CodeModel, EventNumLval),
	trace__call_num_slot(CodeModel, CallNumLval),
	trace__call_depth_slot(CodeModel, CallDepthLval),
	trace__stackref_to_string(EventNumLval, EventNumStr),
	trace__stackref_to_string(CallNumLval, CallNumStr),
	trace__stackref_to_string(CallDepthLval, CallDepthStr),
	string__append_list([
		"\t\t", EventNumStr, " = MR_trace_event_number;\n",
		"\t\t", CallNumStr, " = MR_trace_incr_seq();\n",
		"\t\t", CallDepthStr, " = MR_trace_incr_depth();"
	], FillThreeSlots),
	( MaybeRedoLayoutSlot = yes(RedoLayoutLabel) ->
		trace__redo_layout_slot(CodeModel, RedoLayoutLval),
		trace__stackref_to_string(RedoLayoutLval, RedoLayoutStr),
		llds_out__make_stack_layout_name(RedoLayoutLabel,
			LayoutAddrStr),
		string__append_list([
			FillThreeSlots, "\n",
			"\t\t", RedoLayoutStr, " = (Word) (const Word *) &",
			LayoutAddrStr, ";"
		], FillFourSlots)
	;
		FillFourSlots = FillThreeSlots
	),
	(
		% This could be done by generating proper LLDS instead of C.
		% However, in shallow traced code we want to execute this
		% only when the caller is deep traced, and everything inside
		% that test must be in C code.
		MaybeTrailLvals = yes(TrailLval - TicketLval),
		trace__stackref_to_string(TrailLval, TrailLvalStr),
		trace__stackref_to_string(TicketLval, TicketLvalStr),
		string__append_list([
			FillFourSlots, "\n",
			"\t\tMR_mark_ticket_stack(", TicketLvalStr, ");\n",
			"\t\tMR_store_ticket(", TrailLvalStr, ");"
		], FillAllSlots)
	;
		MaybeTrailLvals = no,
		FillAllSlots = FillFourSlots
	),
	(
		TraceType = shallow_trace(CallFromFullSlot),
		trace__stackref_to_string(CallFromFullSlot,
			CallFromFullSlotStr),
		string__append_list([
			"\t\t", CallFromFullSlotStr, " = MR_trace_from_full;\n",
			"\t\tif (MR_trace_from_full) {\n",
			FillAllSlots, "\n",
			"\t\t} else {\n",
			"\t\t\t", CallDepthStr, " = MR_trace_call_depth;\n",
			"\t\t}"
		], TraceStmt)
	;
		TraceType = deep_trace,
		TraceStmt = FillAllSlots
	),
	TraceCode = node([
		pragma_c([], [pragma_c_raw_code(TraceStmt)],
			will_not_call_mercury, no, no, yes) - ""
	])
	}.

trace__prepare_for_call(TraceCode) -->
	code_info__get_maybe_trace_info(MaybeTraceInfo),
	code_info__get_proc_model(CodeModel),
	{
		MaybeTraceInfo = yes(TraceInfo)
	->
		trace_info_get_trace_type(TraceInfo, TraceType),
		trace__call_depth_slot(CodeModel, CallDepthLval),
		trace__stackref_to_string(CallDepthLval, CallDepthStr),
		string__append_list([
			"MR_trace_reset_depth(", CallDepthStr, ");\n"
		], ResetDepthStmt),
		(
			TraceType = shallow_trace(_),
			ResetFromFullStmt = "MR_trace_from_full = FALSE;\n"
		;
			TraceType = deep_trace,
			ResetFromFullStmt = "MR_trace_from_full = TRUE;\n"
		),
		TraceCode = node([
			c_code(ResetFromFullStmt) - "",
			c_code(ResetDepthStmt) - ""
		])
	;
		TraceCode = empty
	}.

trace__maybe_generate_internal_event_code(Goal, Code) -->
	code_info__get_maybe_trace_info(MaybeTraceInfo),
	(
		{ MaybeTraceInfo = yes(TraceInfo) },
		{ trace_info_get_trace_internal(TraceInfo, yes) }
	->
		{ Goal = _ - GoalInfo },
		{ goal_info_get_goal_path(GoalInfo, Path) },
		{
			Path = [LastStep | _],
			(
				LastStep = switch(_),
				PortPrime = switch
			;
				LastStep = disj(_),
				PortPrime = disj
			;
				LastStep = ite_cond,
				PortPrime = ite_cond
			;
				LastStep = ite_then,
				PortPrime = ite_then
			;
				LastStep = ite_else,
				PortPrime = ite_else
			;
				LastStep = neg,
				PortPrime = neg_enter
			)
		->
			Port = PortPrime
		;
			error("trace__generate_internal_event_code: bad path")
		},
		(
			{ ( Port = ite_cond ; Port = neg_enter ) },
			{ trace_info_get_trace_decl(TraceInfo, no) }
		->
			{ Code = empty }
		;
			{ goal_info_get_pre_deaths(GoalInfo, PreDeaths) },
			{ goal_info_get_context(GoalInfo, Context) },
			trace__generate_event_code(Port,
				internal(Path, PreDeaths), TraceInfo,
				Context, _, _, Code)
		)
	;
		{ Code = empty }
	).

trace__maybe_generate_negated_event_code(Goal, NegPort, Code) -->
	code_info__get_maybe_trace_info(MaybeTraceInfo),
	(
		{ MaybeTraceInfo = yes(TraceInfo) },
		{ trace_info_get_trace_internal(TraceInfo, yes) },
		{ trace_info_get_trace_decl(TraceInfo, yes) }
	->
		{
			NegPort = neg_failure,
			Port = neg_failure
		;
			NegPort = neg_success,
			Port = neg_success
		},
		{ Goal = _ - GoalInfo },
		{ goal_info_get_goal_path(GoalInfo, Path) },
		{ goal_info_get_context(GoalInfo, Context) },
		trace__generate_event_code(Port, negation_end(Path),
			TraceInfo, Context, _, _, Code)
	;
		{ Code = empty }
	).

trace__maybe_generate_pragma_event_code(PragmaPort, Context, Code) -->
	code_info__get_maybe_trace_info(MaybeTraceInfo),
	(
		{ MaybeTraceInfo = yes(TraceInfo) },
		{ trace_info_get_trace_internal(TraceInfo, yes) }
	->
		{ trace__convert_nondet_pragma_port_type(PragmaPort, Port) },
		trace__generate_event_code(Port, nondet_pragma, TraceInfo,
			Context, _, _, Code)
	;
		{ Code = empty }
	).

trace__generate_external_event_code(ExternalPort, TraceInfo, Context,
		Label, TvarDataMap, Code) -->
	{ trace__convert_external_port_type(ExternalPort, Port) },
	trace__generate_event_code(Port, external, TraceInfo,
		Context, Label, TvarDataMap, Code).

:- pred trace__generate_event_code(trace_port::in, trace_port_info::in,
	trace_info::in, prog_context::in, label::out,
	map(tvar, set(layout_locn))::out, code_tree::out,
	code_info::in, code_info::out) is det.

trace__generate_event_code(Port, PortInfo, TraceInfo, Context,
		Label, TvarDataMap, Code) -->
	code_info__get_next_label(Label),
	code_info__get_known_variables(LiveVars0),
	(
		{ PortInfo = external },
		{ LiveVars = LiveVars0 },
		{ Path = [] }
	;
		{ PortInfo = internal(Path, PreDeaths) },
		code_info__current_resume_point_vars(ResumeVars),
		{ set__difference(PreDeaths, ResumeVars, RealPreDeaths) },
		{ set__to_sorted_list(RealPreDeaths, RealPreDeathList) },
		{ list__delete_elems(LiveVars0, RealPreDeathList, LiveVars) }
	;
		{ PortInfo = negation_end(Path) },
		{ LiveVars = LiveVars0 }
	;
		{ PortInfo = nondet_pragma },
		{ LiveVars = [] },
		{ Port = nondet_pragma_first ->
			Path = [first]
		; Port = nondet_pragma_later ->
			Path = [later]
		;
			error("bad nondet pragma port")
		}
	),
	code_info__get_varset(VarSet),
	code_info__get_instmap(InstMap),
	{ set__init(TvarSet0) },
	trace__produce_vars(LiveVars, VarSet, InstMap, TvarSet0, TvarSet,
		VarInfoList, ProduceCode),
	code_info__max_reg_in_use(MaxReg),
	code_info__get_max_reg_in_use_at_trace(MaxTraceReg0),
	( { MaxTraceReg0 < MaxReg } ->
		code_info__set_max_reg_in_use_at_trace(MaxReg)
	;
		[]
	),
	code_info__variable_locations(VarLocs),
	code_info__get_proc_info(ProcInfo),
	{
	set__to_sorted_list(TvarSet, TvarList),
	continuation_info__find_typeinfos_for_tvars(TvarList,
		VarLocs, ProcInfo, TvarDataMap),
	set__list_to_set(VarInfoList, VarInfoSet),
	LayoutLabelInfo = layout_label_info(VarInfoSet, TvarDataMap),
	llds_out__get_label(Label, yes, LabelStr),
	DeclStmt = "\t\tCode *MR_jumpaddr;\n",
	SaveStmt = "\t\tsave_transient_registers();\n",
	RestoreStmt = "\t\trestore_transient_registers();\n",
	GotoStmt = "\t\tif (MR_jumpaddr != NULL) GOTO(MR_jumpaddr);"
	},
	{ string__append_list([
		"\t\tMR_jumpaddr = MR_trace(\n",
		"\t\t\t(const MR_Stack_Layout_Label *)\n",
		"\t\t\t&mercury_data__layout__", LabelStr, ");\n"],
		CallStmt) },
	code_info__add_trace_layout_for_label(Label, Context, Port, Path,
		LayoutLabelInfo),
	(
		{ Port = fail },
		{ trace_info_get_maybe_redo_layout_slot(TraceInfo,
			yes(RedoLabel)) }
	->
		% The layout information for the redo event is the same as
		% for the fail event; all the non-clobbered inputs in their
		% stack slots. It is convenient to generate this common layout
		% when the code generator state is set up for the fail event;
		% generating it for the redo event would be much harder.
		% On the other hand, the address of the layout structure
		% for the redo event should be put into its fixed stack slot
		% at procedure entry. Therefore trace__setup reserves a label
		% for the redo event, whose layout information is filled in
		% when we get to the fail event.
		code_info__add_trace_layout_for_label(RedoLabel, Context, redo,
			Path, LayoutLabelInfo)
	;
		[]
	),
	{
	string__append_list([DeclStmt, SaveStmt, CallStmt, RestoreStmt,
		GotoStmt], TraceStmt),
	TraceCode =
		node([
			label(Label)
				- "A label to hang trace liveness on",
				% Referring to the label from the pragma_c
				% prevents the label from being renamed
				% or optimized away.
				% The label is before the trace code
				% because sometimes this pair is preceded
				% by another label, and this way we can
				% eliminate this other label.
			pragma_c([], [pragma_c_raw_code(TraceStmt)],
				may_call_mercury, yes(Label), no, yes)
				- ""
		]),
	Code = tree(ProduceCode, TraceCode)
	}.

trace__maybe_setup_redo_event(TraceInfo, Code) :-
	trace_info_get_maybe_redo_layout_slot(TraceInfo, TraceRedoLayout),
	( TraceRedoLayout = yes(_) ->
		trace_info_get_trace_type(TraceInfo, TraceType),
		(
			TraceType = shallow_trace(Lval),
			% The code in the runtime looks for the from-full
			% flag in framevar 5; see the comment before
			% trace__reserved_slots.
			require(unify(Lval, framevar(5)),
				"from-full flag not stored in expected slot"),
			Code = node([
				mkframe(temp_frame(nondet_stack_proc),
					do_trace_redo_fail_shallow)
					- "set up shallow redo event"
			])
		;
			TraceType = deep_trace,
			Code = node([
				mkframe(temp_frame(nondet_stack_proc),
					do_trace_redo_fail_deep)
					- "set up deep redo event"
			])
		)
	;
		Code = empty
	).

:- pred trace__produce_vars(list(prog_var)::in, prog_varset::in, instmap::in,
	set(tvar)::in, set(tvar)::out, list(var_info)::out, code_tree::out,
	code_info::in, code_info::out) is det.

trace__produce_vars([], _, _, Tvars, Tvars, [], empty) --> [].
trace__produce_vars([Var | Vars], VarSet, InstMap, Tvars0, Tvars,
		[VarInfo | VarInfos], tree(VarCode, VarsCode)) -->
	code_info__produce_variable_in_reg_or_stack(Var, VarCode, Rval),
	code_info__variable_type(Var, Type),
	code_info__get_inst_table(InstTable),
	code_info__get_module_info(ModuleInfo),
	{
	( Rval = lval(LvalPrime) ->
		Lval = LvalPrime
	;
		error("var not an lval in trace__produce_vars")
		% If the value of the variable is known,
		% we record it as living in a nonexistent location, r0.
		% The code that interprets layout information must know this.
		% Lval = reg(r, 0)
	),
	( varset__search_name(VarSet, Var, SearchName) ->
		Name = SearchName
	;
		Name = ""
	),
	instmap__lookup_var(InstMap, Var, Inst),
	( inst_match__inst_is_ground(Inst, InstMap, InstTable, ModuleInfo) ->
		LldsInst = ground
	;
		LldsInst = partial(InstTable, Inst)
	),
	LiveType = var(Var, Name, Type, LldsInst),
	VarInfo = var_info(direct(Lval), LiveType),
	type_util__real_vars(Type, TypeVars),

	set__insert_list(Tvars0, TypeVars, Tvars1)
	},
	trace__produce_vars(Vars, VarSet, InstMap, Tvars1, Tvars,
		VarInfos, VarsCode).

%-----------------------------------------------------------------------------%

:- pred trace__build_fail_vars(list(prog_var)::in, list(inst)::in,
	list(arg_info)::in, instmap::in, inst_table::in, module_info::in,
	list(prog_var)::out) is semidet.

trace__build_fail_vars([], [], [], _, _, _, []).
trace__build_fail_vars([Var | Vars], [Inst | Insts], [Info | Infos],
		InstMap, InstTable, ModuleInfo, FailVars) :-
	trace__build_fail_vars(Vars, Insts, Infos, InstMap, InstTable,
		ModuleInfo, FailVars0),
	Info = arg_info(_Loc, ArgMode),
	(
		ArgMode = top_in,
		\+ inst_is_clobbered(Inst, InstMap, InstTable, ModuleInfo)
	->
		FailVars = [Var | FailVars0]
	;
		FailVars = FailVars0
	).

%-----------------------------------------------------------------------------%

:- pred trace__code_model_to_string(code_model::in, string::out) is det.

trace__code_model_to_string(model_det,  "MR_MODEL_DET").
trace__code_model_to_string(model_semi, "MR_MODEL_SEMI").
trace__code_model_to_string(model_non,  "MR_MODEL_NON").

:- pred trace__stackref_to_string(lval::in, string::out) is det.

trace__stackref_to_string(Lval, LvalStr) :-
	( Lval = stackvar(Slot) ->
		string__int_to_string(Slot, SlotString),
		string__append_list(["MR_stackvar(", SlotString, ")"], LvalStr)
	; Lval = framevar(Slot) ->
		string__int_to_string(Slot, SlotString),
		string__append_list(["MR_framevar(", SlotString, ")"], LvalStr)
	;
		error("non-stack lval in stackref_to_string")
	).

%-----------------------------------------------------------------------------%

trace__path_to_string(Path, PathStr) :-
	trace__path_steps_to_strings(Path, StepStrs),
	list__reverse(StepStrs, RevStepStrs),
	string__append_list(RevStepStrs, PathStr).

:- pred trace__path_steps_to_strings(goal_path::in, list(string)::out) is det.

trace__path_steps_to_strings([], []).
trace__path_steps_to_strings([Step | Steps], [StepStr | StepStrs]) :-
	trace__path_step_to_string(Step, StepStr),
	trace__path_steps_to_strings(Steps, StepStrs).

:- pred trace__path_step_to_string(goal_path_step::in, string::out) is det.

trace__path_step_to_string(conj(N), Str) :-
	string__int_to_string(N, NStr),
	string__append_list(["c", NStr, ";"], Str).
trace__path_step_to_string(disj(N), Str) :-
	string__int_to_string(N, NStr),
	string__append_list(["d", NStr, ";"], Str).
trace__path_step_to_string(switch(N), Str) :-
	string__int_to_string(N, NStr),
	string__append_list(["s", NStr, ";"], Str).
trace__path_step_to_string(ite_cond, "?;").
trace__path_step_to_string(ite_then, "t;").
trace__path_step_to_string(ite_else, "e;").
trace__path_step_to_string(neg, "~;").
trace__path_step_to_string(exist, "q;").
trace__path_step_to_string(first, "f;").
trace__path_step_to_string(later, "l;").

:- pred trace__convert_external_port_type(external_trace_port::in,
	trace_port::out) is det.

trace__convert_external_port_type(call, call).
trace__convert_external_port_type(exit, exit).
trace__convert_external_port_type(fail, fail).

:- pred trace__convert_nondet_pragma_port_type(nondet_pragma_trace_port::in,
	trace_port::out) is det.

trace__convert_nondet_pragma_port_type(nondet_pragma_first,
	nondet_pragma_first).
trace__convert_nondet_pragma_port_type(nondet_pragma_later,
	nondet_pragma_later).

%-----------------------------------------------------------------------------%

:- pred trace__event_num_slot(code_model::in, lval::out) is det.
:- pred trace__call_num_slot(code_model::in, lval::out) is det.
:- pred trace__call_depth_slot(code_model::in, lval::out) is det.
:- pred trace__redo_layout_slot(code_model::in, lval::out) is det.

trace__event_num_slot(CodeModel, EventNumSlot) :-
	( CodeModel = model_non ->
		EventNumSlot  = framevar(1)
	;
		EventNumSlot  = stackvar(1)
	).

trace__call_num_slot(CodeModel, CallNumSlot) :-
	( CodeModel = model_non ->
		CallNumSlot   = framevar(2)
	;
		CallNumSlot   = stackvar(2)
	).

trace__call_depth_slot(CodeModel, CallDepthSlot) :-
	( CodeModel = model_non ->
		CallDepthSlot = framevar(3)
	;
		CallDepthSlot = stackvar(3)
	).

trace__redo_layout_slot(CodeModel, RedoLayoutSlot) :-
	( CodeModel = model_non ->
		RedoLayoutSlot = framevar(4)
	;
		error("attempt to access redo layout slot for det or semi procedure")
	).

%-----------------------------------------------------------------------------%

	% Information for tracing that is valid throughout the execution
	% of a procedure.
:- type trace_info
	--->	trace_info(
			trace_type,	% The trace level (which cannot be
					% none), and if it is shallow, the
					% lval of the slot that holds the
					% from-full flag.
			bool,		% The value of --trace-internal.
			bool,		% The value of --trace-decl.
			maybe(pair(lval)),
					% If trailing is enabled, the lvals
					% of the slots that hold the value
					% of the trail pointer and the ticket
					% counter at the time of the call.
			maybe(label)	% If we are generating redo events,
					% this has the label associated with
					% the fail event, which we then reserve
					% in advance, so we can put the
					% address of its layout struct
					% into the slot which holds the
					% layout for the redo event (the
					% two events have identical layouts).
		).

:- pred init_trace_info(trace_type::in, bool::in, bool::in,
	maybe(pair(lval))::in, maybe(label)::in, trace_info::out) is det.

:- pred trace_info_get_trace_type(trace_info::in, trace_type::out) is det.
:- pred trace_info_get_trace_internal(trace_info::in, bool::out) is det.
:- pred trace_info_get_trace_decl(trace_info::in, bool::out) is det.
:- pred trace_info_get_maybe_trail_slots(trace_info::in,
	maybe(pair(lval))::out) is det.
:- pred trace_info_get_maybe_redo_layout_slot(trace_info::in,
	maybe(label)::out) is det.

init_trace_info(TraceType, TraceInternal, TraceDecl,
	MaybeTrailSlot, MaybeRedoLayoutSlot,
	trace_info(TraceType, TraceInternal, TraceDecl,
		MaybeTrailSlot, MaybeRedoLayoutSlot)).

trace_info_get_trace_type(trace_info(TraceType, _, _, _, _), TraceType).
trace_info_get_trace_internal(trace_info(_, TraceInternal, _, _, _),
	TraceInternal).
trace_info_get_trace_decl(trace_info(_, _, TraceDecl, _, _), TraceDecl).
trace_info_get_maybe_trail_slots(trace_info(_, _, _, MaybesTrailSlot, _),
	MaybesTrailSlot).
trace_info_get_maybe_redo_layout_slot(trace_info(_, _, _, _,
	MaybeRedoLayoutSlot), MaybeRedoLayoutSlot).
