% Orchestrator Documentation Volume II: Application Definition

# Overview

Applications are consumed by the Orchestrator, and perform computation desired
by the user on POETS. Applications in POETS are described as graphs, where
vertices represent "compute" behaviour, and edges represent "communication"
behaviour. Such applications must be realised as eXtensible Markup Language
(XML) files, suitable for the Orchestrator. This document explains the
properties of these application-graphs conceptually, and how these graphs are
represented in POETS-XML along with examples. A surface-level understanding of
event-based computing concepts, and the design intent of the Orchestrator, is
assumed.

This document outlines how applications are to be written, by external software
or "by hand", in a form suitable for the Orchestrator. This document does not
include design decisions, past designs, future extensions or refactors, or
common design patterns. This document introduces a series of concepts before
introducing the semantics of acceptable XML. Tags surrounded by colons, like
`:GraphType:`, relate a concept to an appropriate XML chunk, and they
correspond to elements defined the "Application Files" Section.

# Applications as Graphs

Event-based computing is appropriate for problems that can be decomposed into a
discrete mesh. This often manifests as a spatial discretisation[^dis], though
any domain that **remains constant with respect to the execution of the
application** is suitable. This decomposition results in connected "regions" of
the problem, which can be represented as a graph[^formal]. Figure 1 shows an
example of this, where:

![A graph representation of an application. Computation is performed by
"Normal Devices", and communication is facilitated by "Pins" and
"Edges".](images/application_graph_simple.png)

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

 - The major set of nodes (black circles) represent "Normal Devices"
   (`:DeviceInstances:`), which each capture the behaviour of a node in the
   discretised problem. A normal device could represent a vertex in the
   finite-difference mesh, an element in a finite-element discretisation, or
   even a collection of vertices or elements. Each device has machine
   instructions associated with it to perform computation (`:CDATA:`).

 - The set of edges (black arrows) represent "Edges" (`:EdgeInstances:`), which
   each capture a "communication mode" between two devices. By way of example,
   a device could send a "start" type of message (`:MessageType:`) to another
   device along an edge, but would have to send a different "stop" type of
   message along a different edge.

 - The minor set of nodes (red and blue circles) represent "Pins"
   (`:InputPin:`, `:OutputPin:`). Input pins alter the behaviour of messages
   sent along the edges associated with them, which is useful to assign
   "weights" to communications along an edge (`:Pin-Properties:`,
   `:Pin-State:`). Each edge is associated with one input pin and one output
   pin. Each input/output pin can have multiple input/output edges connected
   to/from it, and can only receive/send messages of a single type. A device an
   have any number of input pins and output pins.

Applications in POETS can consist of millions of devices, each with thousands
of connections to other devices. The design intent is that normal device
behaviour is as atomic and local as possible, and results in emergent
macroscale behaviour. There exists no notion of global application state, as
devices only operate on information visible to them, or that they request from
neighbouring devices.

## Types and Instances

As an application can contain many normal devices, a typing system
(`:GraphType:`) exists to define properties, initial state, code, and pin types
for a set of normal devices in the application. This Section presents an
abridged, accessible definition for the main features of the typing system.

All devices and all pins must have a defined type. An application will
instantiate each device with a type (`:DevI:`), with:

 - **Properties** (`:DeviceType-Properties:`), which define attributes of all
   devices of the type that remain constant throughout the execution of the
   application. The value of a property can be overriden on a per-device basis
   (`:DevI-Properties:`).

 - **Initial State** (`:DeviceType-State:`), which defines attributes that can
   change during execution, but are initialised to a certain value. The initial
   value of a state can be overriden on a per-device basis (`:DevI-State:`),
   and is free to differ across devices as an application executes.

 - **Code**, which defines the behaviours for devices of this type, and are
   invoked in response to input messages (`:InputPin-OnReceive:`), in response
   to sending a message (`:OutputPin-OnSend:`), on initialisation
   (`:DeviceType-OnInit:`), and when no computation is being carried out
   (`:OnDeviceIdle:`).

 - **Output Pin Types**, which hold code (`:OutputPin-OnSend:`) to define the
   contents of messages sent from them. Output pins can read the properties of
   the device that contains them, and can alter its state, which is useful to
   locally "track" that a message has been sent.

 - **Input Pin Types**, which also hold code (`:InputPin-OnReceive:`) to read
   in messages, and to influence the device that contains them. Input pins also
   hold property (`:InputPin-Properties:`) and state (`:InputPin-State:`)
   information, to support "weighting" of messages.

The messages that devices use to communicate also have types
(`:MessageTypes:`), which determines the fields of their payload. Each pin type
is associated with a message type (`:MessageType:`) - if it is an input/output
pin, then it can only receive/send messages of that type. This typing mechanism
allows messages to be populated by the code of the sender
(`:OutputPin-OnSend:`), and decoded by the receiver (`:InputPin-OnReceive:`).

