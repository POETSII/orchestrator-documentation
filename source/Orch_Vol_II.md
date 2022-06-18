% Orchestrator Documentation Volume II: Application Definition
\thispagestyle{fancy}

# Introduction

The "big picture" of the design intention and capabilities of a POETS system is
provided in Volume I of the Orchestrator documentation. This document describes
the practical details of preparing a POETS application. The middleware used to
control the system is known as the Orchestrator, and the command portfolio
supported by the Orchestrator, which allows applications to be loaded, is
described in the User Guide (Volume IV). The (developer facing) internals
details are described in Volume III.

Recall that the central idea of POETS is that it is capable of delivering
orders of magnitude wallclock speedup for certain classes of problems. It does
nothing, in principle, that cannot be done by a single-thread equivalent
process. **As with anything, if the system is taken outside its intended design
envelope, the behaviour may degrade to the point that it is slower than a
conventional counterpart.**

The target audience for this document is the developers of domain-specific
applications and front ends, who are already sympathetic to the motivation
behind POETS. That said, getting the best from the system involves a complex -
and possibly counter intuitive - operating protocol and application definition.

---

The first few sections of this document explain the basis of event-based
processing as implemented by POETS. They explain *why* the steps outlined in
subsequent sections are necessary and *how* they interact. If you are already
comfortable with this rationale, you can skip to the Application Language
Section, which describes the details of application definition minutiae at the
syntactic level if that's all you need. If you prefer to learn by example, and
to follow concepts as they are introduced, you can skip to the "Example: Ring
Test" section, and search the document for more information on concepts as they
are introduced.

---

## Disambiguation

A historical mismatch in terminology: From the developer point of view, the
POETS-Orchestrator system consists of two networks: the MPI 'conventional'
network, where the processes execute on conventional X86 architectures, and the
POETS network, where the devices communicate via the bespoke hardware network.

MPI processes communicate with arbitrarily sized **messages**, and POETS
devices communicate via fixed size **packets**.

Parallel development and poor management combine to get us into a situation
where the definition of a packet from the application writer's perspective is
called a **MessageType**, and the packet itself is sometimes called a
message. It's too embedded to change now.

In the Concepts and Architectural Concerns Section, packets are called packets,
but in the XML fragments provided as examples, and in the description of the
application language (XML), they are messages. It's usually obvious from
context what is being referred to.

# Concepts and Architectural Concerns

## Event Based Compute in the Abstract

This Section describes the POETS perspective of event-based processing, the
assumed knowledge base of the reader, and the system itself, again from the
perspective of an application writer creating an application for use on the
POETS hardware. Assumed knowledge includes C++ and the notion of classes and
data/method encapsulation.

### The Idealisation

Event-based computing is appropriate for problems that can be decomposed into a
discrete mesh. This often manifests as a spatial discretisation[^dis], though
any domain that **remains constant with respect to the execution of the
application** is suitable.

In the abstract, a POETS **application** is a directed graph[^formal]. Figure 1
shows an example of this, where:

[^dis]: For example, finite-difference or finite-element schemes where space is
    tiled (sometimes irregularly), in order to "break up" computation.

[^formal]: Formally, application graphs are tripartite directed graphs, which
    may contain loops, disconnected regions, and isolated vertices. The three
    independent sets of nodes consist of the "major" set as "the set of normal
    devices", the "minor input" as "the set of input pins", and the "minor
    output" set as "the set of output pins". For brevity, we define the union
    of the minor input and minor output sets as the "minor" set, which holds
    all pins. When we refer to the edges of the application graph, we intend
    only the edges that connect elements of the minor set together.

 - The major set of nodes (hollow black circles) represent "Devices", which
   each capture the behaviour of a node in the discretised problem. A device
   could represent a vertex in the finite-difference mesh, an element in a
   finite-element discretisation, or even a collection of vertices or elements.

 - The set of edges (black arrows) capture a "communication mode" between two
   devices. Devices communicate between themselves, using application-defined
   behaviour, by sending **packets** along these edges.

 - The minor set of nodes (hollow red circles and filled red circles) represent
   "Pins". Input pins alter the behaviour of messages sent along the edges
   associated with them, which is useful to assign "weights" to communications
   along an edge. Each edge is associated with one input pin and one output
   pin. Each input/output pin can have multiple input/output edges connected
   to/from it.

![Typed graph components. A graph representation of an application. Computation
is performed by "Normal Devices", and communication is facilitated by "Pins"
and "Edges".](images/app_concepts/app_concepts_01.pdf)

When a packet arrives at an input pin, a **behaviour** is invoked. This has
visibility of:

 - The packet content.
 - The state of the input pin.
 - The state of the device that owns the pin.

These behaviours are defined as part of the application, by the application
writer. It may (or may not):

 - Alter the state of the device/pins.
 - Cause output pin(s) on the device to emit packets of their own.

Different output pins may emit different packets, but a packet sent from an
output pin will be *copied* to all the edges attached to that pin. The intended
operational envelope for POETS assumes that[^limits]:

 - There are a **large** number ($\mathcal{O}$(millions)) of devices, but
   $<2^{32}$.
 - Their **logic** - application-writer-defined C++ code - is simple and short.
 - Communication between them is brokered by **small** fixed size (64 byte)
   packets.
 - The devices, pins, and packets are strongly typed, and there are a low
   number ($<100$) of distinct types.
 - There are $\le32$ output pins, and $\le256$ input pins, on a device.
 - There are $<2^{24}$ edges on an individual input pin, and $<2^{32}$ edges in
   total.

[^limits]: Limits on the numbers of devices, types, and pins are
    Orchestrator-enforced.

### Temporal Idiosyncrasies

Building on the abstraction described in the previous Section, here we allow
physical limitations to impact on the progress of the application.

#### Network Congestion and Pushback

The physical realisation of the underlying hardware communications network is
almost completely hidden from the user, but it is a physical entity and finite
in size (albeit extremely large). It is possibly helpful to think of it as a
large (but finite) communication pool, in the CSP sense of the term. As with
any finite network, if packets are injected at a rate higher than the network
is drained, something must give. The POETS network addresses this problem by
enforcing conditional acceptance at the hardware level. In other words, the
network will only accept a packet if it has capacity to buffer it. The
implication is that - after some finite time - it will be delivered. If the
network is unable to accept a packet, this information is pushed back to the
point that is most capable of reacting sensibly to it.

Between the application-writer-defined behaviours and the underlying hardware
sits a thin layer of software called the Softswitch (described later). The
operation of the Softswitch is defined by the POETS system architects and
cannot be modified by the application writer, but is configurable. Relevant
here is the default operation of the Softswitch if it receives pushback from
the hardware: it will retry sending on that pin at a later time, and prioritise
draining the network of packets first. This behaviour will (fairly, we intend)
effectively throttle the network until it can be drained.

#### Wallclock Time

In general, a device's behaviour will be single threaded, although this is not
enforced (see intended operation envelope above). These behaviours are small
segments of sequential code, which are mapped to arbitrarily separated physical
threads by the POETS system. Whilst the Orchestrator operator can control this
mapping, for canonical use cases this mapping is irrelevant. There is no notion
of synchronised wallclock time built into POETS at a low level, but real time
can be "injected" into devices by **supervisors**, which are described later.

From the above, two points are of relevance to the application designer:

 - POETS guarantees packet delivery in a finite time, but it does not guarantee
   transitivity: packets can "overtake" each other in transit.
 - Timestamps attached to data by a sender should be interpreted with due
   caution, as the time skew between devices is never predictable.

### Application Components: Graphs, Devices, Pins, and Packets

Applications and their components parts are strongly typed. An application
consists of two principal components: a **topology graph** (describing the
interconnectivity of the devices, see Figure 1), and a type tree, shown in
Figure 2, to which the topology graph is fully linked. A type tree may contain
multiple (named) graph types. A graph type may contain multiple device types,
multiple packet types, and optionally one supervisor type (see later). Device
types have associated input and output pin types. The shielding and scope of
typenames up to this point is what one would expect in a conventional
tree-based definition. This entire tree is specified by the application writer.

At this level, all types are identified by simple `name` string. A packet type
name is associated with each pin type, which defines the data layout of the
packets that may enter/exit the pin (dotted links in Figure 2). **POETS
requires that the type of the packet associated with the pins on each end of an
edge are the same.**

Each component type may have **data areas** (including the aforementioned
device and pin states) and a portfolio of **behaviours** associated with it:
these are fragments of C++14, which will later be assembled and compiled into
an executable Softswitch by POETS[^gpu].

[^gpu]: There is a strong - but entirely coincidental - similarity between the
    definition dataflow here and that employed in programming GPUs.

![Application type tree, used to define devices in the topology graph (Figure
1).](images/app_concepts/app_concepts_02.pdf)

### Type Linking

Type linking, Figure 3, refers to the act of defining an application graph
using a type tree. This is done explicitly by a command (refer to Volume IV),
and the reason for this separation of activity is purely pragmatic: useful
application graphs will typically be enormous, and will take considerable time
to load. Type trees, on the other hand, will be small and easy to load/unload
(see the design envelope in the Idealisation Section). The use case where
explicit manual typelinking is helpful is as follows: the Orchestrator operator
loads a graph (slow) and a type tree (fast), typelinks and performs some
experiment. The results are not satisfactory/useful. The Orchestrator operator
can then unlink the tree (fast), load an additional tree (fast), re-typelink
(fast) and repeat the analysis, without having to load/unload the graph (slow).

![Typelinking: an application graph linked to a type
tree](images/app_concepts/app_concepts_04.pdf)

### Supervisors in the Abstract

