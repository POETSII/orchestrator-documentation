% Orchestrator Usage

# Overview

This document acts as a walkthrough for getting the Orchestrator
running. Prerequisite reading:

 - Orchestrator Overview (in this repository)

This document explains basic Orchestrator operation, given that you have the
sources. It also describes compilation and execution on a rudimentary
level. This document does not:

 - Explain what components of the Orchestrator that each command communicates
   with.

 - Provide an exhaustive list of commands.

# Building the Orchestrator

The only way to use the Orchestrator is to build it from its sources.

## System Requirements

In order to compile the Orchestrator, you will need:

 - A C++ compiler. We aim to support as wide a range of compilers as is
   reasonably possible. The Orchestrator is written to use the C++98 standard.

 - An implementation of the MPI-3 standard (Message Passing Interface). This is
   used to connect the Orchestrator components together. Mark uses mpich 3.2.1.

 - Qt (5.6). This is used by the XML parser, and will eventually
   disappear from this list of requirements.

 - Tinsel (from https://github.com/poetsii/tinsel).

 - QuartusPro. TODO: A description is needed here

There may be more dependencies.

## Building

### With Make

In short, there should have been a Makefile provided in the source of the
Orchestrator you have obtained. As appropriate, you will need to define the
paths to your dependencies in the makefile. When running the makefile (by
commanding `make` in your shell), if any warnings are raised, please shout
loudly at one of the maintainers. The build process creates a series of
disparate executables in the `bin` directory.

### Without Make

TODO: Perhaps ADB can weigh in here.

# Usage

## Execution

The Orchestrator is comprised of a series of disparate components (see
Orchestrator Overview). Each of these components is built into a separate
binary. To execute these binaries so that they can communicate with each other
using MPI, you will need to use the MIMD syntax (look at the man page for your
MPI distribution). By way of example, using mpich, command:

    # NB: The backslash (\) is a linebreak, included for typesetting reasons.

    mpirun ./orchestrator : ./logserver : ./rtcl : ./injector :\
           ./nameserver : ./supervisor : ./mothership

The order of executables doesn't matter, save for the `orchestrator`
executable, which must be first (corresponding to MPI rank zero). Each
executable should be run with a single process, hence the `-n` flag is not
used. Once executed, the Orchestrator states something to the effect of:

    Attach debugger to Root process 0 (0).....

which pauses execution of the Orchestrator, and invites you to connect a
debugging process, using your debugger of choice, to the process you created in
the execution step. Whether or not you attach a debugger, enter a newline
character into your shell to continue execution. You will then reach the
Orchestrator prompt:

    POETS>

at which commands can be executed. See Usage Examples for what to do from
here. Once you are finished with your Orchestrator session, command

    exit

then hit any key to end the Orchestrator process. Note that this will
effectively disown any jobs running on the Engine, so you will be unable to
reconnect to any jobs started in this way.

While your session is running, if you include the LogServer component, a log
file will be written in the current directory containing details of the
Orchestrator session.

## Usage Examples

Here are some common usage examples of the Orchestrator. The individual
commands are more fully described in the implementation documentation.

### Verifying all Orchestrator Components are Loaded

Once built, you may wish to verify that the components of the Orchestrator have
been started correctly, and can be communicated with. In the `POETS>` prompt,
command:

    system \show

which will print something like:

    Processes for comm 0
    Rank 00,            Root:OrchBase:CommonBase, created 12:05:16 Aug  8 2018
    Rank 02,                     RTCL:CommonBase, created 12:05:16 Aug  8 2018
    Rank 01,                LogServer:CommonBase, created 12:05:16 Aug  8 2018

In this case, the Root, RTCL, and LogServer components of the Orchestrator have
been started. Note that all components of the Orchestrator exist on the same
MPI communicator.

### Loading a task (XML)

In order to perform compute tasks on POETS using the Orchestrator, a task
(graph, XML) must first be loaded^[This example assumes that you have an
example XML task graph to load, but you can extrapolate the commands used here
for your purposes.]. At the `POETS>` prompt, command:

    task /path = "/path/to/the/task"

This command sets the path to load application XMLs from^[You can command this
multiple times per Orchestrator-session, and the path will change each
time]. The Orchestrator should respond, and you should see:

    POETS>task /path = "/path/to/the/task"
    POETS> 08:49:01.44:  23(I) task /path = "/path/to/the/task"
    POETS> 08:49:01.44: 102(I) Task graph default file path is || ||
    POETS> 08:49:01.44: 103(I) New path is ||/home/mv1g18/Aesop_image/application_source/||

This output from the Orchestrator is created by the LogServer, and is written
both to your prompt (on stdout), and to a log file in your current working
directory. This output simply:

 - Logs the command you have typed.

 - Shows the previous file path.

 - Shows the new path.

Now the path has been set, you can load the task graph into the Orchestrator by
commanding:

    task /load = "graph.xml"

which will print:

    POETS>task /load = "graph.xml"
    POETS> 08:49:18.01:  23(I) task /load = "graph.xml"

You can then verify that your task is loaded correctly by commanding:

    task /show

which shows all loaded tasks, and some information about them. This command
will print something like:

    POETS>task /show

    Orchestrator has 1 tasks loaded:

        |Task       |Supervisor |Linked   |Devices  |Channels |Declare    |PoL? |PoL type   |Parameters
        +-----------+-----------+---------+---------+---------+-----------+-----+-----------+------------+----....
      0 | graph     |graph_sup_unknown_inst |      no |    4687 |    7811 |graph |User |           |/path/to/the/task/graph.xml  |
        +-----------+-----------+---------+---------+---------+-----------+-----+-----------+------------+----....
    Default display filepath ||/path/to/the/task||

    POETS> 08:57:18.53:  23(I) task /show

This output shows that:

 - The Orchestrator has parsed the XML, so the task has been loaded.

 - Tasks have names (in this case, the name is `graph`, as shown in the `Task`
   column.

 - The Orchestrator knows whether or not a task has been linked (a linked task
   is a task that the Orchestrator has successfully mapped onto a model of the
   hardware).

 - The Orchestrator knows how many nodes and edges the task graph has.

As a user, you should verify that the information displayed by `task /show` is
correct for your task. Last minute verification is valuable! Now that you have
successfully loaded your task, you can run your task on the hardware.

### Running a loaded task

This example assumes you have completed the previous example, and that you have
an Orchestrator with your loaded task. This example will show you,
sequentially, how to:

 1. Inform the Orchestrator of the topology of the POETS engine (i.e. how many
    boxes/boards/threads/cores, and how they are connected). We call this the
    "hardware graph".

 2. Map the devices in the task graph to the hardware graph using the
    Orchestrator.

 3. How to generate binary files, from the C sources defined in the XML, which
    will run on the cores on the POETS engine.

 4. How to load these binary files onto their respective cores.

 5. How to start an application, once the binary files have been loaded.

#### Defining hardware topology in the Orchestrator

In order to run an application on the POETS engine, the Orchestrator needs to
know the topology of the hardware the application is to run on. For a one-box
system, command:

    topology /set1

The Orchestrator should respond simply with:

    POETS>topology /set1
    POETS> 09:24:05.29:  23(I) topology /set1
    POETS> 09:24:05.29: 138(I) Creating topology ||Set1||

If you are suspicious of the loaded topology, command:

    topology /dump = "./my_topology_dump"

This creates the file `./my_topology_dump`, and dumps a description of the
topology to that file. The Orchestrator prints:

    POETS>topology /dump = "./my_topology_dump"
    Config_t                   O_.Set1.ConfigXXX++++++++++++++++++++++++++++++++++++
    NameBase       O_.Set1.ConfigXXX
    Me,Parent      0x0x2080a10,0x0x2080c90
    bMem           = 4294967295
    boards         = 3
    cores          = 64
    threads        = 16
    Config_t                   O_.Set1.ConfigXXX------------------------------------
    POETS> 09:24:59.63:  23(I) topology /dump = "./my_topology_dump"

The file contains a hierarchical description of the topology, and is mostly
useful for debugging suspicious behaviour.

#### Mapping the devices in the task graph to the hardware graph (linking)

With both a task graph (loaded application), and a hardware graph (POETS engine
topology), the Orchestrator can map the former onto the latter. Command:

    link /link = "$NAME"

where the name of your task (`$NAME`) can be obtained from `task /show` in the
`Task` column. In this case, I'm loading a clocktree example. The Orchestrator
prints a lot of output:

    POETS>link /link = "clock_5_5"
    XLinking device O_.clock_5_5.clock_5_5_graph.root_2_0_1_1_3_leaf to thread O_.Set1.Bx20324.Bo20325.Co20326.Th20329
    XLinking device O_.clock_5_5.clock_5_5_graph.root_3_0_3_3_2_leaf to thread O_.Set1.Bx20324.Bo20325.Co20326.Th20329
    XLinking device O_.clock_5_5.clock_5_5_graph.root_3_0_2_3_4_leaf to thread O_.Set1.Bx20324.Bo20325.Co20326.Th20329
    ...
    XLinking device O_.clock_5_5.clock_5_5_graph.root_2_3_1_2_4_leaf to thread O_.Set1.Bx20324.Bo20325.Co20326.Th20333
    XLinking device O_.clock_5_5.clock_5_5_graph.drain_3_2_1 to thread O_.Set1.Bx20324.Bo20325.Co20326.Th20333
    XLinking device O_.clock_5_5.clock_5_5_graph.drain_4_2_0_0 to thread O_.Set1.Bx20324.Bo20325.Co20326.Th20333
    POETS> 09:32:39.98:  23(I) link /link = "clock_5_5"

TODO: Explain this, and mention `link /dump = "file"` in a footnote.

# Further Reading

 - The implementation documentation, specifically Chapter 5 (Console
   Operation). Seriously, do read this.
