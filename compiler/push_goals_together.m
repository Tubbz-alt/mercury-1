%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: push_goals_together.m.
% Main author: zs.
%
% The expensive goals in a procedure are not always in the same conjunction.
% However, in some cases, the procedure body can be tranformed to PUT them
% into the same conjunction, which can then be parallelised. This module
% performs that transformation.
%
%-----------------------------------------------------------------------------%

:- module transform_hlds.implicit_parallelism.push_goals_together.
:- interface.

:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module mdbcomp.feedback.
:- import_module mdbcomp.feedback.automatic_parallelism.

:- import_module list.

:- type push_result
    --->    push_failed
    ;       push_succeeded.

    % push_goals_in_proc(PushGoals, OverallResult, !ProcInfo, !ModuleInfo):
    %
    % Each PushGoal in PushGoals specifies a transformation that should bring
    % two or more expensive goals into the same conjunction. This predicate
    % attempts to perform each of those transformations. It returns
    % push_succeeded if they all worked, and push_failed if at least one
    % failed. This can happen because the program has changed since PushGoals
    % was computed and put into the feedback file, or because PushGoals is
    % invalid (regardless of the date of the file). One example of a validity
    % problem would be asking to push a goal into the condition of an
    % if-then-else.
    %
:- pred push_goals_in_proc(list(push_goal)::in, push_result::out,
    proc_info::in, proc_info::out, module_info::in, module_info::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.mode_util.
:- import_module hlds.goal_util.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_pred.
:- import_module hlds.hlds_rtti.
:- import_module hlds.quantification.
:- import_module mdbcomp.feedback.
:- import_module mdbcomp.feedback.automatic_parallelism.
:- import_module mdbcomp.program_representation.
:- import_module parse_tree.prog_data.

:- import_module assoc_list.
:- import_module int.
:- import_module list.
:- import_module map.
:- import_module pair.
:- import_module require.
:- import_module svmap.
:- import_module term.

%-----------------------------------------------------------------------------%

:- type push_info
    --->    push_info(
                pi_rtti_varmaps         ::  rtti_varmaps
            ).

push_goals_in_proc(PushGoals, OverallResult, !ProcInfo, !ModuleInfo) :-
    proc_info_get_goal(!.ProcInfo, Goal0),
    proc_info_get_varset(!.ProcInfo, VarSet0),
    proc_info_get_vartypes(!.ProcInfo, VarTypes0),
    proc_info_get_rtti_varmaps(!.ProcInfo, RttiVarMaps0),
    PushInfo = push_info(RttiVarMaps0),
    do_push_list(PushGoals, PushInfo, OverallResult, Goal0, Goal1),
    (
        OverallResult = push_failed
    ;
        OverallResult = push_succeeded,
        % We need to fix up the goal_infos by recalculating the nonlocal sets
        % and the instmap deltas of the compound goals.
        proc_info_get_headvars(!.ProcInfo, HeadVars),
        implicitly_quantify_clause_body_general(ordinary_nonlocals_no_lambda,
            HeadVars, _Warnings, Goal1, Goal2,
            VarSet0, VarSet, VarTypes0, VarTypes,
            RttiVarMaps0, RttiVarMaps),
        proc_info_get_initial_instmap(!.ProcInfo, !.ModuleInfo, InstMap0),
        proc_info_get_inst_varset(!.ProcInfo, InstVarSet),
        recompute_instmap_delta(do_not_recompute_atomic_instmap_deltas,
            Goal2, Goal, VarTypes, InstVarSet, InstMap0, !ModuleInfo),
        proc_info_set_goal(Goal, !ProcInfo),
        proc_info_set_varset(VarSet, !ProcInfo),
        proc_info_set_vartypes(VarTypes, !ProcInfo),
        proc_info_set_rtti_varmaps(RttiVarMaps, !ProcInfo)
    ).

%-----------------------------------------------------------------------------%

:- pred do_push_list(list(push_goal)::in, push_info::in,
    push_result::out, hlds_goal::in, hlds_goal::out) is det.

do_push_list([], _, push_succeeded, !Goal).
do_push_list([PushGoal | PushGoals], PushInfo, OverallResult, !Goal) :-
    do_one_push(PushGoal, PushInfo, Result, !Goal),
    (
        Result = push_succeeded,
        do_push_list(PushGoals, PushInfo, OverallResult, !Goal)
    ;
        Result = push_failed,
        OverallResult = push_failed
    ).

:- pred do_one_push(push_goal::in, push_info::in,
    push_result::out, hlds_goal::in, hlds_goal::out) is det.

do_one_push(PushGoal, PushInfo, Result, !Goal) :-
    PushGoal = push_goal(GoalPathStr, _Lo, _Hi, _PushedInto),
    ( goal_path_from_string(GoalPathStr, GoalPath) ->
        GoalPath = fgp(GoalPathSteps),
        do_push_in_goal(GoalPathSteps, PushGoal, PushInfo, Result, !Goal)
    ;
        Result = push_failed
    ).

%-----------------------------------------------------------------------------%

:- pred do_push_in_goal(list(goal_path_step)::in, push_goal::in, push_info::in,
    push_result::out, hlds_goal::in, hlds_goal::out) is det.

do_push_in_goal([], PushGoal, PushInfo, Result, !Goal) :-
    % We have arrives at the goal in which the push should take place.
    perform_push_transform(PushGoal, PushInfo, Result, !Goal).
do_push_in_goal([Step | Steps], PushGoal, PushInfo, Result, !Goal) :-
    !.Goal = hlds_goal(GoalExpr0, GoalInfo0),
    (
        Step = step_conj(N),
        ( GoalExpr0 = conj(ConjType, Goals0) ->
            do_push_in_goals(N, Steps, PushGoal, PushInfo, Result,
                Goals0, Goals),
            GoalExpr = conj(ConjType, Goals),
            !:Goal = hlds_goal(GoalExpr, GoalInfo0)
        ;
            Result = push_failed
        )
    ;
        Step = step_disj(N),
        ( GoalExpr0 = disj(Goals0) ->
            do_push_in_goals(N, Steps, PushGoal, PushInfo, Result,
                Goals0, Goals),
            GoalExpr = disj(Goals),
            !:Goal = hlds_goal(GoalExpr, GoalInfo0)
        ;
            Result = push_failed
        )
    ;
        Step = step_switch(N, _),
        ( GoalExpr0 = switch(Var, CanFail, Cases0) ->
            do_push_in_cases(N, Steps, PushGoal, PushInfo, Result,
                Cases0, Cases),
            GoalExpr = switch(Var, CanFail, Cases),
            !:Goal = hlds_goal(GoalExpr, GoalInfo0)
        ;
            Result = push_failed
        )
    ;
        Step = step_ite_cond,
        ( GoalExpr0 = if_then_else(Vars0, Cond0, Then0, Else0) ->
            do_push_in_goal(Steps, PushGoal, PushInfo, Result, Cond0, Cond),
            GoalExpr = if_then_else(Vars0, Cond, Then0, Else0),
            !:Goal = hlds_goal(GoalExpr, GoalInfo0)
        ;
            Result = push_failed
        )
    ;
        Step = step_ite_then,
        ( GoalExpr0 = if_then_else(Vars0, Cond0, Then0, Else0) ->
            do_push_in_goal(Steps, PushGoal, PushInfo, Result, Then0, Then),
            GoalExpr = if_then_else(Vars0, Cond0, Then, Else0),
            !:Goal = hlds_goal(GoalExpr, GoalInfo0)
        ;
            Result = push_failed
        )
    ;
        Step = step_ite_else,
        ( GoalExpr0 = if_then_else(Vars0, Cond0, Then0, Else0) ->
            do_push_in_goal(Steps, PushGoal, PushInfo, Result, Else0, Else),
            GoalExpr = if_then_else(Vars0, Cond0, Then0, Else),
            !:Goal = hlds_goal(GoalExpr, GoalInfo0)
        ;
            Result = push_failed
        )
    ;
        Step = step_neg,
        ( GoalExpr0 = negation(SubGoal0) ->
            do_push_in_goal(Steps, PushGoal, PushInfo, Result,
                SubGoal0, SubGoal),
            GoalExpr = negation(SubGoal),
            !:Goal = hlds_goal(GoalExpr, GoalInfo0)
        ;
            Result = push_failed
        )
    ;
        Step = step_scope(_),
        ( GoalExpr0 = scope(Reason, SubGoal0) ->
            do_push_in_goal(Steps, PushGoal, PushInfo, Result,
                SubGoal0, SubGoal),
            GoalExpr = scope(Reason, SubGoal),
            !:Goal = hlds_goal(GoalExpr, GoalInfo0)
        ;
            Result = push_failed
        )
    ;
        ( Step = step_lambda
        ; Step = step_try
        ; Step = step_atomic_main
        ; Step = step_atomic_orelse(_)
        ),
        % The constructs represented by these steps should have been
        % expanded out by now.
        Result = push_failed
    ).

:- pred do_push_in_goals(int::in, list(goal_path_step)::in, push_goal::in,
    push_info::in, push_result::out,
    list(hlds_goal)::in, list(hlds_goal)::out) is det.

do_push_in_goals(_N, _Steps, _PushGoal, _PushInfo, push_failed, [], []).
do_push_in_goals(N, Steps, PushGoal, PushInfo, Result,
        [Goal0 | Goals0], [Goal | Goals]) :-
    ( N = 1 ->
        do_push_in_goal(Steps, PushGoal, PushInfo, Result, Goal0, Goal),
        Goals = Goals0
    ;
        Goal = Goal0,
        do_push_in_goals(N - 1, Steps, PushGoal, PushInfo, Result,
            Goals0, Goals)
    ).

:- pred do_push_in_cases(int::in, list(goal_path_step)::in, push_goal::in,
    push_info::in, push_result::out, list(case)::in, list(case)::out) is det.

do_push_in_cases(_N, _Steps, _PushGoal, _PushInfo, push_failed, [], []).
do_push_in_cases(N, Steps, PushGoal, PushInfo, Result,
        [Case0 | Cases0], [Case | Cases]) :-
    ( N = 1 ->
        Case0 = case(MainConsId, OtherConsIds, Goal0),
        do_push_in_goal(Steps, PushGoal, PushInfo, Result, Goal0, Goal),
        Case = case(MainConsId, OtherConsIds, Goal),
        Cases = Cases0
    ;
        Case = Case0,
        do_push_in_cases(N - 1, Steps, PushGoal, PushInfo, Result,
            Cases0, Cases)
    ).

%-----------------------------------------------------------------------------%

:- pred perform_push_transform(push_goal::in, push_info::in,
    push_result::out, hlds_goal::in, hlds_goal::out) is det.

perform_push_transform(PushGoal, PushInfo, Result, !Goal) :-
    PushGoal = push_goal(GoalPathStr, Lo, Hi, PushedInto),
    goal_path_from_string_det(GoalPathStr, GoalPath),
    !.Goal = hlds_goal(GoalExpr0, GoalInfo0),
    (
        GoalExpr0 = conj(plain_conj, Conjuncts),
        find_lo_hi_goals(PushInfo, Conjuncts, Lo, Hi, 1, Before0, LoHi, After,
            pushable),
        find_relative_paths(GoalPath, PushedInto, RelGoalSteps),
        RelGoalSteps = [HeadRelGoalSteps | TailRelGoalSteps],
        HeadRelGoalSteps = [step_conj(PushConjNum) | HeadRestRelSteps],
        list.map(maybe_steps_after(step_conj(PushConjNum)),
            TailRelGoalSteps, TailRestRelSteps),
        list.index1(Before0, PushConjNum, PushIntoGoal0),
        push_into_goal(LoHi, HeadRestRelSteps, TailRestRelSteps,
            PushIntoGoal0, PushIntoGoal, pushable),
        % If PushConjNum specifies a conjunct that is NOT the last conjunct
        % before Lo, then this transformation reorders the code.
        % For now, we don't allow that.
        PushConjNum + 1 = Lo
    ->
        list.replace_nth_det(Before0, PushConjNum, PushIntoGoal, Before),
        GoalExpr = conj(plain_conj, Before ++ After),
        !:Goal = hlds_goal(GoalExpr, GoalInfo0),
        Result = push_succeeded
    ;
        Result = push_failed
    ).

%-----------------------------------------------------------------------------%

    % find_lo_hi_goals(PushInfo, Conjuncts, Lo, Hi, Cur, Before, LoHi, After,
    %   Pushable):
    %
    % Given a list of conjuncts in which the head conjunct (if it exists)
    % has index Cur, and a range of integers Lo..Hi, where Cur =< Lo,
    % return the list of conjuncts with indexes Lo..Hi in LoHi,
    % the conjuncts before them in Before, and the conjuncts after them
    % in After, PROVIDED that
    %   - conjuncts with indexes Lo..Hi actually exist, and
    %   - all those conjuncts are pushable.
    % If either of these conditions isn't met, return Pushable = not_pushable,
    % and garbage in Before, LoHi and After.
    %
:- pred find_lo_hi_goals(push_info::in, list(hlds_goal)::in, int::in, int::in,
    int::in, list(hlds_goal)::out, list(hlds_goal)::out, list(hlds_goal)::out,
    maybe_pushable::out) is det.

find_lo_hi_goals(PushInfo, Conjuncts, Lo, Hi, Cur, Before, LoHi, After,
        Pushable) :-
    ( Cur = Lo ->
        find_hi_goals(PushInfo, Conjuncts, Hi, Cur, LoHi, After, Pushable),
        Before = []
    ;
        (
            Conjuncts = [],
            Before = [],
            LoHi = [],
            After = [],
            Pushable = not_pushable
        ;
            Conjuncts = [Head | Tail],
            find_lo_hi_goals(PushInfo, Tail, Lo, Hi, Cur + 1,
                BeforeTail, LoHi, After, Pushable),
            Before = [Head | BeforeTail]
        )
    ).

    % find_hi_goals(PushInfo, Conjuncts, Hi, Cur, LoHi, After, Pushable):
    %
    % Given a list of conjuncts in which the head conjunct (if it exists)
    % has index Cur, and an integer Hi, where Cur =< Hi,
    % return the list of conjuncts with indexes up to Hi in LoHi,
    % and the conjuncts after them in After, PROVIDED that
    %   - conjuncts with indexes up to Hi actually exist, and
    %   - all those conjuncts are pushable.
    % If either of these conditions isn't met, return Pushable = not_pushable,
    % and garbage in LoHi and After.
    %
:- pred find_hi_goals(push_info::in, list(hlds_goal)::in, int::in, int::in,
    list(hlds_goal)::out, list(hlds_goal)::out, maybe_pushable::out) is det.

find_hi_goals(_PushInfo, [], _Hi, _Cur, [], [], not_pushable).
find_hi_goals(PushInfo, [Head | Tail], Hi, Cur, LoHi, After, Pushable) :-
    is_pushable_goal(PushInfo, Head, HeadPushable),
    (
        HeadPushable = pushable,
        ( Cur = Hi ->
            LoHi = [Head],
            After = Tail,
            Pushable = pushable
        ;
            find_hi_goals(PushInfo, Tail, Hi, Cur + 1, LoHiTail, After,
                Pushable),
            LoHi = [Head | LoHiTail]
        )
    ;
        HeadPushable = not_pushable,
        LoHi = [],
        After = [],
        Pushable = not_pushable
    ).

%-----------------------------------------------------------------------------%

:- type maybe_pushable
    --->    not_pushable
    ;       pushable.

    % Check whether pushing the given goal, which will require duplicating it,
    % would be ok, or whether it would cause problems by altering the
    % pushed-into goal's purity, by altering its determinism, or
    % by screwing up the compiler's record of existentially typed variables.
    %
:- pred is_pushable_goal(push_info::in, hlds_goal::in,
    maybe_pushable::out) is det.

is_pushable_goal(PushInfo, Goal, Pushable) :-
    Goal = hlds_goal(GoalExpr, GoalInfo),
    Purity = goal_info_get_purity(GoalInfo),
    Detism = goal_info_get_determinism(GoalInfo),
    (
        Purity = purity_pure,
        Detism = detism_det
    ->
        (
            GoalExpr = unify(_, _, _, Unification, _),
            (
                ( Unification = assign(_, _)
                ; Unification = simple_test(_, _)
                ; Unification = construct(_, _, _, _, _, _, _)
                ),
                Pushable = pushable
            ;
                Unification = deconstruct(_, _, Args, _, _, _),
                RttiVarMaps = PushInfo ^ pi_rtti_varmaps,
                % See the comment in move_follow_code_select in follow_code.m 
                % for the reason for this test.
                ( list.all_true(is_non_rtti_var(RttiVarMaps), Args) ->
                    Pushable = pushable
                ;
                    Pushable = not_pushable
                )
            ;
                Unification = complicated_unify(_, _, _),
                unexpected($module, $pred, "complicated_unify")
            )
        ;
            ( GoalExpr = plain_call(_, _, _, _, _, _)
            ; GoalExpr = generic_call(_, _, _, _)
            ; GoalExpr = call_foreign_proc(_, _, _, _, _, _, _)
            ),
            Pushable = pushable
        ;
            ( GoalExpr = conj(_, Goals)
            ; GoalExpr = disj(Goals)
            ),
            is_pushable_goal_list(PushInfo, Goals, Pushable)
        ;
            GoalExpr = switch(_, _, Cases),
            is_pushable_case_list(PushInfo, Cases, Pushable)
        ;
            GoalExpr = if_then_else(_, Cond, Then, Else),
            is_pushable_goal_list(PushInfo, [Cond, Then, Else], Pushable)
        ;
            ( GoalExpr = negation(SubGoal)
            ; GoalExpr = scope(_, SubGoal)
            ),
            is_pushable_goal(PushInfo, SubGoal, Pushable)
        ;
            GoalExpr = shorthand(Shorthand),
            (
                ( Shorthand = atomic_goal(_, _, _, _, _, _, _)
                ; Shorthand = try_goal(_, _, _)
                ),
                % May be too conservative, but better safe than sorry.
                Pushable = not_pushable
            ;
                Shorthand = bi_implication(_, _),
                unexpected($module, $pred, "bi_implication")
            )
        )
    ;
        Pushable = not_pushable
    ).

:- pred is_pushable_goal_list(push_info::in, list(hlds_goal)::in,
    maybe_pushable::out) is det.

is_pushable_goal_list(_PushInfo, [], pushable).
is_pushable_goal_list(PushInfo, [Goal | Goals], Pushable) :-
    is_pushable_goal(PushInfo, Goal, GoalPushable),
    (
        GoalPushable = not_pushable,
        Pushable = not_pushable
    ;
        GoalPushable = pushable,
        is_pushable_goal_list(PushInfo, Goals, Pushable)
    ).

:- pred is_pushable_case_list(push_info::in, list(case)::in,
    maybe_pushable::out) is det.

is_pushable_case_list(_PushInfo, [], pushable).
is_pushable_case_list(PushInfo, [Case | Cases], Pushable) :-
    Case = case(_MainConsId, _OtherConsIds, Goal),
    is_pushable_goal(PushInfo, Goal, GoalPushable),
    (
        GoalPushable = not_pushable,
        Pushable = not_pushable
    ;
        GoalPushable = pushable,
        is_pushable_case_list(PushInfo, Cases, Pushable)
    ).

:- pred is_non_rtti_var(rtti_varmaps::in, prog_var::in) is semidet.

is_non_rtti_var(RttiVarMaps, Arg) :-
    rtti_varmaps_var_info(RttiVarMaps, Arg, RttiVarInfo),
    RttiVarInfo = non_rtti_var.

%-----------------------------------------------------------------------------%

    % push_into_goal(LoHi, HeadSteps, TailSteps, Goal0, Goal, Pushable):
    %
    % Push the goals LoHi into Goal0, putting them at the ends of the
    % (possibly implicit) conjunctions holding the expensive goals indicated
    % by the goal paths [HeadSteps | TailSteps], which are all relative to
    % Goal0, and at the ends of the branches that are alternatives to these.
    %
    % Return Pushable = pushable if the transformation was successful.
    % Return Pushable = not_pushable and a garbage Goal if it wasn't.
    %
    % The returned goal will need to have its nonlocal sets and instmap deltas
    % recomputed.
    %
    % For example, if HeadSteps and TailSteps together specified the two
    % expensive goals in the original goal below,
    %
    %   ( Cond ->
    %       (
    %           X = f,
    %           EXPENSIVE GOAL 1,
    %           cheap goal 2
    %       ;
    %           X = g,
    %           cheap goal 3
    %       )
    %   ;
    %       EXPENSIVE GOAL 4
    %   )
    %
    % this predicate should return this transformed goal:
    %
    %   ( Cond ->
    %       (
    %           X = f,
    %           EXPENSIVE GOAL 1,
    %           cheap goal 2,
    %           LoHi
    %       ;
    %           X = g,
    %           cheap goal 3,
    %           LoHi
    %       )
    %   ;
    %       EXPENSIVE GOAL 4,
    %       LoHi
    %   )
    %
:- pred push_into_goal(list(hlds_goal)::in,
    list(goal_path_step)::in, list(list(goal_path_step))::in,
    hlds_goal::in, hlds_goal::out, maybe_pushable::out) is det.

push_into_goal(LoHi, HeadSteps, TailSteps, Goal0, Goal, Pushable) :-
    Goal0 = hlds_goal(GoalExpr0, GoalInfo0),
    (
        HeadSteps = [],
        expect(unify(TailSteps, []), $module, "TailSteps != []"),
        add_goals_at_end(LoHi, Goal0, Goal),
        Pushable = pushable
    ;
        HeadSteps = [FirstHeadStep | LaterHeadSteps],
        (
            ( GoalExpr0 = unify(_, _, _, _, _)
            ; GoalExpr0 = plain_call(_, _, _, _, _, _)
            ; GoalExpr0 = generic_call(_, _, _, _)
            ; GoalExpr0 = call_foreign_proc(_, _, _, _, _, _, _)
            ),
            Goal = Goal0,
            Pushable = not_pushable
        ;
            GoalExpr0 = conj(ConjType, Conjuncts0),
            (
                % If the expensive goal is a conjunct in this conjunction,
                % then put LoHi at the end of this conjunction.
                FirstHeadStep = step_conj(_),
                LaterHeadSteps = []
            ->
                expect(unify(TailSteps, []), $module, "TailSteps != []"),
                add_goals_at_end(LoHi, Goal0, Goal),
                Pushable = pushable
            ;
                % If the expensive goal or goals are INSIDE a conjunct
                % in this conjunction, push LoHi into the selected conjunct.
                % We insist on all expensive goals being inside the SAME
                % conjunct, because  pushing LoHi into more than one conjunct
                % would be a mode error.
                %
                FirstHeadStep = step_conj(ConjNum),
                list.map(maybe_steps_after(step_conj(ConjNum)), TailSteps,
                    LaterTailSteps),
                list.index1(Conjuncts0, ConjNum, SelectedConjunct0),

                % If ConjNum specifies a conjunct that is NOT the last
                % conjunct, then this transformation reorders the code.
                % For now, we don't allow that.
                %
                % However, we could also avoid reordering by removing
                % all the conjuncts after ConjNum from this conjunction,
                % and moving them to the front of LoHi.
                list.length(Conjuncts0, Length),
                ConjNum = Length
            ->
                push_into_goal(LoHi, LaterHeadSteps, LaterTailSteps,
                    SelectedConjunct0, SelectedConjunct, Pushable),
                list.replace_nth_det(Conjuncts0, ConjNum, SelectedConjunct,
                    Conjuncts),
                GoalExpr = conj(ConjType, Conjuncts),
                Goal = hlds_goal(GoalExpr, GoalInfo0)
            ;
                Goal = Goal0,
                Pushable = not_pushable
            )
        ;
            GoalExpr0 = disj(Disjuncts0),
            (
                build_disj_steps_map([HeadSteps | TailSteps], map.init,
                    StepMap)
            ->
                map.to_assoc_list(StepMap, StepList),
                push_into_disjuncts(LoHi, StepList, 1, Disjuncts0, Disjuncts,
                    Pushable),
                GoalExpr = disj(Disjuncts),
                Goal = hlds_goal(GoalExpr, GoalInfo0)
            ;
                Goal = Goal0,
                Pushable = not_pushable
            )
        ;
            GoalExpr0 = switch(Var, CanFail, Cases0),
            (
                build_switch_steps_map([HeadSteps | TailSteps], map.init,
                    StepMap)
            ->
                map.to_assoc_list(StepMap, StepList),
                push_into_cases(LoHi, StepList, 1, Cases0, Cases, Pushable),
                GoalExpr = switch(Var, CanFail, Cases),
                Goal = hlds_goal(GoalExpr, GoalInfo0)
            ;
                Goal = Goal0,
                Pushable = not_pushable
            )
        ;
            GoalExpr0 = if_then_else(Vars, Cond, Then0, Else0),
            (
                build_ite_steps_map([HeadSteps | TailSteps],
                    ThenSteps, ElseSteps)
            ->
                (
                    ThenSteps = [],
                    add_goals_at_end(LoHi, Then0, Then),
                    ThenPushable = pushable
                ;
                    ThenSteps = [ThenStepsHead | ThenStepsTail],
                    push_into_goal(LoHi, ThenStepsHead, ThenStepsTail,
                        Then0, Then, ThenPushable)
                ),
                (
                    ElseSteps = [],
                    add_goals_at_end(LoHi, Else0, Else),
                    ElsePushable = pushable
                ;
                    ElseSteps = [ElseStepsHead | ElseStepsTail],
                    push_into_goal(LoHi, ElseStepsHead, ElseStepsTail,
                        Else0, Else, ElsePushable)
                ),
                (
                    ThenPushable = pushable,
                    ElsePushable = pushable
                ->
                    GoalExpr = if_then_else(Vars, Cond, Then, Else),
                    Goal = hlds_goal(GoalExpr, GoalInfo0),
                    Pushable = pushable
                ;
                    Goal = Goal0,
                    Pushable = not_pushable
                )
            ;
                Goal = Goal0,
                Pushable = not_pushable
            )
        ;
            GoalExpr0 = negation(_SubGoal0),
            % Pushing goals into a negation changes the meaning of the program.
            Goal = Goal0,
            Pushable = not_pushable
        ;
            GoalExpr0 = scope(Reason, SubGoal0),
            SubGoal0 = hlds_goal(_SubGoalExpr0, SubGoalInfo0),
            Detism = goal_info_get_determinism(GoalInfo0),
            SubDetism = goal_info_get_determinism(SubGoalInfo0),
            (
                Detism = SubDetism,
                maybe_steps_after(step_scope(scope_is_no_cut),
                    HeadSteps, HeadStepsAfter),
                list.map(maybe_steps_after(step_scope(scope_is_no_cut)),
                    TailSteps, TailStepsAfter)
            ->
                push_into_goal(LoHi, HeadStepsAfter, TailStepsAfter,
                    SubGoal0, SubGoal, Pushable),
                GoalExpr = scope(Reason, SubGoal),
                Goal = hlds_goal(GoalExpr, GoalInfo0)
            ;
                Goal = Goal0,
                Pushable = not_pushable
            )
        ;
            GoalExpr0 = shorthand(Shorthand),
            (
                ( Shorthand = atomic_goal(_, _, _, _, _, _, _)
                ; Shorthand = try_goal(_, _, _)
                ),
                Goal = Goal0,
                Pushable = not_pushable
            ;
                Shorthand = bi_implication(_, _),
                unexpected($module, $pred, "bi_implication")
            )
        )
    ).

:- pred push_into_case(list(hlds_goal)::in,
    list(goal_path_step)::in, list(list(goal_path_step))::in,
    case::in, case::out, maybe_pushable::out) is det.

push_into_case(LoHi, HeadSteps, TailSteps, Case0, Case, Pushable) :-
    Case0 = case(MainConsId, OtherConsIds, Goal0),
    push_into_goal(LoHi, HeadSteps, TailSteps, Goal0, Goal, Pushable),
    Case = case(MainConsId, OtherConsIds, Goal).

:- pred push_into_disjuncts(list(hlds_goal)::in,
    assoc_list(int, one_or_more(list(goal_path_step)))::in,
    int::in, list(hlds_goal)::in, list(hlds_goal)::out, maybe_pushable::out)
    is det.

push_into_disjuncts(_LoHi, DisjStepList, _Cur, [], [], Pushable) :-
    (
        DisjStepList = [],
        Pushable = pushable
    ;
        DisjStepList = [_ | _],
        Pushable = not_pushable
    ).
push_into_disjuncts(LoHi, StepList, Cur, [HeadDisjunct0 | TailDisjuncts0],
        [HeadDisjunct | TailDisjuncts], Pushable) :-
    (
        StepList = [],
        add_goals_at_end(LoHi, HeadDisjunct0, HeadDisjunct),
        list.map(add_goals_at_end(LoHi), TailDisjuncts0, TailDisjuncts),
        Pushable = pushable
    ;
        StepList = [StepListHead | StepListTail],
        (
            StepListHead = StepListHeadNum - one_or_more(One, More),
            ( StepListHeadNum = Cur ->
                push_into_goal(LoHi, One, More, HeadDisjunct0, HeadDisjunct,
                    GoalPushable),
                (
                    GoalPushable = pushable,
                    push_into_disjuncts(LoHi, StepListTail, Cur + 1,
                        TailDisjuncts0, TailDisjuncts, Pushable)
                ;
                    GoalPushable = not_pushable,
                    TailDisjuncts = TailDisjuncts0,
                    Pushable = not_pushable
                )
            ;
                add_goals_at_end(LoHi, HeadDisjunct0, HeadDisjunct),
                push_into_disjuncts(LoHi, StepList, Cur + 1,
                    TailDisjuncts0, TailDisjuncts, Pushable)
            )
        )
    ).

:- pred push_into_cases(list(hlds_goal)::in,
    assoc_list(int, one_or_more(list(goal_path_step)))::in,
    int::in, list(case)::in, list(case)::out, maybe_pushable::out) is det.

push_into_cases(_LoHi, StepList, _Cur, [], [], Pushable) :-
    (
        StepList = [],
        Pushable = pushable
    ;
        StepList = [_ | _],
        Pushable = not_pushable
    ).
push_into_cases(LoHi, StepList, Cur, [HeadCase0 | TailCases0],
        [HeadCase | TailCases], Pushable) :-
    (
        StepList = [],
        add_goals_at_end_of_case(LoHi, HeadCase0, HeadCase),
        list.map(add_goals_at_end_of_case(LoHi), TailCases0, TailCases),
        Pushable = pushable
    ;
        StepList = [StepListHead | StepListTail],
        (
            StepListHead = StepListHeadNum - one_or_more(One, More),
            ( StepListHeadNum = Cur ->
                push_into_case(LoHi, One, More, HeadCase0, HeadCase,
                    GoalPushable),
                (
                    GoalPushable = pushable,
                    push_into_cases(LoHi, StepListTail, Cur + 1,
                        TailCases0, TailCases, Pushable)
                ;
                    GoalPushable = not_pushable,
                    TailCases = TailCases0,
                    Pushable = not_pushable
                )
            ;
                add_goals_at_end_of_case(LoHi, HeadCase0, HeadCase),
                push_into_cases(LoHi, StepList, Cur + 1,
                    TailCases0, TailCases, Pushable)
            )
        )
    ).

%-----------------------------------------------------------------------------%

:- pred build_disj_steps_map(list(list(goal_path_step))::in,
    map(int, one_or_more(list(goal_path_step)))::in,
    map(int, one_or_more(list(goal_path_step)))::out) is semidet.

build_disj_steps_map([], !DisjStepMap).
build_disj_steps_map([Head | Tail], !DisjStepMap) :-
    Head = [step_disj(N) | HeadSteps],
    ( map.search(!.DisjStepMap, N, one_or_more(One, More)) ->
        svmap.det_update(N, one_or_more(HeadSteps, [One | More]), !DisjStepMap)
    ;
        svmap.det_insert(N, one_or_more(HeadSteps, []), !DisjStepMap)
    ),
    build_disj_steps_map(Tail, !DisjStepMap).

:- pred build_switch_steps_map(list(list(goal_path_step))::in,
    map(int, one_or_more(list(goal_path_step)))::in,
    map(int, one_or_more(list(goal_path_step)))::out) is semidet.

build_switch_steps_map([], !DisjStepMap).
build_switch_steps_map([Head | Tail], !DisjStepMap) :-
    Head = [step_switch(N, _) | HeadSteps],
    ( map.search(!.DisjStepMap, N, one_or_more(One, More)) ->
        svmap.det_update(N, one_or_more(HeadSteps, [One | More]), !DisjStepMap)
    ;
        svmap.det_insert(N, one_or_more(HeadSteps, []), !DisjStepMap)
    ),
    build_switch_steps_map(Tail, !DisjStepMap).

:- pred build_ite_steps_map(list(list(goal_path_step))::in,
    list(list(goal_path_step))::out, list(list(goal_path_step))::out)
    is semidet.

build_ite_steps_map([], [], []).
build_ite_steps_map([Head | Tail], ThenSteps, ElseSteps) :-
    build_ite_steps_map(Tail, ThenStepsTail, ElseStepsTail),
    Head = [HeadFirstStep | HeadSteps],
    ( HeadFirstStep = step_ite_then ->
        ThenSteps = [HeadSteps | ThenStepsTail],
        ElseSteps = ElseStepsTail
    ; HeadFirstStep = step_ite_then ->
        ThenSteps = ThenStepsTail,
        ElseSteps = [HeadSteps | ElseStepsTail]
    ;
        fail
    ).

%-----------------------------------------------------------------------------%

:- pred add_goals_at_end(list(hlds_goal)::in, hlds_goal::in, hlds_goal::out)
    is det.

add_goals_at_end(AddedGoals, Goal0, Goal) :-
    Goal0 = hlds_goal(GoalExpr0, _GoalInfo0),
    ( GoalExpr0 = conj(plain_conj, Conjuncts0) ->
        create_conj_from_list(Conjuncts0 ++ AddedGoals, plain_conj, Goal)
    ;
        create_conj_from_list([Goal0 | AddedGoals], plain_conj, Goal)
    ).

:- pred add_goals_at_end_of_case(list(hlds_goal)::in, case::in, case::out)
    is det.

add_goals_at_end_of_case(AddedGoals, Case0, Case) :-
    Case0 = case(MainConsId, OtherConsIds, Goal0),
    add_goals_at_end(AddedGoals, Goal0, Goal),
    Case = case(MainConsId, OtherConsIds, Goal).

%-----------------------------------------------------------------------------%

:- pred find_relative_paths(forward_goal_path::in, list(goal_path_string)::in,
    list(list(goal_path_step))::out) is semidet.

find_relative_paths(_GoalPath, [], []).
find_relative_paths(GoalPath, [HeadStr | TailStrs],
        [HeadRelSteps | TailRelSteps]) :-
    goal_path_from_string(HeadStr, HeadGoalPath),
    GoalPath = fgp(GoalPathSteps),
    HeadGoalPath = fgp(HeadGoalPathSteps),
    list.append(GoalPathSteps, HeadRelSteps, HeadGoalPathSteps),
    find_relative_paths(GoalPath, TailStrs, TailRelSteps).

:- pred maybe_steps_after(goal_path_step::in,
    list(goal_path_step)::in, list(goal_path_step)::out) is semidet.

maybe_steps_after(Step, [Step | Tail], Tail).

%-----------------------------------------------------------------------------%

:- type one_or_more(T)
    --->    one_or_more(T, list(T)).

%-----------------------------------------------------------------------------%
