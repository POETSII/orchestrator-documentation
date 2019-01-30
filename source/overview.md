% Orchestrator Overview

# Overview

This document assumes that you have a working knowledge of the POETS project,
and defines the following in a high-level way:

 - What the Orchestrator is, and its role in the POETS project ([Orchestrator
   Introduction][]).

 - Components of the Orchestrator, and their features ([Components of the
   Orchestrator][]).

This document does not explain:

 - The implementation of the Orchestrator in detail. This can be found in the
   implementation documentation (big Word document).

 - Development strategy and timelines.

# Orchestrator Introduction

## Motivating the Orchestrator

Figure 1 (left) shows the POETS stack; POETS consists of major three layers,
one of which is the Orchestrator. Here are the other two:

 - Application Layer: The application is domain-specific problem (with
   context), which is to be solved on the POETS Engine. The role of the
   Application Layer is provide an interface for the user to translate their
   problem into a task, which is a contextless graph of connected
   devices. These devices are units of compute that can send signals to other
   devices in the graph to solve a problem.

 - Engine Layer: The highly-distributed hardware on which the application is
   solved. The POETS Engine (or just "Engine") has no idea about context. The
   Engine Layer consists of a POETS box, which contains some interconnected
   FPGA boards, and an x86 machine used to control them (termed a
   "Mothership"). Hostlink exists as an API for the Engine.

With only these two layers, POETS still requires a way to map the task
(Application Layer) onto the hardware (Engine Layer). POETS also lacks any way
for the user to start, stop, observe, get results from, or otherwise generally
interact with the Engine during operation. Enter the Orchestrator!

## Features of the Orchestrator

The Orchestrator is a middleware that interfaces between the Application Layer
and the Engine Layer, and between the user and the Engine Layer. The core
responsibilities of the Orchestrator are:

 - To load and manage tasks passed in from the application layer.

 - To identify the Engine it is operating on.

 - To efficiently map the task (from the application layer) onto the Engine.

 - To deploy and "undeploy" tasks onto the Engine.

 - To allow the user to start and stop tasks running on the Engine.

 - To allow the user to view the current state of the Engine.

 - To allow the user to retrieve results computed by the Engine.

Figure 1 (right) shows how the layers of POETS interact to deliver on these
features.

![Layers in the POETS stack](images/stack.png "The POETS Stack"){width=40%}
\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ ![How the Orchestrator
interacts with those layers](images/orchestrator_interaction.png "How the
Orchestrator interacts with the POETS Stack"){width=40%}
\begin{figure}
\caption{Left: Layers in the POETS stack. Right: How the Orchestrator interacts
with those layers to achieve its objectives}
\end{figure}

# Components of the Orchestrator

The Orchestrator consists of disparate components, which are logically arranged
to achieve the objectives of the Orchestrator as a whole, while maintaining a
sensible degree of modularity. These components are as follows:

 - "Root": While the Orchestrator is comprised of a series of modular
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

 - "LogServer": The LogServer component records logging messages sent to it
   from other components, either for post-mortem purposes, or for elementary
   real-time system observation.

 - "RTCL": The "Real-Time Clock" component manages an internal clock. A unit of
   functionality of this clock is to support a rudimentary "delay" command,
   which can be used as part of a command batch. This allows the user to stage
   a series of packets to be added to the Engine at a given time, to support
   controlled "bursts" of activity.

 - "Injector": The Root component allows the Orchestrator to be controlled by a
   batch of commands. The Injector component is a developer tool that supports
   this functionality, but where the batch of commands is run in the context of
   the Orchestrator. This allows developers to "script" the behaviour of the
   Orchestrator in response to changes in the state of the Orchestrator, as
   opposed to a naive batch.

 - "NameServer": In the Orchestrator, devices in the Engine are referred to by
   flat numeric addresses. The NameServer stores a mapping between these
   addresses, and colloquial, hierarchy-based device identifiers. User-facing
   components in the Orchestrator can query this component to determine a
   correct address for a packet they may wish to send. The NameServer also
   enables lookup in either direction.

 - "Monitor": The Monitor component displays information about the current
   activity of the Engine, and other useful details from the Orchestrator.

 - "User Input and User Output": The User Input component handles inputs from
   the application frontend, by translating them into instructions (messages)
   for other components to execute. The User Output component handles messages
   from components to be displayed in the application frontend.

 - "Mothership": The Orchestrator plays host to a number of mothership
   processes, which must operate on the various boxes of the Engine. The
   Mothership process is primarily responsible for managing communications
   between the Orchestrator processes (MPI), and the hardware (packets), and
   for loading and unloading of binaries passed to it from the Root process.

All of these components exist as separate processes in the same MPI
(Message-Passing Interface,
[https://www.mpi-forum.org/docs/](https://www.mpi-forum.org/docs/)) universe,
so that each component is able to communicate with each other component. A
fully-functioning Orchestrator must have exactly one running instance of each
of these component processes. All components of the Orchestrator make use of
the communications broker "CommonBase" (see the implementation documentation).

## The Supervisor

The Supervisor^[Note that "Supervisor" in the context of POETS is not related
to supervisors in the context of UNIX-likes; the concepts are completely
different.] (3.3) is one further component of the Orchestrator, but is unique
in that it must execute on a POETS box, as part of the Mothership. The
Supervisor is uniquely positioned at interface between the message-based (MPI)
communication of the Orchestrator, and the packet-based communication of the
Engine. Due to this positioning, the primary purpose of the Supervisor is to
broker communication over this interface. This purpose enables the Supervisor
to conduct its responsibilities, which are:

 - Input targetted data into the Engine (on the POETS box the Supervisor is
   running on).

 - Collect data from the Engine (on the POETS box the Supervisor is running on)
   requested by another component of the Orchestrator, or the user.

Note that an Orchestrator can contain multiple Supervisors in Engines with
multiple POETS boxes.

### Supervisor-Device Duality

While a Supervisor is a component of the Orchestrator (reachable by messages
from the Orchestrator), a Supervisor is also a device in the Engine (reachable
by packets from the Engine). Unlike other devices:

 - Supervisors cannot be explicitly defined in a task graph (Application
   Layer), as they are "added" to the graph while the Orchestrator processes
   it.

 - On the task graph, Supervisors are always connected to all devices that are
   mapped inside the box it is supervising, by one input edge and one output
   edge.

As a device, Supervisors can be provisioned with application-specific packet
handlers.

# Key Points

- The Orchestrator is a middleware that interfaces between the Application
  Layer and the Engine Layer, and between the user and the Engine Layer.

- The Orchestrator allows tasks (contextless descriptions of applications) to
  be mapped onto the Engine, to start and stop tasks on the engine, to view the
  state of the Engine, and to retrieve results computed by the Engine.

- The Orchestrator is a modular system; it is divided into a series of
  components each responsible for a unit of functionality.

- Supervisors are components of the Orchestrator that exist at the interface
  between the Orchestartor and the Engine.

# Further Reading

 - The implementation documentation (big Word document). Seriously, do read
   this.

 - Orchestrator Usage (in this repository).
