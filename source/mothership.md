% The Mothership and Supervisor Interfacing

# Overview
This document describes the mothership, which is the Orchestrator process that
facilitates communication between the compute backend (normally Tinsel) on its
box, and the rest of the Orchestrator via MPI. It also describes interfacing
with Supervisor devices, which operate within the Mothership process. The
desirable features of the Mothership process are:

 - To house supervisor devices: Supervisor logic must be loaded at application
   run-time, and the Mothership process must be robust to invalid Supervisor
   binaries.

 - To drain the compute fabric as quickly as possible: One performance-failure
   condition of a POETS compute job is for the compute fabric (Network-On-Chip
   for Tinsel) to become overloaded with packets sent from devices to their
   supervisor, or to external processes. This situation is easily reached by
   applications with devices that regularly report their results to their
   supervisor device, and causes packets from normal devices to be delayed by
   this traffic, significantly hampering execution time. This problem is abated
   when the Mothership process drains packets destined for the supervisor as
   quickly as possible, without significant compromise to its other features.

 - To support multiple applications simultaneously running on its box: This
   means applications may be loaded while one is already running, and means
   that the Mothership process must support the loading of multiple supervisor
   binaries.

 - Support a debugging interface (UART, in the case of Tinsel): Problems with
   applications can be diagnosed more easily with a functioning debugging
   interface.

 - Operate in conjunction with other Mothership processes (multibox)

 - Respond reasonably quickly to instructions sent to it (over MPI): Note that,
   while resolving traffic from the compute fabric is a high priority activity,
   certain command-and-control (C&C) instructions are more important still,
   including quitting, and killing an application. The Mothership process must
   enact these commands in reasonable time, without significantly compromising
   fabric-draining performance.

 - Support swappable backends: In the future, to use the Orchestrator with
   non-Tinsel backends. The Mothership process should support a common
   interface to multiple fabrics. This feature is not immediately essential,
   but should be designed around.

NB: Terminology in this document:

 - *Message*: An addressed item (`(P)Msg_p` depending on context) with some
   payload that traverses the MPI network via the CommonBase interface.

 - *Packet*: An addressed item (usually `P_Msg_t`, or `P_Pkt_t` if GMB's change
   has been accepted) with some payload that traverses the compute fabric.

 - *Thread*: POSIX thread running under the Mothership process (x86-land). NB:
   Not a "thread" in the compute fabric.

 - *Mothership*: Occasionally, I refer to the Mothership as a class (or
   object/instance), and a process. This is legacy - documentation is written
   to take people from the past to the present after all. I'll try to be
   explicit wherever I use this term.

# Threads and Queues: Producer-Consumer
To support these features, a Producer-Consumer approach is used by the
Mothership. Figure 1 shows a schematic of how the Mothership process employs
this pattern using POSIX threads. Each thread has access to a Mothership
object, in which queues and mutexes for the producer-consumer pattern are
stored. Consumer threads have exactly one spinner[^spinners], which is either
a:

 - Fast Spinners: These spin aggressively on the consumer queue, with no
   delay between checks, ever.

 - Slow Spinners: Once an event triggers the spinner, and has been resolved,
   the next event is immediately checked for. If there is no next event, the
   spinner delays for a brief period before checking again, and delays after
   each check until an event triggers the spinner.

[^spinners]: Spinner: Event loop, where events are items (packets or messages)
    in the consumer queue.

The discrepancy between spinner types is to encourage context to prioritise
threads with fast spinners. The threads are:

 - `main`: The root thread, which spawns the other threads below and waits for
   them to exit. All threads are running for the duration of the Mothership
   process (excepting process startup and teardown).

 - `MPIInputBroker`: Responsible for filtering MPI messages into either the
   Mothership object C&C queue (`MPICncQueue`), or the Application-handling
   queue (`MPIApplicationQueue`). This "splitting" is needed because, if a
   poorly-written supervisor[^malicious] floods with MPI messages, it will not
   be possible for the operator to stop the application in reasonable time,
   potentially compromising the running of other applications on the compute
   fabric. It calls `CommonBase::MPISpinner`. This is a fast spinner.

 - `MPICncResolver`: Responsible for draining the `MPICncQueue` queue, and
   enacting those messages in sequence as appropriate. This is a slow spinner.

 - `MPIApplicationResolver`: As above, but for the `MPIApplicationQueue`
   queue. This is a slow spinner. These messages will either be:

       - Converted into packets for the compute fabric, and placed in the
         `BackendOutputQueue` queue.

       - Used to call a supervisor method (which may in turn produce more
         traffic).

 - `BackendOutputBroker`: Responsible for draining the `BackendOutputQueue`
   queue by sending packets into the compute fabric. This is a slow spinner,
   which spins not only on the existence of packets in the queue, but also on
   being able to send the message (on asking the compute fabric).

 - `BackendInputBroker`: Responsible for draining the compute fabric into a
   large (but finite) queue buffer (`BackendInputQueue`)[^backendinput]. When
   there are no packets to drain from the compute fabric, or when the
   `BackendInputQueue` buffer is full, this thread converts the next packet
   into a message, and sends it to the appropriate destination over MPI. This
   is a fast spinner.

 - `DebugInputBroker`: As above, but for the debugging interface provided by
   the backend. Debug packets are queued into the `DebugInputQueue` buffer
   before being resolved in the same way. This is a slow spinner.

