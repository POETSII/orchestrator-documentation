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
   payload that traverses the MPI network via the `CommonBase` interface. NB:
   MPI messages sent/received in this way are asynchronous.

 - *Packet*: An addressed item (usually `P_Pkt_t`, or `P_Pkt_t` if GMB's change
   has been accepted) with some payload that traverses the compute fabric.

 - *Debug packet*: An addressed item sent over DebugLink (UART) connection in
   the Tinsel backend (`P_Debug_Pkt_t`, see the Debugging section).

 - *Thread*: POSIX thread running under the Mothership process (x86-land). NB:
   Not a "thread" in the compute fabric.

 - *Mothership*: Occasionally, I refer to the Mothership as a class (or
   object/instance), and a process. This is legacy - documentation is written
   to take people from the past to the present after all. I'll try to be
   explicit wherever I use this term.

# Threads and Queues: Producer-Consumer
To support these features, a Producer-Consumer approach is used by the
Mothership. Figure 1 shows a schematic of how the Mothership process employs
this pattern using POSIX threads. Each thread has access to the Mothership
object (of which there is only one per Mothership process), in which queues and
mutexes for the producer-consumer pattern are stored. Consumer threads have
exactly one spinner[^spinners], which is either a:

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
   into a message, and either sends it to the appropriate destination over MPI,
   or pushes it to `MPICncQueue` (Tinsel Command and Control) or
   `MPIApplicationQueue` (Supervisor) if intended to be processed locally. This
   is a fast spinner.

 - `DebugInputBroker`: Responsible for draining the debug fabric into a large
   queue buffer (`DebugInputQueue`). When there are no packets to drain, or
   when the `DebugInputQueue` buffer is full, this thread converts the next
   packet into a message to be `Post`-ed, using MPI. This is a slow spinner.

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
`ThreadComms` class (accessed via `Mothership.threading`):

 - `bool quit`: Defaults to `false`, is set to `true` when one thread
   encounters a fatal error[^fatalerror], or an `EXIT` C&C message. Threads
   regularly poll this variable, and gracefully join when it is `true`.

 - Various `pthread_mutex_t`s lock operations of different queues to prevent
   race conditions between push and pop operations. Queues that are only
   read/written by one thread have no mutexes. The mutexes are:

     - `pthread_mutex_t mutex_MPI_cnc_queue` locks `MPICncQueue`.

     - `pthread_mutex_t mutex_MPI_app_queue` locks `MPIApplicationQueue`.

     - `pthread_mutex_t mutex_backend_output_queue` locks `BackendOutputQueue`.

The above variables are private, and can be accessed by the following getters
and setters in `Mothership::ThreadComms` (which manipulate the queues and
mutexes):

 - `void set_quit()`: Sets `quit` (and also sends a logserver message).

 - `void is_it_time_to_go()`: Reads `quit`.

 - `bool pop_MPI_cnc_queue(PMsg_p* message)`: Moves the message from the end of
   the `MPICncQueue` queue to message. Returns `false` if the queue was empty
   (leaving `message` unmodified), and `true` otherwise.

 - `bool pop_MPI_cnc_queue(std::vector<PMsg_p>* messages)`: Moves all messages
   from `MPICncQueue` into `messages`. Returns `false` if the queue was empty
   (leaving `messages` unmodified), and `true` otherwise.

 - `void push_MPI_cnc_queue(PMsg_p message)`: Pushes `message` to the start of
   the `MPICncQueue` queue.

 - `void push_MPI_cnc_queue(std::vector<PMsg_p>* messages)`: Pushes each
   message in `messages` to the start of the `MPICncQueue` queue, in the order
   that they exist `messages`. Does nothing if `messages` is empty.

 - The four above methods are also defined for the `MPIApplicationQueue` queue
   (using `PMsg_p` messages), for `BackendOutputQueue` and `BackendInputQueue`
   (using `P_Pkt_t` packets), and for `DebugInputQueue` (using `P_Debug_Pkt_t`
   debug packets, see the Debugging section).

[^fatalerror]: By "fatal error", I mean that an exception is thrown in the
    thread logic, which is not caught. When this happens, the error is logged,
    and a graceful shutdown is attempted.

