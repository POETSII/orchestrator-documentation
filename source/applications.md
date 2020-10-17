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
devices in the application. All devices and all pins must have a defined
type. An application will instantiate each device with a type
(`:DevI:`). Definitions:

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
   sending a message (`:OutputPin-OnSend:`), on initialisation
   (`:DeviceType-OnInit:`), and when no computation is being carried out
   (`:OnDeviceIdle:`).

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

Pins are instantiated by edge connections (`:EdgeI:`). A device can have types
of pins that are not connected - for example, a device instance (`:DevI:`) can
have a type with a defined input pin, but not have any connections that use
that input pin.

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
Messages received by devices over the implicit supervisor connection are
handled by their Supervisor input pin (`:DeviceType - SupervisorInPin:`), and
likewise messages are sent over the implicit connection by their supervisor
output pin (`:DeviceType - SupervisorOutPin:`)

# Walk Through Example

Because it's easier to learn by example than by trawling through a
specification.

# Application Files

This section outlines how each of the features described in the "Applications
as Graphs" section manifest as an application file (XML), which is consumed by
the Orchestrator. The Orchestrator accepts only application files encoded in
ASCII.

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
|                                          | - `deviceState` (read-only)      |
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

## Expected Semantic Structure

This section introduces the meaning behind each element of the XML tree. The
order of elements on each level is free to vary without compromising the
semantic integrity of an application definition file. The XML tree structure
for a semantically-valid input file is:

~~~
Graphs
-GraphType
--Properties
--SharedCode
--MessageTypes
---MessageType
--DeviceTypes
---DeviceType
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
---SupervisorType
----Code
----SupervisorInPin
-----OnReceive
----SupervisorOutPin
-----OnSend
----OnSupervisorIdle
-GraphInstance
--Properties
--DeviceInstances
---DevI
--EdgeInstances
---EdgeI
~~~

**Graphs**

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

**Graphs/GraphType/Properties**

Defines graph-level properties (constant throughout execution), which can be
accessed by code fragments through the `graphProperties` structure
pointer. Members of the structure pointed to by `graphProperties` are defined
as `CDATA`.

This element must occur at most once in each `:GraphType:` section. No
attributes are valid.

**Graphs/GraphType/SharedCode**

Contains code common to all devices in an application. Useful for defining
constants and free functions for use in handler `CDATA` sections.

This element must occur at most once in each `:GraphType:` section. No
attributes are valid.

**Graphs/GraphType/MessageTypes**

Contains definitions for all payloads of all message types used in an
application. Message types may have different payload configurations.

This element must occur at most once in each `:GraphType:` section. No
attributes are valid.

**Graphs/GraphType/MessageTypes/MessageType** (`:MessageType:`)

Contains code that populates the fields for the message structure of this
message type.

This element may occur any number of times in each `:MessageTypes:` section
(once per message type), though each occurence must have a unique `id`
value. Valid attributes:

 - `id` (must occur exactly once): Used by pins to define the type of message
   they correspond to, via the `:messageTypeId:` attribute

**Graphs/GraphType/DeviceTypes**

Contains type definitions for all normal devices and supervisor devices.

This element must occur exactly once in each `:GraphType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType** (`:DeviceType`)

Contains the definitions for a single normal device type.

This element may occur any number of times in each `:DeviceTypes:` section
(once per normal device type), though each occurence must have a unique `id`
value. Valid attributes:

 - `id` (must occur exactly once): Used by a device instantiation list to
   define the type of a device instance (`:DevI:`).

**Graphs/GraphType/DeviceTypes/DeviceType/Properties**
(`:DeviceType-Properties:`)

Defines device-type-level properties (constant throughout execution), which can
be accessed by code fragments through the `deviceProperties` structure
pointer. Members of the structure pointed to by `deviceProperties` are defined
as `CDATA`.

This element must occur at most once in each `:DeviceType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/State** (`:DeviceType-State:`)

