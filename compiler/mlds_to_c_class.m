%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 2018 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% Output the declarations and definitions of classes.
%
%---------------------------------------------------------------------------%

:- module ml_backend.mlds_to_c_class.
:- interface.

:- import_module ml_backend.mlds.
:- import_module ml_backend.mlds_to_c_util.
:- import_module ml_backend.mlds_to_target_util.

:- import_module io.

%---------------------------------------------------------------------------%

:- pred mlds_output_class_defn(mlds_to_c_opts::in, io.text_output_stream::in,
    indent::in, mlds_module_name::in, mlds_class_defn::in,
    io::di, io::uo) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module hlds.
:- import_module hlds.hlds_pred.         % for pred_proc_id.
:- import_module libs.
:- import_module libs.globals.
:- import_module ml_backend.ml_code_util.
:- import_module ml_backend.mlds_to_c_data.
:- import_module ml_backend.mlds_to_c_func.
:- import_module ml_backend.mlds_to_c_name.
:- import_module ml_backend.mlds_to_c_stmt.
:- import_module ml_backend.mlds_to_c_type.
:- import_module parse_tree.
:- import_module parse_tree.parse_tree_out_info.
:- import_module parse_tree.prog_data.

:- import_module bool.
:- import_module char.
:- import_module int.
:- import_module list.
:- import_module maybe.
:- import_module require.
:- import_module term.

%---------------------------------------------------------------------------%

:- pred mlds_output_class_decl_opts(mlds_to_c_opts::in,
    io.text_output_stream::in, indent::in, mlds_module_name::in,
    mlds_class_defn::in, io::di, io::uo) is det.
:- pragma consider_used(mlds_output_class_decl_opts/7).

mlds_output_class_decl_opts(Opts, Stream, Indent, ModuleName, ClassDefn, !IO) :-
    ClassDefn = mlds_class_defn(ClassName, Arity, Context, Flags, Kind,
        _Imports, _Inherits, _Implements,
        _TypeParams, _MemberFields, _MemberClasses, _MemberMethods, _Ctors),
    % ANSI C does not permit forward declarations of enumeration types.
    % So we just skip those. Currently they are not needed since we do not
    % actually use the enum types.
    ( if Kind = mlds_enum then
        true
    else
        c_output_context(Stream, Opts ^ m2co_line_numbers, Context, !IO),
        output_n_indents(Stream, Indent, !IO),
        mlds_output_class_decl_flags(Opts, Stream, Flags, forward_decl, !IO),
        mlds_output_class_decl(Stream, Indent, ModuleName, ClassName,
            Arity, ClassDefn, !IO),
        io.write_string(Stream, ";\n", !IO)
    ).

:- pred mlds_output_class_decl(io.text_output_stream::in, indent::in,
    mlds_module_name::in, mlds_class_name::in, arity::in, mlds_class_defn::in,
    io::di, io::uo) is det.

mlds_output_class_decl(Stream, _Indent, ModuleName, ClassName, Arity,
        ClassDefn, !IO) :-
    ClassKind = ClassDefn ^ mcd_kind,
    (
        ClassKind = mlds_enum,
        io.write_string(Stream, "enum ", !IO),
        output_qual_name_prefix_c(Stream, ModuleName, !IO),
        mlds_output_class_name_arity(Stream, ClassName, Arity, !IO),
        io.write_string(Stream, "_e", !IO)
    ;
        ( ClassKind = mlds_class
        ; ClassKind = mlds_interface
        ; ClassKind = mlds_struct
        ),
        io.write_string(Stream, "struct ", !IO),
        output_qual_name_prefix_c(Stream, ModuleName, !IO),
        mlds_output_class_name_arity(Stream, ClassName, Arity, !IO),
        io.write_string(Stream, "_s", !IO)
    ).

%---------------------------------------------------------------------------%

:- pred mlds_output_class_defns(mlds_to_c_opts::in, io.text_output_stream::in,
    indent::in, mlds_module_name::in, list(mlds_class_defn)::in,
    io::di, io::uo) is det.

mlds_output_class_defns(_, _, _, _, [], !IO).
mlds_output_class_defns(Opts, Stream, Indent, ModuleName,
        [ClassDefn | ClassDefns], !IO) :-
    mlds_output_class_defn(Opts, Stream, Indent, ModuleName, ClassDefn, !IO),
    mlds_output_class_defns(Opts, Stream, Indent, ModuleName, ClassDefns, !IO).

