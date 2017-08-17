%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 2009, 2011-2012 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: ml_code_util.m.
% Main author: fjh.
%
% This module is part of the MLDS code generator.
% It defines the ml_gen_info type and its access routines.
%
%---------------------------------------------------------------------------%

:- module ml_backend.ml_gen_info.
:- interface.

:- import_module hlds.
:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module hlds.mark_tail_calls.
:- import_module hlds.vartypes.
:- import_module libs.
:- import_module libs.globals.
:- import_module ml_backend.ml_global_data.
:- import_module ml_backend.mlds.
:- import_module parse_tree.
:- import_module parse_tree.error_util.
:- import_module parse_tree.prog_data.

:- import_module bool.
:- import_module list.
:- import_module map.
:- import_module set.

%---------------------------------------------------------------------------%
%
% The `ml_gen_info' ADT.
%

    % The `ml_gen_info' type holds information used during
    % MLDS code generation for a given procedure.
    %
:- type ml_gen_info.

%---------------------------------------------------------------------------%
%
% Operations on the ml_gen_info that are more than getters and setters.
%

:- pred ml_gen_info_get_globals(ml_gen_info::in, globals::out) is det.
:- pred ml_gen_info_get_module_name(ml_gen_info::in, mercury_module_name::out)
    is det.

    % Look up the --gcc-nested-functions option.
    %
:- pred ml_gen_info_use_gcc_nested_functions(ml_gen_info::in, bool::out)
    is det.

    % Look up the --put-commit-in-nested-func option.
    %
:- pred ml_gen_info_put_commit_in_own_func(ml_gen_info::in, bool::out) is det.

    % Generate a new label number for use in label statements.
    % This is used to give unique names to the case labels generated
    % for dense switch statements.
    %
:- type label_num == int.
:- pred ml_gen_info_new_label(label_num::out,
    ml_gen_info::in, ml_gen_info::out) is det.

    % Generate a new function label number. This is used to give unique names
    % to the nested functions used when generating code for nondet procedures.
    %
:- pred ml_gen_info_new_aux_func_id(mlds_maybe_aux_func_id::out,
    ml_gen_info::in, ml_gen_info::out) is det.

    % Increase the function label and const sequence number counters by some
    % amount which is presumed to be sufficient to ensure that if we start
    % again with a fresh ml_gen_info and then call this function, we won't
    % encounter any already-used function labels or constants. (This is used
    % when generating wrapper functions for type class methods.)
    %
:- pred ml_gen_info_bump_counters(ml_gen_info::in, ml_gen_info::out) is det.

    % Generate a new auxiliary variable of the given kind,
    % with a sequence number that differentiates this aux var from all others.
    %
    % Auxiliary variables are used for purposes such as commit label numbers
    % and holding table indexes in switches.
    %
:- pred ml_gen_info_new_aux_var_name(mlds_compiler_aux_var::in,
    mlds_local_var_name::out, ml_gen_info::in, ml_gen_info::out) is det.

    % Generate a new `cond' variable number.
    %
:- type cond_seq ---> cond_seq(int).
:- pred ml_gen_info_new_cond_var(cond_seq::out,
    ml_gen_info::in, ml_gen_info::out) is det.

    % Generate a new `conv' variable number. This is used to give unique names
    % to the local variables generated by ml_gen_box_or_unbox_lval, which are
    % used to handle boxing/unboxing argument conversions.
    %
:- type conv_seq ---> conv_seq(int).
:- pred ml_gen_info_new_conv_var(conv_seq::out,
    ml_gen_info::in, ml_gen_info::out) is det.

:- type ml_ground_term
    --->    ml_ground_term(
                % The value of the ground term.
                mlds_rval,

                % The type of the ground term (actually, the type of the
                % variable the ground term was constructed for).
                mer_type,

                % The corresponding MLDS type. It could be computed from the
                % Mercury type, but there is no point in doing so when using
                % the ground term as well when constructing it.
                mlds_type
            ).

:- type ml_ground_term_map == map(prog_var, ml_ground_term).

:- type ml_const_struct_map == map(int, ml_ground_term).

    % Set the `const' variable name corresponding to the given HLDS variable.
    %
:- pred ml_gen_info_set_const_var(prog_var::in, ml_ground_term::in,
    ml_gen_info::in, ml_gen_info::out) is det.

    % Look up the `const' sequence number corresponding to a given HLDS
    % variable.
    %
:- pred ml_gen_info_lookup_const_var(ml_gen_info::in, prog_var::in,
    ml_ground_term::out) is det.