Defines device-type-level state (that can vary throughout execution), which can
be accessed by code fragments through the `deviceState` structure
pointer. Members of the structure pointed to by `deviceState` are defined as
`CDATA`.

This element must occur at most once in each `:DeviceType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/SharedCode**

Contains code common to all normal devices in an application. Useful for
defining constants and free functions for use in handler `CDATA` sections.

This element must occur at most once in each `:DeviceType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/SupervisorInPin** (`:DeviceType -
SupervisorInPin:`)

Included to maintain a consistent structure for pins - only contains an
`OnSend` element and nothing else.

This element must occur at most once in each `:DeviceType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/SupervisorInPin/OnReceive**

Contains code to handle an inbound message to the supervisor, which may change
the state of the device.

This element must occur exactly once in each `:SupervisorInPin:` section. No
attributed are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/SupervisorOutPin** (`:DeviceType -
SupervisorOutPin:`)

Included to maintain a consistent structure for pins - only contains an
`OnReceive` element and nothing else.

This element must occur at most once in each `:DeviceType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/SupervisorOutPin/OnSend**

Contains code that may populate an outbound message to the supervisor, and may
change the state of the device.

This element must occur exactly once in each `:SupervisorInPin:` section. No
attributed are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/InputPin** (`:InputPin:`)

Contains elements that together define an input pin type.

This element may occur any number of times in each `:DeviceType:` section
(once per input pin type), though each occurence must have a unique `name`
value. Valid attributes:

 - `name` (must occur exactly once): Used by edge instances to define the pin
   on which a message is to be received by a device

 - `messageTypeId` (must occur exactly once): Defines the type of message to be
   received by this pin. Must match with the `id` attribute of a message type
   defined in the `MessageTypes` section.

**Graphs/GraphType/DeviceTypes/DeviceType/InputPin/Properties**
(`:PinType-Properties:`)

Defines pin-type-level properties (constant throughout execution), which can be
accessed by code fragments through the `pinProperties` structure
pointer. Members of the structure pointed to by `pinProperties` are defined as
`CDATA`.

This element must occur at most once in each `:InputPin:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/DeviceType/InputPin/State** (`:PinType-State:`)

Defines pin-type-level state (that can vary throughout execution), which can be
accessed by code fragments through the `pinState` structure pointer. Members of
the structure pointed to by `pinState` are defined as `CDATA`.

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
(once per output pin type), though each occurence must have a unique `name`
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

Contains code that reads the state of the device, and determines whether any
messages are to be sent. Note that the state of the device cannot be modified
in this block. Execution of this block is dependent on the softswitch used,
though the default softswitch executes this block:

 - After a message has been received and handled by the handler code in
   `InputPin/OnReceive` or `SupervisorInPin/OnReceive`.

 - After the handler code in `OnDeviceIdle` executes and returns a non-zero
   unsigned value.

 - After the handler code in `OnInit` executes and returns a non-zero unsigned
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

Contains code that is executed by the device when the softswitch is in the
"idle" state. Under the default softswitch, this block is executed when no
devices have any messages to receive or send. If the code in this block returns
a non-zero unsigned value, the code in the `ReadyToSend` section is executed,
which may result in the sending of messages.

This element must occur at most once in each `:DeviceType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/SupervisorType**

Contains the type definition for all supervisor devices.

This element must occur at most once in each `:DeviceTypes:` section. Valid
attributes:

 - `id` (must occur exactly once): Currently unused.

 - `SupervisorInPin` (must occur at most once): Defines the `:SupervisorType -
   SupervisorInPin` to be used to consume incoming messages from normal devices
   over implicit connections. If this attribute is used, it must match the
   value of the `id` of a `:SupervisorType - SupervisorInPin`. If this
   attribute is not used, the implicit connections from normal devices to
   their supervisor device are disabled in this application.

 - `SupervisorOutPin` (must occur at most once): Defines the `:SupervisorType -
   SupervisorOutPin` to be used to send messages to normal devices over
   implicit connections. If this attribute is used, it must match the value of
   the `id` of a `:SupervisorType - SupervisorOutPin`. If this attribute is not
   used, the implicit connections from supervisor devices to their normal
   devices are disabled in this application.

