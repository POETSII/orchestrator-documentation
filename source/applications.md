% Application Definition

# Overview

Applications are consumed by the Orchestrator, and perform computation desired
by the user on POETS. This document outlines how applications are to be
written, by external software, in a form suitable for consumption by the
Orchestrator.

Applications in POETS are described as graphs, where vertices represent
"compute" behaviour, and edges represent "communication" behaviour. Such
applications must be realised as Extensible Markup Language (XML) files,
suitable for the Orchestrator. This document explains the properties of these
application-graphs conceptually, and how these graphs are represented in
POETS-XML along with examples. A surface-level understanding of event-based
computing concepts, and the design intent of the Orchestrator, is assumed.

This document introduces a series of concepts before introducing the semantics
of acceptable XML. Tags surrounded by colons, like `:This:`, relate a concept
to an appropriate XML chunk.

# Applications as Graphs

Event-based computing is appropriate for problems that can be decomposed into a
discrete mesh. This often manifests as a spatial discretisation[^dis], though
any domain that **remains constant with respect to the execution of the
application** is suitable. This decomposition results in connected "regions" of
the problem, which can be represented as a graph. Figure 1 shows an example of
this. Formally, application graphs are tripartite directed graphs, which may
contain loops and disconnected regions. With reference to Figure 1:

[^dis]: For example, finite-difference or finite-element schemes where space is
    tiled (sometimes irregularly), in order to "break up" computation.

 - The major set of nodes (black circles) represent "Devices"
   (`:DeviceInstances:`), which each capture the behaviour of a vertex in the
   discretised problem - it could be a vertex in the finite-difference mesh, or
   an element in a finite-element discretisation. Each device has machine
   instructions associated with it (introduced as C) to perform computation.

 - The minor set of edges (black arrows) represent "Edges" (`:EdgeInstances:`),
   which each capture communication behaviour between one communication mode
   between two devices. By way of example, a device could send a "start" type
   of message (`:MessageType:`) to another device along an edge, but would have
   to send a different "stop" type of message along a different edge.

 - The minor set of nodes (red and blue circles) represent "Pins"
   (`:InputPin:`, `:OutputPin:`). Input pins alter the behaviour of messages
   sent along the edges associated with them, which is useful to assign
   "weights" to communications along an edge (`:Pin-Properties:`,
   `:Pin-State:`). Each edge is associated with one input pin and one output
   pin. Each input/output pin can have multiple input/output edges connected to
   it.

![A graph representation of an application. Computation is performed by
"Devices", and communication is facilitated by "Pins" and "Edges".](images/application_graph_simple.png)

Applications in POETS can consist of millions of devices, each with thousands
of connections to other devices. The behaviour of the device is intended to be
as atomic and local as possible, supporting emergent macroscale
behaviour. There exists no notion of global application state, as devices only
operate on information visible to them, or that they request from neighbouring
devices.

## Types and Instances

As an application can contain many devices, a typing system (`:GraphType:`)
exists to define properties, initial state, code, and pin types for a set of
devices in the application without repetition, where:

 - **Properties** (`:DeviceType-Properties:`) define attributes of all devices
   of the type, which remain constant throughout the execution of the
   application. The value of a property can be overriden on a per-device basis
   (`:DevI-Properties:`).

 - **Initial State** (`:DeviceType-State:`) defines attributes that can change
   during execution, but are initialised to a certain value. The initial value
   of a state can be overriden on a per-device basis (`:DevI-State:`).

 - **Code** defines the behaviours for devices of this type, which are invoked
   in response to input messages (`:InputPin-OnReceive:`), in response to
   sending a message (`:OutputPin-OnReceive:`), on initialisation
   (`:DeviceType-OnInit:`), and when no computation is being carried out
   (`:DeviceType-OnDeviceIdle:`).

 - **Pin Types** hold property (`:InputPin-Properties:`,
   `:OutputPin-Properties:`), state (`:InputPin-State:`, `:OutputPin-State:`),
   and code (`:InputPin-OnReceive:`, `:OutputPin-OnSend:`) information for the
   types of pins that can be connected to devices of this type. A pin type only
   exists "in the context" of its containing device type.