mlds_output_class_defn(Opts, Stream, Indent, ModuleName, ClassDefn, !IO) :-
    ClassDefn = mlds_class_defn(_ClassName, _Arity, Context, Flags, _Kind,
        _Imports, _Inherits, _Implements, _TypeParams,
        _MemberFields, _MemberClasses, _MemberMethods, _Ctors),
    io.nl(Stream, !IO),
    c_output_context(Stream, Opts ^ m2co_line_numbers, Context, !IO),
    output_n_indents(Stream, Indent, !IO),
    mlds_output_class_decl_flags(Opts, Stream, Flags, definition, !IO),
    mlds_output_class(Opts, Stream, Indent, ModuleName, ClassDefn, !IO).

%---------------------------------------------------------------------------%

:- pred mlds_output_class(mlds_to_c_opts::in, io.text_output_stream::in,
    indent::in, mlds_module_name::in, mlds_class_defn::in,
    io::di, io::uo) is det.

mlds_output_class(Opts, Stream, Indent, ModuleName, ClassDefn, !IO) :-
    ClassDefn = mlds_class_defn(ClassName, ClassArity, Context, _Flags,
        Kind, _Imports, Inherits, _Implements, _TypeParams,
        MemberFields, MemberClasses, MemberMethods, Ctors),
    expect(unify(MemberMethods, []), $pred,
        "MemberMethods != []"),

    % To avoid name clashes, we need to qualify the names of the member
    % constants with the class name. (In particular, this is needed for
    % enumeration constants and for the nested classes that we generate for
    % constructors of discriminated union types.) Here we compute the
    % appropriate qualifier.
    ClassModuleName = mlds_append_class_qualifier_module_qual(ModuleName,
        ClassName, ClassArity),

    % Hoist out static members, since plain old C does not support
    % static members in structs (except for enumeration constants).
    %
    % XXX This should be conditional: only when compiling to C,
    % not when compiling to C++.

    (
        Kind = mlds_enum,
        StaticCtors = [],
        StructCtors = Ctors,
        StaticMemberFields = [],
        StructMemberFields = MemberFields
    ;
        ( Kind = mlds_class
        ; Kind = mlds_interface
        ; Kind = mlds_struct
        ),
        list.filter(function_defn_is_static_member, Ctors,
            StaticCtors, NonStaticCtors),
        list.filter(field_var_defn_is_static_member, MemberFields,
            StaticMemberFields, NonStaticMemberFields),
        StructCtors = NonStaticCtors,
        StructMemberFields = NonStaticMemberFields
    ),

    % Convert the base classes into member variables,
    % since plain old C does not support base classes.
    %
    % XXX this should be conditional: only when compiling to C,
    % not when compiling to C++

    (
        Inherits = inherits_nothing,
        BaseFieldVarDefns = []
    ;
        Inherits = inherits_class(BaseClassId),
        BaseVarName = fvn_base_class(1),
        Type = mlds_class_type(BaseClassId),
        % We only need GC tracing code for top-level variables,
        % not for base classes.
        GCStmt = gc_no_stmt,
        BaseFieldVarDefns = [mlds_field_var_defn(BaseVarName, Context,
            ml_gen_public_field_decl_flags, Type, no_initializer, GCStmt)]
    ;
        Inherits = inherits_generic_env_ptr_type,
        % This should happen only if the target language requires
        % put_nondet_env_on_heap to be "yes"; for C, it should be "no".
        unexpected($pred, "inherits_generic_env_ptr_type")
    ),

    % Output the class declaration and the class members.
    % We treat enumerations specially.
    %
    % Note that standard ANSI/ISO C does not allow empty structs. We could
    % handle empty structs here, by adding a dummy member, but that would
    % waste a lot of space, and would also cause incompatibilities between
    % the data layout for --high-level-data and --no-high-level-data.
    % So instead, we make it is the responsibility of the MLDS code generator
    % to not generate any. (E.g. ml_type_gen.m checks whether
    % `target_uses_empty_base_classes' before generating empty structs.)
    % Hence we do not need to check for empty structs here.

    mlds_output_class_decl(Stream, Indent, ModuleName, ClassName, ClassArity,
        ClassDefn, !IO),
    io.write_string(Stream, " {\n", !IO),
    (
        Kind = mlds_enum,
        mlds_output_enum_constants(Opts, Stream, Indent + 1, ClassModuleName,
            BaseFieldVarDefns, !IO),
        mlds_output_enum_constants(Opts, Stream, Indent + 1, ClassModuleName,
            StructMemberFields, !IO)
    ;
        ( Kind = mlds_class
        ; Kind = mlds_interface
        ; Kind = mlds_struct
        ),
        % XXX Why don't we output all the field vars in one block?
        list.foldl(
            mlds_output_field_var_defn(Opts, Stream, Indent + 1, no,
                ClassModuleName),
            BaseFieldVarDefns, !IO),
        list.foldl(
            mlds_output_function_defn(Opts, Stream, Indent + 1,
                ClassModuleName),
            StructCtors, !IO),
        list.foldl(
            mlds_output_field_var_defn(Opts, Stream, Indent + 1, no,
                ClassModuleName),
            StructMemberFields, !IO)
    ),
    c_output_context(Stream, Opts ^ m2co_line_numbers, Context, !IO),
    output_n_indents(Stream, Indent, !IO),
    io.write_string(Stream, "};\n", !IO),
    mlds_output_function_defns(Opts, Stream, Indent, ClassModuleName,
        StaticCtors, !IO),
    mlds_output_field_var_defns(Opts, Stream, Indent, yes, ClassModuleName,
        StaticMemberFields, !IO),
    mlds_output_class_defns(Opts, Stream, Indent, ClassModuleName,
        MemberClasses, !IO).

%---------------------------------------------------------------------------%

:- pred function_defn_is_static_member(mlds_function_defn::in) is semidet.

function_defn_is_static_member(FuncDefn) :-
    FuncDefn ^ mfd_decl_flags ^ mfdf_per_instance = one_copy.

:- pred field_var_defn_is_static_member(mlds_field_var_defn::in) is semidet.

field_var_defn_is_static_member(FieldVarDefn) :-
    FieldVarDefn ^ mfvd_decl_flags ^ mfvdf_per_instance = one_copy.

%---------------------------------------------------------------------------%

:- pred mlds_output_field_var_decl(mlds_to_c_opts::in,
    io.text_output_stream::in, qual_field_var_name::in,
    mlds_type::in, initializer_array_size::in, io::di, io::uo) is det.

mlds_output_field_var_decl(Opts, Stream, FieldVarName, Type,
        InitializerSize, !IO) :-
    mlds_output_type_prefix(Opts, Stream, Type, !IO),
    io.write_char(Stream, ' ', !IO),
    mlds_output_fully_qualified_field_var_name(Stream, FieldVarName, !IO),
    mlds_output_type_suffix(Opts, Stream, Type, InitializerSize, !IO).

:- pred mlds_output_field_var_defns(mlds_to_c_opts::in,
    io.text_output_stream::in, indent::in, bool::in,
    mlds_module_name::in, list(mlds_field_var_defn)::in,
    io::di, io::uo) is det.

mlds_output_field_var_defns(_, _, _, _, _, [], !IO).
mlds_output_field_var_defns(Opts, Stream, Indent, Separate, ModuleName,
        [FieldVarDefn | FieldVarDefns], !IO) :-
    mlds_output_field_var_defn(Opts, Stream, Indent, Separate, ModuleName,
        FieldVarDefn, !IO),
    mlds_output_field_var_defns(Opts, Stream, Indent, Separate, ModuleName,
        FieldVarDefns, !IO).

:- pred mlds_output_field_var_defn(mlds_to_c_opts::in,
    io.text_output_stream::in, indent::in, bool::in,
    mlds_module_name::in, mlds_field_var_defn::in, io::di, io::uo) is det.

mlds_output_field_var_defn(Opts, Stream, Indent, Separate, ModuleName,
        FieldVarDefn, !IO) :-
    FieldVarDefn = mlds_field_var_defn(FieldVarName, Context, Flags,
        Type, Initializer, GCStmt),
    (
        Separate = yes,
        io.nl(Stream, !IO)
    ;
        Separate = no
    ),
    c_output_context(Stream, Opts ^ m2co_line_numbers, Context, !IO),
    output_n_indents(Stream, Indent, !IO),
    mlds_output_field_var_decl_flags(Opts, Stream, Flags, definition, !IO),
    QualFieldVarName =
        qual_field_var_name(ModuleName, module_qual, FieldVarName),
    mlds_output_field_var_decl(Opts, Stream, QualFieldVarName, Type,
        get_initializer_array_size(Initializer), !IO),
    mlds_output_initializer(Opts, Stream, Type, Initializer, !IO),
    io.write_string(Stream, ";\n", !IO),
    mlds_output_gc_statement(Opts, Stream, Indent, GCStmt, "", !IO).

%---------------------------------------------------------------------------%

    % Output the definitions of the enumeration constants
    % for an enumeration type.
    %
:- pred mlds_output_enum_constants(mlds_to_c_opts::in,
    io.text_output_stream::in, indent::in, mlds_module_name::in,
    list(mlds_field_var_defn)::in, io::di, io::uo) is det.

mlds_output_enum_constants(Opts, Stream, Indent, EnumModuleName,
        MemberFields, !IO) :-
    % Select the enumeration constants from the list of members
    % for this enumeration type, and output them.
    list.filter(field_var_defn_is_enum_const, MemberFields,
        EnumConstMemberFields),
    write_out_list(mlds_output_enum_constant(Opts, Indent, EnumModuleName),
        ",\n", EnumConstMemberFields, Stream, !IO),
    io.nl(Stream, !IO).

    % Output the definition of a single enumeration constant.
    %
:- pred mlds_output_enum_constant(mlds_to_c_opts::in, indent::in,
    mlds_module_name::in, mlds_field_var_defn::in,
    io.text_output_stream::in, io::di, io::uo) is det.

mlds_output_enum_constant(Opts, Indent, EnumModuleName, FieldVarDefn,
        Stream, !IO) :-
    FieldVarDefn = mlds_field_var_defn(FieldVarName, Context, _Flags,
        Type, Initializer, _GCStmt),
    c_output_context(Stream, Opts ^ m2co_line_numbers, Context, !IO),
    output_n_indents(Stream, Indent, !IO),
    QualFieldVarName =
        qual_field_var_name(EnumModuleName, type_qual, FieldVarName),
    mlds_output_fully_qualified_field_var_name(Stream, QualFieldVarName, !IO),
    mlds_output_initializer(Opts, Stream, Type, Initializer, !IO).

%---------------------------------------------------------------------------%

:- pred mlds_output_field_var_decl_flags(mlds_to_c_opts::in,
    io.text_output_stream::in, mlds_field_var_decl_flags::in,
    decl_or_defn::in, io::di, io::uo) is det.

mlds_output_field_var_decl_flags(Opts, Stream, Flags, DeclOrDefn, !IO) :-
    Constness = Flags ^ mfvdf_constness,
    Comments = Opts ^ m2co_auto_comments,
    (
        Comments = yes,
        % XXX We used to call mlds_output_extern_or_static
        % on mlds_data_decl_flags. This predicate pays attention to PerInstance
        % *only* when the access flag is acc_local, while field var's
        % access flags were always acc_public (which is why we do not need
        % to explicitly store that flag).
        PerInstance = Flags ^ mfvdf_per_instance,
        mlds_output_per_instance_comment(Stream, PerInstance, !IO)
    ;
        Comments = no
    ),
    (
        DeclOrDefn = forward_decl,
        io.write_string(Stream, "extern ", !IO)
    ;
        DeclOrDefn = definition
    ),
    mlds_output_constness(Stream, Constness, !IO).

:- pred mlds_output_class_decl_flags(mlds_to_c_opts::in,
    io.text_output_stream::in, mlds_class_decl_flags::in,
    decl_or_defn::in, io::di, io::uo) is det.

mlds_output_class_decl_flags(Opts, Stream, Flags, _DeclOrDefn, !IO) :-
    Flags = mlds_class_decl_flags(Access, Overridability, Constness),
    Comments = Opts ^ m2co_auto_comments,
    (
        Comments = yes,
        (
            Access = class_public,
            io.write_string(Stream, "/* public: */ ", !IO)
        ;
            Access = class_private,
            io.write_string(Stream, "/* private: */ ", !IO)
        ),
        io.write_string(Stream, "/* one_copy */ ", !IO)
    ;
        Comments = no
    ),
    (
        Overridability = overridable
    ;
        Overridability = sealed,
        io.write_string(Stream, "/* sealed */ ", !IO)
    ),
    mlds_output_constness(Stream, Constness, !IO).

:- pred mlds_output_per_instance_comment(io.text_output_stream::in,
    per_instance::in, io::di, io::uo) is det.

mlds_output_per_instance_comment(_, per_instance, !IO).
mlds_output_per_instance_comment(Stream, one_copy, !IO) :-
    io.write_string(Stream, "/* one_copy */ ", !IO).

:- pred mlds_output_constness(io.text_output_stream::in, constness::in,
    io::di, io::uo) is det.

mlds_output_constness(Stream, const, !IO) :-
    io.write_string(Stream, "const ", !IO).
mlds_output_constness(_, modifiable, !IO).

%---------------------------------------------------------------------------%
:- end_module ml_backend.mlds_to_c_class.
%---------------------------------------------------------------------------%