Pins are instantiated by edge connections (`:EdgeI:`). A device can have types
of pins that are not connected - for example, a device instance (`:DevI:`) can
have a type with a defined input pin, but not have any connections that use
that input pin.

A graph can also define properties (`:GraphType-Properties:`) and code
(`:GraphType-SharedCode:`) common to all devices and pins in the
application.

## Supervisor Devices

Supervisor devices^[Note that "Supervisor" in the context of POETS is not
related to supervisors in the context of UNIX-likes; the concepts are
completely different.] are an optional component of a POETS application, which
allow application writers to define behaviours at a centralised point. Unlike
normal devices which run on POETS hardware, supervisor devices run on the host
machine, making them suitable for file I/O and heavier compute
loads. Supervisor devices are both components of the Orchestrator (reachable by
messages over the Orchestrator's multiprocess communications mechanism), and
components of an application (reachable by messages from the POETS Engine).

Unlike normal devices (`:DevI:`), supervisor devices are not instantiated by
the application writer. If a supervisor device is required, the supervisor
device type (`:SupervisorType:`) can be defined by the application writer (one
per application), and the Orchestrator will instantiate supervisor devices
automatically, and connect them to normal devices. Supervisor devices have
input pins (`:SupervisorType - SupervisorInPin:`), output (`:SupervisorType -
SupervisorOutPin:`) pins.

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
output pin (`:DeviceType - SupervisorOutPin:`). Being "implicit", this
connection does not need to be defined in the edge instance (`:EdgeI:`) section
of the application definition.

# Example: Ring Test

This Section presents an example application, which is arrived at from a
high-level description of the intended behaviour. This is not intended to be as
detailed as the comprehensive description presented in the "Application Files"
section, but should be sufficient to educate the reader in writing simple
applications. A listing of the complete application, with additional comments,
is presented in Appendix A. For further information about elements presented in
this example, consult the "Application Files" Section. We recommend the reader
to follow along in their favourite text editor as concepts are introduced, to
see how components of the XML file connect together.

The desired application, "Ring Test", is similar to the ring oscillator device
in electrical engineering, in which "NOT" gates are connected in a ring to
oscillate the voltage state of a circuit. In the ring test, a message is to be
passed around a ring of devices multiple times. Each time the message is
received at a destination, the receiver informs the supervisor of the progress
of the message. After ten (=$N$) "laps" of the ring, the message is dropped and
the application is complete. When the supervisor is informed that the message
has completed $N$ laps, it writes a success value (1) to a file. If the
supervisor sees that the message has looped too many times, it writes a failure
value (0) to a file.

## Towards a Normal Device Type

To begin, we define the skeletal structure of the XML:

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
`ring_test`. An empty graph type is created, and an empty graph instance is
connected to that type - these will both be populated as we progress through
this example.

Within the `GraphType`, we can define the behaviour for the members of the
ring - the type of devices that are going to propagate our data around the
ring.

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

It is convenient at this point to define an identifier for the ring members -
one of them is going to have to start the application by sending a message
later, and it will be relevant for supervisor communications:

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

This declares a property of all ring elements, which should be defined when the
ring is instantiated later. Note that this property is defined in a `:CDATA:`
section, written in C++11. This property will be readable by other code
sections (for ring elements) via `deviceProperties->id`.

With a way to identify devices in code, we can define startup logic. We make
device zero be the first to send a message:

~~~ {.xml}
...
    <DeviceType id="ring_element">
      <Properties><![CDATA[
/* An identifier for this device, useful for supervisor communications. */
uint8_t id;
      ]]></Properties>
      <State><![CDATA[
/* When a message is received, this field is populated either with one (true)
* or zero (false). */
uint8_t sendMessage = 0;
      ]]></State>
      <OnInit><![CDATA[
/* Device zero starts things off by telling the ReadyToSend handler to send a
 * message. No other device does this. */
if (deviceProperties->id == 0) deviceState->sendMessage = 1;

/* A return of one invokes ReadyToSend (in the default softswitch), whereas a
 * return of zero does not. */
return deviceState->sendMessage;
      ]]></OnInit>
    </DeviceType>
...
~~~

A state field `sendMessage` is introduced here, with an initial value of
zero. This field will be read by another handler later, to determine whether a
message is to be sent or not. The code in the `:OnInit:` handler is run by each
device when the application starts. This handler sets the `sendMessage` field
in the state to one (so that a message will be sent later). The `:OnInit:`
handler also returns one on device zero, causing the `ReadyToSend` handler to
be invoked.

The `ReadyToSend` handler is responsible for determining whether messages
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
if (deviceState->sendMessage == 1) *readyToSend |= RTS_FLAG_sender;
      ]]></ReadyToSend>
    </DeviceType>
