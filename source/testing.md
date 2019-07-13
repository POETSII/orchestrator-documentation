% Orchestrator Testing Infrastructure

# Overview

The Orchestrator, at its simplest, is an interface between the application
writer and the compute hardware. System-level testing is not yet implemented,
but some unit tests are beginning to emerge for certain components.

# Unit Testing

Various components of the Orchestrator, including the hardware model items and
the hardware description file reader, are supported by a suite of unit tests in
the `Tests` directory of the Orchestrator repository. These unit tests are
driven by the Catch2 (1.x, classic) testing framework, described by the file
`Tests/catch.hpp`. The tests can be built using GCC in a similar manner to the
Orchestrator build process, by commanding `make tests`. This will compile the
source with debugging symbols, allowing for the developer to "gdb in".

Each file in `Tests/*.cpp` produces a file once compiled with the Catch2
header. These files can be executed to determine whether or not the source
functions as intended, along with output describing what went wrong. Each test
can also be run with a memory checker (I use Valgrind) to verify the integrity
of the structures under test. For example, if the hardware model tests
(Tests/TestHardwareModel.cpp) are compiled and run, and all pass, something
like the following is printed to the standard output (JUnit output can also be
produced for CI):

```
$ ./TestHardwareModel.test
===============================================================================
All tests passed (67 assertions in 18 test cases)
```

Or, with Valgrind, something like (this is good output):

```
$ valgrind --track-origins=yes --leak-check=full ./TestHardwareModel.test
==20767== Memcheck, a memory error detector
==20767== Copyright (C) 2002-2017, and GNU GPL'd, by Julian Seward et al.
==20767== Using Valgrind-3.14.0 and LibVEX; rerun with -h for copyright info
==20767== Command: ./TestHardwareModel.test
==20767==
===============================================================================
All tests passed (67 assertions in 18 test cases)

==20767==
==20767== HEAP SUMMARY:
==20767==     in use at exit: 18,572 bytes in 6 blocks
==20767==   total heap usage: 1,474 allocs, 1,468 frees, 230,292 bytes allocated
==20767==
==20767== LEAK SUMMARY:
==20767==    definitely lost: 0 bytes in 0 blocks
==20767==    indirectly lost: 0 bytes in 0 blocks
==20767==      possibly lost: 0 bytes in 0 blocks
==20767==    still reachable: 18,572 bytes in 6 blocks
==20767==         suppressed: 0 bytes in 0 blocks
==20767== Reachable blocks (those to which a pointer was found) are not shown.
==20767== To see them, rerun with: --leak-check=full --show-leak-kinds=all
==20767==
==20767== For counts of detected and suppressed errors, rerun with: -v
==20767== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)
```

The `make tests` build process also creates a GNU Linux Bash test script,
`run-tests.sh`, which runs all tests, points a memory checker at them, and
writes information to various files.
