% The Mothership and Supervisor Interfacing

# Overview
This document describes the Mothership, which is the Orchestrator process that
facilitates communication between the compute backend (normally Tinsel) on its
box, and the rest of the Orchestrator via MPI. The Mothership bridges the
event-computing paradigm on the backend, with conventional compute in the
Orchestrator. It also describes interfacing with Supervisor devices, which
operate within the Mothership process. The desirable features of the Mothership
process are:

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

 - *Packet*: An addressed item (`P_Pkt_t`) with some payload that traverses the
   compute fabric.

 - *Debug packet*: An addressed item sent over DebugLink (UART) connection in
   the Tinsel backend (`P_Debug_Pkt_t`, see the Debugging section).

 - *Thread*: POSIX thread running under the Mothership process (x86-land). NB:
   Not a "thread" in the compute fabric.

 - *Mothership*: Occasionally, I refer to the Mothership as a class (or
   object/instance), and a process. This is legacy - documentation is written
   to take people from the past to the present after all. I'll try to be
   explicit wherever I use this term.

Figure 1 shows the class structure diagram for the proposed Mothership design.

![Mothership class structure diagram](images/mothership_data_structure.png)

# Threads and Queues: Producer-Consumer
To support these features, a Producer-Consumer approach is used by the
Mothership. Figure 2 shows a schematic of how the Mothership process employs
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
   fabric. It calls `CommonBase::MPISpinner` and, when idle, executes idle
   logic from supervisor devices. This is a fast spinner.

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
   or pushes it to `MPICncQueue` (Tinsel Command and Control). Note that it
   does not push to `MPIApplicationQueue` (Supervisor) for fairness. This is a
   fast spinner.

 - `DebugInputBroker`: Responsible for draining the debug fabric into a large
   queue buffer (`DebugInputQueue`). When there are no packets to drain, or
   when the `DebugInputQueue` buffer is full, this thread converts the next
   packet into a message to be `Post`-ed, using MPI. This is a slow spinner.

[^malicious]: Or a maliciously-written supervisor, but we assume people will be
    playing nice for now.

[^backendinput]: I know Tinsel implements such a queue, but other backends may
    not. Better to have some uniformity, I think.

![Mothership process producer-consumer pattern. White-filled boxes represent
looping threads (spawned by `main`) where the fast/slow annotations denote the
behaviour of the spinner, black-filled boxes represent queues, black arrows
represent the producer-consumer relationship, red arrows represent MPI message
flow, and blue arrows represent backend packet flow. Logging not shown (all
threads can `Post` over MPI)](images/mothership_producer_consumer.png)

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
   (using `PMsg_p` messages), for `BackendOutputQueue` (using
   `std::pair<uint32_t, P_Pkt_t>` addressed packets), for `BackendInputQueue`
   (using `P_Pkt_t` packets), and for `DebugInputQueue` (using `P_Debug_Pkt_t`
   debug packets, see the Debugging section).

[^fatalerror]: By "fatal error", I mean that an exception is thrown in the
    thread logic, which is not caught. When this happens, the error is logged,
    and a graceful shutdown is attempted.

Another lock exists on a per-supervisor basis (`pthread_mutex_t
SuperHolder::lock`), which ensures that only one method from a given supervisor
is called at a time (to maintain the integrity of properties and state provided
by the application writer), and ensures that the supervisor is not compromised
when the application is stopped and started again. All supervisor calls respect
this lock.

# Command and Control
The Mothership process exists on the front of two streams of data traffic - the
MPI network connecting the Mothership to the rest of the Orchestrator, and the
compute backend network (typically Tinsel).