:- pred ml_gen_info_search_const_var(ml_gen_info::in, prog_var::in,
    ml_ground_term::out) is semidet.

    % A success continuation specifies the (rval for the variable holding
    % the address of the) function that a nondet procedure should call
    % if it succeeds, and possibly also the (rval for the variable holding)
    % the environment pointer for that function, and possibly also the
    % (list of rvals for the) arguments to the continuation.
    %
:- type success_cont
    --->    success_cont(
                % Function pointer.
                mlds_rval,

                % Environment pointer. Note that if we are using
                % nested functions, then the environment pointer
                % will not be used.
                mlds_rval,

                % The argument types, if any.
                list(mlds_type),

                % The arguments, if any. The arguments will only be non-empty
                % if the --nondet-copy-out option is enabled. They do not
                % include the environment pointer.
                list(mlds_lval)
            ).

    % The ml_gen_info contains a stack of success continuations.
    % The following routines provide access to that stack.

:- pred ml_gen_info_push_success_cont(success_cont::in,
    ml_gen_info::in, ml_gen_info::out) is det.

:- pred ml_gen_info_pop_success_cont(ml_gen_info::in, ml_gen_info::out) is det.

:- pred ml_gen_info_current_success_cont(ml_gen_info::in, success_cont::out)
    is det.

    % We keep a partial mapping from vars to lvals. This is used in special
    % cases to override the normal lval for a variable. ml_gen_var will check
    % this map first, and if the variable is not in this map, then it will go
    % ahead and generate an lval for it as usual.
    %
    % Set the lval for a variable.
    %
:- pred ml_gen_info_set_var_lval(prog_var::in, mlds_lval::in,
    ml_gen_info::in, ml_gen_info::out) is det.

    % The ml_gen_info contains a list of extra definitions of functions or
    % global constants which should be inserted before the definition of the
    % function for the current procedure. This is used for the definitions
    % of the wrapper functions needed for closures. When generating code
    % for a procedure that creates a closure, we insert the definition of
    % the wrapper function used for that closure into this list.
    %
    % Insert an extra definition at the start of the list of extra
    % definitions.
    %
:- pred ml_gen_info_add_closure_wrapper_defn(mlds_function_defn::in,
    ml_gen_info::in, ml_gen_info::out) is det.

    % Add the given string as the name of an environment variable used by
    % the function being generated.
    %
:- pred ml_gen_info_add_env_var_name(string::in,
    ml_gen_info::in, ml_gen_info::out) is det.

:- type tail_rec_mechanism
    --->    tail_rec_via_while_loop
            % The procedure body is wrapped in a "while (true)" loop,
            % tail recursive calls are converted to "continue" statements,
            % and the normal exit at the end of the procedure body
            % is done by a "break".

    ;       tail_rec_via_start_label(string).
            % The procedure body starts with a label with the given name,
            % tail recursive calls are converted to "goto label" statements,
            % and the normal exit at the end of the procedure body
            % requires no special handling.

:- type have_we_done_tail_rec
    --->    have_not_done_tail_rec
    ;       have_done_tail_rec.

    % This map should have an entry for each procedure in the TSCC.
    % The set of keys in the map won't change and neither will
    % the target mechanism of each, which tells the code generator
    % how to generate code for a tail recursive call to the given
    % procedure, but if the code generator *does* generate such
    % a tail recursive call, it should set the
    % have_we_done_tail_rec field to have_done_tail_rec.
:- type tail_rec_target_map == map(pred_proc_id, tail_rec_target_info).
:- type tail_rec_target_info
    --->    tail_rec_target_info(
                % The target at the start of the procedure.
                tail_rec_mechanism,

                % The list of the *input* arguments of the procedure.
                list(mlds_argument),

                % Have we generated a jump to that target?
                have_we_done_tail_rec
            ).

:- type tail_rec_info
    --->    tail_rec_info(
                tri_target_map      :: tail_rec_target_map,
                tri_warn_params     :: warn_non_tail_rec_params,
                tri_msgs            :: list(error_spec)
            ).

%---------------------------------------------------------------------------%
%
% Initialize the ml_gen_info.
%

    % Initialize the ml_gen_info, so that it is ready for generating code
    % for the given procedure. The last argument records the persistent
    % information accumulated by the code generator so far during the
    % processing of previous procedures.
    %