**Graphs/GraphType/DeviceTypes/SupervisorType/Code**

Contains code common to all handler code for supervisor devices in an
application. Useful for defining constants and free functions for use in
handler `CDATA` sections.

This element must occur at most once in each `:SupervisorType:` section. No
attributes are valid.

**Graphs/GraphType/DeviceTypes/SupervisorType/SupervisorInPin**
(`:SupervisorType - SupervisorInPin:`)

Contains elements that together define an input pin type.

This element may occur any number of times in each `:SupervisorType:` section
(once per output pin type), though each occurence must have a unique `id`
value. Valid attributes:

 - `id` (must occur exactly once): Used by edge instances to define the pin on
   which a message is to be received by a supervisor device. Also may be used
   by the `SupervisorInPin` attribute to mark a pin as being the input pin for
   all implicit connections.

 - `messageTypeId` (must occur exactly once): Defines the type of message to be
   sent by this pin. Must match with the `id` attribute of a message type
   defined in the `MessageTypes` section.

**Graphs/GraphType/DeviceTypes/SupervisorType/SupervisorInPin/OnReceive**
(`:SupervisorInPin - OnReceive:`)

Contains code to handle an inbound message to the supervisor.

This element must occur exactly once in each `:SupervisorInPin:` section. No
attributed are valid.

**Graphs/GraphType/DeviceTypes/SupervisorType/SupervisorOutPin**
(`:SupervisorType - SupervisorOutPin:`)

Contains elements that together define an output pin type.

This element may occur any number of times in each `:SupervisorType:` section
(once per output pin type), though each occurence must have a unique `id`
value. Valid attributes:

 - `id` (must occur exactly once): Used by edge instances to define the pin on
   which a message is to be sent by a supervisor device. Also may be used by
   the `SupervisorOutPin` attribute to mark a pin as being the output pin for
   all implicit connections.

 - `messageTypeId` (must occur exactly once): Defines the type of message to be
   sent by this pin. Must match with the `id` attribute of a message type
   defined in the `MessageTypes` section.

**Graphs/GraphType/DeviceTypes/SupervisorType/SupervisorOutPin/OnSend**
(`:SupervisorOutPin - OnSend:`)

Contains code that may populate an outbound message from a supervisor device.

This element must occur exactly once in each `:SupervisorOutPin:` section. No
attributed are valid.

**Graphs/GraphType/DeviceTypes/SupervisorType/OnSupervisorIdle**
(`:OnSupervisorIdle:`)

Contains code that is executed by the supervisor device when no messages are
being received by the Mothership (and hence all supervisor devices from all
applications running on it)

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

**Graphs/GraphInstance/Properties**

Mark has no idea what this is for. When Graeme reads this document, he will
fill it in.

This element must occur at most once in each `GraphInstance` section. No
attributes are valid.

**Graphs/GraphInstance/DeviceInstances** (`:DeviceInstances:`)

Contains elements that instantiate every normal device in an application. If
this section contains no children, no normal devices are instantiated (a
supervisor device is still instantiated, though this is of questionable value
outside debugging).

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

 - `P` (must occur at most once): Default property definitions overriding type
   defaults. Define using the same syntax as the content of a `CDATA` section.

 - `S` (must occur at most once): Default initial state definitions overriding
   type defaults. Define using the same syntax as the content of a `CDATA`
   section.

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

 - `P` (must occur at most once): Default property definitions overriding type
   defaults for the input pin on the receiving device, if the receiving device
   is a normal device. Define using the same syntax as the content of a `CDATA`
   section. This attribute must be undefined if the receiving device is a
   supervisor device.

 - `S` (must occur at most once): Default initial state definitions overriding
   type defaults for the input pin on the receiving device, if the receiving
   device is a normal device. Define using the same syntax as the content of a
   `CDATA` section. This attribute must be undefined if the receiving device is
   a supervisor device.