## MPI Command and Control
The operator controls Mothership processes through the console in the Root
process. The Root process sends messages to the Mothership process to perform
various C&C jobs, including application manipulation. Table 1 denotes subkeys
of messages that Mothership processes act upon (not including default handlers
introduced by `CommonBase`). Messages are received by the `MPIInputBroker`
consumer, which inherits from `CommonBase`. Messages with invalid key
combinations are dropped. Note that messages with `CMND` in their key
permutation stage a state transition from one application state to another (see
the Applications section); that transition is staged even if the Mothership has
no other information about the application yet.

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
| `APP`,  `SPEC`  | 0. `std::string`      | Defines that an application on    |
|                 |    `appName`          | the receiving Mothership process  |
|                 | 1. `uint32_t`         | must have received `distCount`    |
|                 |    `distCount`        | unique distribution (`APP`,       |
|                 | 2. `uint8_t`          | `DIST` and `APP`, `SUPD`)         |
|                 |    `appNumber`        | messages in order to be fully     |
|                 |                       | defined.                          |
+-----------------+-----------------------+-----------------------------------+
| `APP`,  `DIST`  | 0. `std::string`      | Defines the properties for a      |
|                 |    `appName`          | given core for a given            |
|                 | 1. `std::string`      | application on this Mothership    |
|                 |    `codePath`         | process.                          |
|                 | 2. `std::string`      |                                   |
|                 |    `dataPath`         |                                   |
|                 | 3. `uint32_t`         |                                   |
|                 |    `coreAddr`         |                                   |
|                 | 4. `std::vector<`     |                                   |
|                 |    `uint32_t>`        |                                   |
|                 |    `threadsExpected`  |                                   |
+-----------------+-----------------------+-----------------------------------+
| `APP`,  `SUPD`  | 0. `std::string`      | Defines the properties for the    |
|                 |    `appName`          | supervisor for a given            |
|                 | 1. `std::string`      | application on this Mothership.   |
|                 |    `soPath`           | Also loads the supervisor, and    |
|                 |                       | provisions its API.               |
+-----------------+-----------------------+-----------------------------------+
| `CMND`,  `RECL` | 0. `std::string`      | Removes information for an        |
|                 |    `appName`          | application, by name, from the    |
|                 |                       | Mothership. Does nothing on a     |
|                 |                       | running application (it must be   |
|                 |                       | stopped first).                   |
+-----------------+-----------------------+-----------------------------------+
| `CMND`, `INIT`  | 0. `std::string`      | Takes a fully-defined             |
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
| `CMND`, `RUN`   | 0. `std::string`      | Takes an application held at the  |
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
| `CMND`, `STOP`  | 0. `std::string`      | Takes a running application (with |
|                 |    `appName`          | state `RUNNING`) and sends a stop |
|                 |                       | packet (`P_CNC_STOP`) to all      |
|                 |                       | normal devices owned by that task |
|                 |                       | on the Mothership process. If the |
|                 |                       | application is not `RUNNING`,     |
|                 |                       | this message is acted on when it  |
|                 |                       | reaches that state (stopping      |
|                 |                       | before it starts will not stop it |
|                 |                       | from starting).                   |
+-----------------+-----------------------+-----------------------------------+
| `BEND`, `CNC`   | 0. `std::vector<`     | Calls a C&C method, via the       |
|                 |    `P_Pkt_t> packets` | `MPICncQueue`. The opcode (and    |
|                 |                       | hence the method) is identified   |
|                 |                       | from `packet`.                    |
+-----------------+-----------------------+-----------------------------------+
| `BEND`, `SUPR`  | 0. `std::string `     | Calls a method from a loaded      |
|                 |    `appName`          | supervisor, via the               |
|                 | 1. `std::vector<`     | `MPIApplicationQueue`.            |
|                 |    `P_Pkt_t> packets` |                                   |
+-----------------+-----------------------+-----------------------------------+
| `PKTS`          | 0. `std::vector<`     | Queues a series of destination-   |
|                 |    `std::pair<`       | hardware-address and packet pairs |
|                 |    `uint32_t,`        | into the backend.                 |
|                 |    `P_Pkt_t> packets` |                                   |
+-----------------+-----------------------+-----------------------------------+
| `DUMP`          | 0. `std::string path` | Dumps Mothership process state    |
|                 |                       | to a file at `path`.              |
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
| `MSHP`, `ACK`,  | 0. `std::string`      | Notifies the Root process that    |
| `DEFD`          |    `appName`          | the application has been fully    |
|                 |                       | defined.                          |
+-----------------+-----------------------+-----------------------------------+
| `MSHP`, `ACK`,  | 0. `std::string`      | Notifies the Root process that    |
| `LOAD`          |    `appName`          | the application has been fully    |
|                 |                       | loaded.                           |
+-----------------+-----------------------+-----------------------------------+
| `MSHP`, `ACK`,  | 0. `std::string`      | Notifies the Root process that    |
| `RUN`           |    `appName`          | the application has started       |
|                 |                       | running.                          |
+-----------------+-----------------------+-----------------------------------+
| `MSHP`, `ACK`,  | 0. `std::string`      | Notifies the Root process that    |
| `STOP`          |    `appName`          | the application has been fully    |
|                 |                       | stopped.                          |
+-----------------+-----------------------+-----------------------------------+
| `MSHP`, `REQ`,  | 0. `std::string`      | Requests the Root process to send |
| `STOP`          |    `appName`          | a stop message to all Motherships |
|                 |                       | running the application. Used by  |
|                 |                       | `stop_application` Supervisor API |
|                 |                       | call.                             |
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

 - `P_CNC_INSTR`: A packet with instrumentation data. See the Instrumentation
   section.

 - `P_CNC_LOG`: A packet with a logging message (possibly created by a call to
   `handler_log`). The information from the packet is formatted, and `Post`-ed
   to the Logserver.

 - `P_CNC_BARRIER`: A packet that, when received, informs the Mothership that a
   given thread has reached the softswitch barrier. If the state of the
   application to which this device belongs is `LOADING`, the field
   `Mothership.appdb.coreInfos[coreAddr].threadsCurrent` (where `coreAddr` is a
   `uint32_t` hardware address) for the core in question has the address of the
   sending thread inserted into it. If all of the threads for that core have
   reported back, `coreAddr` is appended to `coresLoaded`. Then, if all cores
   have been loaded (by checking the length of coresLoaded), the state of the
   application is transitioned from `LOADING` to `READY`.

 - `P_CNC_STOP`: A packet that, when received, informs the Mothership that a
   given thread has received the stop command (and has presumably now
   stopped). If the state of the application to which this device belongs is
   `STOPPING`, the field `Mothership.appdb.coreInfos[coreAddr].threadsCurrent`
   for the core in question has the address of the sending thread removed from
   it. If all of the threads for that core have reported back, `coreAddr` is
   removed from `coresLoaded`. Then, if `coresLoaded` is empty, the state of
   the application is transitioned from `STOPPING` to `STOPPED`, and the
   supervisor is unloaded.

 - `P_CNC_KILL`: A packet that, when received, stops the application associated
   with the packet (similar to the `CMND`, `STOP` message).

