% The Mothership and Supervisor Interfacing

# Overview
This document describes the mothership, which is the Orchestrator process that
facilitates communication between the compute backend (normally Tinsel) on its
box, and the rest of the Orchestrator via MPI. It also describes interfacing
with Supervisor devices, which operate within the Mothership. The desirable
features of the Mothership are:

 - To house supervisor devices: Supervisor logic must be loaded at application
   run-time, and the Mothership must be robust to invalid Supervisor binaries.

 - To drain the compute fabric as quickly as possible: One performance-failure
   condition of a POETS compute job is for the compute fabric (Network-On-Chip
   for Tinsel) to become overloaded with packets sent from devices to their
   supervisor, or to external processes. This situation is easily reached by
   applications with devices that regularly report their results to their
   supervisor device, and causes packets from normal devices to be delayed by
   this traffic, significantly hampering execution time. This problem is abated
   when the Mothership drains packets destined for the supervisor as quickly as
   possible, without significant compromise to its other features.

 - To support multiple applications simultaneously running on its box: This
   means applications may be loaded while one is already running, and means
   that the Mothership must support the loading of multiple supervisor
   binaries.

 - Support a debugging interface (UART, in the case of Tinsel): Problems with
   applications can be diagnosed more easily with a functioning debugging
   interface.

 - Operate in conjunction with other Mothership processes (multibox)

 - Respond reasonably quickly to instructions sent to it (over MPI): Note that,
   while resolving traffic from the compute fabric is a high priority activity,
   certain Mothership command-and-control (C&C) instructions are more important
   still, including quitting, and killing an application. The Mothership must
   enact these commands in reasonable time, without significantly compromising
   fabric-draining performance.

 - Support swappable backends: In the future, to use the Orchestrator with
   non-Tinsel backends. The Mothership should support a common interface to
   multiple fabrics. This feature is not immediately essential, but should be
   designed around.

# A Quick Note on Terminology

 - *Message*: An addressed item (`(P)Msg_p` depending on context) with some
   payload that traverses the MPI network via the CommonBase interface.

 - *Packet*: An addressed item with some payload that traverses the compute
   fabric.

# Threads and Queues: Producer-Consumer
To support these features, a Producer-Consumer approach is used by the
Mothership. Figure 1 shows a schematic of how the Mothership employs this
pattern using POSIX threads. Each thread has access to a Mothership object, in
which queues and mutexes for the producer-consumer pattern are stored. The
threads are:

 - `main`: The root thread, which spawns the other threads below and waits for
   them to exit. All threads are running for the duration of the Mothership
   process (excepting process startup and teardown).

 - `MPIInputBroker`: Responsible for filtering MPI messages into either the
   Mothership C&C queue (`MPICncQueue`), or the Application-handling queue
   (`MPIApplicationQueue`). This "splitting" is needed because, if
   poorly-written supervisor[^malicious] could flood the Mothership with MPI
   messages, it will not be possible for the operator to stop the application
   in reasonable time, potentially compromising the running of other
   applications on the compute fabric.

 - `MPICncResolver`: Responsible for draining the `MPICncQueue` queue, and
   enacting those messages in sequence as appropriate.

 - `MPIApplicationResolver`: As above, but for the `MPIApplicationQueue`
   queue. These messages will either be:

       - Converted into packets for the compute fabric, and placed in the
         `BackendOutputQueue` queue.

       - Used to call a supervisor method (which may in turn produce more
         traffic).

 - `BackendOutputBroker`: Responsible for draining the `BackendOutputQueue`
   queue by sending packets into the compute fabric. Waits for the compute
   fabric to accept sending of each packet before actually sending it.

 - `BackendInputBroker`: Responsible for draining the compute fabric into a
   large (but finite) queue buffer (`BackendInputQueue`)[^backendinput]. When
   there are no packets to drain from the compute fabric, or when the
   `BackendInputQueue` buffer is full, this thread converts the next packet
   into a message, and sends it to the appropriate destination over MPI.

 - `DebugInputBroker`: As above, but for the debugging interface provided by
   the backend. Debug packets are queued into the `DebugInputQueue` buffer
   before being resolved in the same way.

[^malicious]: Or a maliciously-written supervisor, but we assume people will be
    playing nice for now.

[^backendinput]: I know Tinsel supports this, but other backends may not.

![Mothership producer-consumer pattern. White-filled boxes represent looping
threads, black-filled boxes represent queues, black arrows represent the
producer-consumer relationship, red arrows represent MPI message flow, and blue
arrows represent backend packet flow. Logging not shown (all threads can `Post`
over MPI)](images/mothership_producer_consumer.pdf)

## TODO Communication and Semaphores
How do we quit? How do we communicate when queues are full? How do we block
queues while writing/reading? (POSIX thread mutexes, probably).

# Command and Control
The operator controls Mothership processes through the console in the Root
process. The Root process sends messages to the Mothership to perform various
C&C jobs, including task manipulation. Table 1 denotes subkeys of messages that
Motherships act upon (not including default handlers introduced by
`CommonBase`). Messages are received by the `MPIInputBroker` consumer, which
inherits from `CommonBase`. Messages with invalid key combinations are dropped.

---------------------------------------------------------------------------------------
Key Permutation Arguments                      Function
--------------- ------------------------------ ----------------------------------------
`EXIT`                                         Stops processing of further messages and
                                               packets, and shuts down the Mothership
                                               as *gracefully* as possible.

`SYST`, `KILL`                                 Stops processing of further messages and
                                               packets, and shuts down the Mothership
                                               as *quickly* as possible.

`NAME`, `SPEC`  `std::string taskName`         Defines that a task on the receiving
                `uint32_t distCount`           Mothership must have received
                                               `distCount` unique distribution (`NAME`,
                                               `DIST`) messages in order to be fully
                                               defined.

`NAME`, `DIST`  `std::string taskName`         Defines the properties for a given core
                `std::string codePath`         for a given application on this
                `std::string dataPath`         Mothership.
                `uint32_t coreAddr`
                `uint8_t numThreads`

`NAME`, `RECL`  `std::string taskName`         Removes information for a task, by name,
                                               from the Mothership. Does nothing on a
                                               running task (it must be stopped first).

`CMND`, `INIT`  `std::string taskName`         Takes a fully-defined task, loads its
                                               code and data binaries onto the
                                               appropriate hardware, boots the
                                               appropriate boards, loads supervisors,
                                               and holds execution of normal devices
                                               at the softswitch barrier.

`CMND`, `RUN`   `std::string taskName`         Takes a task held at the softswitch
                                               barrier, and "starts" it by sending a
                                               barrier-breaking message to all normal
                                               devices owned by that task on this
                                               Mothership.

`CMND`, `STOP`  `std::string taskName`         Takes a running task and sends a stop
                                               packet to all normal devices owned by
                                               that task on the Mothership.

`SUPR`          `P_Sup_Msg_t message`          Calls a method from a loaded supervisor.

`PKTS`          `std::vector<P_Msg_t> packets` Pumps a series of packets into the
                                               backend.
---------------------------------------------------------------------------------------

Table: Input message key permutations that the Mothership understands, and what
the Mothership does with those messages.

## TODO Manipulating Tasks
Defining a task, loading, initialising, and running. Paths? Task states?

# TODO Supervisor Interface
What is the API? How will it work?

 - A safe directory
 - A messaging interface
 - A way to identify a leader (lowest relevant Mothership rank, probably. Or
   perhaps most populated)

# TODO Debugging
Both the Mothership itself, and applications using DebugLink.
