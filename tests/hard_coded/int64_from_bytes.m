%---------------------------------------------------------------------------%
% vim: ts=4 sw=4 et ft=mercury
%---------------------------------------------------------------------------%

:- module int64_from_bytes.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.

:- import_module int64.

main(!IO) :-
     Test1 = int64.from_bytes_le(0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0xffu8),
     io.write_line(Test1, !IO),
     Test2 = int64.from_bytes_le(0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0xffu8, 0x00u8),
     io.write_line(Test2, !IO),
     Test3 = int64.from_bytes_le(0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0xffu8, 0x00u8, 0x00u8),
     io.write_line(Test3, !IO),
     Test4 = int64.from_bytes_le(0x00u8, 0x00u8, 0x00u8, 0x00u8, 0xffu8, 0x00u8, 0x00u8, 0x00u8),
     io.write_line(Test4, !IO),
     Test5 = int64.from_bytes_le(0x00u8, 0x00u8, 0x00u8, 0xffu8, 0x00u8, 0x00u8, 0x00u8, 0x00u8),
     io.write_line(Test5, !IO),
     Test6 = int64.from_bytes_le(0x00u8, 0x00u8, 0xffu8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8),
     io.write_line(Test6, !IO),
     Test7 = int64.from_bytes_le(0x00u8, 0xffu8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8),
     io.write_line(Test7, !IO),
     Test8 = int64.from_bytes_le(0xffu8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8),
     io.write_line(Test8, !IO),

     Test9 = int64.from_bytes_be(0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0xffu8),
     io.write_line(Test9, !IO),
     Test10 = int64.from_bytes_be(0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0xffu8, 0x00u8),
     io.write_line(Test10, !IO),
     Test11 = int64.from_bytes_be(0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0xffu8, 0x00u8, 0x00u8),
     io.write_line(Test11, !IO),
     Test12 = int64.from_bytes_be(0x00u8, 0x00u8, 0x00u8, 0x00u8, 0xffu8, 0x00u8, 0x00u8, 0x00u8),
     io.write_line(Test12, !IO),
     Test13 = int64.from_bytes_be(0x00u8, 0x00u8, 0x00u8, 0xffu8, 0x00u8, 0x00u8, 0x00u8, 0x00u8),
     io.write_line(Test13, !IO),
     Test14 = int64.from_bytes_be(0x00u8, 0x00u8, 0xffu8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8),
     io.write_line(Test14, !IO),
     Test15 = int64.from_bytes_be(0x00u8, 0xffu8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8),
     io.write_line(Test15, !IO),
     Test16 = int64.from_bytes_be(0xffu8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8),
     io.write_line(Test16, !IO).