...
~~~

The `ReadyToSend` handler here checks whether another handler "wants a message
to be sent". If so, it sets a flag (`RTS_FLAG_sender`) in the `readyToSend`
structure. This flag is checked after the `ReadyToSend` handler is invoked, and
causes a message to be sent. In order to send a message in this way, an output
pin with the name "`sender`" must be defined for this type, as follows:

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
message->lap = deviceState->lap;

/* Since we're sending a message, reset this field so that we don't send
 * another one. */
deviceState->sendMessage = 0;
        ]]></OnSend>
      </OutputPin>
      ...
      <ReadyToSend><![CDATA[
if (deviceState->sendMessage == 1) *readyToSend |= RTS_FLAG_sender;
      ]]></ReadyToSend>
    </DeviceType>
...
~~~

Note that the `name` attribute on the output pin is "`sender`", which
corresponds to the suffix of the flag "`RTS_FLAG_sender`" used in the
`ReadyToSend` element. This is essential to ensure that the correct pin is
selected to send the message. Output pins define an `OnSend` handler - in this
case, the handler clears the `sendMessage` state set by `OnInit` (or another
handler, later on). It also defines the `lap` field in the payload of the
outgoing message from the state - to facilitate this, the state of ring element
devices is expanded to include a `lap` field.

Like pins and devices, all messages must have a defined type. The element
introducing the "`sender`" output pin also has attribute `messageTypeId` with
value "`ring_propagate`", so a message type must also be defined as follows:

~~~ {.xml}
...
    <MessageTypes>
      <MessageType id="ring_propagate"><![CDATA[
uint8_t lap;
      ]]></MessageType>
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
communications from output pins:

~~~ {.xml}
...
    <DeviceType id="ring_element">
      <InputPin name="receiver" messageTypeId="ring_propagate">
        <OnReceive><![CDATA[
/* Only device zero increments the lap counter. Remember - this field in the
 * state is later propagated into the message. */
deviceState->lap = message->lap;
if (deviceProperties->id == 0) deviceState->lap += 1;

/* Don't send a message if the incoming message has completed its tenth lap. */
if (deviceState->lap <= graphProperties->maxLaps) deviceState->sendMessage = 1;
else deviceState->sendMessage = 0;
        ]]></OnReceive>
      </InputPin>
      ...
    </DeviceType>
...
~~~

When a `"ring_propagate"` message is received on this input pin, the `"lap"`
state of the device is updated with the contents of the message. Only device
zero is permitted to increment the lap (as it is the origin point of the
message). Like the `OnInit` handler, this `OnReceive` handler sets the
`"sendMessage"` state of the device for the `ReadyToSend` handler (which is
called after `OnReceive`).

Note that the output pin name "`sender`" and the input pin name "`receiver`"
are not special - as long as their names are used consistently throughout the
XML where they are required.

Lastly, this handler requires the definition of a global `maxLaps` property,
which determines when the application should stop. This is defined on the graph
level, and will be accessible by all code fragments in the application:

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
      <MessageType id="ring_propagate"><![CDATA[
uint8_t lap;
      ]]></MessageType>
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
deviceState->lap = message->lap;
if (deviceProperties->id == 0) deviceState->lap += 1;