Notes:

 - The bulleted logic above is enacted by `MPICncResolver`.

 - Some of the opcodes listed above (e.g. `P_CNC_LOG`) can also meaningfully be
   sent by the Mothership to devices in the compute fabric, specifically:

    - `P_CNC_BARRIER`, which is the barrier-breaking packet sent as a result of
      a (`CMND`, `INIT`)

    - `P_CNC_STOP`, sent by (`CMND`, `STOP`))

    - `P_CNC_INSTR` to request instrumentation information from a softswitch
      (though this is not currently used).

 - A rogue application can shut down arbitrary applications by using
   `P_CNC_STOP` packets with different application IDs.

 - Applications can stop themselves in two ways - either a normal device sends
   a `P_CNC_KILL` packet to the Mothership, or the supervisor calls the `void
   Super::end()` API method (documented in the Supervisor API section).

 - There is no `P_CNC_INIT`. This opcode was used in the barrier-breaking
   packet for normal devices. It is replaced by `P_CNC_BARRIER`.

# Applications
The Mothership class contains an instance of class AppDB (`Mothership.appdb`),
which in turn maintains a map, `std::map<std::string, AppInfo> AppDB.appInfos`,
which describes applications that the Mothership process has been informed of,
as a function of their name. This map complements the database provided by
`SBase` (from which the Mothership inherits), by defining the states of
applications and loading information, as opposed to purely addressing
information. `AppInfo` is a class with these fields:

 - `std::string name`: The name of the application, redundant with the map key.

 - `AppState state`: The state that the application is in. Table 3 shows how
     C&C messages consumed by `MPICncResolver` drive application states. These
     states are enumerated by `AppState` as:

    - `UNDERDEFINED`: The application has been partly sent to the Mothership
      process, but some cores have not been defined, or their binaries refer to
      files that could not be found on the filesystem.

    - `DEFINED`: The application (`APP`, `SPEC`), its cores and binaries
      (`APP`, `DIST`), and its supervisor (`APP`, `SUPD`) have been completely
      defined on this Mothership, but nothing has been loaded onto hardware
      yet.

    - `LOADING`: As with `DEFINED`, but the loading process (`CMND`, `INIT`)
      has begun.

    - `READY`: All cores and supervisors are ready to start for this
      application.

    - `RUNNING`: As with `READY`, and the running process (`CMND`, `RUN`) has
      begun.

    - `STOPPING`: The application is running, but the stopping process (`CMND`,
      `STOP`) has begun.

    - `STOPPED`: The application was running, but has been stopped

    - `BROKEN`: Something went wrong, and the issue has been reported. The
      application is not stopped or otherwise "cleaned up" (for now).

 - `uint8_t pendingCommands`: Bit-vector storing pending commands from other
   processes (Root). This is private - accessed and set using these methods:

    - `void stage_init()`: Setter for the `INIT` command.

    - `void stage_run()`: Setter for the `RUN` command.

    - `void stage_stop()`: Setter for the `STOP` command.

    - `void stage_recl()`: Setter for the `RECL` command.

    - `bool should_we_continue()`: Given the current values of `state` and
      `pendingCommands`, returns `true` if the application is to "advance to
      the next state", and `false` otherwise.

    - `bool should_we_recall()`: As above, but for recalling.

 - `uint32_t distCountExpected`: Expected number of distribution messages for
   this application. Note that if an application is created by a distribution
   message, and a specification message has not been received, this is set to
   zero. Zero is treated as a special value denoting that the application is
   missing its specification message. Note that this also includes the
   supervisor distribution message for this Mothership process.

 - `uint32_t distCountCurrent`: Current number of distribution messages
   processed for this application. When this is equal to `distCountExpected`
   (and `distCountExpected` is nonzero), the application is fully defined. If
   `distCountCurrent` exceeds `distCountExpected` when incremented, the
   application state is set to `BROKEN`, and an error message is `Post`-ed.

 - `std::map<uint32_t, CoreInfo> coreInfos`: Information about the cores known
   about, and their loading state. The key is the hardware address of the
   core. CoreInfo is a structure with these fields:

    - `std::string codePath`: Path to the instruction binary for this core.

    - `std::string dataPath`: Path to the data binary for this core.

    - `std::set<uint32_t> threadsExpected`: Addresses of backend threads
      expected to report back for this core.

    - `std::set<uint32_t> threadsCurrent`: Addresses of backend threads that
      have reported back after loading the core. Used to transition from the
      `LOADING` state to the `READY` state. Also used for the opposite purpose,
      transitioning from `STOPPING` to `STOPPED`.

 - `std::set<uint32_t> coresLoaded`: Holds addresses for each core that have
   been completely loaded (i.e. all threads have reported back), and not
   stopped (see `threadsCurrent`)

