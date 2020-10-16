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
contain loops, disconnected regions, and isolated vertices. With reference to
Figure 1:

[^dis]: For example, finite-difference or finite-element schemes where space is
    tiled (sometimes irregularly), in order to "break up" computation.

 - The major set of nodes (black circles) represent "Devices"
   (`:DeviceInstances:`), which each capture the behaviour of a vertex in the
   discretised problem. A device could represent a (set of) vertex/ices in the
   finite-difference mesh, or a/n (set of) element/s in a finite-element
   discretisation. Each device has machine instructions associated with it
   to perform computation (`:CDATA:`).

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
   pin. Each input/output pin can have multiple input/output edges connected
   to/from it.

![A graph representation of an application. Computation is performed by
"Devices", and communication is facilitated by "Pins" and "Edges".](images/application_graph_simple.png)

Applications in POETS can consist of millions of devices, each with thousands
of connections to other devices. The design intent is that device behaviour is
as atomic and local as possible, and results in emergent macroscale
behaviour. There exists no notion of global application state, as devices only
operate on information visible to them, or that they request from neighbouring
devices.

## Types and Instances

As an application can contain many devices, a typing system (`:GraphType:`)
exists to define properties, initial state, code, and pin types for a set of
devices in the application. An application will instantiate each device with a
type (`:DevI:`). Definitions:

 - **Properties** (`:DeviceType-Properties:`) define attributes of all devices
   of the type, which remain constant throughout the execution of the
   application. The value of a property can be overriden on a per-device basis
   (`:DevI-Properties:`).

 - **Initial State** (`:DeviceType-State:`) defines attributes that can change
   during execution, but are initialised to a certain value. The initial value
   of a state can be overriden on a per-device basis (`:DevI-State:`), and is
   free to differ across devices as an application executes.

 - **Code** defines the behaviours for devices of this type, which are invoked
   in response to input messages (`:InputPin-OnReceive:`), in response to
   sending a message (`:OutputPin-OnReceive:`), on initialisation
   (`:DeviceType-OnInit:`), and when no computation is being carried out
   (`:DeviceType-OnDeviceIdle:`).

 - **Output Pin Types** hold code (`:OutputPin-OnSend:`) to define the contents
   of messages sent from them. Output pins can read the properties of the
   device that contains them, and can alter its state, which is useful to
   locally "track" that a message has been sent

 - **Input Pin Types** also hold code (`:InputPin-OnReceive:`) to read in
   messages, and to influence the device that contains them. Input pins also
   hold property (`:InputPin-Properties:`) and state (`:InputPin-State:`)
   information, to support "weighting" of messages.

The messages that devices use to communicate also have types
(`:MessageTypes:`), which determines the fields of its payload. Each pin type
is associated with a message type (`:MessageType:`) - if it is an input/output
pin, then it can only receive/send messages of that type. This typing mechanism
allows messages to be populated by the code of the sender
(`:OutputPin-OnSend:`), and decoded by the receiver (`:InputPin-OnReceive:`).

 Pins are
instantiated by edge connections (`:EdgeI:`). A device can have types of pins
that are not connected - for example, a device instance (`:DevI:`) can have a
type with a defined input pin, but not have any connections that use that input
pin.

## Supervisor Devices

Supervisor devices are an optional component of a POETS application, which
allow application writers to define behaviours at a centralised point. Unlike
normal devices[^normal] which run on POETS hardware, supervisor devices run on
the host machine, making them suitable for file I/O and heavier compute
loads. Also unlike normal devices (`:DevI:`), supervisor devices are not
instantiated by the application writer. If a supervisor device is required, the
supervisor device type (`:SupervisorType:`) can be defined by the application
writer (one per application), and the Orchestrator will instantiate supervisor
devices automatically.

[^normal]: Prior to the introduction of supervisor devices in this document,
    the term "devices" specifically referred to normal devices for
    simplicity. Going forwards, this document makes an explicit distinction
    between "normal devices" and "supervisor devices" where possible.

Supervisor devices have input pins (`:SupervisorType - SupervisorInPin:`),
output (`:SupervisorType - SupervisorOutPin:`) pins. Edges (`:EdgeI:`) can be
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
**All normal devices have an implicit connection to their supervisor device.**

# Walk Through Example

Because it's easier to learn by example than by trawling through a
specification.

# Application Files

This section outlines how each of the features described in the "Applications
as Graphs" section manifest as an application file (XML), which is consumed by
the Orchestrator. The Orchestrator accepts only application files encoded in
ASCII. Prior to defining each element and attribute in detail, behaviours that
are common to a significant number of concepts in the application definition
are introduced. Then, each of the following subsections describes a
(semantically-acceptable) element of the XML tree:

~~~
Graphs                (4.2)
-GraphType            (4.2.1)
--Properties          (4.2.1.1)
--SharedCode          (4.2.1.2)
--MessageTypes        (4.2.1.3)
---MessageType        (4.2.1.3.1)
--DeviceTypes         (4.2.1.4)
---DeviceType         (4.2.1.4.1)
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
---SupervisorType     (4.2.1.4.2)
----Code
----SupervisorInPin
-----OnReceive
----SupervisorOutPin
-----OnSend
----OnSupervisorIdle
-GraphInstance        (4.2.2)
--Properties          (4.2.2.1)
--DeviceInstances     (4.2.2.2)
---DevI               (4.2.2.2.1)
--EdgeInstances       (4.2.2.3)
---EdgeI              (4.2.2.3.1)
~~~