# Command and Control
The Mothership process exists on the front of two streams of data traffic - the
MPI network connecting the Mothership to the rest of the Orchestrator, and the
compute backend network (typically Tinsel)

## MPI Command and Control
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
| `APP`,  `SPEC`  | 1. `std::string`      | Defines that an application on    |
|                 |    `appName`          | the receiving Mothership process  |
|                 | 2. `uint32_t`         | must have received `distCount`    |
|                 |    `distCount`        | unique distribution (`APP`,       |
|                 |                       | `DIST`) messages in order to be   |
|                 |                       | fully defined.                    |
+-----------------+-----------------------+-----------------------------------+
| `APP`,  `DIST`  | 1. `std::string`      | Defines the properties for a      |
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
| `APP`,  `SUPD`  | 1. `std::string`      | Defines the properties for the    |
|                 |    `appName`          | supervisor for a given            |
|                 | 2. `std::string`      | application on this Mothership.   |
|                 |    `soPath`           |                                   |
+-----------------+-----------------------+-----------------------------------+
| `CMND`,  `RECL` | 1. `std::string`      | Removes information for an        |
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
|                 |                       | message (`P_CNC_BARRIER`) to all  |
|                 |                       | normal devices owned by that      |
|                 |                       | application on this Mothership    |
|                 |                       | process. If the application is    |
|                 |                       | not `READY`, this message is      |
|                 |                       | acted on when it reaches that     |
|                 |                       | state.                            |
+-----------------+-----------------------+-----------------------------------+
| `CMND`, `STOP`  | 1. `std::string`      | Takes a running application (with |
|                 |    `appName`          | state `RUNNING`) and sends a stop |
|                 |                       | packet (`P_CNC_STOP`) to all      |
|                 |                       | normal devicesowned by that task  |
|                 |                       | on the Mothership process. If the |
|                 |                       | application is not `RUNNING`,     |
|                 |                       | this message is acted on when it  |
|                 |                       | reaches that state (stopping      |
|                 |                       | before it starts will not stop it |
|                 |                       | from starting).                   |
+-----------------+-----------------------+-----------------------------------+
| `BEND`, `CNC`   | 1. `P_Pkt_t packet`   | Calls a C&C method, via the       |
|                 |                       | `MPICncQueue`. The opcode (and    |
|                 |                       | hence the method) is identified   |
|                 |                       | from `packet`.                    |
+-----------------+-----------------------+-----------------------------------+
| `BEND`, `SUPR`  | 1. `P_Pkt_t packet`   | Calls a method from a loaded      |
|                 |                       | supervisor, via the               |
|                 |                       | `MPIApplicationQueue`. The        |
|                 |                       | supervisor is identified by       |
|                 |                       | querying `NameBase` using the     |
|                 |                       | address in `packet`.              |
+-----------------+-----------------------+-----------------------------------+
| `PKTS`          | 1. `std::vector<`     | Queues a series of packets into   |
|                 |    `P_Pkt_t> packets` | the backend.                      |
+-----------------+-----------------------+-----------------------------------+
| `DUMP`          | 1. `std::string path` | Dumps Mothership process state    |
|                 |                       | to a file at `path`               |
|                 |                       | (`Mothership::Dump(std::string)`) |
+-----------------+-----------------------+-----------------------------------+

Table: Input message key permutations that the Mothership process understands,
and what the Mothership does with those messages.

The Mothership process occasionally also sends messages to the Root
process. Table 2 denotes subkeys of messages that Mothership processes send to
Root, along with their intended use. They're mostly acknowledgements of work
done, and are useful for debugging.

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
| `MSHP`, `ACK`,  | 1. `std::string`      | Notifies the Root process that    |
| `LOAD`          |    `appName`          | the application has been fully    |
|                 |                       | loaded.                           |
+-----------------+-----------------------+-----------------------------------+
| `MSHP`, `ACK`,  | 1. `std::string`      | Notifies the Root process that    |
| `RUN`           |    `appName`          | the application has started       |
|                 |                       | running.                          |
+-----------------+-----------------------+-----------------------------------+
| `MSHP`, `ACK`,  | 1. `std::string`      | Notifies the Root process that    |
| `STOP`          |    `appName`          | the application has been fully    |
|                 |                       | stopped.                          |
+-----------------+-----------------------+-----------------------------------+