The messages that devices use to communicate also have types
(`:MessageTypes:`), which determine their fields. Each pin type is associated
with a message type (`:MessageType:`) - if it is an input/output pin, then it
expects to receive/send a message of a certain type. This typing mechanism
allows messages to be populated by the code of the sender
(`:OutputPin-OnSend:`), and decoded by the receiver (`:InputPin-OnReceive:`).

An application will instantiate each device with a type (`:DevI:`). Pins are
instantiated by edge connections (`:EdgeI:`). A device can have types of pins
that are not connected - for example, a device instance (`:DevI:`) can have a
type with a defined input pin, but not have any connections that use that input
pin.

## Supervisor Devices

Supervisor devices are an optional component of a POETS application, which
allow application writers to define behaviours at a centralised point. Unlike
normal devices[^normal] which run on POETS hardware, supervisor devices run on
the host machine, making them suitable for file I/O. Also unlike normal devices
(`:DevI:`), supervisor devices are not instantiated by the application
writer. If a supervisor device is required, the supervisor device type
(`:SupervisorType:`) can be defined by the application writer (one per
application), and supervisor devices are instantiated automatically by the
Orchestrator.

[^normal]: Prior to the introduction of supervisor devices in this document,
    the term "devices" specifically referred to normal devices for
    simplicity. Going forwards, this document makes an explicit distinction
    between "normal devices" and "supervisor devices" where possible.

Supervisor devices have input (`:SupervisorType-SupervisorInPin:`) and output
(`:SupervisorType-SupervisorOutPin:`) pins, and edges (`:EdgeI`) can be
instantiated in the same way as with normal devices.

Two common uses for supervisor devices is in data exfiltration and application
termination. These uses require all normal devices in the application to
communicate with the supervisor, as the devices need to send the data to the
supervisor to exfiltrate it for the former use, and the supervisor needs to
know when normal devices have stopped sending to other normal devices for the
latter use. However, declaring one edge connecting each device to its
supervisor (or vice-versa) significantly increases the number of edge
declarations, resulting in a larger input file. Consequently, supervisors
support implicit input and output pins for communication with normal devices.

# Walk Through Example

Because it's easier to learn by example than by trawling through a
specification.

# Application Files

This section outlines how each of the features described in the "Applications
as Graphs" section manifest as an application file (XML), which is consumed by
the Orchestrator. Each of the following subsections describes a
(semantically-acceptable) element of the XML tree, as follows:

~~~
Graphs                (4.1)
-GraphType            (4.1.1)
--Properties          (4.1.1.1)
--SharedCode          (4.1.1.2)
--MessageTypes        (4.1.1.3)
---MessageType        (4.1.1.3.1)
--DeviceTypes         (4.1.1.4)
---DeviceType         (4.1.1.4.1)
----Properties
----State
----SharedCode
----SupervisorInPin
-----OnReceive
----SupervisorOutPin
-----OnSend
----InputPin
-----Properties
-----State
-----OnReceive
----OutputPin
-----OnSend
----ReadyToSend
----OnInit
----OnDeviceIdle
---SupervisorType     (4.1.1.4.2)
----Code
----SupervisorInPin
-----OnReceive
----SupervisorOutPin
-----OnSend
----OnSupervisorIdle
-GraphInstance        (4.1.2)
--Properties          (4.1.2.1)
--DeviceInstances     (4.1.2.2)
---DevI               (4.1.2.2.1)
--EdgeInstances       (4.1.2.3)
---EdgeI              (4.1.2.3.1)
~~~

## Graphs

This element exists because XML demands that a single root node exists in the
syntax tree.

This element must occur exactly once in each file. Valid attributes:

 - `xmlns` (must occur exactly once): Unused, ignored.

 - `formatMinorVersion` (must occur at most once): Unused, ignored.

 - `appname` (must occur exactly once): Defines the string used to reference
   this file in the Orchestrator.

### GraphType (`:GraphType:`)

Defines the types of devices, messages, and pins for applications, including
properties, state, and code.

This element must occur exactly once in each file, and must have exactly one
`id` attribute, which is used by the graph instance (`:GraphInstance:`) to
determine the types for instantiated application.

#### Properties

Defines graph-level properties (constant throughout execution), which can be
accessed by code fragments through the `graphProperties` structure
pointer. Members of the structure pointed to by `graphProperties` are defined
as `CDATA`.