## Source Code Fragments (`:CDATA:`)

Application XML supports the use of `CDATA` sections to define various system
behaviours. Code in these sections should be written in C++11, and make no
assumptions of included non-standard libraries or functions that are not
introduced in this documentation. Table 1 shows the variables exposed to each
`CDATA` section. Table 2 explains what each variable introduced in Table 1
represents.

+------------------------------------------+----------------------------------+
| Containing Element                       | Provided Variables               |
+==========================================+==================================+
| `DeviceType / SupervisorInPin /`         | - `deviceProperties` (read-only) |
| `OnReceive`                              | - `deviceState`                  |
|                                          | - `graphProperties` (read-only)  |
|                                          | - `message` (read-only)          |
+------------------------------------------+----------------------------------+
| `DeviceType / SupervisorOutPin /`        | - `deviceProperties` (read-only) |
| `OnSend`                                 | - `deviceState`                  |
|                                          | - `graphProperties` (read-only)  |
|                                          | - `message`                      |
+------------------------------------------+----------------------------------+
| `InputPin / OnReceive`                   | - `deviceProperties` (read-only) |
|                                          | - `deviceState`                  |
|                                          | - `graphProperties` (read-only)  |
|                                          | - `message` (read-only)          |
|                                          | - `pinProperties` (read-only)    |
|                                          | - `pinState`                     |
+------------------------------------------+----------------------------------+
| `OutputPin / OnSend`                     | - `deviceProperties` (read-only) |
|                                          | - `deviceState`                  |
|                                          | - `graphProperties` (read-only)  |
|                                          | - `message`                      |
+------------------------------------------+----------------------------------+
| `ReadyToSend`                            | - `deviceProperties` (read-only) |
|                                          | - `deviceState`                  |
|                                          | - `graphProperties` (read-only)  |
|                                          | - `readyToSend`                  |
+------------------------------------------+----------------------------------+
| `OnInit`                                 | - `deviceProperties` (read-only) |
|                                          | - `deviceState`                  |
|                                          | - `graphProperties` (read-only)  |
+------------------------------------------+----------------------------------+
| `DeviceType / OnDeviceIdle`              | - `deviceProperties` (read-only) |
|                                          | - `deviceState`                  |
|                                          | - `graphProperties` (read-only)  |
+------------------------------------------+----------------------------------+
| `SupervisorType / SupervisorInPin /`     | - `deviceState`                  |
| `OnReceive`                              | - `graphProperties` (read-only)  |
|                                          | - `message` (read-only)          |
+------------------------------------------+----------------------------------+
| `SupervisorType / SupervisorOutPin /`    | - `deviceState`                  |
| `OnSend`                                 | - `graphProperties` (read-only)  |
|                                          | - `message`                      |
+------------------------------------------+----------------------------------+
| `OnSupervisorIdle`                       | - `deviceState`                  |
|                                          | - `graphProperties` (read-only)  |
+------------------------------------------+----------------------------------+
| Other elements                           | None                             |
+------------------------------------------+----------------------------------+

Table: Variables exposed to code written in `CDATA` sections.

+--------------------+--------------------------------------------------------+
| Variable           | Meaning (All variables are pointers to structures)     |
+====================+========================================================+
| `deviceProperties` | The target structure defines one field for each        |
|                    | variable defined in the `CFRAG` in                     |
|                    | `DeviceType/Properties`.                               |
+--------------------+--------------------------------------------------------+
| `deviceState`      | The target structure defines one field for each        |
|                    | variable defined (or at least declared) in the `CFRAG` |
|                    | in `DeviceType/State`.                                 |
+--------------------+--------------------------------------------------------+
| `graphProperties`  | The target structure defines one field for each        |
|                    | variable defined in the `CFRAG` in                     |
|                    | `GraphType/Properties`.                                |
+--------------------+--------------------------------------------------------+
| `message`          | The target structure defines one field for each        |
|                    | variable declared in the `CFRAG` in `MessageType`,     |
|                    | for the message type with `id` attribute matching the  |
|                    | `messageTypeId` attribute of the pin element using this|
|                    | variable.                                              |
+--------------------+--------------------------------------------------------+
| `pinProperties`    | The target structure defines one field for each        |
|                    | variable defined in the `CFRAG` in the `Properties`    |
|                    | element in the pin element using this variable.        |
+--------------------+--------------------------------------------------------+
| `pinState`         | The target structure defines one field for each        |
|                    | variable defined (or at least declared) in the `CFRAG` |
|                    | in the `Properties` element in the pin element using   |
|                    | this variable.                                         |
+--------------------+--------------------------------------------------------+
| `readyToSend`      | The target structure defines one field for each        |
|                    | `OutputPin` associated with this `DeviceType`. The     |
|                    | names of these fields are the names of each `OutputPin`|
|                    | as defined by their `name` attribute, prefixed with    |
|                    | "`RTS_FLAG_`". At the beginning of the `readyToSend`   |
|                    | handler, each of these fields is initialised to zero.  |
|                    | For each field, if it is one after the handler has been|
|                    | executed, a message is sent over that `OutputPin`.     |
+--------------------+--------------------------------------------------------+

Table: Explanation of variables exposed to `CDATA` code.

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