Table: Output message key permutations that the Mothership process sends to the
Root process, and why.

## Tinsel Command and Control

Softswitches in the compute backend can send C&C packets to the Mothership
process. These packets, in addition to being addressed to the supervisor, have
a value defined in their `opcode` field in the software address (see the
Software Addresses documentation). Such packets are packaged and queued for the
Mothership in the MPI backend by `BackendInputBroker` as (`BEND`, `CNC`)
messages. The sender of each packet is uniquely identified in `MPICncResolver`
from the `pinAddr` component in the software address. Packets received by the
Mothership with opcode values not defined by this list of constants (defined
in-source) are routed to the supervisor as (`BEND`, `SUPR`) messages:

 - `P_CNC_INSTR`: A packet with instrumentation data, which causes the
   instrumentation data to be written to a set of CSV files in the
   `~/.orchestrator/instrumentation` (left deliberately vague - it's also
   covered in part in the Softswitch documentation).

 - `P_CNC_LOG`: A packet with a logging message (possibly created by a call to
   `handler_log`). The information from the packet is formatted, and `Post`-ed
   to the Logserver.

 - `P_CNC_BARRIER`: A packet that, when received, informs the Mothership that a
   given thread has reached the softswitch barrier. If the state of the
   application to which this device belongs is `LOADING`, the field
   `Mothership.appdb.coreInfos[coreAddr].numThreadsCurrent` (where `coreAddr`
   is a `uint32_t` hardware address) for the core in question is
   incremented. If all of the threads for that core have reported back,
   `coreAddr` is appended to `coresLoaded`. Then, if all cores have been loaded
   (by checking the length of coresLoaded), the state of the application is
   transitioned from `LOADING` to `READY`.

 - `P_CNC_STOP`: A packet that, when received, informs the Mothership that a
   given thread has received the stop command (and has presumably now
   stopped). If the state of the application to which this device belongs is
   `STOPPING`, the field
   `Mothership.appdb.coreInfos[coreAddr].numThreadsCurrent` for the core in
   question is decremented. If all of the threads for that core have reported
   back, `coreAddr` is removed from `coresLoaded`. Then, if `coresLoaded` is
   empty, the state of the application is transitioned from `STOPPING` to
   `STOPPED`, and the supervisor is unloaded.

Notes:

 - The bulleted logic above is enacted by `MPICncResolver`.

 - Some of the opcodes listed above (e.g. `P_CNC_LOG`) can also meaningfully be
   sent by the Mothership to devices in the compute fabric, specifically
   `P_CNC_BARRIER` (which is the barrier-breaking packet sent as a result of a
   (`CMND`, `INIT`)), and `P_CNC_STOP` (sent by (`CMND`, `STOP`)).

 - There is no `P_CNC_KILL`. Applications can no longer stop the Mothership. A
   normal device can send a packet to the supervisor, (via a (`BEND`, `SUPR`)
   message), which causes the supervisor to call the `void Super::end()` API
   method (documented in the Supervisor API section), which closes the
   application gracefully.

 - There is no `P_CNC_INIT`. This opcode was used in the barrier-breaking
   packet for normal devices. It is replaced by `P_CNC_BARRIER`.

