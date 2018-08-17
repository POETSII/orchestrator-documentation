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

In short, there should have been a Makefile provided in the source of the
Orchestrator you have obtained. As appropriate, you will need to define the
paths to your dependencies in the makefile.

When running the makefile (by commanding "Make" in your shell), if any warnings
are raised, please shout loudly at one of the maintainers.

# Usage

## Execution

## Overview of Simple Commands

## Usage Examples

# Further Reading

 - The implementation documentation, specifically Chapter 5 (Console
   Operation). Seriously, do read this.