:- func ml_gen_info_init(module_info, mlds_target_lang, ml_const_struct_map,
    pred_proc_id, proc_info, tail_rec_target_map, ml_global_data)
    = ml_gen_info.

%---------------------------------------------------------------------------%
%
% Getters and setters of the ml_gen_info structure.
%

:- pred ml_gen_info_get_const_var_map(ml_gen_info::in,
    map(prog_var, ml_ground_term)::out) is det.
:- pred ml_gen_info_get_used_succeeded_var(ml_gen_info::in, bool::out) is det.
:- pred ml_gen_info_get_closure_wrapper_defns(ml_gen_info::in,
    list(mlds_function_defn)::out) is det.
:- pred ml_gen_info_get_global_data(ml_gen_info::in, ml_global_data::out)
    is det.
:- pred ml_gen_info_get_module_info(ml_gen_info::in, module_info::out) is det.
:- pred ml_gen_info_get_pred_proc_id(ml_gen_info::in,
    pred_proc_id::out) is det.
:- pred ml_gen_info_get_varset(ml_gen_info::in, prog_varset::out) is det.
:- pred ml_gen_info_get_var_types(ml_gen_info::in, vartypes::out) is det.
:- pred ml_gen_info_get_high_level_data(ml_gen_info::in, bool::out) is det.
:- pred ml_gen_info_get_target(ml_gen_info::in, mlds_target_lang::out) is det.
:- pred ml_gen_info_get_gc(ml_gen_info::in, gc_method::out) is det.
:- pred ml_gen_info_get_const_struct_map(ml_gen_info::in,
    map(int, ml_ground_term)::out) is det.
:- pred ml_gen_info_get_var_lvals(ml_gen_info::in,
    map(prog_var, mlds_lval)::out) is det.
:- pred ml_gen_info_get_env_var_names(ml_gen_info::in, set(string)::out)
    is det.
:- pred ml_gen_info_get_disabled_warnings(ml_gen_info::in,
    set(goal_warning)::out) is det.
:- pred ml_gen_info_get_tail_rec_info(ml_gen_info::in,
    tail_rec_info::out) is det.
:- pred ml_gen_info_get_byref_output_vars(ml_gen_info::in, list(prog_var)::out)
    is det.