# Applications
The Mothership class maintains a map, `std::map<std::string, AppInfo>
Mothership.appdb`, which describes applications that the Mothership process has
been informed of, as a function of their name. This map complements the
database provided by `NameBase` (from which the Mothership inherits), by
defining the states of applications and loading information, as opposed to
purely addressing information. `AppInfo` is a class with these fields:

 - `std::string name`: The name of the application, redundant with the map key.

 - `AppState state`: The state that the application is in. Table 3 shows how
     C&C messages consumed by `MPICncResolver` drive application states. These
     states are enumerated by `AppState` as:

   - `UNDERDEFINED`: The application has been partly sent to the Mothership
     process, but some cores have not been defined, or their binaries refer to
     files that could not be found on the filesystem.

   - `DEFINED`: The application (`APP`, `SPEC`), its cores and binaries (`APP`,
     `DIST`), and its supervisor (`APP`, `SUPD`) have been completely defined
     on this Mothership, but nothing has been loaded onto hardware yet.

   - `LOADING`: As with `DEFINED`, but the loading process (`CMND`, `INIT`) has
     begun.

   - `READY`: All cores and supervisors are ready to start for this
     application.

   - `RUNNING`: As with `READY`, and the running process (`CMND`, `RUN`) has
     begun.

   - `STOPPING`: The application is running, but the stopping process (`CMND`,
     `STOP`) has begin.

   - `STOPPED`: The application was running, but has been stopped

   - `BROKEN`: Something went wrong, and the issue has been reported. The
     application is not stopped or otherwise "cleaned up" (for now).

 - `uint8_t pendingCommands`: Bit-vector storing pending commands from other
   processes (Root). This is private - accessed and set using these methods:

   - `void stage_init()`: Setter for the `INIT` command.

   - `void stage_run()`: Setter for the `RUN` command.

   - `void stage_stop()`: Setter for the `STOP` command.

   - `void stage_recl()`: Setter for the `RECL` command.

   - `bool continue()`: Given the current values of `state` and
     `pendingCommands`, returns `true` if the application is to "advance to the
     next state", and `false` otherwise. The "next state" is loosely defined in
     Table 3, where `RECL` takes priority over other commands.

 - `uint32_t distCountExpected`: Expected number of distribution messages for
   this application.

 - `uint32_t distCountCurrent`: Current number of distribution messages
   processed for this application. When this is equal to `distCountExpected`,
   the application is fully defined.

 - `std::map<uint32_t, CoreInfo> coreInfos`: Information about the cores known
   about, and their loading state. The key is the hardware address of the
   core. CoreInfo is a structure with these fields:

   - `std::string codePath`: Path to the instruction binary for this core.

   - `std::string dataPath`: Path to the data binary for this core.

   - `uint8_t numThreadsExpected`: Number of backend threads expected to report
     back for this core.

   - `uint8_t numThreadsCurrent`: Number of backend threads that have reported
     back after loading the core. Used to transition from the `LOADING` state
     to the `READY` state. Also used for the opposite purpose, transitioning
     from `STOPPING` to `STOPPED`.

 - `std::set<uint32_t> coresLoaded`: Holds addresses for each core that have
   been completely loaded (i.e. all threads have reported back), and not
   stopped (see `numThreadsCurrent`)

There is a corresponding backwards map, `std::map<uint32_t, std::string>
Mothership.coreToApp`, which maps core addresses to the name of the application
that has claimed them. This map allows the Mothership process to more elegantly
catch when applications have been incorrectly overlayed, and to enable the
debug reporting feature of `DebugInputBroker`.

+--------------------+-----------------+------------------+------------------+
| Key Permutation    | Input State     | Transition State | Output State     |
+====================+=================+==================+==================+
| (`APP`, `SPEC`) or | None [^none]    |                  | `UNDERDEFINED`   |
| (`APP`, `DIST`) or |                 |                  |                  |
| (`APP`, `SUPD`)    |                 |                  |                  |
+--------------------+-----------------+------------------+------------------+
| (`APP`, `SPEC`) or | `UNDERDEFINED`  |                  | `DEFINED`        |
| (`APP`, `DIST`) or |                 |                  | [^last]          |
| (`APP`, `SUPD`)    |                 |                  |                  |
+--------------------+-----------------+------------------+------------------+
| `CMND`, `INIT`     | `DEFINED`       | `LOADING`        | `READY`          |
+--------------------+-----------------+------------------+------------------+
| `CMND`, `RUN`      | `READY`         |                  | `RUNNING`        |
+--------------------+-----------------+------------------+------------------+
| `CMND`, `STOP`     | `RUNNING`       | `STOPPING`       | `STOPPED`        |
+--------------------+-----------------+------------------+------------------+
| `CMND`, `RECL`     | `UNDERDEFINED`  |                  | None             |
|                    | or `DEFINED` or |                  |                  |
|                    | `READY` or      |                  |                  |
|                    | `STOPPED`       |                  |                  |
+--------------------+-----------------+------------------+------------------+