/* Don't send a message if the incoming message has completed its tenth lap. */
if (deviceState->lap <= graphProperties->maxLaps) deviceState->sendMessage = 1;
else deviceState->sendMessage = 0;
          ]]></OnReceive>
        </InputPin>
        <OutputPin name="sender" messageTypeId="ring_propagate">
          <OnSend><![CDATA[
/* Define the fields in the message. */
message->lap = deviceState->lap;

/* Since we're sending a message, reset this field so that we don't send
 * another one. */
deviceState->sendMessage = 0;
          ]]></OnSend>
        </OutputPin>
        <ReadyToSend><![CDATA[
if (deviceState->sendMessage == 1) *readyToSend |= RTS_FLAG_sender;
        ]]></ReadyToSend>
        <OnInit><![CDATA[
/* Device zero starts things off by telling the ReadyToSend handler to send a
 * message. No other device does this. */
if (deviceProperties->id == 0) deviceState->sendMessage = 1;

/* A return of one invokes ReadyToSend (in the default softswitch), whereas a
 * return of zero does not. */
return deviceState->sendMessage;
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
as it runs on the host machine, and can communicate with the other normal
devices in the application.

Starting from the output of the previous Section, we introduce a supervisor
device type alongside the ring element normal device type:

~~~ {.xml}
<?xml version="1.0"?>
<Graphs xmlns="" appname="ring_test">
  <GraphType id="ring_test_type">
    <DeviceTypes>
      <DeviceType id="ring_element">
      </DeviceType>
      <SupervisorType id="" SupervisorInPin="tracker">
      </SupervisorType>
    </DeviceTypes>
  </GraphType>
  ...
</Graphs>
~~~

This supervisor type holds a single input pin ("`tracker`"), so that ring
element devices can send messages to it using their implicit connection. When
the supervisor device receives a message, it increments a counter indexed by
the sender. Then, if it has received $N$ messages from all devices, it opens a
file and writes "1" to it. If the supervisor receives too many messages from a
given device, it instead opens a file and writes "0" to it, denoting
application failure. If the application fails in this way, it doesn't process
any more messages. The full supervisor type definition is:

~~~ {.xml}
...
      <SupervisorType id="" SupervisorInPin="tracker">
        <Code><![CDATA[
#include <stdio.h>  /* For writing an output file */

/* Holds state information to ensure each ring member has seen the packet an
 * appropriate number of times. */
uint8_t messagesPerDevice[graphProperties->numDevices];
for (uint8_t index = 0; index < graphProperties->numDevices; index++)
{
    messagesPerDevice[index] = 0;
}

/* Ominous. */
bool failed = false;
bool finished = false;
        ]]></Code>
        <SupervisorInPin id="tracker" messageTypeId="exfiltration">
          <OnReceive><![CDATA[
/* If the application has failed, don't act on any more messages. */
if (!failed)
{
    /* Failure condition: once we've finished, we fail if we receive any more
     * messages. Also, fail if we receive a message that has done too many
     * laps. Note that this does not fail if the messages are received out of
     * order - POETS guarantees delivery, not ordering. */
    if (message->lap > graphProperties->maxLaps or finished)
    {
        failed = true;
        FILE* resultFile = fopen("ring_test_output", "a");
        fprintf(resultFile, "0");
        fclose(resultFile);
    }

    /* If we've not failed, track the message, and check the finishing
     * condition. */
    else
    {
        messagesPerDevice[message->sourceId] += 1;

        /* Check the finishing condition. */
        finished = true;
        for (uint8_t index = 0; index < graphProperties->numDevices; index++)
        {
            if (messagesPerDevice[index] != graphProperties->maxLaps)
            {
                finished = false;
                break;
            }
        }

        /* Check the finish condition. */
        if (finished)
        {
            FILE* resultFile = fopen("ring_test_output", "a");
            fprintf(resultFile, "1");
            fclose(resultFile);
        }
    }
}
          ]]></OnReceive>
        </SupervisorInPin>
      </SupervisorType>
...
~~~

The `Code` section holds includes and variables accessible to supervisor
handlers - in this case, the `stdio` library from C is included, two booleans
(`failed` and `finished`) are initialised, as is an array that holds the number
of messages received from each device (initialised to zero). The
`SupervisorInPin` section introduces an input pin type named "`tracker`", which
consumes a new type of "`exfiltration`" messages. The source in the `OnReceive`
element, analogous to `OnReceive` elements for normal devices, encapsulates the
logic the supervisor needs to execute when it receives a message.

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
      <MessageType id="exfiltration"><![CDATA[
uint8_t sourceId;
uint8_t lap;
      ]]></MessageType>
      <MessageType id="only"><![CDATA[
uint8_t lap;
      ]]></MessageType>
    </MessageTypes>
    <DeviceTypes>
      <DeviceType id="ring_element">
        ...
        <SupervisorOutPin messageTypeId="exfiltration">
          <OnSend><![CDATA[
/* Define the fields in the message. */
message->sourceId = deviceProperties->id;
message->lap = deviceState->lap;

/* Since we're sending a message, reset this field so that we don't send
 * another one. */
deviceState->sendMessage = 0;
          ]]></OnSend>
        </SupervisorOutPin>
        ...
        <ReadyToSend><![CDATA[
/* If the input handler determined that we should send a message, do so to the
 * next normal device in the ring, and to our supervisor device. */
if (deviceState->sendMessage == 1)
{
    *readyToSend |= RTS_FLAG_sender;
    *readyToSend |= RTS_SUPER_IMPLICIT_SEND_FLAG;
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
supervisor, and includes the additional\
`RTS_SUPER_IMPLICIT_SEND_FLAG` in the
`ReadyToSend` element, to ensure all messages go to the supervisor device as
well as the next device in the ring.

Following this example, the `GraphType` section now matches with the complete
XML in Appendix A.

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
  <GraphInstance id="ring_test_instance" graphTypeId="ring_test_type">
    <Properties><![CDATA[
numDevices = 5;
    ]]></Properties>
  </GraphInstance>
...
~~~

This particular property is used by the supervisor logic to capture the number
of devices it is supervising (to track incoming messages). Consequently, we
instantiate exactly five devices:

~~~ {.xml}
...
  <GraphInstance id="ring_test_instance" graphTypeId="ring_test_type">
    <Properties><![CDATA[
numDevices = 5;
    ]]></Properties>
    <DeviceInstances>
      <DevI id="0" type="ring_element" P="id = 0"/>
      <DevI id="1" type="ring_element" P="id = 1"/>
      <DevI id="2" type="ring_element" P="id = 2"/>
      <DevI id="3" type="ring_element" P="id = 3"/>
      <DevI id="4" type="ring_element" P="id = 4"/>
    </DeviceInstances>
  </GraphInstance>
...
~~~

Each device instance has a different value for its `id` property (defined in
the `P` element). Note that the `id` attribute of each `DevI` element can be
any alphanumeric, as long as they are unique. Each device instance is of the
`"ring_element"` device type. Note that we do not need to instantiate a
supervisor device, as the Orchestrator does so as the application is handled.

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

For information on the path syntax, see the description of the `:EdgeI:`
element in the "Application Files" Section. Note that we do not define
connections between the normal devices and their supervisor device, as we are
using implicit connections to achieve this (every normal device can talk to
their supervisor device over the implicit connection, facilitated by
`:DeviceType - SupervisorOutPin:`.

Now we have created a fully-defined application with both a graph type
definition (detailing the behaviour of normal devices, supervisor devices, and
their communication), and an instantiation (a given number of devices in a
certain configuration). The resulting file (see Appendix A) can be loaded in
the Orchestrator and run as a complete application (see the Usage
documentation, or Orchestrator Volume IV, for further information on how to do
this).

# Writing for POETS Hardware

This Section provides a brief description of the POETS hardware, sufficient for
writing applications for the Orchestrator. For a more detailed description, see
the Tinsel documentation (at https://github.com/poetsii/tinsel)^[Specifically,
in README.md, visible if you scroll down past the source listing.]. Values here
are correct as of Tinsel 0.8.

Tinsel is the overlay architecture used on POETS hardware. The Tinsel system
operates on a series of connected FPGA boards, and implements a subset of the
RISCV32IMF instruction set profile. **This subset notably omits integer divison
(and the modulo operator as a consequence), and floating-point fused
instructions** (as the ALU doesn't support them). See the Tinsel documentation
for the full set of forbidden instructions.

Each board consists of two 4GB DDR3 DRAMs and four 8MB QDRII+ SRAMs, which are
shared evenly throughout the POETS Engine. The Softswitch (see
"softswitch.pdf") only makes use of these DRAMs to store properties, state, and
connections information at present. Consequently, **data space is limited**,
which imposes a constraint on the footprint of properties, state, and
connection information (though this has yet to become an issue in Orchestrator
applications).

Instruction memory is stored in on-chip RAM (8kB) shared between core pairs. As
such, **all threads across each pair of cores shares the same instruction
memory**. Put another way, this means that a given "neighbouring" pair of cores
in the POETS Engine can have only one type of device placed upon it (but can
have many instances of those types). This provides an intrisic communications
benefit to devices of the same type: since they can be placed on the same core
(pair), their communication is less latent. **Application writers must ensure
their application (and the supporting Softswitch infrastructure) together
optimise-compiles to fit in this on-chip RAM.** Also of note, **instruction
memory cannot be accessed explicitly using load and store instructions** (so no
cheating).

The Orchestrator will inform you during application composition if any of these
conditions is violated by the application (or its placement). If so, the
Orchestrator will refuse to build it.

# Application Files

This Section outlines how each of the features described in the "Applications
as Graphs" Section manifest as an application file (XML), which is consumed by
the Orchestrator. The Orchestrator accepts only application files encoded in
ASCII.

## Mark's Questions for Graeme

 - Do SupervisorInPins and SupervisorOutPins (on both normal and supervisor
   devices) have message types associated with them?

## Source Code Fragments (`:CDATA:`)

Application XML supports the use of `CDATA` sections to define various system
behaviours. Code in these sections should be written in C++14, and make no
assumptions of included non-standard libraries or functions that are not
introduced in this documentation. Table 1 shows the variables exposed to each
`CDATA` section. Table 2 explains what each variable introduced in Table 1
represents. Aside from these variables, avoid declaring variables with the `__`
prefix to avoid collisions with (internal) Softswitch data structures.

+--------------------------------------+--------------------------------------+
| Containing Element                   | Provided Variables                   |
+======================================+======================================+
| `DeviceType / SupervisorInPin /`     | - `deviceProperties` (read-only)     |
| `OnReceive`                          | - `deviceState`                      |
|                                      | - `graphProperties` (read-only)      |
|                                      | - `message` (read-only)              |
+--------------------------------------+--------------------------------------+
| `DeviceType / SupervisorOutPin /`    | - `deviceProperties` (read-only)     |
| `OnSend`                             | - `deviceState`                      |
|                                      | - `graphProperties` (read-only)      |
|                                      | - `message`                          |
+--------------------------------------+--------------------------------------+
| `InputPin / OnReceive`               | - `deviceProperties` (read-only)     |
|                                      | - `deviceState`                      |
|                                      | - `graphProperties` (read-only)      |
|                                      | - `message` (read-only)              |
|                                      | - `pinProperties` (read-only)        |
|                                      | - `pinState`                         |
+--------------------------------------+--------------------------------------+
| `OutputPin / OnSend`                 | - `deviceProperties` (read-only)     |
|                                      | - `deviceState`                      |
|                                      | - `graphProperties` (read-only)      |
|                                      | - `message`                          |
+--------------------------------------+--------------------------------------+
| `ReadyToSend`                        | - `deviceProperties` (read-only)     |
|                                      | - `deviceState` (read-only)          |
|                                      | - `graphProperties` (read-only)      |
|                                      | - `readyToSend`                      |
+--------------------------------------+--------------------------------------+
| `DeviceType / OnInit`                | - `deviceProperties` (read-only)     |
|                                      | - `deviceState`                      |
|                                      | - `graphProperties` (read-only)      |
+--------------------------------------+--------------------------------------+
| `DeviceType / OnDeviceIdle`          | - `deviceProperties` (read-only)     |
|                                      | - `deviceState`                      |
|                                      | - `graphProperties` (read-only)      |
+--------------------------------------+--------------------------------------+
| `SupervisorType / SupervisorInPin /` | - `supervisorProperties` (read-only) |
| `OnReceive`                          | - `supervisorState`                  |
|                                      | - `graphProperties` (read-only)      |
|                                      | - `message` (read-only)              |
+--------------------------------------+--------------------------------------+
| `SupervisorType / SupervisorOutPin`  | - `supervisorProperties` (read-only) |
| `/ OnSend`                           | - `supervisorState`                  |
|                                      | - `graphProperties` (read-only)      |
|                                      | - `message`                          |
+--------------------------------------+--------------------------------------+
| `SupervisorType / OnSupervisorIdle`  | - `supervisorProperties` (read-only) |
|                                      | - `supervisorState`                  |
|                                      | - `graphProperties` (read-only)      |
+--------------------------------------+--------------------------------------+
| `SupervisorType / OnInit`            | - `supervisorProperties` (read-only) |
|                                      | - `supervisorState`                  |
|                                      | - `graphProperties` (read-only)      |
+--------------------------------------+--------------------------------------+
| `SupervisorType / OnStop`            | - `supervisorProperties` (read-only) |
|                                      | - `supervisorState`                  |
|                                      | - `graphProperties` (read-only)      |
+--------------------------------------+--------------------------------------+
| Other elements                       | None                                 |
+--------------------------------------+--------------------------------------+

Table: Variables exposed to code written in `CDATA` sections.

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
| `pinProperties`        | The target structure defines one field for each    |
|                        | variable defined in the `CFRAG` in the `Properties`|
|                        | element in the pin element using this variable.    |
+------------------------+----------------------------------------------------+
| `pinState`             | The target structure defines one field for each    |
|                        | variable defined (or at least declared) in the     |
|                        | `CFRAG` in the `Properties` element in the pin     |
|                        | element using this variable.                       |
+------------------------+----------------------------------------------------+
| `readyToSend`          | The target structure (defining `|=`) holds one     |
|                        | flag for each `OutputPin` associated with this     |
|                        | `DeviceType`. The names of these flags are the     |
|                        | names of each `OutputPin` as defined by their      |
|                        | `name` attribute, prefixed with "`RTS_FLAG_`". At  |
|                        | the beginning of the `readyToSend` handler, each   |
|                        | of these flags is lowered, and can be raised using |
|                        | the `|=` operator. For each flag, if it is raised  |
|                        | after the handler has been executed, a message is  |
|                        | sent sent over that `OutputPin`. To send a message |
|                        | over the implicit supervisor output pin, raise the |
|                        | flag "`RTS_SUPER_IMPLICIT_SEND_FLAG`". The order   |
|                        | in which handlers are executed are undefined,      |
|                        | except that the implicit supervisor handler is     |
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

Table: Explanation of variables exposed to `CDATA` code.

## Expected Semantic Structure

This Section introduces the meaning behind each element of the XML tree. The
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
----OnInit
----OnSupervisorIdle
----OnStop
-GraphInstance
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

**Graphs/GraphType/Properties** (`:GraphType-Properties:`)

Defines graph-level properties (constant throughout execution), which can be
accessed by code fragments through the `graphProperties` structure
pointer. Members of the structure pointed to by `graphProperties` are defined
as `CDATA`. These properties may be overriden using the `P` attribute in the
graph instance definition (`:GraphInstance:`).

This element must occur at most once in each `:GraphType:` section. No
attributes are valid.

**Graphs/GraphType/SharedCode** (`:GraphType-SharedCode:`)

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

This element must occur at most once in each `:DeviceType:` section. Valid
attributes:

 - `messageTypeId` (must occur exactly once): Defines the type of message to be
   sent by this pin. Must match with the `id` attribute of a message type
   defined in the `MessageTypes` section.

**Graphs/GraphType/DeviceTypes/DeviceType/SupervisorOutPin/OnSend**

Contains code that may populate an outbound message to the supervisor, and may
change the state of the device.

This element must occur exactly once in each `:SupervisorInPin:` section. No
attributes are valid.

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
messages are to be sent. If multiple messages are to be sent, the order of
their sending is undefined. Note that the state of the device cannot be
modified in this block. Execution of this block is dependent on the softswitch
used, though the default softswitch executes this block:

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
stopped by the operator (root). Note that this handler is not executed in the
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

**Graphs/GraphInstance/Properties** (`:GraphInstance-Properties:`)

Overrides graph-level properties defined by the graph type used by this
instance (`:GraphType-Properties:`). These overrides are defined as
(`:CDATA:`).

This element must occur at most once in each `GraphInstance` section. No
attributes are valid.

**Graphs/GraphInstance/DeviceInstances** (`:DeviceInstances:`)

Contains elements that instantiate every normal device in an application. If
this section contains no children, no normal devices are instantiated (a
supervisor device is still instantiated, though this is of questionable value
outside debugging). The order of devices introduced in this section is
preserved, which affects the result of bucket-filling placement.

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
   for the input pin on the receiving device, if the receiving device is a
   normal device. Define using syntax that is valid in C++14 initialiser lists
   (e.g. `value,anothervalue` for each property field in order). This attribute
   must be undefined if the receiving device is a supervisor device.

 - `S` (must occur at most once): Initial state definitions overriding type
   defaults for the input pin on the receiving device, if the receiving device
   is a normal device. Define using syntax that is valid in C++14 initialiser
   lists (e.g. `value,anothervalue` for each state field in order). This
   attribute must be undefined if the receiving device is a supervisor device.

# Appendix A: Ring Test Example (XML)

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
uint8_t maxLaps = 9;  /* Zero-based indexing */
uint8_t numDevices;  /* Defined in the graph instance section, used by the
                      * supervisor */
    ]]></Properties>
    <MessageTypes>
      <!-- Communications between normal devices use this message type. -->
      <MessageType id="ring_propagate"><![CDATA[
uint8_t lap;
      ]]></MessageType>
      <!-- Communications from normal devices to supervisor devices use this
           message type.
       -->
      <MessageType id="exfiltration"><![CDATA[
uint8_t sourceId;
      ]]></MessageType>
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
message->sourceId = deviceProperties->id;
message->lap = deviceState->lap;

/* Since we're sending a message, reset this field so that we don't send
 * another one. */
deviceState->sendMessage = 0;
          ]]></OnSend>
        </SupervisorOutPin>
        <InputPin name="receiver" messageTypeId="ring_propagate">
          <OnReceive><![CDATA[
/* Only device zero increments the lap counter. Remember - this field in the
 * state is later propagated into the message. */
deviceState->lap = message->lap;
if (deviceProperties->id == 0) deviceState->lap += 1;

/* Don't send a message if the incoming message has completed its tenth lap. */
if (deviceState->lap <= graphProperties->maxLaps) deviceState->sendMessage = 1;
else deviceState->sendMessage = 0;
          ]]></OnReceive>
        </InputPin>
        <OutputPin name="sender" messageTypeId="ring_propagate">
          <OnSend><![CDATA[
/* Define the fields in the message. */
message->lap = deviceState->lap;

/* Since we're sending a message, reset this field so that we don't send
 * another one. */
deviceState->sendMessage = 0;
          ]]></OnSend>
        </OutputPin>
        <!-- This handler is invoked after a message is received, and after
             OnInit (if it returns nonzero).
        -->
        <ReadyToSend><![CDATA[
/* If the input handler determined that we should send a message, do so to the
 * next normal device in the ring, and to our supervisor device. */
if (deviceState->sendMessage == 1)
{
    *readyToSend |= RTS_FLAG_sender;
    *readyToSend |= RTS_SUPER_IMPLICIT_SEND_FLAG;
}
        ]]></ReadyToSend>
        <!-- Initialisation logic. -->
        <OnInit><![CDATA[
/* Device zero starts things off by telling the ReadyToSend handler to send a
 * message. No other device does this. */
if (deviceProperties->id == 0) deviceState->sendMessage = 1;

/* A return of one invokes ReadyToSend (in the default softswitch), whereas a
 * return of zero does not. */
return deviceState->sendMessage;
        ]]></OnInit>
      </DeviceType>
      <SupervisorType id="" SupervisorInPin="tracker">
        <!-- There is one supervisor device type in a given application. This
             particular supervisor is written assuming there is only one
             instance for simplicity.
        -->
        <Code><![CDATA[
#include <stdio.h>  /* For writing an output file */

/* Holds state information to ensure each ring member has seen the packet an
 * appropriate number of times. */
uint8_t messagesPerDevice[graphProperties->numDevices];
for (uint8_t index = 0; index < graphProperties->numDevices; index++)
{
    messagesPerDevice[index] = 0;
}

/* Ominous. */
bool failed = false;
bool finished = false;
        ]]></Code>
        <SupervisorInPin id="tracker" messageTypeId="only">
          <OnReceive><![CDATA[
/* If the application has failed, don't act on any more messages. */
if (!failed)
{
    /* Failure condition: once we've finished, we fail if we receive any more
     * messages. Also, fail if we receive a message that has done too many
     * laps. Note that this does not fail if the messages are received out of
     * order - POETS guarantees delivery, not ordering. */
    if (message->lap > graphProperties->maxLaps or finished)
    {
        failed = true;
        FILE* resultFile = fopen("ring_test_output", "a");
        fprintf(resultFile, "0");
        fclose(resultFile);
    }

    /* If we've not failed, track the message, and check the finishing
     * condition. */
    else
    {
        messagesPerDevice[message->sourceId] += 1;

        /* Check the finishing condition. */
        finished = true;
        for (uint8_t index = 0; index < graphProperties->numDevices; index++)
        {
            if (messagesPerDevice[index] != graphProperties->maxLaps)
            {
                finished = false;
                break;
            }
        }

        /* Check the finish condition. */
        if (finished)
        {
            FILE* resultFile = fopen("ring_test_output", "a");
            fprintf(resultFile, "1");
            fclose(resultFile);
        }
    }
}
          ]]></OnReceive>
        </SupervisorInPin>
      </SupervisorType>
    </DeviceTypes>
  </GraphType>
  <GraphInstance id="ring_test_instance" graphTypeId="ring_test_type">
    <Properties><![CDATA[
numDevices = 5;
    ]]></Properties>
    <DeviceInstances>
      <DevI id="0" type="ring_element" P="id = 0"/>
      <DevI id="1" type="ring_element" P="id = 1"/>
      <DevI id="2" type="ring_element" P="id = 2"/>
      <DevI id="3" type="ring_element" P="id = 3"/>
      <DevI id="4" type="ring_element" P="id = 4"/>
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

# Glossary of Terms

Application:

: Defined by the user, applications perform computation and output information
  using the POETS compute system. See the Applications as Graphs Section.

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

: A set of instructions, provided by the application writer as C++11 source
  code, to be executed in response to an event occuring. See all terms ending
  in "(handler)".

Input Pin:

: A pin, attached to a device, and the receiving end of one or more
  edges. Messages received by this pin are handled by its "OnReceive" handler,
  which may draw from the properties and state of the input pin.

Message:

: A representation of a packet, used to communicate between two
  devices. Messages are lightweight, and are guaranteed to eventually arrive at
  their destination, though are not guaranteed to arrive in the order they are
  sent. Messages may have a payload, populated by the sender.

Normal Device:

: A device that participates in an application as part of the underlying POETS
  compute fabric.

OnInit (handler):

: See the definition provided in Appendix A.

OnDeviceIdle(handler):

: See the definition provided in Appendix A.

OnReceive (handler):

: A handler, called in response to a message being received on a pin, which
  changes the state of the device that owns the pin that owns this
  handler. Once a message is received, messages may be sent (according to the
  behaviour of the ReadyToSend handler.

OnSend (handler):

: A handler, called when a message has been sent (as instructed by the
  ReadyToSend handler). This handler populates the content of the outgoing
  message, and may change the state of the device that owns the pin that owns
  this handler.

Output Pin:

: A pin, attached to a device, and the sending end of one or more
  edges. Messages sent by this pin are populated by its "OnSend"
  handler. Output pins have no properties or state.

Pin:

: A node in the minor set of nodes in the tripartite application graph. Also
  see **Input Pin** and **Output Pin**.

Properties (graph, device, input pin):

: Fields with values that are constant with respect to application execution,
  defined either on the graph level, device level, or input pin
  level. Properties can be accessed through the structures introduced in the
  Source Code Fragments (:CDATA:) Section. See also **State**.

ReadyToSend (handler):

: A handler, called in response to a message being received, or a non-zero
  return value from OnInit or OnDeviceIdle handlers. Determines, from the state
  of the device, which output pins are to be "activated" for sending
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