The application graph is an abstract graph, as shown in Figure 1. The intention
is that the interplay of packets and device/pin functionality combine to
produce a "solution" as an emergent property of this graph. This "solution" by
itself is of limited utility without any mechanism of data setup or
exfiltration. This capability is provided by the **supervisor**^[Note that
"Supervisor" in the context of POETS is not related to supervisors in the
context of UNIX-likes; the concepts are completely unrelated.] (or **supervisor
device**). This is defined (from the application writer's perspective) as an
abstract type, and is instantiated by POETS without control or visibility for
the user. Every POETS device is implicitly connected to a supervisor device,
and it is the supervisor that brokers communication to the overseer POETS
infrastructure.

To explain this more clearly, we must pre-empt the POETS Platform Section, and
describe the deployment of the application graph. In the abstract, the POETS
application graph consists of a (typelinked) arbitrary graph, defined by the
application-writer. This is mapped onto a fixed architecture that
supports/implements the behaviour defined by the application. This architecture
is hierarchical in nature, and described in detail in the POETS Platform
Section, but the relevant point is that the mapping is performed automatically,
and the user has no visibility of the mapping, nor of any partitioning of the
application graph necessary to support the application graph.

Figure 4 illustrates this idea. The application (arbitrary) device graph is
mapped to an a-priori fixed hardware graph. Subsets of this graph are overseen
by (connected to) separate instances of the supervisor, the behaviour of which
is defined by the application-writer. As with packet transit non-transitivity,
this introduces a subtlety in the operation of the overall system: supervisors
have local state which is not coherent across an application. A supervisor
knows which devices it is responsible for, and may count exfiltrated data
packets, so that it may take action when every subordinate device has
reported. This counter will reside in the supervisor state, but in the course
of execution, the various supervisor instances will have different values of
this counter at a given wallclock moment. There is no reason why the
application-writer cannot enforce coherence (via the message backplane) if they
choose, but that is strictly application-specific behaviour, and subject to
latency-induced skew from the message backplane.

---

In the current implementation of the Orchestrator, there is only one supervisor
device overseeing the entire application. We intend to enact the separation in
the above paragraph in a future release.

---

![Information movement within the system](images/app_concepts/app_concepts_03.pdf)

## The POETS Platform

This Section uses the concepts introduced in the prior (Event Based Compute in
the Abstract) Section to explain how applications may deployed in the
POETS/Orchestrator compute framework. This injection of context will inform the
reader of the execution and communication flow of applications on POETS to a
rudimentary level.

The POETS hardware platform consists of a bespoke network of multithreaded
RISC-V cores, instantiated on a set of FPGA platforms, which are contained
within networked conventional machines. The Orchestrator software interacts
with these machines, which are connected together in a single MPI universe. The
responsibilities of the Orchestrator are command and control of the system;
loading user-defined applications, assembling (composing) them, cross-compiling
and loading the RISC-V memory, and overseeing initialisation, execution,
termination, and data exfiltration.

### The Abstract Compute Stack (Engine)

Figure 5 shows an abstract representation of the compute stack. The
**P_engine** (POETS Engine) is the name given to the combination of the set of
FPGAs hosting the RISC-V cores and the communication infrastructure, and the
set of conventional hosts. Each engine contains a set of **P_boards** (compute
FPGA boards, contained in the **P_boxes**[^hierarchy]). The boards are
configured as a **fixed** graph. Each board contains a graph of mailboxes, each
mailbox addresses a set of cores, each core is multithreaded, and each thread
runs one instance of a sequential binary called a **Softswitch**. Each
Softswitch hosts multiple (or just one) compute devices.

[^hierarchy]: A P_box is a historical term for a level in the physical
    hierarchy. It plays no part in the functioning of the system.

![Software (Softswitch and up) running on hardware (tile and
down).](images/app_concepts/app_concepts_06.pdf)

### The Illusion of Parallelism

The abstract POETS graph (Figure 1) and compute model has devices reacting to
incident packets as and when they arrive; in principle, in this model, it is
possible for every device in an application to be active simultaneously. In
reality, execution of even the simplest set of instructions takes finite time,
and at the finest level of granularity, a thread can only do one thing at a
time[^andcores]. POETS attempts to implement the massive potential parallelism
of the compute model by providing an abundance of threads, and in applications
where the number of devices is less than the number of physical threads, makes
a pretty good job of it. Two factors combine to disrupt this idealisation:

[^andcores]: Under the POETS platform, cores can only "execute" one thread at a
    time.

 - The number of physical threads is fixed, and small.

 - The number of devices is at the behest of the application-writer, and is
   usually large.

To reconcile these conflicting trends, the placement system can map multiple
devices to a single thread - effectively serialising their execution. If the
reality has the device execution windows not overlapping, this will have
minimal effect on the overall operation of the system. If the reality has the
devices executing in parallel, this enforced serialisation may have an effect
on the overall operation of the system[^occupancy].

[^occupancy]: Whilst it is possible to both control the placement and thread
    occupancy of the compute elements (refer to the Placement annex) and
    monitor Softswitch operation in real time (refer to the the Softswitch,
    Supervisor, and Composer annex), this is a subtlety which requires careful
    handling.

### The Softswitch, and Fairness

The Softswitch is a **serial** binary executable that runs on each thread. Its
source is programmatically assembled by the Orchestrator from a boiler-plate
skeleton, and code fragments supplied by the application-writer that define the
behaviour of the individual devices. It is then compiled by the Orchestrator
(manually, after the application is loaded, but before it is deployed). **The
purpose of the Softswitch is to bridge the gap between the compute model
idealisation (devices react instantaneously to incoming packets) and reality
(every instruction in every code fragment takes a finite time to execute).**
Even in the canonical situation where a Softswitch holds only one device, the
thread has no ability to predict when multiple packets may impinge
simultaneously (incoming packet reactions must be serialised) or what to do
about multiple consequent broadcasts from the same device.main goal

To address these issues, the primary design goal of the Softswitch is
fairness. At the highest level, the design targets are to:

 - Drain the network of packets as fast as possible, to help maximise global
   throughput.
 - Prevent any single device from 'hogging' Softswitch cycles, in terms of (i)
   incoming packet processing (ii) core processing and (iii) sending packets.

The Softswitch interfaces between the application-writer's device code, and the
compute hardware. In the most simple form, the interface consists effectively
of four function invocations, each of which interact the hardware[^idle]:

 - Are there any incoming packets for me to read?
 - Read incoming packet.
 - Can I send a packet?
 - Send a packet.

[^idle]: Excluding idling behaviour.

These are hidden from the application-writer, but ultimately all instructions
in the device definitions resolve down to these four calls. They are only
visible to the Softswitch, so using them incorrectly (e.g. attempting to send a
packet when the system has explicitly forbidden it) is not possible.

Figure 6 shows an outline of the program flow of the Softswitch. Recall that
one Softswitch (created by the Orchestrator) executes on each hardware thread,
and may hold many devices. It is a blocking spinner, pausing on the bottom
(hardware) **wait** in the figure. **OnInit** *et al* are composed from code
fragments supplied by the application-writer (see the Application Language
Section). The precise sequencing of the implied switch clause controlling the
invocation of the **OnRecieve**, **OnIdle** and **OnSend** bundles (these are
abstract concepts here) can be altered by Orchestrator switches. Performance
monitors (mainly in the form of loop cycle counters) are available at the
points "I" in the figure. Details of their utility and access are in the
Softswitch, Supervisor, and Composer annex (Experience has shown that these are
extremely useful in performance tuning and debugging.)

Key points - performant applications must be robustly written to account for
these effects:

 - While devices are understood as parallel, independently-executed compute
   units in the abstract, the reality is that **devices are serialised on a
   per-thread level in the Softswitch**.

 - **Applications may not be loaded evenly** (i.e. different Softswitches may
   have different numbers of devices) onto threads, and threads may not have
   identical communication patterns with the rest of the hardware.

![Abstract Softswitch model. `On*` blocks represent code supplied by the
application writer. Consuming packets is preferred over sending, in order to
drain the network as quickly as possible. Refer to the Softswitch, Supervisor,
and Composer annex for a more detailed explanation, and for a similar model
incorporating more possible device
behaviours.](images/app_concepts/app_concepts_08.pdf)

### Defining Device and Pin Behaviours

Device instances (devices) Input and output pin instances have defined
behaviour via their type definition, introduced by typelinking. These
**behaviours** manifest as code fragments (in POETS/Orchestrator, these are
C++14). Note these fragments are not translation units or even functions: they
are "pasted" into the Softswitch source prior to compilation. We use the term
"invoke" (as opposed to "execute" or "call") to highlight this difference.

This section introduces these behaviours at a high-level, in a shallow,
Softswitch-sympathetic manner. See the "Expected Semantic Structure" Section
for a comprehensive, detailed definition of these behaviours, and how they are
incorporated into application files (also introduced later). Refer to the
Softswitch, Supervisor, and Composer annex for precise definitions on how these
behaviours are coupled. The behaviour of the default (non-buffering) Softswitch
is described here.

Pin behaviours:

 - `OnRecieve`: Invoked when a packet is received on an input pin.

 - `OnSend`: Invoked just before a packet is to be sent on an output pin, but
   after a device has decided it "wants" to send a packet.

Device behaviours:

 - `OnInit`: Invoked when the application starts. Note that the Softswitch will
   execute the `OnInit` behaviour for each device it manages in sequence. This
   behaviour may return a non-zero unsigned value to indicate that the device
   may "want" to send a packet.

 - `OnStop`: Invoked when the application is stopped by the Orchestrator, or by
   the Supervisor. Note that the Softswitch will execute the `OnStop` behaviour
   for each device it manages in sequence.

 - `OnIdle`: Invoked when there is nothing to receive, and nothing to send. The
   Softswitch will execute the `OnDeviceIdle` behaviour for each device it
   manages that has requested idle in its `ReadyToSend` handler, unless request
   idle has been disabled. The Softswitch will iterate over its hosted devices
   until either a packet can be received, or it has attempted to execute
   `OnDeviceIdle` for each device. If any of the `OnDeviceIdle`
   application-writer-supplied fragments returned a non-zero unsigned value,
   that indicates the device may "want" to send a packet.

#### Properties and State

As with behaviours, device instances and pin instances may have available "data
space" accessible from their behaviours, defined by their type
definition. These data spaces are [^nooutputdata]:

 - **Input Pin Properties**: Data that is constant with respect to the
   execution of the application, and that is read-accessible by the `OnReceive`
   behaviour of an input pin.

 - **Input Pin State**: Data that may change while an application is running,
   at the behest of input pin behaviour. This state can be written to, or read
   from, the `OnReceive` behaviour of an input pin.

 - **Device Properties**: As with input pin properties, but is read-accessible
   by all device and input/output pin behaviours.

 - **Device State**: As with input pin state, but can be written to, or read
   from, all device and input/output pin behaviours.

 - **Graph Properties**: As with device properties, but are the same across all
   devices in the application (and is only read-accessible). Exists as a
   convenience mechanism.

[^nooutputdata]: Note that an output pin has no properties or state associated
    with it. Output pin behaviours can still read from device properties, and
    can still read/write device state.

The existence of these data spaces allows behaviours of devices to interact, and
are primarily used to identify whether a behaviour "wants" one or more packets to
be sent, as well as the payload of those packets.

#### "Wanting" to send (`:ReadyToSend:`)

A common point in device and pin behaviours is the notion of a device "wanting"
to send a packet. This "wanting" behaviour is controlled by an `OnReadyToSend`
behaviour, represented by the "Do I **want** to send" box in Figure 6. The
`OnReadyToSend` of a device is invoked after either an `OnRecv` or `OnSend`
behaviour, or `OnIdle` or `OnInit` behaviour returning a non-zero unsigned
value has been invoked. This behaviour defines which output pins to send on, as
a function of device properties and state. Note that, unlike all other pin and
device behaviours, **this behaviour cannot modify state data**, though it can
read from state data.

### Defining Supervisor Behaviours

Supervisors, as introduced in the "Supervisors in the Abstract" Section, are
special overseer devices that supervise many "normal" devices. Colloquially,
one can think of supervisor devices as a "more able participant" in the
application, with greater memory and processing power. Supervisor devices exist
to allow application writers to:

 - Exfiltrate data from normal devices back to the host machine[^architecture],
   so that they can be interpreted by the user.

 - Influence the execution of the application from the host machine while it's
   running, supporting user interaction (data infiltration).

 - Perform aggregated computation that is essential to the running of an
   application.

[^architecture]: Here, the host machine is typically an x86 machine, but it
    doesn't have to be.

Supervisor devices support the `OnInit`, `OnStop`, and `OnIdle` behaviours as
with normal devices.

**Implicit supervisor pins** and **implicit supervisor edges** facilitate
communication between normal devices and their supervisor device. All normal
devices and supervisor devices optionally have one implicit supervisor output
pin and one implicit supervisor input pin, and the send/receive logic is
defined using `OnSend` and `OnReceive` behaviours. Being implicit, **this
concept connects all normal devices to their supervisor, and vice versa**,
supporting exfiltration and infiltration of data. As with usual input and
output pins, **POETS requires that the type of the packet associated with
the pins on each end of an edge are the same.**

Unlike normal devices, a supervisor device can send data, using it's implicit
output pin, in two ways:

 - **Response**: Send a "reply" packet back to the device that triggered an
   `OnReceive` behaviour.

 - **Broadcast**: Send a packet to all devices managed by this supervisor.

This functionality allows supervisors to induce a localised stimulus into an
application.

## Writing for POETS Hardware

This Section provides a brief description of the POETS hardware, sufficient for
writing applications for the Orchestrator. For a more detailed description, see
the Tinsel documentation (at
<https://github.com/poetsii/tinsel>)^[Specifically, in README.md, visible if
you scroll down past the source listing.]. Values here are correct as of Tinsel
0.8.

Tinsel is the overlay architecture used on POETS hardware. The Tinsel system
operates on a series of connected FPGA boards, and implements a subset of
the RISCV32IMF instruction set profile. **This subset notably omits integer
division (and the modulo operator as a consequence), and floating-point
fused instructions** (as the ALU doesn't support them). See the Tinsel
documentation for the full set of forbidden instructions.

Each board consists of two 2GB DDR3 DRAMs and four 8MB QDRII+ SRAMs, which are
shared evenly throughout the POETS Engine. The Softswitch (see
"softswitch.pdf") only makes use of these DRAMs to store properties, state, and
connections information at present. Consequently, **data space is limited**,
which imposes a constraint on the footprint of properties, state, and
connection information (though this has yet to become an issue in Orchestrator
applications).

Instruction memory is stored in on-chip RAM (8kB) shared between core pairs. As
such, **all threads across each pair of cores share the same instruction
memory**. Put another way, this means that a given "neighbouring" pair of cores
in the POETS Engine can have only one type of device placed upon it (but can
have many instances of those types). This provides an intrinsic communications
benefit to devices of the same type: since they can be placed on the same core
(pair), their communication is less latent. **Application writers must ensure
their application (and the supporting Softswitch infrastructure) together
optimise-compiles to fit in this on-chip RAM.** Also of note, **instruction
memory cannot be accessed explicitly using load and store instructions** (so no
cheating).

The Orchestrator will inform you during application composition if any of these
conditions is violated by the application (or its placement). If so, the
Orchestrator will refuse to build it.

# Application Language (XML)

## Overview

Applications are consumed by the Orchestrator, and perform computation desired
by the user on POETS. Applications in POETS are described as graphs, where
vertices represent "compute" behaviour, and edges represent "communication"
behaviour. Such applications must be realised as eXtensible Markup Language
(XML) files, suitable for the Orchestrator. This Section explains how these
graphs are represented in POETS-XML. Application files must be encoded in
ASCII.

Note that this document outlines how applications are to be written, by
external software or "by hand", in a form suitable for the Orchestrator. It
does not include design decisions, past designs, future extensions or
refactors, or discussion of common design patterns. This section assumes you
have read "Concepts and Architectural Concerns".

## Expected Semantic Structure

This Section introduces the meaning behind each element of the XML tree. The
order of elements on each level is free to vary without compromising the
semantic integrity of an application definition file. The XML tree structure
for a semantically-valid input file follows, where each line corresponds to an
element:

+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Root   | ...               | ...             | ...            | ...                  | Leaf      |
+========+===================+=================+================+======================+===========+
| Graphs |                   |                 |                |                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         |                 |                |                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | *Properties*    |                |                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | *SharedCode*    |                |                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | *MessageTypes*  |                |                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | MessageTypes    | **MessageType**|                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | MessageTypes    | MessageType    | *Message*            |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     |                |                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | **DeviceType** |                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | *Properties*         |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | *State*              |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | *SharedCode*         |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | *SupervisorInPin*    |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | SupervisorInPin      | OnReceive |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | *SupervisorOutPin*   |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | SupervisorOutPin     | OnSend    |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | **InputPin**         |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | InputPin             | *Properties*|
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | InputPin             | *State*   |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | InputPin             | OnReceive |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | **OutputPin**        |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | OutputPin            | OnSend    |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | *ReadyToSend*        |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | *OnInit*             |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | DeviceType     | *OnDeviceIdle*       |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     |*SupervisorType*|                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | SupervisorType | *Properties*         |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | SupervisorType | *State*              |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | SupervisorType | *Code*               |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | SupervisorType | **SupervisorInPin**  |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | SupervisorType | SupervisorInPin      | OnReceive |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | SupervisorType | **SupervisorOutPin** |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | SupervisorType | SupervisorOutPin     | OnSend    |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | SupervisorType | *OnInit*             |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | SupervisorType | *OnSupervisorIdle*   |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphType         | DeviceTypes     | SupervisorType | *OnStop*             |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | **GraphInstance** |                 |                |                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphInstance     | DeviceInstances |                |                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphInstance     | DeviceInstances | **DevI**       |                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphInstance     | EdgeInstances   |                |                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+
| Graphs | GraphInstance     | EdgeInstances   | **EdgeI**      |                      |           |
+--------+-------------------+-----------------+----------------+----------------------+-----------+

Table: Valid XML elements and their nesting. **Emboldened** elements may appear any
number of times. *Emphasised* elements may appear exactly zero or one time.

Some elements may occur multiple times (**emboldened** in Table 1), or not at
all (*emphasised* in Table 1), at the application-writer's behest. An
explanation of each of these elements follows. Some notable elements are
accompanied by a tag (e.g. `:Graphs:`), to link with other elements of this
document. Some elements refer to macros - these macros are described in the
"Application Programming Interface" section.

**Graphs** (`:Graphs:`)

This element exists because XML demands that a single root node exists in the
syntax tree.

This element must occur exactly once in each file. Valid attributes:

 - `xmlns` (must occur exactly once): Unused, ignored.

 - `formatMinorVersion` (must occur at most once): Unused, ignored.

 - `appname` (must occur exactly once): Defines the string used to reference
   this file in the Orchestrator.

**Graphs/GraphType** (`:GraphType:`)

Defines the types of devices, messages, and pins for applications, including
properties, state, and code.

This element must occur exactly once in each `:Graphs:` section. Valid
attributes:

 - `id` (must occur exactly once): Used by graph instances
   (`:GraphInstance:`) to determine the types for an instantiated application.

**Graphs/GraphType/Properties** (`:GraphType-Properties:`)

Defines graph-level properties (constant throughout execution), which can be
accessed by code fragments through the `GRAPHPROPERTIES(x)` macro. Individual
properties are defined as `CDATA`. These properties may be overridden using the
`P` attribute in the graph instance definition (`:GraphInstance:`).

The definition of the generated structure is available to the application writer
in all code across all devices and the supervisor. The type name has a format of
`{graphTypeId}_properties_t` where `graphTypeId` is the `id` attribute of the
`GraphType` element.

This element must occur at most once in each `:GraphType:` section. No
attributes are valid.

**Graphs/GraphType/SharedCode** (`:GraphType-SharedCode:`)

Contains code common to all devices in an application. Useful for defining
constants and free functions for use in behaviour `CDATA` sections.

This element must occur at most once in each `:GraphType:` section. No
attributes are valid.

**Graphs/GraphType/MessageTypes**

Contains definitions for all payloads of all message types used in an
application. Message types may have different payload configurations.
When compiled into a POETS application, the Message types specified
here are tightly packed in memory with no padding bytes.

This element must occur at most once in each `:GraphType:` section. No
attributes are valid.

**Graphs/GraphType/MessageTypes/MessageType** (`:MessageType:`)

Defines a Message Type and contains a single Message child.

This element may occur any number of times in each `:MessageTypes:` section
(once per message type), though each occurrence must have a unique `id`
value. Valid attributes:

 - `id` (must occur exactly once): Used by pins to define the type of message
   they correspond to, via the `:messageTypeId:` attribute

**Graphs/GraphType/MessageTypes/MessageType/Message** (`:Message:`)

Contains code that populates the fields for the message structure of this
message type.

This element must occur at most once in each `:MessageType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes**

Contains type definitions for all normal devices and supervisor devices.

This element must occur exactly once in each `:GraphType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType** (`:DeviceType`)

Contains the definitions for a single normal device type.

This element may occur any number of times in each `:DeviceTypes:` section
(once per normal device type), though each occurrence must have a unique `id`
value. Valid attributes:

 - `id` (must occur exactly once): Used by a device instantiation list to
   define the type of a device instance (`:DevI:`).

**Graphs/GraphType/DeviceTypes/DeviceType/Properties**
(`:DeviceType-Properties:`)

Defines device-type-level properties (constant throughout execution), which can
be accessed by code fragments through the `DEVICEPROPERTIES(x)`
macro. Individual properties are defined as `CDATA`.

The definition of the generated structure is available to the application writer
in all code across all devices and the supervisor. The type name has a format of
`{graphTypeId}_{deviceTypeId}_properties_t` where `graphTypeId` is the `id`
attribute of the `GraphType` element and `deviceTypeId` is the `id` attribute of
the relevant `DeviceType` element.

This element must occur at most once in each `:DeviceType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/State** (`:DeviceType-State:`)

Defines device-type-level state (that can vary throughout execution), which can
be accessed by code fragments through the `DEVICESTATE(x)` macro. Individual
state fields are defined as `CDATA`.

The definition of the generated structure is available to the application writer
in all code across all devices and the supervisor. The type name has a format of
`{graphTypeId}_{deviceTypeId}_state_t` where `graphTypeId` is the `id` attribute
of the `GraphType` element and `deviceTypeId` is the `id` attribute of the relevant
`DeviceType` element.

This element must occur at most once in each `:DeviceType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/SharedCode**

Contains code common to all normal devices in an application. Useful for
defining constants and free functions for use in behaviour `CDATA` sections.

This element must occur at most once in each `:DeviceType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/SupervisorInPin** (`:DeviceType -
SupervisorInPin:`)

Included to maintain a consistent structure for pins - only contains an
`OnReceive` element and nothing else. Note that unlike traditional input pins,
implicit Supervisor input pins do not need to be connected in the edge instance
section of the XML, and do not have properties or state associated with them.

This element must occur at most once in each `:DeviceType:` section. Valid
attributes:

 - `messageTypeId` (must occur exactly once): Defines the type of message to be
   received by this pin. Must match with the `id` attribute of a message type
   defined in the `MessageTypes` section.

**Graphs/GraphType/DeviceTypes/DeviceType/SupervisorInPin/OnReceive**

Contains code to handle an inbound message to the supervisor, which may change
the state of the device.

This element must occur exactly once in each `:SupervisorInPin:` section. No
attributed are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/SupervisorOutPin** (`:DeviceType -
SupervisorOutPin:`)

Included to maintain a consistent structure for pins - only contains an
`OnSend` element and nothing else. Note that unlike traditional output pins,
implicit Supervisor output pins do not need to be connected in the edge instance
section of the XML.

This element must occur at most once in each `:DeviceType:` section. Valid
attributes:

 - `messageTypeId` (must occur exactly once): Defines the type of message to be
   sent by this pin. Must match with the `id` attribute of a message type
   defined in the `MessageTypes` section.

**Graphs/GraphType/DeviceTypes/DeviceType/SupervisorOutPin/OnSend**

Contains code that may populate an outbound message to the supervisor, and may
change the state of the device.

This element must occur exactly once in each `:SupervisorOutPin:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/InputPin** (`:InputPin:`)

Contains elements that together define an input pin type.

This element may occur any number of times in each `:DeviceType:` section
(once per input pin type), though each occurrence must have a unique `name`
value. Valid attributes:

 - `name` (must occur exactly once): Used by edge instances to define the pin
   on which a message is to be received by a device

 - `messageTypeId` (must occur exactly once): Defines the type of message to be
   received by this pin. Must match with the `id` attribute of a message type
   defined in the `MessageTypes` section.

**Graphs/GraphType/DeviceTypes/DeviceType/InputPin/Properties**
(`:PinType-Properties:`)

Defines pin-type-level properties (constant throughout execution), which can be
accessed by code fragments through the `EDGEPROPERTIES(X)` macro. Individual
properties are defined as `CDATA`.

The definition of the generated structure is available to the application writer
in all code across all devices and the supervisor. The type name has a format of
`{graphTypeId}_{deviceTypeId}_{inputPinId}_properties_t` where `graphTypeId` is
the `id` attribute of the `GraphType` element, `deviceTypeId` is the `id` attribute
of the relevant `DeviceType` element and `inputPinId` is the `id` attribute of
the relevant `InputPin`.

This element must occur at most once in each `:InputPin:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/InputPin/State** (`:PinType-State:`)

Defines pin-type-level state (that can vary throughout execution), which can be
accessed by code fragments through the `EDGESTATE(x)` macro. Individual
state fields are defined as `CDATA`.

The definition of the generated structure is available to the application writer
in all code across all devices and the supervisor. The type name has a format of
`{graphTypeId}_{deviceTypeId}_{inputPinId}_state_t` where `graphTypeId` is the
`id` attribute of the `GraphType` element, `deviceTypeId` is the `id` attribute
of the relevant `DeviceType` element and `inputPinId` is the `id` attribute of
the relevant `InputPin`.

This element must occur at most once in each `:InputPin:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/InputPin/OnReceive**
(`:InputPin-OnReceive:`)

Contains code to handle an inbound message to the supervisor, which may change
the state of the device.

This element must occur exactly once in each `:InputPin:` section. No
attributed are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/OutputPin** (`:OutputPin:`)

Contains elements that together define an output pin type.

This element may occur any number of times in each `:DeviceType:` section
(once per output pin type), though each occurrence must have a unique `name`
value. Valid attributes:

 - `name` (must occur exactly once): Used by edge instances to define the pin
   on which a message is to be sent by a device

 - `messageTypeId` (must occur exactly once): Defines the type of message to be
   sent by this pin. Must match with the `id` attribute of a message type
   defined in the `MessageTypes` section.

**Graphs/GraphType/DeviceTypes/DeviceType/OutputPin/OnSend**
(`:OutputPin-OnSend:`)

Contains code that may populate an outbound message to another device, and may
change the state of the device.

This element must occur exactly once in each `:OutputPin:` section. No
attributed are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/ReadyToSend** (`:ReadyToSend:`)

Contains code that reads the state of the device, determines whether any
messages are to be sent, via the `RTS(x)` and `RTSSUP()` macros, and determines
whether `OnDeviceIdle` should be called, via the `*requestIdle` bool. If multiple
messages are to be sent, the order of their sending is undefined. Note that the
state of the device cannot be modified in this block. Execution of this block
is dependent on the Softswitch used, though the default Softswitch executes
this block:

 - After a message has been received and handled by the behaviour code in
   `InputPin/OnReceive` or `SupervisorInPin/OnReceive`.

 - After the behaviour code in `OnDeviceIdle` executes and returns a non-zero
   unsigned value.

 - After the behaviour code in `OnInit` executes and returns a non-zero unsigned
   value.

This element must occur at most once in each `:DeviceType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/OnInit** (`:OnInit:`)

Contains code that is executed by the device when it is started, and at no
other time. Useful for setting an initial state as a function of properties at
run-time. If the code in this block returns a non-zero unsigned value, the code
in the `ReadyToSend` section is executed, which may result in the sending of
messages.

This element must occur at most once in each `:DeviceType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/OnDeviceIdle** (`:OnDeviceIdle:`)

Contains code that is executed by the device when the Softswitch is in the
"idle" state. Under the default Softswitch, this block is executed when no
devices have any messages to receive or send and idle has been requested by
setting `*requestIdle` to `true` in `ReadyToSend`. If the code in this block
returns a non-zero unsigned value, the code in the `ReadyToSend` section is
executed, which may result in the sending of messages.

This element must occur at most once in each `:DeviceType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/SupervisorType**

Contains the type definition for all supervisor devices.

This element must occur at most once in each `:DeviceTypes:` section. Valid
attributes:

 - `id` (must occur exactly once): Currently unused.

**Graphs/GraphType/DeviceTypes/SupervisorType/Properties**

Defines supervisor-device-type-level properties (constant throughout
execution), which can be accessed by code fragments through the
`SUPPROPERTIES(x)` macro. Individual properties are defined as `CDATA`.

This element must occur at most once in each `:SupervisorType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/SupervisorType/State**

Defines supervisor-device-type-level state (that can vary throughout
execution), which can be accessed by code fragments through the `SUPSTATE(x)`
macro. Individual state fields are defined as `CDATA`.

This element must occur at most once in each `:SupervisorType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/SupervisorType/Code**

Contains code common to all behaviour code for supervisor devices in an
application. Useful for defining constants and free functions for use in
behaviour `CDATA` sections.

This element must occur at most once in each `:SupervisorType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/SupervisorType/SupervisorInPin**
(`:SupervisorType - SupervisorInPin:`)

Contains elements that together define an input pin type.

This element may occur one of fewer times in each `:SupervisorType:`
section. Valid attributes:

 - `messageTypeId` (must occur exactly once): Defines the type of message to be
   received by this pin. Must match with the `id` attribute of a message type
   defined in the `MessageTypes` section.

**Graphs/GraphType/DeviceTypes/SupervisorType/SupervisorInPin/OnReceive**
(`:SupervisorInPin - OnReceive:`)

Contains code to handle an inbound message to the supervisor. This code might
provision (`REPLY(x)`) and stage (`RTSREPLY()`) a reply message, and/or
provision (`BCAST(x)`) and stage (`RTSBCAST()`) a broadcast message using
accessibility macros.

This element must occur exactly once in each `:SupervisorInPin:` section. No
attributed are valid.

**Graphs/GraphType/DeviceTypes/SupervisorType/SupervisorOutPin**
(`:SupervisorType - SupervisorOutPin:`)

Contains elements that together define an output pin type.

This element may occur one or fewer times in each `:SupervisorType:`
section. Valid attributes:

 - `messageTypeId` (must occur exactly once): Defines the type of message to be
   sent by this pin. Must match with the `id` attribute of a message type
   defined in the `MessageTypes` section.

**Graphs/GraphType/DeviceTypes/SupervisorType/SupervisorOutPin/OnSend**
(`:SupervisorOutPin - OnSend:`)

Contains code that may populate an outbound message from a supervisor device.

This element must occur exactly once in each `:SupervisorOutPin:` section. No
attributed are valid.

**Graphs/GraphType/DeviceTypes/SupervisorType/OnInit**
(`:SupervisorType - OnInit:`)

Contains code that is executed by the supervisor device when the application
starts.

This element must occur at most once in each `:SupervisorType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/SupervisorType/OnSupervisorIdle**
(`:OnSupervisorIdle:`)

Contains code that is executed by the supervisor device when no messages are
being received by the Mothership (and hence all supervisor devices from all
applications running on it)

This element must occur at most once in each `:SupervisorType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/SupervisorType/OnStop**
(`:SupervisorType - OnStop:`)

Contains code that is executed by the supervisor device when the application is
stopped by the operator (root). Note that this behaviour is not executed in the
event of an application crash or an "unrecoverable" Orchestrator state.

This element must occur at most once in each `:SupervisorType:` section. No
attributes are valid.

**Graphs/GraphInstance** (`:GraphInstance:`)

Defines the topology of an application. Specifically, how many devices there
are, what their types are, how they are connected, and the types of pins on
each device that facilitate those connections. A file can contain many graph
instances that draw definitions from a given graph type.

This element may occur any number of times in each `:Graphs:` section. Valid
attributes:

 - `id` (must occur exactly once): Label that allows the Orchestrator operator
   to refer to this graph instance (for example, to place it or to run it).

 - `graphTypeId` (must occur exactly once): Identifies the graph type to read
   from, to determine the behaviour of device and pin types. Corresponds to the
   `id` attribute of a `:GraphType:` element.

 - `P` (must occur at most once): Property definitions overriding graph-level
   type defaults. Define using syntax that is valid in C++14 initialiser lists
   (e.g. `value,anothervalue` for each property field in order).

**Graphs/GraphInstance/DeviceInstances** (`:DeviceInstances:`)

Contains elements that instantiate every normal device in an application. If
this section contains no children, no normal devices are instantiated (a
supervisor device is still instantiated, though this is of questionable value
outside debugging). The order of devices introduced in this section is
preserved, which affects the result of certain placement algorithms (thread
filling and spreading).

This element must occur exactly once in each `GraphInstance` section. No
attributes are valid.

**Graphs/GraphInstance/DeviceInstances/DevI** (`:DevI:`)

Defines a single device instance.

This element may occur any number of times in each `DeviceInstances`
section. Valid attributes:

 - `id` (must occur exactly once): A name identifying the device. Used in edge
   instantiations (:`EdgeI:`).

 - `type` (must occur exactly once): The type of this device, corresponding to
   the value of the `id` field of a `:DeviceType:` element.

 - `P` (must occur at most once): Property definitions overriding device-level
   type defaults. Define using syntax that is valid in C++14 initialiser lists
   (e.g. `value,anothervalue` for each property field in order).

 - `S` (must occur at most once): Initial state definitions overriding
   device-level type defaults. Define using syntax that is valid in C++14
   initialiser lists (e.g. `value,anothervalue` for each state field in order).

**Graphs/GraphInstance/EdgeInstances** (`:EdgeInstances:`)

Contains elements that instantiate every edge connecting devices in an
application (aside from implicit connections between normal devices and their
supervisor device). If this section contains no children, no edges are
instantiated.

This element must occur exactly once in each `GraphInstance` section. No
attributes are valid.

**Graphs/GraphInstance/EdgeInstances/EdgeI** (`:EdgeI:`)

Defines a single edge, as well as the pins connecting either side of that edge
(see Figure 1).

This element may occur any number of times in each `EdgeInstances`
section. Valid attributes:

 - `path` (must occur exactly once): A string of the form
   `<DeviceTo>:<PinTo>-<DeviceFrom>:<PinFrom>`, where:

   - `<DeviceTo>` is either the `id` of a device instance (`:DevI:`) expected
     to receive messages over this edge, or is blank if a supervisor device is
     the recipient.

   - `<PinTo>` is the `name` of an input pin type (`:InputPin:` or
     `:SupervisorType - SupervisorInPin:` that exists for the type of
     `<DeviceTo>`.

   - `<DeviceFrom>` is either the `id` of a device instance (`:DevI:`) expected
     to send messages over this edge, or is blank if a supervisor device is the
     sender.

   - `<PinFrom>` is the `name` of an output pin type (`:OutputPin:` or
     `:SupervisorType - SupervisorOutPin:` that exists for the type of
     `<DeviceFrom>`.

 - `P` (must occur at most once): Property definitions overriding type defaults
   for the input pin on the receiving device, if the receiving device is a normal
   device. Define using braced syntax that is valid in C++14 initialiser lists
   (e.g. `{value,anothervalue}` for each property field in order). This attribute
   must be undefined if the receiving device is a supervisor device.

 - `S` (must occur at most once): Initial state definitions overriding type
   defaults for the input pin on the receiving device, if the receiving device
   is a normal device. Define using braced syntax that is valid in C++14 initialiser
   lists (e.g. `{value,anothervalue}` for each state field in order). This
   attribute must be undefined if the receiving device is a supervisor device.

## Application Programming Interface (for Source Code Fragments)

Application XML supports the use of `CDATA` sections to define various system
behaviours. Valid code in these sections should be written in C++14, encoded in
ASCII, and make no assumptions of included non-standard libraries or functions
that are not introduced in this documentation.

### Reserved Names

To avoid conflicts with the Softswitch and underlying hardware, user-supplied
behaviours and code must not define or use any variable names or preprocessor
defines that begin with:

 - `P_`
 - `p_`
 - `__`
 - `tinsel`
 - `softswitch_`

or are named:

 - `DeviceVector`
 - `CoreVector`
 - `LOG_BOARDS_PER_BOX`
 - `LOG_CORES_PER_BOARD`
 - `LOG_THREADS_PER_CORE`
 - `ThreadContext`
 - `deviceInstance`
 - `pkt`
 - `reply`
 - `bcast`

**This restriction is not checked by the Orchestrator. Use of these names in
CDATA sections will result in undefined behaviour.** Also see Appendix A for a
list of legacy variables.

### Attributes

Application XML does not support newline characters (`\n`) in attribute values.

### Accessibility Macros and Functions

Tables 2, 3, and 4 lists all macros and functions used to access device properties,
state, incoming/outgoing packets, to set pins for sending, and various other
functions. Table 5 explains where each macro can be used. Many of the macros
below access internal state variables, which are commonly referenced in legacy
code. These internal state variables are listed in Appendix A.

By way of small example, if an application defines a device with state in its
`DeviceType/Properties` element:

~~~ {.c}
uint32_t numberOfOctopodes;
const char* lemon = "fruit";
~~~

Then a behaviour could read/write state: (e.g. `DeviceType/OnInit`):

~~~ {.c}
if (DEVICESTATE(lemon) == "fruit")  // Reading
{
    DEVICESTATE(numberOfOctopodes) = 5;  // Writing
}
~~~

+---------------------------+-------------------------------------------------+
| Macro                     | Purpose                                         |
+===========================+=================================================+
| `GRAPHPROPERTIES(x)`      | Access field `x` of graph properties for        |
|                           | reading.                                        |
+---------------------------+-------------------------------------------------+
| `MSG(x)`                  | Access field `x` of an incoming (for reading)   |
|                           | or outgoing (for writing) field of a packet.    |
+---------------------------+-------------------------------------------------+
| `PKT(x)`                  | Synonym of `MSG(x)`.                            |
+---------------------------+-------------------------------------------------+

Table: Explanation of accessibility macros and functions in `CDATA` code common
to normal devices (running in a Softswitch) and Supervisor devices.

+---------------------------+-------------------------------------------------+
| Macro                     | Purpose                                         |
+===========================+=================================================+
| `DEVICEPROPERTIES(x)`     | Access field `x` of device properties for       |
|                           | reading.                                        |
+---------------------------+-------------------------------------------------+
| `DEVICESTATE(x)`          | Access field `x` of device state for reading    |
|                           | and writing (outside of `ReadyToSend`).         |
+---------------------------+-------------------------------------------------+
| `EDGEPROPERTIES(x)`       | Access field `x` of corresponding input pin     |
|                           | properties for reading.                         |
+---------------------------+-------------------------------------------------+
| `EDGESTATE(x)`            | Access field `x` of corresponding input pin     |
|                           | state for reading and writing.                  |
+---------------------------+-------------------------------------------------+
| `RTS(x)`                  | Marks the output pin named `x`, on a normal     |
|                           | device, to send a packet when sending is        |
|                           | available.                                      |
+---------------------------+-------------------------------------------------+
| `RTSSUP()`                | Marks the implicit supervisor output pin, on a  |
|                           | normal device, to send a packet when sending is |
|                           | available.                                      |
+---------------------------+-------------------------------------------------+
| `handler_log(int level,`  | Sends a logging packet from a normal device to  |
| `const char* text)`       | the Orchestrator, with log level `level`, and   |
|                           | content `text`. For more information, refer to  |
|                           | the Softswitch, Supervisor, and Composer annex. |
+---------------------------+-------------------------------------------------+

Table: Explanation of accessibility macros and functions in `CDATA` for normal
devices (running in a Softswitch), in addition to those in Table 2.

+---------------------------+-------------------------------------------------+
| Macro                     | Purpose                                         |
+===========================+=================================================+
| `SUPPROPERTIES(x)`        | Access field `x` of supervisor device           |
|                           | properties for reading.                         |
+---------------------------+-------------------------------------------------+
| `SUPSTATE(x)`             | Access field `x` of supervisor device state for |
|                           | reading and writing.                            |
+---------------------------+-------------------------------------------------+
| `REPLY(x)`                | In a Supervisor-context when a packet is        |
|                           | received, access field `x` of an outgoing field |
|                           | of a packet, that is going to be sent in        |
|                           | response to the incoming packet that is         |
|                           | currently being handled.                        |
+---------------------------+-------------------------------------------------+
| `BCAST(x)`                | In a Supervisor-context when a packet is        |
|                           | received, access field `x` of an outgoing field |
|                           | of a packet, that is going to be sent in        |
|                           | response to the incoming packet that is         |
|                           | currently being handled, to all devices managed |
|                           | by this supervisor.                             |
+---------------------------+-------------------------------------------------+
| `RTSREPLY()`              | In a Supervisor context, denote that a reply    |
|                           | packet is to be sent, analogous to the          |
|                           | `ReadyToSend` mechanism on normal devices.      |
+---------------------------+-------------------------------------------------+
| `RTSBCAST()`              | In a Supervisor context, denote that a broadcast|
|                           | packet is to be sent, analogous to the          |
|                           | `ReadyToSend` mechanism on normal devices.      |
+---------------------------+-------------------------------------------------+

Table: Explanation of accessibility macros and functions in `CDATA` for
Supervisor devices, in addition to those in Table 2.

+--------------------------------------+--------------------------------------+
| Containing Element                   | Provided Macros (variable            |
|                                      | accessibility)                       |
+======================================+======================================+
| `DeviceType / SupervisorInPin /`     | - `DEVICEPROPERTIES` (read-only)     |
| `OnReceive`                          | - `DEVICESTATE`                      |
|                                      | - `GRAPHPROPERTIES` (read-only)      |
|                                      | - `MSG` (read-only)                  |
|                                      | - `handler_log`                      |
+--------------------------------------+--------------------------------------+
| `DeviceType / SupervisorOutPin /`    | - `DEVICEPROPERTIES` (read-only)     |
| `OnSend`                             | - `DEVICESTATE`                      |
|                                      | - `GRAPHPROPERTIES` (read-only)      |
|                                      | - `MSG`                              |
|                                      | - `handler_log`                      |
+--------------------------------------+--------------------------------------+
| `InputPin / OnReceive`               | - `DEVICEPROPERTIES` (read-only)     |
|                                      | - `DEVICESTATE`                      |
|                                      | - `GRAPHPROPERTIES` (read-only)      |
|                                      | - `MSG` (read-only)                  |
|                                      | - `EDGEPROPERTIES` (read-only)       |
|                                      | - `EDGESTATE`                        |
|                                      | - `handler_log`                      |
+--------------------------------------+--------------------------------------+
| `OutputPin / OnSend`                 | - `DEVICEPROPERTIES` (read-only)     |
|                                      | - `DEVICESTATE`                      |
|                                      | - `GRAPHPROPERTIES` (read-only)      |
|                                      | - `MSG`                              |
|                                      | - `handler_log`                      |
+--------------------------------------+--------------------------------------+
| `ReadyToSend`                        | - `DEVICEPROPERTIES` (read-only)     |
|                                      | - `DEVICESTATE` (read-only)          |
|                                      | - `GRAPHPROPERTIES` (read-only)      |
|                                      | - `RTS`                              |
|                                      | - `RTSSUP`                           |
|                                      | - `handler_log`                      |
+--------------------------------------+--------------------------------------+
| `DeviceType / OnInit`                | - `DEVICEPROPERTIES` (read-only)     |
|                                      | - `DEVICESTATE`                      |
|                                      | - `GRAPHPROPERTIES` (read-only)      |
|                                      | - `handler_log`                      |
+--------------------------------------+--------------------------------------+
| `DeviceType / OnDeviceIdle`          | - `DEVICEPROPERTIES` (read-only)     |
|                                      | - `DEVICESTATE`                      |
|                                      | - `GRAPHPROPERTIES` (read-only)      |
|                                      | - `handler_log`                      |
+--------------------------------------+--------------------------------------+
| `SupervisorType / SupervisorInPin /` | - `SUPPROPERTIES` (read-only)        |
| `OnReceive`                          | - `SUPSTATE`                         |
|                                      | - `GRAPHPROPERTIES` (read-only)      |
|                                      | - `MSG` (read-only)                  |
|                                      | - `REPLY`                            |
|                                      | - `RTSREPLY`                         |
|                                      | - `BCAST`                            |
|                                      | - `RTSBCAST`                         |
+--------------------------------------+--------------------------------------+
| `SupervisorType / SupervisorOutPin`  | - `SUPPROPERTIES` (read-only)        |
| `/ OnSend`                           | - `SUPSTATE`                         |
|                                      | - `GRAPHPROPERTIES` (read-only)      |
|                                      | - `MSG`                              |
+--------------------------------------+--------------------------------------+
| `SupervisorType / OnSupervisorIdle`  | - `SUPPROPERTIES` (read-only)        |
|                                      | - `SUPSTATE`                         |
|                                      | - `GRAPHPROPERTIES` (read-only)      |
+--------------------------------------+--------------------------------------+
| `SupervisorType / OnInit`            | - `SUPPROPERTIES` (read-only)        |
|                                      | - `SUPSTATE`                         |
|                                      | - `GRAPHPROPERTIES` (read-only)      |
+--------------------------------------+--------------------------------------+
| `SupervisorType / OnStop`            | - `SUPPROPERTIES` (read-only)        |
|                                      | - `SUPSTATE`                         |
|                                      | - `GRAPHPROPERTIES` (read-only)      |
+--------------------------------------+--------------------------------------+
| Other elements                       | None                                 |
+--------------------------------------+--------------------------------------+

Table: Macros and functions exposed to code written in `CDATA` sections. `PKG`
is accessible wherever `MSG` is.

### Supervisor API

As with the accessibility macros above, supervisor devices support function
calls for convenience operations:

 - `void Super::post(std::string message)`: Posts a logging message to the
   Orchestrator, visible to the Orchestrator operator.

 - `void Super::stop_application()`: Stops the application.

 - `std::string Super::get_output_directory(std::string suffix="")`: Returns
   the absolute path of an empty directory on the disk of the machine hosting
   the supervisor device, and creates the directory. If the directory cannot be
   created, this function posts a logging message to the Orchestrator and
   returns an empty string.

# Example: Ring Test

This Section presents an example application, which is arrived at from a
high-level description of the desired behaviour. This example guides potential
application-writers in formulating simple applications. A listing of the
complete application, with additional comments, is presented at the end of this
section. We recommend the reader to follow along in their favourite text editor
as concepts are introduced, to see how components of the XML file connect
together. We also recommend that, as new XML sections are introduced, the
reader follows along from the reference in the "Application Language" Section
(the tagging system introduced in that Section is used here).  Further
examples, demonstrating both simpler and more complicated examples, are
available at <https://github.com/POETSII/Orchestrator_examples>.

The desired application, "Ring Test", is similar to the ring oscillator device
in electrical engineering, in which "NOT" gates are connected in a ring to
oscillate the voltage state of a circuit. In the ring test, a message is to be
passed around a ring of devices multiple times. Each time the message is
received at a destination, the receiver informs the supervisor of the progress
of the message. After $N=10$) "laps" of the ring, the message is dropped and
the application is complete. When the supervisor is informed that the message
has completed $N$ laps, it writes a success value (1) to a file. If the
supervisor sees that the message has looped too many times, it writes a failure
value (0) to a file.

## Towards a Normal Device Type

We begin from a skeletal structure:

~~~ {.xml}
<?xml version="1.0"?>
<Graphs xmlns="" appname="ring_test">
  <GraphType id="ring_test_type">
  </GraphType>
  <GraphInstance id="ring_test_instance" graphTypeId="ring_test_type">
  </GraphInstance>
</Graphs>
~~~

Here, no `xmlns` is used, and the application name is defined as
`ring_test`. An empty graph type (`:GraphType:`) is created, and an empty graph
instance (`:GraphInstance`) is connected to that type via the `graphTypeId`
attribute. Both the graph type and graph instance sections will be populated as
we progress through this example.

Within the `GraphType`, we can define the behaviour for the members of the
ring, which manifest as devices. These devices are going to propagate data
around the ring.

~~~ {.xml}
...
  <GraphType id="ring_test_type">
    <DeviceTypes>
      <DeviceType id="ring_element">
      </DeviceType>
    </DeviceTypes>
  </GraphType>
...
~~~

It is convenient at this point to define an identifier property `id` for the
ring members - one of them is going to have to start the application by sending
a message later, and it will be relevant for supervisor communications:

~~~ {.xml}
...
    <DeviceType id="ring_element">
      <Properties><![CDATA[
/* An identifier for this device, useful for supervisor communications. */
uint8_t id;
      ]]></Properties>
    </DeviceType>
...
~~~

Fields defined in the Properties element of a device type
(`:DeviceType-Properties:`) are read-accessible to devices of that type. This
declares a property of all ring elements, which we will define when the ring is
instantiated later. Note that this property is defined in a `:CDATA:` section,
written in C++14. This property will be readable by other code sections (for
ring elements) via the `DEVICEPROPERTIES(id)` macro.

With a way to identify devices in code, we can define startup logic. We make
device "zero" be the first to send a message:

~~~ {.xml}
...
    <DeviceType id="ring_element">
      <Properties><![CDATA[
/* An identifier for this device, useful for supervisor communications. */
uint8_t id;
      ]]></Properties>
      <OnInit><![CDATA[
/* Device zero starts things off by telling the ReadyToSend behaviour to send a
 * message. No other device does this. */
if (DEVICEPROPERTIES(id) == 0) DEVICESTATE(sendMessage) = 1;

/* A return of one invokes ReadyToSend (in the default Softswitch), whereas a
 * return of zero does not. */
return DEVICESTATE(sendMessage);
      ]]></OnInit>
      <State><![CDATA[
/* When a message is received, this field is populated either with one (true)
* or zero (false). */
uint8_t sendMessage = 0;
      ]]></State>
    </DeviceType>
...
~~~

A state field `sendMessage` is introduced in the `:DeviceType-State:` section,
with an initial value of zero. State fields are like property fields, but are
read-write accessible. This field will be read by another behaviour later
(`ReadyToSend`), to determine whether a message is to be sent (1) or not
(0). The code in the `:OnInit:` behaviour is run by each device when the
application starts. This behaviour sets the `sendMessage` field in the state to
one (so that a message will be sent later). The `:OnInit:` behaviour also returns
one on device zero, causing the `ReadyToSend` behaviour to be invoked.

The `ReadyToSend` behaviour is responsible for determining whether messages
should be sent, and which output pins should be used to send that message. To
do this, it reads the state of the device, as follows:

~~~ {.xml}
...
    <DeviceType id="ring_element">
      ...
      <State><![CDATA[
/* When a message is received, this field is populated either with one (true)
 * or zero (false). */
uint8_t sendMessage = 0;
      ]]></State>
      ...
      <ReadyToSend><![CDATA[
if (DEVICESTATE(sendMessage) == 1) RTS(sender);
      ]]></ReadyToSend>
    </DeviceType>
...
~~~

The `ReadyToSend` behaviour here checks whether another behaviour "wants a
message to be sent" (see the "Wanting to send" Section). If so, it sets a flag
using the `RTS` macro. This flag is checked after the `ReadyToSend` behaviour
is invoked, and causes a message to be sent on the "`sender`" output pin. In
order to send a message in this way, an output pin with the name "`sender`"
must be defined for this type, as follows:

~~~ {.xml}
...
    <DeviceType id="ring_element">
      <State><![CDATA[
/* Holds the lap for the most recently-received message. Is used to define the
 * lap for outgoing messages. */
uint8_t lap = 0;

/* When a message is received, this field is populated either with one (true)
 * or zero (false). */
uint8_t sendMessage = 0;
      ]]></State>
      <OutputPin name="sender" messageTypeId="ring_propagate">
        <OnSend><![CDATA[
/* Define the fields in the message. */
MSG(lap) = DEVICESTATE(lap);

/* Since we're sending a message, reset this field so that we don't send
 * another one. */
DEVICESTATE(sendMessage) = 0;
        ]]></OnSend>
      </OutputPin>
      ...
      <ReadyToSend><![CDATA[
if (DEVICESTATE(sendMessage) == 1) RTS(sender);
      ]]></ReadyToSend>
    </DeviceType>
...
~~~

Note that the `name` attribute on the output pin is "`sender`", which
corresponds to the argument to the "`RTS(sender)`" macro, called in the
`ReadyToSend` behaviour. This is essential to ensure that the correct pin is
selected to send the message. Output pins define an `OnSend` behaviour - in
this case, the behaviour clears the `sendMessage` state set by `OnInit` (or
another behaviour, later on). It also defines the `lap` field in the payload of
the outgoing message from the state - to facilitate this, the state of ring
element devices is expanded to include a `lap` field.

Like pins and devices, all messages must have a defined type. The element
introducing the "`sender`" output pin also has attribute `messageTypeId` with
value "`ring_propagate`", so a message type must also be defined as follows:

~~~ {.xml}
...
    <MessageTypes>
      <MessageType id="ring_propagate">
          <Message><![CDATA[
uint8_t lap;
          ]]></Message>
      </MessageType>
    </MessageTypes>
    <DeviceTypes>
      <DeviceType id="ring_element">
        <OutputPin name="sender" messageTypeId="ring_propagate">
          ...
        </OutputPin>
        ...
      </DeviceType>
    </DeviceTypes>
...
~~~

Again, a `:CDATA:` section is introduced to hold the field for the payload.

To complete the device definition, we require an input pin to receive
communications from the `"sender"` output pins of other devices:

~~~ {.xml}
...
    <DeviceType id="ring_element">
      <InputPin name="receiver" messageTypeId="ring_propagate">
        <OnReceive><![CDATA[
/* Only device zero increments the lap counter. Remember - this field in the
 * state is later propagated into the message. */
DEVICESTATE(lap) = MSG(lap);
if (DEVICEPROPERTIES(id) == 0) DEVICESTATE(lap) += 1;

/* Don't send a message if the incoming message has completed its tenth lap. */
if (DEVICESTATE(lap) <= GRAPHPROPERTIES(maxLaps)) DEVICESTATE(sendMessage) = 1;
else DEVICESTATE(sendMessage) = 0;
        ]]></OnReceive>
      </InputPin>
      ...
    </DeviceType>
...
~~~

When a `"ring_propagate"` message is received on this input pin, the `"lap"`
state of the device is updated with the contents of the message. Only device
zero is permitted to increment the lap (as it is the origin point of the
message). Like the `OnInit` behaviour, this `OnReceive` behaviour sets the
`"sendMessage"` state of the device for the `ReadyToSend` behaviour (which is
called after `OnReceive`).

Note that the output pin name "`sender`" and the input pin name "`receiver`"
are not special - as long as their names are used consistently throughout the
XML where they are required.

Lastly, this behaviour requires the definition of a "global" `maxLaps`
property, which determines when the application should stop. This is defined on
the graph level, and will be accessible by all code fragments in the
application:

~~~ {.xml}
<?xml version="1.0"?>
<Graphs xmlns="" appname="ring_test">
  <GraphType id="ring_test_type">
    <Properties><![CDATA[
uint8_t maxLaps = 9;  /* Zero-based indexing */
    ]]></Properties>
    ...
  </GraphType>
  <GraphInstance id="ring_test_instance" graphTypeId="ring_test_type">
  </GraphInstance>
</Graphs>
~~~

So far, we have defined the behaviour for all normal devices in the application
using the type system. The (incomplete) XML at this stage is:

~~~ {.xml}
<?xml version="1.0"?>
<Graphs xmlns="" appname="ring_test">
  <GraphType id="ring_test_type">
    <Properties><![CDATA[
uint8_t maxLaps = 9;  /* Zero-based indexing */
    ]]></Properties>
    <MessageTypes>
      <MessageType id="ring_propagate">
          <Message><![CDATA[
uint8_t lap;
          ]]></Message>
      </MessageType>
    </MessageTypes>
    <DeviceTypes>
      <DeviceType id="ring_element">
        <Properties><![CDATA[
/* An identifier for this device, useful for supervisor communications. */
uint8_t id;
        ]]></Properties>
        <State><![CDATA[
/* Holds the lap for the most recently-received message. Is used to define the
 * lap for outgoing messages. */
uint8_t lap = 0;

/* When a message is received, this field is populated either with one (true)
* or zero (false). */
uint8_t sendMessage = 0;
        ]]></State>
        <InputPin name="receiver" messageTypeId="ring_propagate">
          <OnReceive><![CDATA[
/* Only device zero increments the lap counter. Remember - this field in the
 * state is later propagated into the message. */
DEVICESTATE(lap) = MSG(lap);
if (DEVICEPROPERTIES(id) == 0) DEVICESTATE(lap) += 1;

/* Don't send a message if the incoming message has completed its tenth lap. */
if (DEVICESTATE(lap) <= GRAPHPROPERTIES(maxLaps)) DEVICESTATE(sendMessage) = 1;
else DEVICESTATE(sendMessage) = 0;
          ]]></OnReceive>
        </InputPin>
        <OutputPin name="sender" messageTypeId="ring_propagate">
          <OnSend><![CDATA[
/* Define the fields in the message. */
MSG(lap) = DEVICESTATE(lap);

/* Since we're sending a message, reset this field so that we don't send
 * another one. */
DEVICESTATE(sendMessage) = 0;
          ]]></OnSend>
        </OutputPin>
        <ReadyToSend><![CDATA[
if (DEVICESTATE(sendMessage) == 1) RTS(sender);
        ]]></ReadyToSend>
        <OnInit><![CDATA[
/* Device zero starts things off by telling the ReadyToSend behaviour to send a
 * message. No other device does this. */
if (DEVICEPROPERTIES(id) == 0) DEVICESTATE(sendMessage) = 1;

/* A return of one invokes ReadyToSend (in the default Softswitch), whereas a
 * return of zero does not. */
return DEVICESTATE(sendMessage);
        ]]></OnInit>
      </DeviceType>
    </DeviceTypes>
  </GraphType>
  <GraphInstance id="ring_test_instance" graphTypeId="ring_test_type">
  </GraphInstance>
</Graphs>
~~~

We now have a device type definition, which is capable of receiving messages
from the prior devices in the ring, and "forwarding" them to the next devices
in the ring.

## Introducing the Supervisor Device Type

The application brief requires a file to be written, whose contents depend on
the behaviour of the system. A supervisor device is well-positioned to do this,
as it can interact with the filesystem on the host machine, and can communicate
with the other normal devices in the application.

Starting from the output of the previous Section, we introduce a supervisor
device type alongside the ring element normal device type:

~~~ {.xml}
<?xml version="1.0"?>
<Graphs xmlns="" appname="ring_test">
  <GraphType id="ring_test_type">
    <Properties>
    ...
    </Properties>
    <MessageTypes>
    ...
    </MessageTypes>
    <DeviceTypes>
      <DeviceType id="ring_element">
      ...
      </DeviceType>
      <SupervisorType id="">
      </SupervisorType>
    </DeviceTypes>
  </GraphType>
  ...
</Graphs>
~~~

This supervisor type holds a single input pin, so that ring element devices can
send messages to it using their implicit connection. When the supervisor device
receives a message, it increments a counter indexed by the sender. Then, if it
has received $N$ messages from all devices, it opens a file and writes "1" to
it. If the supervisor receives too many messages from a given device, it
instead opens a file and writes "0" to it, denoting application failure. If the
application fails in this way, it doesn't process any more messages. The full
supervisor type definition is:

~~~ {.xml}
...
      <SupervisorType id="">
        <!-- There is one supervisor device type in a given application. This
             particular supervisor is written assuming there is only one
             instance for simplicity.
        -->
        <Code><![CDATA[
#include <stdio.h>  /* For writing an output file */
#include <vector>  /* Defines the type for `messagesPerDevice` */
        ]]></Code>
        <State><![CDATA[
/* Holds state information to ensure each ring member has seen the packet an
 * appropriate number of times. */
std::vector<uint8_t> messagesPerDevice;

/* Ominous. */
bool failed = false;
bool finished = false;

/* Output file. */
FILE* resultFile;
        ]]></State>
        <OnInit><![CDATA[
SUPSTATE(messagesPerDevice) = \
    std::vector<uint8_t>(GRAPHPROPERTIES(numDevices), 0);
SUPSTATE(resultFile) = fopen("ring_test_output", "w");
        ]]></OnInit>
        <SupervisorInPin id="" messageTypeId="exfiltration">
          <OnReceive><![CDATA[
/* If the application has failed, don't act on any more messages. */
if (!SUPSTATE(failed))
{
    /* Failure condition: once we've finished, we fail if we receive any more
     * messages. Also, fail if we receive a message that has done too many
     * laps. Note that this does not fail if the messages are received out of
     * order - POETS guarantees delivery, not ordering. */
    if (MSG(lap) > GRAPHPROPERTIES(maxLaps) or SUPSTATE(finished))
    {
        SUPSTATE(failed) = true;
        fprintf(SUPSTATE(resultFile), "0");
    }

    /* If we've not failed, track the message, and check the finishing
     * condition. */
    else
    {
        SUPSTATE(messagesPerDevice).at(MSG(sourceId)) += 1;

        /* Check the finishing condition. */
        SUPSTATE(finished) = true;
        for (std::vector<uint8_t>::size_type index = 0;
             index < GRAPHPROPERTIES(numDevices); index++)
        {
            if (SUPSTATE(messagesPerDevice).at(index) !=
                GRAPHPROPERTIES(maxLaps) + 1)
            {
                SUPSTATE(finished) = false;
                break;
            }
        }

        /* Check the finish condition. */
        if (SUPSTATE(finished))
        {
            fprintf(SUPSTATE(resultFile), "1");
        }
    }
}
          ]]></OnReceive>
        </SupervisorInPin>
        <OnStop><![CDATA[
fclose(SUPSTATE(resultFile));
        ]]></OnStop>
      </SupervisorType>
...
~~~

The `Code` section holds free code (includes, in this case) accessible to
supervisor behaviours. Here, the `stdio` library from C is included, along with
the `vector` header from the Standard Template Library in C++. The `State`
section is analogous to the state of normal devices. Here two booleans
(`failed` and `finished`) are declared with a default value, an output file
pointer (`resultFile`) is declared, and a vector that holds the number of
messages received from each device (`messagesPerDevice`) is declared. Both
`resultFile` and `messagesPerDevice` are given initial definitions in the
`OnInit` section. Also note that the file is closed in the `OnStop` section,
which is called when either the Orchestrator is closed down, or the application
is commanded to stop by the operator (see Orchestrator Documentation Volume
IV).

The `SupervisorInPin` section introduces an input pin type, which consumes a
(new type of) "`exfiltration`" messages. The source in the `OnReceive` element,
analogous to `OnReceive` elements for normal devices, encapsulates the logic
the supervisor needs to execute when it receives a message.

This logic requires another graph-level property to identify the number of
normal devices in the application. This property must be initialised without a
default, as it must be defined by the `GraphInstance` section later. The
following change introduces this property:

~~~ {.xml}
...
  <GraphType id="ring_test_type">
    <Properties><![CDATA[
uint8_t maxLaps = 9;  /* Zero-based indexing */
uint8_t numDevices;   /* Defined in the graph instance section, used by the
                       * supervisor */
    ]]></Properties>
  </GraphType>
...
~~~

This logic also requires an additional "`exfiltration"` message type to be
defined, and requires that field is populated by the sender. The following
changes are necessary:

~~~ {.xml}
...
  <GraphType id="ring_test_type">
    ...
    <MessageTypes>
      <MessageType id="exfiltration">
          <Message><![CDATA[
uint8_t sourceId;
uint8_t lap;
          ]]></Message>
      </MessageType>
      <MessageType id="ring_propagate">
          <Message><![CDATA[
uint8_t lap;
          ]]></Message>
      </MessageType>
    </MessageTypes>
    <DeviceTypes>
      <DeviceType id="ring_element">
        ...
        <SupervisorOutPin messageTypeId="exfiltration">
          <OnSend><![CDATA[
/* Define the fields in the message. */
MSG(sourceId) = DEVICEPROPERTIES(id);
MSG(lap) = DEVICESTATE(lap);

/* Since we're sending a message, reset this field so that we don't send
 * another one. */
DEVICESTATE(sendMessage) = 0;
          ]]></OnSend>
        </SupervisorOutPin>
        ...
        <ReadyToSend><![CDATA[
/* If the input behaviour determined that we should send a message, do so to the
 * next normal device in the ring, and to our supervisor device. */
if (DEVICESTATE(sendMessage) == 1)
{
    RTS(sender);
    RTSSUP();
}
        ]]></ReadyToSend>

      </DeviceType>
      ...
    </DeviceTypes>
  </GraphType>
...
~~~

The above change defines the payload for the new "`exfiltration`" message type,
adds a `SupervisorOutPin` to facilitate an implicit output connection with the
supervisor, and includes the additional `RTSSUP` macro call in the
`ReadyToSend` element, to ensure all messages go to the supervisor device as
well as the next device in the ring.

Following this example, the `GraphType` section now matches with the complete
XML at the end of this section.

## Defining a Graph Instance

Given a complete `GraphType` definition, an instance of the ring test
application can be created, which can be loaded by the Orchestrator and
executed using the POETS compute system. Beginning from the previous Section:

~~~ {.xml}
<?xml version="1.0"?>
<Graphs xmlns="" appname="ring_test">
  <GraphType id="ring_test_type">
    ...
  </GraphType>
  <GraphInstance id="ring_test_instance" graphTypeId="ring_test_type">
  </GraphInstance>
</Graphs>
~~~

we define the graph level property required for the supervisor:

~~~ {.xml}
...
  <GraphInstance id="ring_test_instance" graphTypeId="ring_test_type" P="5">
  </GraphInstance>
...
~~~

The value of `5` populates the first property declared in
`:GraphType-Properties:` - multiple properties can be defined using C++14
initialiser-list syntax (e.g. `5,7`). This particular property is used by the
supervisor logic to capture the number of devices it is supervising (to track
incoming messages). Consequently, we instantiate exactly five devices:

~~~ {.xml}
...
  <GraphInstance id="ring_test_instance" graphTypeId="ring_test_type" P="{5}">
    <DeviceInstances>
      <DevI id="0" type="ring_element" P="{0}"/>
      <DevI id="1" type="ring_element" P="{1}"/>
      <DevI id="2" type="ring_element" P="{2}"/>
      <DevI id="3" type="ring_element" P="{3}"/>
      <DevI id="4" type="ring_element" P="{4}"/>
    </DeviceInstances>
  </GraphInstance>
...
~~~

Each device instance has a different value for its `id` property (defined in
the `P` element). Note that the `id` attribute of each `DevI` element can be
any alphanumeric, as long as they are unique. Each device instance is of the
`"ring_element"` device type. Note that we do not need to instantiate a
supervisor device, as the Orchestrator does this.

We then define the connections between devices:

~~~ {.xml}
...
  <GraphInstance id="ring_test_instance" graphTypeId="ring_test_type">
    ...
    <EdgeInstances>
      <EdgeI path="1:receiver-0:sender"/>
      <EdgeI path="2:receiver-1:sender"/>
      <EdgeI path="3:receiver-2:sender"/>
      <EdgeI path="4:receiver-3:sender"/>
      <EdgeI path="0:receiver-4:sender"/>
    </EdgeInstances>
  </GraphInstance>
...
~~~

By way of example, this first edge instance creates an edge between the
`sender` output pin of the device named `0`, and the `receiver` input pin of
the device named `1`. Note that connections are not defined between normal
devices and their supervisor device, as these connections are implicit (every
normal device can talk to their supervisor device over the implicit connection,
facilitated by `:DeviceType - SupervisorOutPin:`.

Now we have created a fully-defined application with both a graph type
definition (detailing the behaviour of normal devices, supervisor devices, and
their communication), and an instantiation (a given number of devices in a
certain configuration). The resulting file (see listing below) can be loaded in
the Orchestrator and run as a complete application (refer to Volume IV for
information on how to do this).

Further examples accompany the Orchestrator, and are available at
<https://github.com/POETSII/Orchestrator_examples>.

## The Complete XML

What follows is a complete application definition for the example presented in
the Ring Test example Section.

~~~ {.xml}
<?xml version="1.0"?>
<!-- A series of five devices connected in a directional ring. When a device
receives a message, it sends two messages: one to the next normal device in the
ring, and one to its supervisor device.

A message holds the "lap" it's on. Device zero increments the lap counter of a
message on receipt, and stops the packet after its tenth lap. Device zero is
also responsible for sending the initial packet.

The supervisor device records all received packets (including their sender and
the lap), and writes "1" to the output file ("ring_test_output") once the
packet has completed ten laps. If an inappropriate packet is received, the
supervisor device writes "0", and ignores all new packets.
-->
<Graphs xmlns="" appname="ring_test">
  <GraphType id="ring_test_type">
    <Properties><![CDATA[
uint8_t numDevices;   /* Defined in the graph instance section, used by the
                       * supervisor */
uint8_t maxLaps = 9;  /* Zero-based indexing */
    ]]></Properties>
    <MessageTypes>
      <!-- Communications between normal devices use this message type. -->
      <MessageType id="ring_propagate">
          <Message><![CDATA[
uint8_t lap;
          ]]></Message>
      </MessageType>
      <!-- Communications from normal devices to supervisor devices use this
           message type.
       -->
      <MessageType id="exfiltration">
          <Message><![CDATA[
uint8_t sourceId;
uint8_t lap;
          ]]></Message>
      </MessageType>
    </MessageTypes>

    <DeviceTypes>
      <DeviceType id="ring_element">
        <!-- This device type defines the behaviour of all elements in the
             ring.
        -->
        <Properties>
          <!-- Properties remain constant throughout application execution, and
               are set in the DeviceInstances section.
          -->
          <![CDATA[
/* An identifier for this device, useful for supervisor communications. */
uint8_t id;
          ]]>
        </Properties>
        <State>
          <!-- State can change throughout application execution, and is
               initialised here (though it can be initialised in the
               DeviceInstances section).
          -->
            <![CDATA[
/* Holds the lap for the most recently-received message. Is used to define the
 * lap for outgoing messages. */
uint8_t lap = 0;

/* When a message is received, this field is populated either with one (true)
 * or zero (false). */
uint8_t sendMessage = 0;
            ]]>
        </State>

        <SupervisorOutPin messageTypeId="exfiltration">
          <OnSend><![CDATA[
/* Define the fields in the message. */
MSG(sourceId) = DEVICEPROPERTIES(id);
MSG(lap) = DEVICESTATE(lap);

/* Since we're sending a message, reset this field so that we don't send
 * another one. */
DEVICESTATE(sendMessage) = 0;
          ]]></OnSend>
        </SupervisorOutPin>

        <InputPin name="receiver" messageTypeId="ring_propagate">
          <OnReceive><![CDATA[
/* Only device zero increments the lap counter. Remember - this field in the
 * state is later propagated into the message. */
DEVICESTATE(lap) = MSG(lap);
if (DEVICEPROPERTIES(id) == 0) DEVICESTATE(lap) += 1;

/* Don't send a message if the incoming message has completed its tenth lap. */
if (DEVICESTATE(lap) <= GRAPHPROPERTIES(maxLaps)) DEVICESTATE(sendMessage) = 1;
else DEVICESTATE(sendMessage) = 0;
          ]]></OnReceive>
        </InputPin>

        <OutputPin name="sender" messageTypeId="ring_propagate">
          <OnSend><![CDATA[
/* Define the fields in the message. */
MSG(lap) = DEVICESTATE(lap);

/* Since we're sending a message, reset this field so that we don't send
 * another one. */
DEVICESTATE(sendMessage) = 0;
          ]]></OnSend>
        </OutputPin>
        <!-- This behaviour is invoked after a message is received, and after
             OnInit (if it returns nonzero).
        -->
        <ReadyToSend><![CDATA[
/* If the input behaviour determined that we should send a message, do so to the
 * next normal device in the ring, and to our supervisor device. */
if (DEVICESTATE(sendMessage) == 1)
{
    RTS(sender);
    RTSSUP();
}
        ]]></ReadyToSend>
        <!-- Initialisation logic. -->
        <OnInit><![CDATA[
/* Device zero starts things off by telling the ReadyToSend behaviour to send a
 * message. No other device does this. */
if (DEVICEPROPERTIES(id) == 0) DEVICESTATE(sendMessage) = 1;

/* A return of one invokes ReadyToSend (in the default Softswitch), whereas a
 * return of zero does not. */
return DEVICESTATE(sendMessage);
        ]]></OnInit>
      </DeviceType>

      <SupervisorType id="">
        <!-- There is one supervisor device type in a given application. This
             particular supervisor is written assuming there is only one
             instance for simplicity.
        -->
        <Code><![CDATA[
#include <stdio.h>  /* For writing an output file */
#include <vector>  /* Defines the type for `messagesPerDevice` */
        ]]></Code>
        <State><![CDATA[
/* Holds state information to ensure each ring member has seen the packet an
 * appropriate number of times. */
std::vector<uint8_t> messagesPerDevice;

/* Ominous. */
bool failed = false;
bool finished = false;

/* Output file. */
FILE* resultFile;
        ]]></State>
        <OnInit><![CDATA[
SUPSTATE(messagesPerDevice) = \
    std::vector<uint8_t>(GRAPHPROPERTIES(numDevices), 0);
SUPSTATE(resultFile) = fopen("ring_test_output", "w");
        ]]></OnInit>
        <SupervisorInPin id="" messageTypeId="exfiltration">
          <OnReceive><![CDATA[
/* If the application has failed, don't act on any more messages. */
if (!SUPSTATE(failed))
{
    /* Failure condition: once we've finished, we fail if we receive any more
     * messages. Also, fail if we receive a message that has done too many
     * laps. Note that this does not fail if the messages are received out of
     * order - POETS guarantees delivery, not ordering. */
    if (MSG(lap) > GRAPHPROPERTIES(maxLaps) or SUPSTATE(finished))
    {
        SUPSTATE(failed) = true;
        fprintf(SUPSTATE(resultFile), "0");
    }

    /* If we've not failed, track the message, and check the finishing
     * condition. */
    else
    {
        SUPSTATE(messagesPerDevice).at(MSG(sourceId)) += 1;

        /* Check the finishing condition. */
        SUPSTATE(finished) = true;
        for (std::vector<uint8_t>::size_type index = 0;
             index < GRAPHPROPERTIES(numDevices); index++)
        {
            if (SUPSTATE(messagesPerDevice).at(index) !=
                GRAPHPROPERTIES(maxLaps) + 1)
            {
                SUPSTATE(finished) = false;
                break;
            }
        }

        /* Check the finish condition. */
        if (SUPSTATE(finished))
        {
            fprintf(SUPSTATE(resultFile), "1");
        }
    }
}
          ]]></OnReceive>
        </SupervisorInPin>
        <OnStop><![CDATA[
fclose(supervisorState->resultFile);
        ]]></OnStop>
      </SupervisorType>
    </DeviceTypes>
  </GraphType>
  <GraphInstance id="ring_test_instance" graphTypeId="ring_test_type" P="{5}">
    <DeviceInstances>
      <DevI id="0" type="ring_element" P="{0}"/>
      <DevI id="1" type="ring_element" P="{1}"/>
      <DevI id="2" type="ring_element" P="{2}"/>
      <DevI id="3" type="ring_element" P="{3}"/>
      <DevI id="4" type="ring_element" P="{4}"/>
    </DeviceInstances>
    <EdgeInstances>
      <EdgeI path="1:receiver-0:sender"/>
      <EdgeI path="2:receiver-1:sender"/>
      <EdgeI path="3:receiver-2:sender"/>
      <EdgeI path="4:receiver-3:sender"/>
      <EdgeI path="0:receiver-4:sender"/>
    </EdgeInstances>
  </GraphInstance>
</Graphs>
~~~

# Appendix A: Legacy Variable Synonyms for Macros

Many of the macros listed in the "Accessibility Macros and Functions" section
access variables defined by the Orchestrator during application
composition. Table 3 lists these variable synonyms accessed by the above
macros, which are included for legacy use only. Table 4 maps the macros above
to these variable synonyms.

+------------------------+----------------------------------------------------+
| Variable               | Meaning (All variables are pointers to structures) |
+========================+====================================================+
| `deviceProperties`     | The target structure defines one field for each    |
|                        | variable defined in the `CFRAG` in                 |
|                        | `DeviceType/Properties`.                           |
+------------------------+----------------------------------------------------+
| `deviceState`          | The target structure defines one field for each    |
|                        | variable defined (or at least declared) in the     |
|                        | `CFRAG` in `DeviceType/State`.                     |
+------------------------+----------------------------------------------------+
| `graphProperties`      | The target structure defines one field for each    |
|                        | variable defined in the `CFRAG` in                 |
|                        | `GraphType/Properties`.                            |
+------------------------+----------------------------------------------------+
| `message`              | The target structure defines one field for each    |
|                        | variable declared in the `CFRAG` in `MessageType`, |
|                        | for the message type with `id` attribute matching  |
|                        | the `messageTypeId` attribute of the pin element   |
|                        | using this variable.                               |
+------------------------+----------------------------------------------------+
| `edgeProperties`       | The target structure defines one field for each    |
|                        | variable defined in the `CFRAG` in the `Properties`|
|                        | element in the input pin element using this        |
|                        | variable.                                          |
+------------------------+----------------------------------------------------+
| `edgeState`            | The target structure defines one field for each    |
|                        | variable defined (or at least declared) in the     |
|                        | `CFRAG` in the `Properties` element in the input   |
|                        | pin element using this variable.                   |
+------------------------+----------------------------------------------------+
| `readyToSend`          | The target structure (defining `|=`) holds one     |
|                        | flag for each `OutputPin` associated with this     |
|                        | `DeviceType`. The names of these flags are the     |
|                        | names of each `OutputPin` as defined by their      |
|                        | `name` attribute, prefixed with "`RTS_FLAG_`". At  |
|                        | the beginning of the `readyToSend` behaviour, each |
|                        | of these flags is lowered, and can be raised using |
|                        | the `|=` operator. For each flag, if it is raised  |
|                        | after the behaviour has been executed, a message is|
|                        | sent sent over that `OutputPin`. To send a message |
|                        | over the implicit supervisor output pin, raise the |
|                        | flag "`RTS_SUPER_IMPLICIT_SEND_FLAG`". The order   |
|                        | in which behaviours are executed are undefined,    |
|                        | except that the implicit supervisor behaviour is   |
|                        | invoked last.                                      |
+------------------------+----------------------------------------------------+
| `supervisorProperties` | The target structure defines one field for each    |
|                        | variable defined in the `CFRAG` in                 |
|                        | `SupervisorType/Properties`.                       |
+------------------------+----------------------------------------------------+
| `supervisorState`      | The target structure defines one field for each    |
|                        | variable defined (or at least declared) in the     |
|                        | `CFRAG` in `SupervisorType/State`.                 |
+------------------------+----------------------------------------------------+

Table: Explanation of legacy variables exposed to `CDATA` code.

+---------------------------+-------------------------------------------------+
| Macro                     | Variable Synonym                                |
+===========================+=================================================+
| `GRAPHPROPERTIES(x)`      | `graphProperties->x`                            |
+---------------------------+-------------------------------------------------+
| `DEVICEPROPERTIES(x)`     | `deviceProperties->x`                           |
+---------------------------+-------------------------------------------------+
| `DEVICESTATE(x)`          | `deviceState->x`                                |
+---------------------------+-------------------------------------------------+
| `SUPPROPERTIES(x)`        | `supervisorProperties->x`                       |
+---------------------------+-------------------------------------------------+
| `SUPSTATE(x)`             | `supervisorState->x`                            |
+---------------------------+-------------------------------------------------+
| `EDGEPROPERTIES(x)`       | `edgeProperties->x`                             |
+---------------------------+-------------------------------------------------+
| `EDGESTATE(x)`            | `edgeState->x`                                  |
+---------------------------+-------------------------------------------------+
| `MSG(x)` (`PKT(x)`)       | `message->x`                                    |
+---------------------------+-------------------------------------------------+
| `RTS(x)`                  | `*readyToSend |= RTS_FLAG_##x`                  |
+---------------------------+-------------------------------------------------+
| `RTSSUP()`                | `*readyToSend |= RTS_SUPER_IMPLICIT_SEND_FLAG`  |
+---------------------------+-------------------------------------------------+

Table: Mapping of accessibility macros to legacy variables.

# Glossary of Terms

Application:

: Defined by the user, applications perform computation and output information
  using the POETS compute system. See the Applications as Graphs Section.

Behaviour:

: A set of instructions, provided by the application writer as C++14 source
  code, to be invoked in response to an event occurring. See all terms ending
  in "(behaviour)".

Device:

: A "unit of compute", responsible for taking part in an application. Devices
  work together to execute an application. For classes of device, see **Normal
  Device** and **Supervisor Device**. For device typing and instances, see
  **Device Type** and **Device Instance**.

Device Instance:

: A single "unit of compute" that takes part in an application by (typically)
  sending messages to other devices. All device instances have a device type.

Device Type:

: Behaviour common to a set of devices (that share this type). Normal devices
  may have different types, though all supervisor devices have the same
  type. Normal device types may have properties and initial state, though these
  can be overridden on a per-instance basis.

Edge (instance):

: A directed connection between two minor nodes in the tripartite application
  graph (i.e. from the output pin of one device to the input pin of another (or
  the same) device). Messages sent from devices traverse edges.

Handler:

: Synonym for Behaviour

Input Pin:

: A pin, attached to a device, and the receiving end of one or more
  edges. Messages received by this pin are handled by its "OnReceive" behaviour,
  which may draw from the properties and state of the input pin.

Message (Orchestrator):

: The medium of communication for processes in the Orchestrator, which is a
  multi-process software, using MPI, that manages applications running on
  POETS. Not to be confused with **Message (POETS)**, also known as **Packet**.

Message (POETS)

: A representation of a packet, used to communicate between two
  devices. Messages are lightweight, and are guaranteed to eventually arrive at
  their destination, though are not guaranteed to arrive in the order they are
  sent. Messages may have a payload, populated by the sender. Not to be
  confused with **Message (Orchestrator)**

Normal Device:

: A device that participates in an application as part of the underlying POETS
  compute fabric.

OnInit (behaviour):

: See the definition provided in Appendix A.

OnDeviceIdle(behaviour):

: See the definition provided in Appendix A.

OnReceive (behaviour):

: A behaviour, called in response to a message being received on a pin, which
  changes the state of the device that owns the pin that owns this
  behaviour. Once a message is received, messages may be sent (according to the
  behaviour of the ReadyToSend behaviour.

OnSend (behaviour):

: A behaviour, called when a message has been sent (as instructed by the
  ReadyToSend behaviour). This behaviour populates the content of the outgoing
  message, and may change the state of the device that owns the pin that owns
  this behaviour.

Output Pin:

: A pin, attached to a device, and the sending end of one or more
  edges. Messages sent by this pin are populated by its "OnSend"
  behaviour. Output pins have no properties or state.

Packet:

: See **Message (POETS)**.

Pin:

: A node in the minor set of nodes in the tripartite application graph. Also
  see **Input Pin** and **Output Pin**.

Properties (graph, device, input pin):

: Fields with values that are constant with respect to application execution,
  defined either on the graph level, device level, or input pin
  level. Properties can be accessed through the structures introduced in the
  Source Code Fragments (:CDATA:) Section. See also **State**.

ReadyToSend (behaviour):

: A behaviour, called in response to a message being received, or a non-zero
  return value from OnInit or OnDeviceIdle behaviours. Determines, from the
  state of the device, which output pins are to be "activated" for sending
  messages. Also see the definition in Appendix A.

State (device, pin):

: Fields with values that may change during application execution, defined
  either on the device level or input pin level. State can be accessed through
  the structures introduced in the Source Code Fragments (:CDATA:) Section. See
  also **Properties**.

Supervisor Device:

: A device that participates in an application on the host machine (typically a
  more-powerful x86 server). A many-to-one relationship exists between normal
  devices and supervisor devices.