Table: Input key permutations, and how they change the state of an application
on the Mothership (assuming the operations succeed). Note that C&C messages
processed before the application reaches the input state are "stored", and
enacted when the application reaches the input state via some other C&C
message. Transition states exist to aid loading and stopping "completion
detection" by `DebugInputBroker` (see the Debugging section).

[^last]: This state is only set when the final message is received (see the
    Command and Control section for more information on `APP` messages).

[^none]: "None" here means that `Mothership.appdb` and `SBase` do not know
    about the task, and do not hold any information on it.

# Supervisors
Supervisors are devices in an application that exist on the Mothership, and can
communicate with normal devices serviced by the box associated with its
Mothership, as well as external devices elsewhere. They are:

 - Defined in the application description (XML)

 - Compiled into shared object files by `P_Builder`

 - Deployed to the Mothership process via an (`APP`, `SUPD`) message

 - Loaded as part of an application by the Mothership process when the (`CMND`,
   `INIT`) message is received.

 - Represented by a `Supervisor` object with the following fields (defined on
   construction - a supervisor that cannot be loaded and is not fully defined
   will cause the Mothership to report and set the application state to
   `BROKEN`):

     - `std::string path`: Where the supervisor was loaded from.

     - `void* so`: The dynamically-loaded supervisor (using `dlopen`), from
       which the Mothership calls methods defined therein.

 - Stored in the Mothership object in `std::map<std::string, void*>
   Mothership.supervisors`, keyed by task name. For an incoming packet, the
   appropriate supervisor is identified from the task component of the software
   address.

## Supervisor API
The following API is available to application-writers to support functionality
that is common to certain applications:

 - `std::string Super::get_safe_directory()`: Returns the absolute path of a
   directory on the system that was guaranteed safe to write to as of when the
   application was compiled. If you fill up the disk or change the permissions,
   it's on you.

 - `void Super::end()`: Stops the application, by sending a (`CMND`, `STOP`)
   message to the Mothership process (The Supervisor is running on the
   Mothership process, but this way the supervisor can be more easily cleaned
   up, as the application is not stopped while the supervisor handler is
   in-context.

 - `void Super::message_leader(uint8_t[SOME_NUMBER] payload)`: Packages the
   payload into a `P_Pkt_t`, and sends it using a (`BEND`, `SUPR`) message to
   the supervisor "leader" (which is simply the supervisor on the Mothership
   with the lowest rank for this application).

 - `void Super::supervisor_broadcast(uint8_t[SOME_NUMBER] payload)`: Packages
   the payload into a `P_Pkt_t`, and sends it using a (`BEND`, `SUPR`) message
   to all supervisors running for this application, except this one.

 - Can you think of any more? There are probably more we need, but we're not
   going to get them all now. Simply implementing a framework by which this API
   can be extended should be enough.

Note that this API does not define methods for termination detection. It could
do (using a Softswitch-based heartbeats mechanism), but it might be best to let
sleeping dragons lie for now.

# Debugging
In addition to the acknowledgement messages that the Mothership generates while
transitioning tasks between states, and the `DUMP` message, it is useful to
have more fine-grained debugging control over the Mothership. The Tinsel
backend provides a debugging interface over its UART backchannel, which can be
exploited to exfiltrate acknowledgement and debugging information from normal
devices in the backend. The `DebugInputBroker` acts on packets received by the
Mothership by `Post`ing a formatted message to the Logserver, including the
packet payload and its origin. Debug packets sent in this way are stored as
`std::pair<uint32_t, uint8_t>` objects, where the first element of the pair
represents the hardware address source (decoded using `HostLink::toAddr`), and
the second element of the pair represents the byte payload. This class is
type-defined as `P_Debug_Pkt_t`.

Applications can also call the `void handler_log(int level, const char* text)`
free function in a handler, which sends a series of `P_CNC_LOG` packets to the
Mothership, which are repackaged and forwarded onto the LogServer.

# TODO Big Class Structure Diagram
Include NameBase/SBase in here.

# TODO Implementation Planning