[^malicious]: Or a maliciously-written supervisor, but we assume people will be
    playing nice for now.

[^backendinput]: I know Tinsel implements such a queue, but other backends may
    not. Better to have some uniformity, I think.

![Mothership process producer-consumer pattern. White-filled boxes represent
looping threads where the fast/slow annotations denote the behaviour of the
spinner, black-filled boxes represent queues, black arrows represent the
producer-consumer relationship, red arrows represent MPI message flow, and blue
arrows represent backend packet flow. Logging not shown (all threads can `Post`
over MPI)](images/mothership_producer_consumer.pdf)

## Communication and Semaphores
The following communication constructs are accessible to all threads, via the
`Mothership::ThreadComms` class:

 - `bool quit`: Defaults to `false`, is set to `true` when one thread
   encounters a fatal error[^fatalerror], or an `EXIT` C&C message. Threads
   regularly poll this variable, and gracefully join when it is `true`.

 - Various `pthread_mutex_t`s lock operations of different queues to prevent
   race conditions between push and pop operations. Queues that are only
   read/written by one thread have no mutexes. The mutexes are:

     - `pthread_mutex_t MPICncQueueMutex` locks `MPICncQueue`.

     - `pthread_mutex_t MPIApplicationQueueMutex` locks `MPIApplicationQueue`.

     - `pthread_mutex_t BackendOutputQueueMutex` locks
       `BackendOutputQueueMutex`.

The above variables are private, and can be accessed by the following getters
and setters in `Mothership::ThreadComms` (which manipulate the queues and
mutexes):

 - `void set_quit()`: Sets `quit` (and also sends a logserver message).

 - `void is_it_time_to_go()`: Reads `quit`.

 - `bool pop_from_MPI_cnc(PMsg_p* message)`: Moves the message from the end of
   the `MPICncQueue` queue to message. Returns `false` if the queue was empty
   (leaving `message` unmodified), and `true` otherwise.

 - `bool pop_from_MPI_cnc(std::vector<PMsg_p>* messages)`: Moves all messages
   from `MPICncQueue` into `messages`. Returns `false` if the queue was empty
   (leaving `messages` unmodified), and `true` otherwise.

 - `void push_to_from_MPI_cnc(PMsg_p message)`: Pushes `message` to the start
   of the `MPICncQueue` queue.

 - `void push_to_from_MPI_cnc(std::vector<PMsg_p>* messages)`: Pushes each
   message in `messages` to the start of the `MPICncQueue` queue, in the order
   that they exist `messages`. Does nothing if `messages` is empty.

 - The four above methods are also defined for the `MPIApplicationQueue` queue,
   and for the `BackendOutputQueue`, `BackendInputQueue`, and
   `DebugInputQueue`, where the latter three operate with `P_Msg_t packet`s as
   opposed to `PMsg_p message`s.

[^fatalerror]: By "fatal error", I mean that an exception is thrown in the
    thread logic, which is not caught. When this happens, the error is logged,
    and a graceful shutdown is attempted.

# Command and Control
The operator controls Mothership processes through the console in the Root
process. The Root process sends messages to the Mothership process to perform
various C&C jobs, including application manipulation. Table 1 denotes subkeys
of messages that Mothership processes act upon (not including default handlers
introduced by `CommonBase`). Messages are received by the `MPIInputBroker`
consumer, which inherits from `CommonBase`. Messages with invalid key
combinations are dropped.

