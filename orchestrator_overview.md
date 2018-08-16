% Orchestrator Overview
---
header-includes:
  - \usepackage{fullpage}
---

# Overview

This document defines the following, in a high-level way:

 - What the Orchestrator is, and its role in the POETS project ([Orchestrator
   Overview][])

 - Components of the Orchestrator, and their features

This document assumes that you have a working knowledge of:

 - The POETS project

 - The Message-Passing Interface (MPI,
   [https://www.mpi-forum.org/docs/](https://www.mpi-forum.org/docs/)).

This document does not explain:

 - The implementation of the Orchestrator, more than it needs to.

 - Development strategy and timelines.

# Too long, didn't read

- The Orchestrator is a middleware that interfaces between the Application
  Layer and the Engine Layer, and between the user and the Engine Layer.

- The Orchestrator allows tasks (contextless descriptions of applications) to
  be mapped onto the Engine, to start and stop tasks on the engine, to view the
  state of the Engine, and to retrieve results computed by the Engine.

# Orchestrator Introduction

## Motivating the Orchestrator

POETS consists of three layers. Here are two:

 - Application layer: The application is domain-specific problem (with
   context), which is to be solved on the POETS Engine. The role of the
   application layer is to translate the application into a task that can be
   easily understood by a computer. The application layer defines a task as a
   contextless graph of devices, where devices are unit of compute that can
   send signals to other devices in the graph to solve a problem.

 - Engine Layer: The highly-distributed hardware on which the application is
   solved. The POETS Engine (or just "Engine") has no idea about context. The
   engine layer consists of a POETS box, which contains some interconnected
   FPGA boards, and a "typical" x86 machine used to control them (termed a
   "Mothership").

With only these two layers, POETS still requires a way to map the task
(application layer) onto the hardware (Engine layer). POETS also lacks any way
for the user to start, stop, observe, get results from, or otherwise generally
interact with the Engine. Enter the Orchestrator!

## Features of the Orchestrator

The Orchestrator is a middleware that interfaces between the Application Layer
and the Engine Layer, and between the user and the Engine Layer. The core
responsibilities of the Orchestrator are:

 - To efficiently map the task (from the application layer) onto the Engine,
   and to deploy and "undeploy" tasks onto the Engine.

 - To allow the user to start and stop tasks running on the Engine.

 - To allow the user to view the current state of the Engine.

 - To allow the user to retrieve results computed by the Engine (as a set of
   files).

# Components of the Orchestrator

The Orchestrator consists of disparate components, which are logically arranged
to achieve the objectives of the Orchestrator as a whole, while maintaining a
sensible degree of modularity. These components are (numbers in parentheses
denote the corresponding section in the implementation documentation that
describes these components in more detail):

 - "Root" (4.2): While the Orchestrator is comprised of a series of modular
   components, the "Root" uses these components to achieve the features of the
   Orchestrator. Precisely, the Root component:

   - Can interface with a user, via a command prompt, or via batch commands.

   - Manages an internal model of the Engine (the "hardware graph" of how
     cores, threads, mailboxes, FPGA boards, and supervisors are
     connected). This is either achieved through prior knowledge, or through a
     dynamic hardware-discovery mechanism.

   - Can, on command, map a task onto the internal model of the Engine in an
     efficient manner (placement).

   - Can, on command, build binaries to be executed on the cores of the Engine,
     and to stage them for execution on those cores.

 - "LogServer" (4.4): The LogServer component records logging messages sent to
   it from other components, either for post-mortem purposes, or for elementary
   real-time system observation.

 - "RTCL" (4.5): Mark couldn't come up with an elegant explanation of what this
   is for. <!>

 - "Injector" (4.6): The Root component allows the Orchestrator to be
   controlled by a batch of commands. The Injector component is a developer
   tool that supports this functionality, but where the batch of commands is
   run in the context of the Orchestrator. This allows developers to "script"
   the behaviour of the Orchestrator in response to changes in the state of
   the Orchestrator, as opposed to a naive batch.

 - "NameServer" (4.7): In the Orchestrator, devices in the Engine are referred
   to by flat numeric addresses. The NameServer stores a mapping between these
   addresses, and colloquial, hierarchy-based device identifiers. User-facing
   components in the Orchestrator can query this component to determine a
   correct address for a packet they may wish to send. The NameServer also
   enables lookup in either direction.

All of these components exist as separate processes in the same MPI universe,
so that each component is able to communicate with each other component. All
components of the Orchestrator make use of the communications broken
"CommonBase" (see the implementation documentation).