:- pred ml_gen_info_set_const_var_map(map(prog_var, ml_ground_term)::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_used_succeeded_var(bool::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_global_data(ml_global_data::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_module_info(module_info::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_varset(prog_varset::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_var_types(vartypes::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_var_lvals(map(prog_var, mlds_lval)::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_disabled_warnings(set(goal_warning)::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_tail_rec_info(tail_rec_info::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_byref_output_vars(list(prog_var)::in,
    ml_gen_info::in, ml_gen_info::out) is det.

%---------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.
:- import_module check_hlds.mode_util.
:- import_module libs.options.

:- import_module counter.
:- import_module int.
:- import_module stack.

%---------------------------------------------------------------------------%

ml_gen_info_get_globals(Info, Globals) :-
    ml_gen_info_get_module_info(Info, ModuleInfo),
    module_info_get_globals(ModuleInfo, Globals).

ml_gen_info_get_module_name(Info, ModuleName) :-
    ml_gen_info_get_module_info(Info, ModuleInfo),
    module_info_get_name(ModuleInfo, ModuleName).

ml_gen_info_use_gcc_nested_functions(Info, UseNestedFuncs) :-
    ml_gen_info_get_globals(Info, Globals),
    globals.lookup_bool_option(Globals, gcc_nested_functions,
        UseNestedFuncs).

ml_gen_info_put_commit_in_own_func(Info, PutCommitInNestedFunc) :-
    ml_gen_info_get_globals(Info, Globals),
    globals.lookup_bool_option(Globals, put_commit_in_own_func,
        PutCommitInNestedFunc).

ml_gen_info_new_label(Label, !Info) :-
    ml_gen_info_get_label_counter(!.Info, Counter0),
    counter.allocate(Label, Counter0, Counter),
    ml_gen_info_set_label_counter(Counter, !Info).

ml_gen_info_new_aux_func_id(MaybeAux, !Info) :-
    ml_gen_info_get_func_counter(!.Info, Counter0),
    counter.allocate(Num, Counter0, Counter),
    MaybeAux = proc_aux_func(Num),
    ml_gen_info_set_func_counter(Counter, !Info).

ml_gen_info_bump_counters(!Info) :-
    ml_gen_info_get_func_counter(!.Info, FuncLabelCounter0),
    counter.allocate(FuncLabel, FuncLabelCounter0, _),
    FuncLabelCounter = counter.init(FuncLabel + 10000),
    ml_gen_info_set_func_counter(FuncLabelCounter, !Info).

ml_gen_info_new_aux_var_name(AuxVar, VarName, !Info) :-
    ml_gen_info_get_aux_var_counter(!.Info, AuxVarCounter0),
    counter.allocate(AuxVarNum, AuxVarCounter0, AuxVarCounter),
    ml_gen_info_set_aux_var_counter(AuxVarCounter, !Info),
    VarName = lvn_comp_var(lvnc_aux_var(AuxVar, AuxVarNum)).

ml_gen_info_new_cond_var(cond_seq(CondNum), !Info) :-
    ml_gen_info_get_cond_var_counter(!.Info, CondCounter0),
    counter.allocate(CondNum, CondCounter0, CondCounter),
    ml_gen_info_set_cond_var_counter(CondCounter, !Info).

ml_gen_info_new_conv_var(conv_seq(ConvNum), !Info) :-
    ml_gen_info_get_conv_var_counter(!.Info, ConvCounter0),
    counter.allocate(ConvNum, ConvCounter0, ConvCounter),
    ml_gen_info_set_conv_var_counter(ConvCounter, !Info).

ml_gen_info_set_const_var(Var, GroundTerm, !Info) :-
    ml_gen_info_get_const_var_map(!.Info, ConstVarMap0),
    % We cannot call map.det_insert, because we do not (yet) clean up the
    % const_var_map at the start of later branches of a branched goal,
    % and thus when generating code for a later branch, we may come across
    % an entry left by an earlier branch. Using map.set instead throws away
    % such obsolete entries.
    map.set(Var, GroundTerm, ConstVarMap0, ConstVarMap),
    ml_gen_info_set_const_var_map(ConstVarMap, !Info).

ml_gen_info_lookup_const_var(Info, Var, GroundTerm) :-
    ml_gen_info_get_const_var_map(Info, ConstVarMap),
    map.lookup(ConstVarMap, Var, GroundTerm).

ml_gen_info_search_const_var(Info, Var, GroundTerm) :-
    ml_gen_info_get_const_var_map(Info, ConstVarMap),
    map.search(ConstVarMap, Var, GroundTerm).

ml_gen_info_push_success_cont(SuccCont, !Info) :-
    ml_gen_info_get_success_cont_stack(!.Info, Stack0),
    stack.push(SuccCont, Stack0, Stack),
    ml_gen_info_set_success_cont_stack(Stack, !Info).

ml_gen_info_pop_success_cont(!Info) :-
    ml_gen_info_get_success_cont_stack(!.Info, Stack0),
    stack.det_pop(_SuccCont, Stack0, Stack),
    ml_gen_info_set_success_cont_stack(Stack, !Info).

ml_gen_info_current_success_cont(Info, SuccCont) :-
    ml_gen_info_get_success_cont_stack(Info, Stack),
    stack.det_top(Stack, SuccCont).

ml_gen_info_set_var_lval(Var, Lval, !Info) :-
    ml_gen_info_get_var_lvals(!.Info, VarLvals0),
    map.set(Var, Lval, VarLvals0, VarLvals),
    ml_gen_info_set_var_lvals(VarLvals, !Info).

ml_gen_info_add_closure_wrapper_defn(ClosureWrapperDefn, !Info) :-
    ml_gen_info_get_closure_wrapper_defns(!.Info, ClosureWrapperDefns0),
    ClosureWrapperDefns = [ClosureWrapperDefn | ClosureWrapperDefns0],
    ml_gen_info_set_closure_wrapper_defns(ClosureWrapperDefns, !Info).

ml_gen_info_add_env_var_name(Name, !Info) :-
    ml_gen_info_get_env_var_names(!.Info, EnvVarNames0),
    set.insert(Name, EnvVarNames0, EnvVarNames),
    ml_gen_info_set_env_var_names(EnvVarNames, !Info).

%---------------------------------------------------------------------------%
%
% The definition of the `ml_gen_info' ADT.
%
% The ml_gen_info structure is logically an atomic structure,
% but we split it up into three pieces for performance reasons.
% The most frequently updated fields are at the top level, in the ml_gen_info
% structure, whose size is limited to eight fields. This makes it (just) fit
% into one of Boehm gc's size categories, and it limits the amount of copying
% that needs to be done when one of the fields is updated. The other fields
% are stored in one of two substructures. The ml_gen_rare_info is for the
% fields that are never or almost-never updated, while the ml_gen_sub_info
% is for the fields that are updated reasonably frequently, though not
% so frequently as to deserve a spot in the top level structure.

:- type ml_gen_info
    --->    ml_gen_info(
                % A variable can be bound to a constant in one branch
                % of a control structure and to a non-constant term
                % in another branch. We store information about variables
                % bound to constants in the mgsi_const_var_map field.
                %
                % Branched control structures should reset the map
                % to its original value at the start of every branch
                % after the first (to prevent a later branch from using
                % information that is applicable only in a previous branch),
                % and at the end of the branched control structure
                % (to prevent the code after it using information whose
                % correctness depends on the exact route that
                % execution took to there).
                %
/*  1 */        mgi_const_var_map       :: map(prog_var, ml_ground_term),

/*  2 */        mgi_func_counter        :: counter,
/*  3 */        mgi_conv_var_counter    :: counter,
/*  4 */        mgi_used_succeeded_var  :: bool,

/*  5 */        mgi_closure_wrapper_defns :: list(mlds_function_defn),

/*  6 */        mgi_global_data         :: ml_global_data,

/*  7 */        mgi_rare_info           :: ml_gen_rare_info,
/*  8 */        mgi_sub_info            :: ml_gen_sub_info
            ).

:- type ml_gen_rare_info
    --->    ml_gen_rare_info(
                % The module_info. Read-only unless accurate gc needs to make
                % new type_info variables.
/*  1 */        mgri_module_info        :: module_info,

                % The identity of the procedure we are generating code for.
                % Read-only.
/*  2 */        mgri_pred_proc_id       :: pred_proc_id,

                % The varset and vartypes fields of the procedure
                % we are generating code for. Read-only unless accurate gc
                % needs to make new type_info variables.
/*  3 */        mgri_varset             :: prog_varset,
/*  4 */        mgri_var_types          :: vartypes,

                % Quick-access read-only copies of parts of the globals
                % structure taken from the module_info. Read-only.
/*  5 */        mgri_high_level_data    :: bool,
/*  6 */        mgri_target             :: mlds_target_lang,
/*  7 */        mgri_gc                 :: gc_method,

                % The map of the constant ground structures generated by
                % ml_code_gen before we start generating code for procedures. 
/*  8 */        mgri_const_struct_map   :: map(int, ml_ground_term),

                % Normally, we convert each HLDS variable to its own MLDS lval
                % each time the HLDS code refers it, using a simple
                % determininistic algorithm (the ml_gen_var function).
                % However, inside a commit scope, we currently translate
                % the output variables of that scope not to the MLDS lval
                % that the code outside the commit uses to refer to the
                % variable, but to a local *copy* of that variable;
                % when the goal inside the commit succeeds, we then assign
                % the value of the local copy to the MLDS variable used
                % outside the scope. The var_lvals field maps each output var
                % of every commit scope we are in to the local copy MLDS
                % variable.
                %
                % Currenly, this complexity is not actually necessary for the
                % C backend, which has nondet_copy_out set to "no". When the
                % output variable is generated, the code inside the commit
                % could assign its new value to the usual MLDS variable
                % (the one returned by ml_gen_var) directly. I (zs) have
                % just tried a bootcheck which did that, and it works.
                %
                % However, in the future, when we generate implicitly
                % AND-parallel MLDS code, this could come in useful for C as
                % well. This is because it is possible for an output variable
                % of a commit scope to become many times inside the scope
                % before the scope as a whole succeeds, if each binding but
                % the last is followed by a local failure. We want to signal
                % any consumer of the variable *outside* the scope that
                % the variable has actually been bound only when the commit
                % scope succeeds and *its usual MLDS variable* is assigned to,
                % while we want to signal any consumer *inside* the scope
                % when *the local copy* is assigned to. The distinction
                % would then give us two separate assignments to follow with
                % two separate signal operations for two separate classes
                % of consumers.
/*  9 */        mgri_var_lvals          :: map(prog_var, mlds_lval),

                % The set of used environment variables. Writeable.
/* 10 */        mgri_env_var_names      :: set(string),

                % The set of warnings disabled in the current scope. Writeable.
/* 11 */        mgri_disabled_warnings  :: set(goal_warning),

/* 12 */        % For each procedure to whose tail calls we can apply
                % tail recursion optimization, this maps the label of that
                % procedure to (a) the information we need to generate
                % the code to jump to the start of that procedure, and
                % (b) a record of whether we *have* generated such a jump.
                %
                % This field also contains the information we need to generate
                % the right set of warnings for calls marked as tail recursive
                % by mark_tail_calls.m but which we cannot actually turn
                % into tail calls, and the warnings so generated.
                mgri_tail_rec_info      :: tail_rec_info
            ).

:- type ml_gen_sub_info
    --->    ml_gen_sub_info(
                % Output arguments that are passed by reference.
                % (We used to store the list of output arguments that are
                % returned as values in another field, but we don't need that
                % information anymore.)
/*  1 */        mgsi_byref_output_vars  :: list(prog_var),

/*  2 */        mgsi_label_counter      :: counter,
/*  3 */        mgsi_aux_var_counter    :: counter,
/*  4 */        mgsi_cond_var_counter   :: counter,

/*  5 */        mgsi_success_cont_stack :: stack(success_cont)
            ).

% Access stats for the ml_gen_info structure:
%
%  i      read      same      diff   same%
%  0  18766903         0         0              module_info
%  1    548868         0         0              high_level_data
%  2    232588         0         0              target
%  3   2721027         0         0              gc
%  4    158848         0         0              pred_id
%  5    158848         0         0              proc_id
%  6   4647635         0         0              varset
%  7   7835272         0         0              vartypes
%  8   2964012     64588     11516  84.87%      byref_output_vars
%  9         0     65734     11516  85.09%      value_output_vars
% 10   2998238       594         0 100.00%      var_lvals
% 11    135553     13144     27277  32.52%      global_data
% 12     53820         0     53820   0.00%      func_counter
% 13       237         0       237   0.00%      label_counter
% 14      1805         0      1805   0.00%      aux_var_counter
% 15        21         0        21   0.00%      cond_var_counter
% 16     52544         0     52544   0.00%      conv_var_counter
% 17    727348    151728    477494  24.11%      const_var_map
% 18     32375         0         0              const_struct_map
% 19     14408         0      8197   0.00%      success_cont_stack
% 20    127335         0     32258   0.00%      closure_wrapper_defns
% 21     77412         8         8  50.00%      env_var_names
% 22    352575         0         2   0.00%      disabled_warnings
% 23     77250    341887     45872  88.17%      used_succeeded_var

ml_gen_info_init(ModuleInfo, Target, ConstStructMap, PredProcId, ProcInfo,
        TailRecTargetMap, GlobalData) = Info :-
    module_info_get_globals(ModuleInfo, Globals),
    globals.lookup_bool_option(Globals, highlevel_data, HighLevelData),
    globals.get_gc_method(Globals, GC),

    proc_info_get_headvars(ProcInfo, HeadVars),
    proc_info_get_varset(ProcInfo, VarSet),
    proc_info_get_vartypes(ProcInfo, VarTypes),
    proc_info_get_argmodes(ProcInfo, HeadModes),
    ByRefOutputVars = select_output_vars(ModuleInfo, HeadVars, HeadModes,
        VarTypes),

    % XXX This needs to start at 1 rather than 0 otherwise the transformation
    % for adding the shadow stack for accurate garbage collection does not work
    % properly and we will end up generating two C functions with the same
    % name (see ml_elim_nested.gen_gc_trace_func/8 for details).
    %
    counter.init(1, FuncLabelCounter),
    counter.init(0, LabelCounter),
    counter.init(0, AuxVarCounter),
    counter.init(0, CondVarCounter),
    counter.init(0, ConvVarCounter),
    map.init(ConstVarMap),
    stack.init(SuccContStack),
    map.init(VarLvals),
    ClosureWrapperDefns = [],
    set.init(EnvVarNames),
    set.init(DisabledWarnings),
    UsedSucceededVar = no,
    get_default_warn_parms(Globals, DefaultWarnParams),
    maybe_override_warn_params_for_proc(ProcInfo, DefaultWarnParams,
        ProcWarnParams),
    Specs0 = [],
    TailRecInfo = tail_rec_info(TailRecTargetMap, ProcWarnParams, Specs0),

    RareInfo = ml_gen_rare_info(
        ModuleInfo,
        PredProcId,
        VarSet,
        VarTypes,
        HighLevelData,
        Target,
        GC,
        ConstStructMap,
        VarLvals,
        EnvVarNames,
        DisabledWarnings,
        TailRecInfo
    ),
    SubInfo = ml_gen_sub_info(
        ByRefOutputVars,
        LabelCounter,
        AuxVarCounter,
        CondVarCounter,
        SuccContStack
    ),
    Info = ml_gen_info(
        ConstVarMap,
        FuncLabelCounter,
        ConvVarCounter,
        UsedSucceededVar,
        ClosureWrapperDefns,
        GlobalData,
        RareInfo,
        SubInfo
    ).

:- pred ml_gen_info_get_func_counter(ml_gen_info::in, counter::out) is det.
:- pred ml_gen_info_get_conv_var_counter(ml_gen_info::in, counter::out) is det.
:- pred ml_gen_info_get_label_counter(ml_gen_info::in, counter::out) is det.
:- pred ml_gen_info_get_aux_var_counter(ml_gen_info::in, counter::out) is det.
:- pred ml_gen_info_get_cond_var_counter(ml_gen_info::in, counter::out) is det.
:- pred ml_gen_info_get_success_cont_stack(ml_gen_info::in,
    stack(success_cont)::out) is det.

ml_gen_info_get_const_var_map(Info, X) :-
    X = Info ^ mgi_const_var_map.
ml_gen_info_get_func_counter(Info, X) :-
    X = Info ^ mgi_func_counter.
ml_gen_info_get_conv_var_counter(Info, X) :-
    X = Info ^ mgi_conv_var_counter.
ml_gen_info_get_used_succeeded_var(Info, X) :-
    X = Info ^ mgi_used_succeeded_var.
ml_gen_info_get_closure_wrapper_defns(Info, X) :-
    X = Info ^ mgi_closure_wrapper_defns.
ml_gen_info_get_global_data(Info, X) :-
    X = Info ^ mgi_global_data.

ml_gen_info_get_module_info(Info, X) :-
    X = Info ^ mgi_rare_info ^ mgri_module_info.
ml_gen_info_get_pred_proc_id(Info, X) :-
    X = Info ^ mgi_rare_info ^ mgri_pred_proc_id.
ml_gen_info_get_varset(Info, X) :-
    X = Info ^ mgi_rare_info ^ mgri_varset.
ml_gen_info_get_var_types(Info, X) :-
    X = Info ^ mgi_rare_info ^ mgri_var_types.
ml_gen_info_get_high_level_data(Info, X) :-
    X = Info ^ mgi_rare_info ^ mgri_high_level_data.
ml_gen_info_get_target(Info, X) :-
    X = Info ^ mgi_rare_info ^ mgri_target.
ml_gen_info_get_gc(Info, X) :-
    X = Info ^ mgi_rare_info ^ mgri_gc.
ml_gen_info_get_const_struct_map(Info, X) :-
    X = Info ^ mgi_rare_info ^ mgri_const_struct_map.
ml_gen_info_get_var_lvals(Info, X) :-
    X = Info ^ mgi_rare_info ^ mgri_var_lvals.
ml_gen_info_get_env_var_names(Info, X) :-
    X = Info ^ mgi_rare_info ^ mgri_env_var_names.
ml_gen_info_get_disabled_warnings(Info, X) :-
    X = Info ^ mgi_rare_info ^ mgri_disabled_warnings.
ml_gen_info_get_tail_rec_info(Info, X) :-
    X = Info ^ mgi_rare_info ^ mgri_tail_rec_info.

ml_gen_info_get_byref_output_vars(Info, X) :-
    X = Info ^ mgi_sub_info ^ mgsi_byref_output_vars.
ml_gen_info_get_label_counter(Info, X) :-
    X = Info ^ mgi_sub_info ^ mgsi_label_counter.
ml_gen_info_get_aux_var_counter(Info, X) :-
    X = Info ^ mgi_sub_info ^ mgsi_aux_var_counter.
ml_gen_info_get_cond_var_counter(Info, X) :-
    X = Info ^ mgi_sub_info ^ mgsi_cond_var_counter.
ml_gen_info_get_success_cont_stack(Info, X) :-
    X = Info ^ mgi_sub_info ^ mgsi_success_cont_stack.

:- pred ml_gen_info_set_func_counter(counter::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_conv_var_counter(counter::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_closure_wrapper_defns(list(mlds_function_defn)::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_env_var_names(set(string)::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_label_counter(counter::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_aux_var_counter(counter::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_cond_var_counter(counter::in,
    ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_success_cont_stack(stack(success_cont)::in,
    ml_gen_info::in, ml_gen_info::out) is det.

ml_gen_info_set_const_var_map(X, !Info) :-
    ( if private_builtin.pointer_equal(X, !.Info ^ mgi_const_var_map) then
        true
    else
        !Info ^ mgi_const_var_map := X
    ).
ml_gen_info_set_func_counter(X, !Info) :-
    !Info ^ mgi_func_counter := X.
ml_gen_info_set_conv_var_counter(X, !Info) :-
    !Info ^ mgi_conv_var_counter := X.
ml_gen_info_set_used_succeeded_var(X, !Info) :-
    ( if X = !.Info ^ mgi_used_succeeded_var then
        true
    else
        !Info ^ mgi_used_succeeded_var := X
    ).
ml_gen_info_set_closure_wrapper_defns(X, !Info) :-
    !Info ^ mgi_closure_wrapper_defns := X.
ml_gen_info_set_global_data(X, !Info) :-
    ( if private_builtin.pointer_equal(X, !.Info ^ mgi_global_data) then
        true
    else
        !Info ^ mgi_global_data := X
    ).

ml_gen_info_set_module_info(X, !Info) :-
    RareInfo0 = !.Info ^ mgi_rare_info,
    RareInfo = RareInfo0 ^ mgri_module_info := X,
    !Info ^ mgi_rare_info := RareInfo.
ml_gen_info_set_varset(X, !Info) :-
    RareInfo0 = !.Info ^ mgi_rare_info,
    RareInfo = RareInfo0 ^ mgri_varset := X,
    !Info ^ mgi_rare_info := RareInfo.
ml_gen_info_set_var_types(X, !Info) :-
    RareInfo0 = !.Info ^ mgi_rare_info,
    RareInfo = RareInfo0 ^ mgri_var_types := X,
    !Info ^ mgi_rare_info := RareInfo.
ml_gen_info_set_var_lvals(X, !Info) :-
    RareInfo0 = !.Info ^ mgi_rare_info,
    ( if private_builtin.pointer_equal(X, RareInfo0 ^ mgri_var_lvals) then
        true
    else
        RareInfo = RareInfo0 ^ mgri_var_lvals := X,
        !Info ^ mgi_rare_info := RareInfo
    ).
ml_gen_info_set_env_var_names(X, !Info) :-
    RareInfo0 = !.Info ^ mgi_rare_info,
    RareInfo = RareInfo0 ^ mgri_env_var_names := X,
    !Info ^ mgi_rare_info := RareInfo.
ml_gen_info_set_disabled_warnings(X, !Info) :-
    RareInfo0 = !.Info ^ mgi_rare_info,
    RareInfo = RareInfo0 ^ mgri_disabled_warnings := X,
    !Info ^ mgi_rare_info := RareInfo.
ml_gen_info_set_tail_rec_info(X, !Info) :-
    RareInfo0 = !.Info ^ mgi_rare_info,
    RareInfo = RareInfo0 ^ mgri_tail_rec_info := X,
    !Info ^ mgi_rare_info := RareInfo.

ml_gen_info_set_byref_output_vars(X, !Info) :-
    SubInfo0 = !.Info ^ mgi_sub_info,
    ( if
        private_builtin.pointer_equal(X, SubInfo0 ^ mgsi_byref_output_vars)
    then
        true
    else
        SubInfo = SubInfo0 ^ mgsi_byref_output_vars := X,
        !Info ^ mgi_sub_info := SubInfo
    ).
ml_gen_info_set_label_counter(X, !Info) :-
    SubInfo0 = !.Info ^ mgi_sub_info,
    SubInfo = SubInfo0 ^ mgsi_label_counter := X,
    !Info ^ mgi_sub_info := SubInfo.
ml_gen_info_set_aux_var_counter(X, !Info) :-
    SubInfo0 = !.Info ^ mgi_sub_info,
    SubInfo = SubInfo0 ^ mgsi_aux_var_counter := X,
    !Info ^ mgi_sub_info := SubInfo.
ml_gen_info_set_cond_var_counter(X, !Info) :-
    SubInfo0 = !.Info ^ mgi_sub_info,
    SubInfo = SubInfo0 ^ mgsi_cond_var_counter := X,
    !Info ^ mgi_sub_info := SubInfo.
ml_gen_info_set_success_cont_stack(X, !Info) :-
    SubInfo0 = !.Info ^ mgi_sub_info,
    SubInfo = SubInfo0 ^ mgsi_success_cont_stack := X,
    !Info ^ mgi_sub_info := SubInfo.

%---------------------------------------------------------------------------%
:- end_module ml_backend.ml_gen_info.
%---------------------------------------------------------------------------%