+-----------------+-----------------------+-----------------------------------+
| Key Permutation | Arguments             | Function                          |
+=================+=======================+===================================+
| `EXIT`          | None                  | Stops processing of further       |
|                 |                       | messages and packets, and         |
|                 |                       | shuts down the Mothership         |
|                 |                       | process as *gracefully* as        |
|                 |                       | possible.                         |
+-----------------+-----------------------+-----------------------------------+
| `SYST`, `KILL`  | None                  | Stops processing of further       |
|                 |                       | messages and packets, and shuts   |
|                 |                       | down the Mothership process as    |
|                 |                       | *quickly* as possible.            |
+-----------------+-----------------------+-----------------------------------+
| `NAME`, `SPEC`  | 1. `std::string`      | Defines that an application on    |
|                 |    `appName`          | the receiving Mothership process  |
|                 | 2. `uint32_t`         | must have received `distCount`    |
|                 |    `distCount`        | unique distribution (`NAME`,      |
|                 |                       | `DIST`) messages in order to be   |
|                 |                       | fully defined.                    |
+-----------------+-----------------------+-----------------------------------+
| `NAME`, `DIST`  | 1. `std::string`      | Defines the properties for a      |
|                 |    `appName`          | given core for a given            |
|                 | 2. `std::string`      | application on this Mothership    |
|                 |    `codePath`         | process.                          |
|                 | 3. `std::string`      |                                   |
|                 |    `dataPath`         |                                   |
|                 | 4. `uint32_t`         |                                   |
|                 |    `coreAddr`         |                                   |
|                 | 5. `uint8_t`          |                                   |
|                 |    `numThreads`       |                                   |
+-----------------+-----------------------+-----------------------------------+
| `NAME`, `RECL`  | 1. `std::string`      | Removes information for an        |
|                 |    `appName`          | application, by name, from the    |
|                 |                       | Mothership. Does nothing on a     |
|                 |                       | running application (it must be   |
|                 |                       | stopped first).                   |
+-----------------+-----------------------+-----------------------------------+
| `CMND`, `INIT`  | 1. `std::string`      | Takes a fully-defined             |
|                 |    `appName`          | application (with state           |
|                 |                       | `DEFINED`), loads its code and    |
|                 |                       | data binaries onto the            |
|                 |                       | appropriate hardware, boots the   |
|                 |                       | appropriate boards, loads         |
|                 |                       | supervisors, and holds execution  |
|                 |                       | of normal devices at the          |
|                 |                       | softswitch barrier. If the        |
|                 |                       | application is not `DEFINED`      |
|                 |                       | this message is acted on when it  |
|                 |                       | reaches that state.               |
+-----------------+-----------------------+-----------------------------------+
| `CMND`, `RUN`   | 1. `std::string`      | Takes an application held at the  |
|                 |    `appName`          | softswitch barrier (with state    |
|                 |                       | `READY`, and "starts" it by       |
|                 |                       | sending a barrier-breaking        |
|                 |                       | message to all normal devices     |
|                 |                       | owned by that application on      |
|                 |                       | this Mothership process. If the   |
|                 |                       | application is not `READY`, this  |
|                 |                       | message is acted on when it       |
|                 |                       | reaches that state.               |
+-----------------+-----------------------+-----------------------------------+
| `CMND`, `STOP`  | 1. `std::string`      | Takes a running application (with |
|                 |    `appName`          | state `RUNNING`) and sends a stop |
|                 |                       | packet to all normal devices      |
|                 |                       | owned by that task on the         |
|                 |                       | Mothership process. If the        |
|                 |                       | application is not `RUNNING`,     |
|                 |                       | this message is acted on when it  |
|                 |                       | reaches that state (stopping      |
|                 |                       | before it starts will not stop it |
|                 |                       | from starting).                   |
+-----------------+-----------------------+-----------------------------------+
| `SUPR`          | 1. `P_Msg_t message`  | Calls a method from a loaded      |
|                 |                       | supervisor. The supervisor is     |
|                 |                       | identified by querying `NameBase` |
|                 |                       | using the address in `message`.   |
+-----------------+-----------------------+-----------------------------------+
| `PKTS`          | 1. `std::vector<`     | Queues a series of packets into   |
|                 |    `P_Msg_t> packets` | the backend.                      |
+-----------------+-----------------------+-----------------------------------+

Table: Input message key permutations that the Mothership process understands,
and what the Mothership does with those messages.

The Mothership process occasionally also sends messages to the Root
process. Table 2 denotes subkeys of messages that Mothership processes send to
Root, along with their intended use. They're mostly acknowledgements of work
done.

+-----------------+-----------------------+-----------------------------------+
| Key Permutation | Arguments             | Reason                            |
+=================+=======================+===================================+
| `MSHP`, `NOBE`  | None                  | Notifies the Root process that    |
|                 |                       | the Mothership was unable to      |
|                 |                       | connect to the backend compute    |
|                 |                       | fabric.                           |
+-----------------+-----------------------+-----------------------------------+
| `MSHP`, `ACK`,  | 1. `std::string`      | Notifies the Root process that    |
| `DEFD`          |    `appName`          | the application has been fully    |
|                 |                       | defined.                          |
+-----------------+-----------------------+-----------------------------------+
| `MSHP`, `ACK`   | 1. `std::string`      | Notifies the Root process that    |
| `LOAD`          |    `appName`          | the application has been fully    |
|                 |                       | loaded.                           |
+-----------------+-----------------------+-----------------------------------+
| `MSHP`, `ACK`   | 1. `std::string`      | Notifies the Root process that    |
| `RUN`           |    `appName`          | the application has started       |
|                 |                       | running.                          |
+-----------------+-----------------------+-----------------------------------+
| `MSHP`, `ACK`   | 1. `std::string`      | Notifies the Root process that    |
| `STOP`          |    `appName`          | the application has been fully    |
|                 |                       | stopped.                          |
+-----------------+-----------------------+-----------------------------------+


Table: Output message key permutations that the Mothership process sends to the
Root process, and why.

# Applications
The Mothership class maintains a map, `std::map<std::string, AppInfo>
Mothership.appdb`, which describes applications that the Mothership process has
been informed of, as a function of their name. This map complements the
database provided by `NameBase` (from which the Mothership inherits), by
defining the states of applications and loading information, as opposed to
purely addressing information. `AppInfo` is a class with these fields:

 - `std::string name`: The name of the application, redundant with the map key.

 - `AppState state`: The state that the application is in. These states are
   enumerated by `AppState` as:

   - `UNDERDEFINED`: The application has been partly sent to the Mothership
     process, but some cores have not been defined, or their binaries refer to
     files that could not be found on the filesystem.

   - `DEFINED`: The application and its cores and binaries have been completely
     defined on this Mothership, but nothing has been loaded onto hardware yet.

   - `LOADING`: As with `DEFINED`, but the loading process (`INIT`) has begun.

   - `READY`: All cores and supervisors are ready to start for this
     application.

   - `RUNNING`: As with `READY`, and the running process (`RUN`) has begun.

   - `STOPPING`: The application is running, but the stopping process (`STOP`)
     has begin.

   - `STOPPED`: The application was running, has been stopped

 - `uint8_t pendingCommands`: Bit-vector storing pending commands from other
   processes (Root). This is private - accessed and set using these methods:

   - `void stage_init()`: Setter for the `INIT` command.

   - `void stage_run()`: Setter for the `RUN` command.

   - `void stage_stop()`: Setter for the `STOP` command.

   - `bool continue()`: Given the current values of `state` and
     `pendingCommands`, returns `true` if the application is to "advance to the
     next state", and `false` otherwise.

 - `uint32_t distCountExpected`: Expected number of distribution messages for
   this application.

 - `uint32_t distCountCurrent`: Current number of distribution messages
   processed for this application. When this is equal to `distCountExpected`,
   the application is fully defined.

 - `std::map<coreAddr, CoreInfo> coreInfos`: Information about the cores known
   about, and their loading state. CoreInfo is a structure with these fields:

   - `std::string codePath`: Path to the instruction binary for this core.

   - `std::string dataPath`: Path to the data binary for this core.

   - `uint8_t numThreadsExpected`: Number of threads expected to report back
     for this core.

   - `uint8_t numThreadsCurrent`: Number of threads that have reported back
     after loading the core.

There is a corresponding backwards map, `std::map<uint32_t, std::string>
Mothership.coreToApp`, which maps core addresses to the name of the application
that has claimed them. This map allows the Mothership process to more elegantly
catch when applications have been incorrectly overlayed.

## TODO States and Commands
A picture showing state transitions, something like: `UNDERDEFINED`
--(`DIST`,`SPEC`)--> `DEFINED` --(`INIT`)--> `LOADING`, `READY` --(`RUN`)-->
`RUNNING` --(`STOP`)--> `STOPPING`, `STOPPED`. All --(`RECL`)--> `DELETED` (not
a state)

# TODO Supervisor Interface
What is the API? How will it work?

 - A safe directory
 - A messaging interface
 - A way to identify a leader (lowest relevant Mothership rank, probably. Or
   perhaps most populated)

# TODO Debugging
Both the Mothership itself, and applications using DebugLink.

# TODO Big Class Structure Diagram
Include NameBase/SBase in here.
