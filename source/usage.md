% Orchestrator Usage

# Overview

This document acts as a walkthrough for getting the Orchestrator
running. Prerequisite reading:

 - Orchestrator Overview (in this repository)

This document explains basic Orchestrator operation, given that you have the
sources. It also describes compilation and execution on a rudimentary
level. This document does not:

 - Explain what components of the Orchestrator that each command communicates
   with.

 - Provide an exhaustive list of commands.

# Building the Orchestrator

The only way to use the Orchestrator is to build it from its sources.

## System Requirements

In order to compile the Orchestrator, you will need:

 - A C++ compiler. We aim to support as wide a range of compilers as is
   reasonably possible. The Orchestrator is written to use the C++98 standard.

 - An implementation of the MPI-3 standard (Message Passing Interface). This is
   used to connect the Orchestrator components together. Mark uses mpich 3.2.1.

 - Qt (5.6). This is used by the XML parser, and will eventually
   disappear from this list of requirements.

 - Tinsel (from https://github.com/poetsii/tinsel).

 - QuartusPro, which Mark doesn't know much about <!>.

There may be more dependencies.

## Building

### With Make

In short, there should have been a Makefile provided in the source of the
Orchestrator you have obtained. As appropriate, you will need to define the
paths to your dependencies in the makefile. When running the makefile (by
commanding `make` in your shell), if any warnings are raised, please shout
loudly at one of the maintainers. The build process creates a series of
disparate executables in the `bin` directory.

### Without Make

Perhaps ADB can weigh in here.

# Usage

## Execution

The Orchestrator is comprised of a series of disparate components (see
Orchestrator Overview). Each of these components is built into a separate
binary. To execute these binaries so that they can communicate with each other
using MPI, you will need to use the MIMD syntax (look at the man page for your
MPI distribution). By way of example, using mpich, command:

    # NB: The backslash (\) is a linebreak, and is not essential.

    mpirun ./orchestrator : ./logserver : ./rtcl : ./injector :\
           ./nameserver : ./supervisor : ./mothership

The order of executables doesn't matter, save for the `orchestrator`
executable, which must be first (corresponding to MPI rank zero). Each
executable should be run with a single process (hence the lack of the typical
`-n` flag).

Once executed, the Orchestrator states something to the effect of:

    Attach debugger to Root process 0 (0).....

which pauses execution of the Orchestrator, and invites you to connect a
debugging process, using your debugger of choice, to the process you created in
the execution step. Whether or not you attach a debugger, enter a newline
character into your shell to continue execution.

You will then reach the Orchestrator prompt:

    POETS>

at which commands can be executed. See Usage Examples for what to do from
here. Once you are finished with your Orchestrator session, command

    exit

then hit any key to end the Orchestrator process. Note that this will
effectively disown any jobs running on the Engine, so you will be unable to
reconnect to any jobs started in this way.

## Usage Examples

Here are some common usage examples of the Orchestrator. The individual
commands are more fully described in the implementation documentation.

### Verifying all Orchestrator Components are Loaded

Once built, you may wish to verify that the components of the Orchestrator have
been started correctly, and can be communicated with. In the `POETS>` prompt,
command:

    system \show

which will print something like:

    Processes for comm 0
    Rank 00,            Root:OrchBase:CommonBase, created 12:05:16 Aug  8 2018
    Rank 02,                     RTCL:CommonBase, created 12:05:16 Aug  8 2018
    Rank 01,                LogServer:CommonBase, created 12:05:16 Aug  8 2018

In this case, the Root, RTCL, and LogServer components of the Orchestrator have
been started.

### Loading a task (XML)

In order to perform compute tasks on POETS using the Orchestrator, a task
(graph, XML) must first be loaded. At the `POETS>` prompt, command:

    task /load = /path/to/the/task/graph.xml

or alternatively,

    task /path = /path/to/the/task/
    task /load = graph.xml

Note that you may need to double-quote your path. Verify your task is loaded
correctly with

    task /show

### We need more examples! Any ideas? <!>

# Further Reading

 - The implementation documentation, specifically Chapter 5 (Console
   Operation). Seriously, do read this.