There is a corresponding backwards map, `std::map<uint32_t, std::string>
AppDB.coreToApp`, which maps core addresses to the name of the application that
has claimed them. This map allows the Mothership process to more elegantly
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

[^none]: "None" here means that `AppDB` and `SBase` do not know about the
    application, and do not hold any information on it.

# Supervisors
Supervisors are devices in an application that exist on the Mothership, and can
communicate with normal devices serviced by the box associated with its
Mothership, as well as external devices elsewhere. They are:

 - Defined in the application description (XML)

 - Compiled into shared object files by the `Composer`

 - Deployed to the Mothership process via an (`APP`, `SUPD`) message

 - Loaded (it's a shared object) as part of an application by the Mothership
   process when the (`APP`, `SUPD`) message is received. The shared object is
   unloaded when the Mothership closes down, and is reloaded when the
   application is stopped.

 - Provisioned with a connection to the outside world by the Mothership (see
   the Supervisor API section below).

 - Represented by a `SuperHolder` object with the following fields (defined on
   construction - a supervisor that cannot be loaded and is not fully defined
   will cause the Mothership to report and set the application state to
   `BROKEN`):

    - `pthread_mutex_t lock`: Restricts supervisor operations to happen in
      sequence. For example, this prevents the idle handler being invoked while
      another call handler is running. It also prevents the shared object from
      being unloaded while it is being used.

    - `std::string path`: Where the supervisor was loaded from.

    - `void* so`: The dynamically-loaded supervisor (using `dlopen`), which
      populates the function pointer members.

    - `int (*exit)()`: Called when the application is stopped. Be aware that
      this is not called when the Supervisor is destroyed, either due to a
      recalled application, or due to a Mothership shutdown.

    - `int (*idle)()`: Called when the MPI Input Broker thread has no incoming
      messages to process - that thread iterates over every supervisor in the
      Mothership and calls this method if the supervisor is not locked.

    - `int (*init)()`: Called when the application is started.

    - `int (*call)(PMsg_p, PMsg_p)`: The entry point for all incoming
      supervisor packets while the application is running.

    - `SupervisorApi* (*getApi)()`: Used to provision the Supervisor API (see
      below).

 - Stored in the `SuperDB` object (`Mothership.superdb`) within
   `std::map<std::string, SuperHolder> SuperDB.supervisors`, keyed by
   application name. For an incoming packet, the appropriate supervisor is
   identified from the task component of the software address. If the task
   component does not correspond to a loaded application, the Mothership
   `Post`-s an error message, and drops the packet. The packet is also dropped
   if the application is not running.

## Supervisor API
Supervisor shared objects contain an unpopulated `SupervisorAPI` object, which
is provisioned by the Mothership when the Supervisor shared object is loaded
(via `Mothership::provision_supervisor_api`). The supervisor API exposes a set
of functions that can be called from supervisor handler (as described in the
application definition document). Specifically, a supervisor handler can call
these functions (where `Super` is a namespace):

 - `void Super::post(std::string message)`: Posts a message to the logserver.

 - `void Super::stop_application()`: Stops the application, by sending a
   (`MSHP`, `REQ`, `STOP`) message to the Root process. The Root process then
   sends a (`CMND`, `STOP`) message to all Mothership processes running that
   application.

 - `std::string Super::get_output_directory(std::string suffix="")`: Returns
   the absolute path of a directory on the disk of the machine hosting the
   Mothership. This path has the form
   `/home/$USER/<REMOTE_SAFEDIR>/<APPNAME>_<DATETIME_ISO8601><SUFFIX>`, where:

   - `<REMOTE_SAFEDIR>` is defined in the Orchestrator configuration by field
     `remote_safedir` in the `[default_paths]` section, or is overridden by the
     Orchestrator operator.

   - `<APPNAME>` is the name of the application.

   - `<DATETIME_ISO8601>` is a datetime.

   - `<SUFFIX>` is the `suffix` passed as argument (default empty).

`SupervisorAPI` is a "bridge class" used by both the Mothership, and by
Supervisors. It has the following fields:

 - `Mothership* mship`: A back-pointer used to send MPI messages to other
   processes, to queue packets to compute devices, post error messages, and
   more. Note that nefarious application writers can access this pointer via
   `Supervisor::__api::mship`, but they'll earn a slap on the wrist if they
   manage it without first reading about it here.

 - `std::string appName`: The name of the application.

 - `void (*post)(Mothership*, std::string)`: A function pointer provisioned by
   the Mothership when the supervisor is loaded. This is called by the
   `post` API call.

 - `void (*stop_application)(Mothership*, std::string)`: A function pointer
   provisioned by the Mothership when the supervisor is loaded. This is called
   by the `stop_application` API call.

As a side note, future API methods may include:

 - `void Super::message_leader(uint8_t[SOME_NUMBER] payload)`: Packages the
   payload into a `P_Pkt_t`, and sends it using a (`BEND`, `SUPR`) message to
   the supervisor "leader" (which is simply the supervisor on the Mothership
   with the lowest rank for this application).

 - `void Super::supervisor_broadcast(uint8_t[SOME_NUMBER] payload)`: Packages
   the payload into a `P_Pkt_t`, and sends it using a (`BEND`, `SUPR`) message
   to all supervisors running for this application, except this one.

 - `std::vector<std::string> Super::expose_device_map(const
   std::vector<DeviceAddress>`: Some method that exposes the name of a device
   (or set thereof) given a full address. Of particular use when outputting the
   name of a device, from Supervisor handler, is desired. External devices
   should still query NameServer to get this information.

 - Some method to set an RTCL "wake up call". Such a method could accept a
   paylod that is stored in the Mothership (as opposed to sent over the
   network), which is read when RTCL issues the "wake up call". Clock ticks in
   neuromorphic modelling is the usecase for this.

# Logging
Normal devices in applications can send log messages to the Mothership by using
the `handler_log` method described in the Softswitch documentation. This
manifests as a series of log packets (with a `P_CNC_LOG` opcode) sent from the
logging device to the Mothership, where multiple packets are sent for each log
message. The `LogPacketManager` stores these packets until a complete message
is formed, at which point the message is `Post`-ed and forgotten. Packets are
stored on a per-compute-thread basis.

# Debugging
In addition to the acknowledgement messages that the Mothership generates while
transitioning applications between states, and the `DUMP` message, it is useful
to have more fine-grained debugging control over running applications. The
Tinsel backend provides a debugging interface over its UART backchannel, which
can be exploited to exfiltrate acknowledgement and debugging information from
normal devices in the backend. The `DebugInputBroker` acts on packets received
by the Mothership by `Post`-ing a formatted message to the Logserver, including
the packet payload and its origin. Debug packets sent in this way are stored as
`std::pair<uint32_t, uint8_t>` objects, where the first element of the pair
represents the hardware address source (decoded using `HostLink::toAddr`), and
the second element of the pair represents the byte payload. This class is
type-defined as `P_Debug_Pkt_t`.

Applications can also call the `void handler_log(int level, const char* text)`
free function in a handler, which sends a series of `P_CNC_LOG` packets to the
Mothership, which are repackaged and forwarded onto the LogServer.

# Instrumentation
Along with logging, it is useful to understand how the compute backend is
performing during a given application, to help with optimisation and problem
diagnosis. The Mothership object holds an `InstrumentationWriter` instance,
which consumes instrumentation data sent from the compute backend, and produces
a set of CSV files at `$HOME/.orchestrator/instrumentation`, one per compute
thread, describing the performance. `InstrumentationWriter` has no `dump`
method, because it writes data to a file on receipt of a packet anyway.

This topic is explained further, from the perspective of the Softswitch, in the
Softswitch documentation. Eventually, instrumentation will be handled by the
Monitor process, which will collect instrumentation data and generate
visualisations in real-time; the Mothership process will continue to act as a
broker between the compute backend and the Orchestrator in this regard.

# Appendix A: Message/Packet Handling Examples
To follow along, use Figure 2 and the Command and Control section.

## Example 1: An `EXIT` Message Arrives at the Mothership
  1. The `MPIInputBroker` thread (which uses `CommonBase::MPISpinner()`) takes
     the message, and decodes its key. On noting that the message is an `EXIT`
     message, it is moved to the `MPICncQueue`.

  2. The `MPICncResolver` thread reads from the `MPICncQueue`, takes the
     message, and decodes its key. On noting that the message is an `EXIT`
     message, the thread calls `Mothership->threading.set_quit()`.

  3. Each thread, before receiving any more packets or messages, calls
     `Mothership->threading.is_it_time_to_go()`. Because `set_quit()` has been
     called, each thread will elegantly exit before handling any more packets
     and messages.

  4. The `main` thread joins successfully, and the Mothership process is exited
     gracefully.

  Note that (`SYST`, `KILL`) messages are handled similarly - when
  `MPIInputBroker` is joined to `main`, `main` checks
  `Mothership->threading.is_it_time_to_go()` and, if not set, cancels the
  remaining threads directly and exits.

## Example 2: A `P_CNC_STOP` Packet Arrives at the Backend
  1. The `BackendInputBroker` consumes the packet and investigates its
     destination and opcode. Given that the opcode is special and the
     destination is for the supervisor, the thread wraps it in a (`BEND`,
     `CNC`) message, and pushes it to the `MPICncQueue`.

  2. The `MPICncResolver` thread reads from the `MPICncQueue`, takes the
     message, and decodes its key. On noting that the message is a (`BEND`,
     `CNC`) message, it decodes the packet key. On noting it's a `P_CNC_STOP`
     packet, this thread updates `Mothership.appdb` as per section 3. If the
     process has been stopped due to this, the Mothership sends a
     (`MSHP`,`ACK`,`STOP`) message to the Root process.

## Example 3: A non-opcoded Packet Arrives at the Backend Addressed to the Supervisor (as opposed to an External)
  1. The `BackendInputBroker` consumes the packet and investigates its
     destination and opcode. Given that the opcode is special and the
     destination is for the supervisor, the thread wraps it in a (`BEND`,
     `SUPR`) message, and pushes it to the `MPIApplicationQueue`.

  2. The `MPIApplicationResolver` reads from the `MPIApplicationQueue`, takes
     the message and decodes its key. On noting that the message is a (`BEND`,
     `SUPR`) message, the thread calls the appropriate supervisor handler with
     it. Then...

### Example 3a: A Supervisor sends a packet to the compute fabric
  3. The `MPIApplicationResolver` creates the packet and pushes it to the
     `BackendOutputQueue`, along with its destination as part of the pair.

  4. The `BackendOutputBroker` reads from the `BackendOutputQueue`, and pushes
     the packet into the compute backend.

# Appendix B: A Rough Implementation Plan
This Mothership design differs from the existing Mothership in the following
ways:

 - Threads are all started at the beginning of the Mothership process
   (i.e. before any messages are received), as opposed to the previous
   Mothership, which starts Twig (the backend-receiving thread) in
   advance. Furthermore, the thread that processes backend packets
   (`BackendInputBroker` vs `Twig`) no longer "resolves" the packet, but simply
   forwards it on

 - MPI messages have different forms and arguments (though backend messages are
   the same), and acknowledgement messages are sent back from the Mothership
   process to the Root process.

 - The data structures for holding application and supervisor information do
   not use the hardware model, and are constructed from different pieces of
   information.

 - Quitting and cleanup operates independently of backend traffic. The proposed
   design does not fail to exit or to terminate an application if it is
   spamming the Mothership.

 - The proposed design introduces intermediate application states for certain
   stages, respects deploy and command messages arriving out-of-order (i.e. due
   to traffic), and has a simpler state transition mechanism.

 - The backend is now loaded independently of Mothership object construction,
   and does not prevent the Orchestrator from starting if unable to load.

 - Multiple supervisors-per-Mothership (not per application) are now supported,
   and communication between supervisors is defined (albeit tenuously for now).

Given these differences, this design will be implemented in the following way,
where each stage represents a reviewable unit (probably by GMB):

 1. An implementation of the core constructs. This implementation will be the
    minimum possible to replicate the feature set of the existing Mothership as
    closely as possible.

 2. A performance comparison between the new and old Motherships to check for
    regression. One key difference expected is that, since Twig calls
    supervisor logic directly, there will be a slightly increased supervisor
    message "processing latency", but the backend queue in the new Mothership
    will be drained more quickly. Any regression issues will be resolved here.

 3. Given that it has been developed, SBase would be integrated next for
    external device support. This will require a small refactor of the
    application deployment messages (`APP`, `*`) to identify the most efficient
    solution.

 4. Implementation of the supervisor API.

 5. True multibox support, including an explicit Box->Mothership map in Root,
    and HostLink considerations.
