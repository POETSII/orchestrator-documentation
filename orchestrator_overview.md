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

 - To allow the user to start and stop applications running on the Engine.

 - To allow the user to view the current state of the Engine.

 - To allow the user to retrieve results computed by the Engine (as a set of
   files).

# Components of the Orchestrator
