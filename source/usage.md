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

 - Qt (>5, =<5.6). This is used by the XML parser, and will eventually
   disappear from this list of requirements.

 - Tinsel (https://github.com/poetsii/tinsel).

 - QuartusPro, which Mark doesn't know anything about <!>.

There may be more dependencies.

## Building

### With Make

In short, there should have been a Makefile provided in the source of the
Orchestrator you have obtained. As appropriate, you will need to define the
paths to your dependencies in the makefile.

When running the makefile (by commanding "Make" in your shell), if any warnings
are raised, please shout loudly at one of the maintainers.

The build process creates a series of disparate executables in the `bin`
directory.

### Without Make

Perhaps ADB can weigh in here.

# Usage

## Execution

The Orchestrator is comprised of a series of disparate components (see
Orchestrator Overview). Each of these components is built into a separate
binary. To execute these binaries so that they can communicate with each other
using MPI, you will need to use the MIMD syntax (look at the man page for your
MPI distribution). By way of example, using mpich, command:

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

## Overview of Simple Commands

# Further Reading

 - The implementation documentation, specifically Chapter 5 (Console
   Operation). Seriously, do read this.
