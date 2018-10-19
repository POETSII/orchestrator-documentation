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

Since the Orchestrator is under development, it is probable that these commands
and their output may change. While the development team will make best efforts
to update this documentation, it is inevitable that some idiosyncrasies are not
captured in testing. If you encounter a mistake, or a section were output or
commands do not match, please inform an Orchestrator developer.

# Building the Orchestrator

The only way to use the Orchestrator is to build it from its sources.

## System Requirements

In order to compile and use the Orchestrator, you will need:

 - A C++ compiler. We aim to support as wide a range of compilers as is
   reasonably possible. The Orchestrator is written to use the C++98 standard.

 - A RISCV C compiler, for compiling the source fragments in task graphs for
   the RISCV cores on FPGAs.

 - An implementation of the MPI-3 standard (Message Passing Interface). This is
   used to connect the Orchestrator components together. Mark uses mpich 3.2.1.

 - Qt (5.6). This is used by the XML parser, and will eventually
   disappear from this list of requirements.

 - Tinsel (from https://github.com/poetsii/tinsel).

 - QuartusPro. TODO: A description is needed here

TODO: There may be more dependencies.

To operate the Orchestrator, these environment variables must be defined and be
available to subprocesses (i.e. `export`-ed):

 - `RISCV_PATH`: Path to the directory in which RISCV C compiler was installed
   (the level before the binary directory).

 - `PATH`: The `PATH` should be appended with the `bin` directory of your MPI
   installation, and the `bin` directory of your RISCV compiler. For example,
   `PATH=$HOME/mpich-3-2-1/bin:$RISCV_PATH/bin:$PATH`.

 - `TRIVIAL_LOG_HANDLER`: Must be set to `1`.

 - `LM_LICENSE_FILE`: Must be set to `:27012@localhost:27001@localhost` TODO:
   What does this do? Should it be different on different boxes? (this works on
   Aesop)

You will also need to have sourced the appropriate Quartus setup script for
your version of Quartus. On Aesop, this is at
`/local/ecad/setup-quartus17v0.bash`. TODO: Needs more explanation.

## Building

### With Make

In short, there should have been a Makefile provided in the source of the
Orchestrator you have obtained. As appropriate, you will need to define the
paths to your dependencies in the makefile. When running the makefile (by
commanding `make` in your shell in the appropriate `Build` directory for your
compiler by changing into it), if any warnings are raised, please shout loudly
at one of the maintainers. The build process creates a series of disparate
executables in the `bin` directory.

### Without Make

TODO: Perhaps ADB can weigh in here.

# Usage

## Execution

The Orchestrator is comprised of a series of disparate components (see
Orchestrator Overview). Each of these components is built into a separate
binary. To execute these binaries so that they can communicate with each other
using MPI, you will need to use the MIMD syntax (look at the man page for your
MPI distribution). By way of example, using mpich, command:

~~~ {.bash}
# NB: You will need to define these environment variables appropriately for your setup.

QT_LIB_PATH="/path/to/QtLib_gcc64"
MPI_LIB_PATH="/path/to/mpi/installation/lib"
GCC_LIB_PATH="/path/to/gcc-7.3.0/lib64"

mpirun -genv LD_LIBRARY_PATH ./:$QT_LIB_PATH:$MPI_LIB_PATH:$GCC_LIB_PATH ./orchestrator : ./logserver : ./rtcl : ./injector : ./nameserver : ./supervisor : ./mothership
~~~

The order of executables doesn't matter, save for the `orchestrator`
executable, which must be first (corresponding to MPI rank zero). Each
executable should be run with a single process, hence the `-n` flag is not
used. Once executed, the Orchestrator states something to the effect of:

~~~ {.bash}
Attach debugger to Root process 0 (0).....
~~~

which pauses execution of the Orchestrator, and invites you to connect a
debugging process, using your debugger of choice, to the process you created in
the execution step. Whether or not you attach a debugger, enter a newline
character into your shell to continue execution. You will then reach the
Orchestrator prompt:

~~~ {.bash}
POETS>
~~~

at which commands can be executed. See Usage Examples for what to do from
here. Once you are finished with your Orchestrator session, command

~~~ {.bash}
exit
~~~

then hit any key to end the Orchestrator process. Note that this will
effectively disown any jobs running on the Engine, so you will be unable to
reconnect to any jobs started in this way.

While your session is running, if you include the LogServer component, a log
file will be written in the current directory containing details of the
Orchestrator session.

## An Exemplary Orchestrator Session

Here are some common usage examples of the Orchestrator. The individual
commands are more fully described in the implementation documentation. This
chain of examples describes an example Orchestrator session. These examples
will show you, sequentially, how to:

 1. Verify that all components of the Orchestrator have been loaded in the
    current session.

 2. Load a task (XML).

 3. Inform the Orchestrator of the topology of the POETS engine (i.e. how many
    boxes/boards/threads/cores, and how they are connected). We call this the
    "hardware graph".

 4. Map the devices in the task graph to the hardware graph using the
    Orchestrator (linking).

 5. How to generate binary files, from the C sources defined in the XML, which
    will run on the cores of the POETS engine.

 6. How to load these binary files onto their respective cores, and to start an
    application once the binary files have been loaded.


### Verifying all Orchestrator Components are Loaded

Once built, you may wish to verify that the components of the Orchestrator have
been started correctly, and can be communicated with. At the `POETS>` prompt,
command:

~~~ {.bash}
system /show
~~~

which will print something like:

~~~ {.bash}
Processes for comm 0
Rank 00,            Root:OrchBase:CommonBase, created 12:05:16 Aug  8 2018
Rank 02,                     RTCL:CommonBase, created 12:05:16 Aug  8 2018
Rank 01,                LogServer:CommonBase, created 12:05:16 Aug  8 2018
~~~

In this case, the Root, RTCL, and LogServer components of the Orchestrator have
been started. Note that all components of the Orchestrator exist on the same
MPI communicator.

### Loading a task (XML)

In order to perform compute tasks on POETS using the Orchestrator, a task
(graph, XML) must first be loaded^[This example assumes that you have an
example XML task graph to load, but you can extrapolate the commands used here
for your purposes.]. At the `POETS>` prompt, command:

~~~ {.bash}
task /path = "/path/to/the/task"
~~~

This command sets the path to load application XMLs from^[You can command this
multiple times per Orchestrator-session, and the path will change each
time]. The Orchestrator should respond, and you should see:

~~~ {.bash}
POETS>task /path = "/path/to/the/task"
POETS> 08:49:01.44:  23(I) task /path = "/path/to/the/task"
POETS> 08:49:01.44: 102(I) Task graph default file path is || ||
POETS> 08:49:01.44: 103(I) New path is ||/path/to/the/task||
~~~

This output from the Orchestrator is created by the LogServer, and is written
both to your prompt (on stdout), and to a log file in your current working
directory. This output simply:

 - Logs the command you have typed.

 - Shows the previous file path.

 - Shows the new path.

Now the path has been set, you can load the task graph into the Orchestrator by
commanding:

~~~ {.bash}
task /load = "graph.xml"
~~~

which will print:

~~~ {.bash}
POETS>task /load = "graph.xml"
POETS> 08:49:18.01:  23(I) task /load = "graph.xml"
~~~

You can then verify that your task is loaded correctly by commanding:

~~~ {.bash}
task /show
~~~

which shows all loaded tasks, and some information about them. This command
will print something like:

~~~ {.bash}
POETS>task /show

Orchestrator has 1 tasks loaded:

    |Task       |Supervisor |Linked   |Devices  |Channels |Declare     |PoL? |PoL type   |Parameters
    +-----------+-----------+---------+---------+---------+----------- +-----+-----------+------------+----....
  0 | graph     |graph_sup_unknown_inst |      no |    4687 |    7811  |graph |User |           |/path/to/the/task/graph.xml  |
    +-----------+-----------+---------+---------+---------+----------- +-----+-----------+------------+----....
Default display filepath ||/path/to/the/task||

POETS> 08:57:18.53:  23(I) task /show
~~~

This output is a table (which is difficult to typeset). This output shows that:

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

### Defining hardware topology in the Orchestrator

In order to run an application on the POETS engine, the Orchestrator needs to
know the topology of the hardware the application is to run on. For a one-box
system, command:

~~~ {.bash}
topology /set1
~~~

The Orchestrator should respond simply with:

~~~ {.bash}
POETS>topology /set1
POETS> 09:24:05.29:  23(I) topology /set1
POETS> 09:24:05.29: 138(I) Creating topology ||Set1||
~~~

If you are suspicious of the loaded topology, command:

~~~ {.bash}
topology /dump = "./my_topology_dump"
~~~

This creates the file `./my_topology_dump`, and dumps a description of the
topology to that file. The Orchestrator prints:

~~~ {.bash}
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
~~~

The file contains a hierarchical description of the topology, and is mostly
useful for debugging suspicious behaviour.

### Mapping the devices in the task graph to the hardware graph (linking)

With both a task graph (loaded application), and a hardware graph (POETS engine
topology), the Orchestrator can map the former onto the latter. Command:

~~~ {.bash}
link /link = "$NAME"
~~~

where the name of your task (`$NAME`) can be obtained from `task /show` in the
`Task` column. In this case, I'm loading a clocktree example. The Orchestrator
prints a lot of output:

~~~ {.bash}
POETS>link /link = "clock_5_5"
XLinking device O_.clock_5_5.clock_5_5_graph.root_2_0_1_1_3_leaf to thread O_.Set1.Bx20324.Bo20325.Co20326.Th20329
XLinking device O_.clock_5_5.clock_5_5_graph.root_3_0_3_3_2_leaf to thread O_.Set1.Bx20324.Bo20325.Co20326.Th20329
XLinking device O_.clock_5_5.clock_5_5_graph.root_3_0_2_3_4_leaf to thread O_.Set1.Bx20324.Bo20325.Co20326.Th20329
...
XLinking device O_.clock_5_5.clock_5_5_graph.root_2_3_1_2_4_leaf to thread O_.Set1.Bx20324.Bo20325.Co20326.Th20333
XLinking device O_.clock_5_5.clock_5_5_graph.drain_3_2_1 to thread O_.Set1.Bx20324.Bo20325.Co20326.Th20333
XLinking device O_.clock_5_5.clock_5_5_graph.drain_4_2_0_0 to thread O_.Set1.Bx20324.Bo20325.Co20326.Th20333
POETS> 09:32:39.98:  23(I) link /link = "clock_5_5"
~~~

Each device defined in the task graph is one-to-one mapped to a thread in the
POETS engine. Note that threads are identified in a hierarchical manner for
debugging purposes; one can interpret `O_.Set1.Bx20324.Bo20325.Co20326.Th20333`
as "The thread with ID '20333' on the core with ID '20326' on the FPGA board
with ID '20325' in the POETS box with ID '20324' as described by the 'Set1'
topology". For diagnostic information, this mapping, and its inverse, can be
dumped by commanding `link /dump = "file"`.

### Building binaries for devices (compilation)

The task definition is comprised of the task graph (how devices are connected
to each other, and how they communicate), and the device logic (the C fragments
that define what each device does). Given the hardware mapping from the linking
step, the Orchestrator can now produce binary files to execute on the cores of
the POETS engine. To build these binaries in an idempotent manner, command:

~~~ {.bash}
task /build = "$NAME"
~~~

where the name of your task (`$NAME`) can be obtained from `task /show` in the
`Task` column. This creates a directory structure at `task /path`, which you
may have set earlier in execution. The code fragments defined in the task XML
are assembled here, and are compiled using the RISCV compiler defined in the
System Requirements section of this document. Compilation may produce warnings
or errors, which will be printed to stdout while the command is being executed;
these should not be ignored in normal operation. Assuming no warnings or errors
are printed, you should see the following output (again, I am using a clocktree
example):

~~~ {.bash}
POETS> task /build = "clock_5_5"
POETS> 12:03:31.70:  23(I) task /build = "clock_5_5"
POETS> 12:03:31.70: 801(D) P_builder::Add(name=clock_5_5, file=/home/mv1g18/Aesop_image/application_source/clock_tree_5_5.xml)
~~~

### Loading binaries into devices for execution, and running the application

With a set of binaries to be loaded onto each core of the POETS engine, the
application can be run. Firstly, stage each binary onto its appropriate core by
commanding:

~~~ {.bash}
task /deploy = "$NAME"
~~~

where the name of your task (`$NAME`) can be obtained from `task /show` in the
`Task` column. Once executed, these binaries ready the cores to execute the
application, but block execution behind a barrier. To ready the cores, command:

~~~ {.bash}
task /init = "$NAME"
~~~

Control is returned to the user once this initialisation command is sent,
though there is no acknowledgement when all of the cores have
initialised. Commanding:

~~~ {.bash}
task /run = "$NAME"
~~~

will start the application once the cores have been initialised; the
application will not start before the cores have been initialised.

## Batch execution with expect

TODO: Coming soon.

## Usage Summary

This section has demonstrated how to execute the Orchestrator, and an example
session for running an application on the POETS engine. The example session
demonstrates rudimentary Orchestrator operation, and is sufficient to execute
most tasks of interest.

# Further Reading

 - The implementation documentation, specifically Chapter 5 (Console
   Operation). Seriously, do read this.
