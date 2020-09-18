% Orchestrator Usage

# Overview

This document acts as a walkthrough for getting the Orchestrator running on
POETS hardware. Prerequisite reading:

 - Orchestrator Overview (in this repository)

This document explains basic Orchestrator operation with a simple example. This
document does not:

 - Describe how to get an account on a POETS machine.

 - Describe compilation in detail (rudimentary knowledge of the POSIX shell
   `sh` is assumed).

 - Describe how compilation and execution can be adapted to run on non-POETS
   machines.

 - Explain what components of the Orchestrator that each command communicates
   with.

 - Provide an exhaustive list of commands.

Since the Orchestrator is under development, it is probable that these commands
and their output may change. While the development team will make best efforts
to update this documentation, it is inevitable that some idiosyncrasies are not
captured. If you encounter a mistake, or a section were output or commands do
not match, please inform an Orchestrator developer.

# Setup

Given that you have an account on a POETS machine, you will first need to build
the Orchestrator. The only way to use the Orchestrator is to build it from its
sources. To set up the Orchestrator, perform the following actions on the POETS
machine from your user account:

 - To obtain the sources, clone the Orchestrator Git repository, at
   https://github.com/poetsii/Orchestrator, and check out the "development"
   branch.

 - In the file `Build/gcc/Makefile.dependencies` in the Orchestrator
   repository, confirm that the directory pointed to by the
   `ORCHESTRATOR_DEPENDENCIES_DIR` variable exists. If it does not, complain to
   an Orchestrator developer, and:

   - Obtain the latest Orchestrator dependencies tarball from
     https://github.com/poetsii/orchestrator-dependencies/releases, extract it,
     and modify the `ORCHESTRATOR_DEPENDENCIES_DIR` variable in
     `Build/gcc/Makefile.dependencies` to point to the root directory of it. If
     you want to help your fellow users and you're on a POETS box, you can
     extract it to `/local/orchestrator-dependencies/`.

 - From the `Build/gcc` directory in the Orchestrator repository, command `make
   all` to build the Orchestrator. You may also wish to build in parallel,
   using the `-j N` flag ("N" build slaves will be used).

The build process creates a series of disparate executables in the `bin`
directory in the Orchestrator repository. If this process fails, or raises
warnings, please alert an Orchestrator developer, who will (hopefully) either
fix these instructions, or fix the mistake in the build process. Once you have
successfully completed the build, you are ready to use the Orchestrator on
POETS hardware.

# Usage (Interactive)

## Execution

Once built, change directory into the root directory of the Orchestrator
repository, and command:

~~~ {.bash}
./orchestrate.sh  #This script is created during the build process
~~~

Once executed, the Orchestrator waits at:

~~~ {.bash}
Attach debugger to Root process 0 (0).....
~~~

which pauses execution of the Orchestrator, and invites you to connect a
debugging process, using your debugger of choice, to the process you created in
the execution step. Whether or not you attach a debugger, enter a newline
character into your shell to continue execution. You will then reach the
Orchestrator operator prompt:

~~~ {.bash}
POETS>
~~~

at which commands can be executed. Once you are finished with your Orchestrator
session, command:

~~~ {.bash}
exit
~~~

then hit any key to end the Orchestrator process. Note that this will
effectively disown any jobs running on the Engine, so you will be unable to
reconnect to any jobs started in this way.

You may also encounter a message similar to:

~~~ {.bash}
POETS> 11:16:30.04: 140(I) Topology loaded from file ||/local/orchestrator-common/hdf.uif||.
POETS>
~~~

in which case, the developer that has set up this machine has installed a
default topology file, which you can later overwrite if desired (for more
information about this default, see the launcher documentation).

If your session terminates with

~~~ {.bash}
Failed to acquire HostLink lock: Resource temporarily unavailable
~~~

then the Mothership process was unable to connect to the API that allows it to
control the Engine, so the Orchestrator has aborted. This error is raised when
another Mothership process is already running on this box; only one Mothership
process can run on a box in the Engine at a time. Until that process ends, you
will not be able to use the Orchestrator. This error may also be raised when
the disk runs out of space, which you can check by commanding `df -h`.

While your session is running, if you include the Logserver component, a log
file will be written in the `bin` directory containing details of the
Orchestrator session.

## Help

Command `./orchestrate.sh --help` (obviously).

## An Exemplary Orchestrator Session

This section presents an examplar Orchestrator session, where we will simulate
the flow of heat across a plate. This requires you to:

 - Have built the Orchestrator successfully on a POETS machine.

 - Obtain an XML description of the heated plate example from the Git
   repository of examples, at https://github.com/poetsii/Orchestrator_examples,
   in `plate_heat`. For this demonstration, we will be using the premade 3x3
   example. Place the XML file in the `application_staging/xml` directory in
   the Orchestrator repository on the POETS machine.

This session will, in order (using Byron):

 1. Verify that all components of the Orchestrator have been loaded in the
    current session.

 2. Load a task (XML).

 3. Inform the Orchestrator of the topology of the POETS engine (i.e. how many
    boxes/boards/threads/cores, and how they are connected).

 4. Map the devices in the task graph to the hardware graph using the
    Orchestrator (linking).

 5. Generate binary files, from the sources defined in the XML, which will run
    on the RISCV cores of the POETS engine.

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
Rank 00,            Root:OrchBase:CommonBase, created 10:28:19 Apr 16 2020
Rank 01,                LogServer:CommonBase, created 10:28:19 Apr 16 2020
Rank 02,                     RTCL:CommonBase, created 10:28:19 Apr 16 2020
Rank 03,               Mothership:CommonBase, created 10:28:19 Apr 16 2020

POETS> 16:06:32.31:  23(I) system /show
POETS> 16:06:32.31:  29(I) The Orchestrator has 4 MPI processes on comm 0
POETS> 16:06:32.31:  30(I) Process fielding has console I/O
~~~

In this case, the Root, RTCL, LogServer, and Mothership components of the
Orchestrator have been started. Note that all components of the Orchestrator
exist on the same MPI communicator.

### Loading a task (XML)

In order to perform compute tasks on POETS using the Orchestrator, a task
(graph, XML) must first be loaded. At the `POETS>` prompt, command:

~~~ {.bash}
task /path = "/path_to_orchestrator_repository/application_staging/xml"
~~~

This command sets the path to load application XMLs from^[You can command this
multiple times per Orchestrator-session, and the path will change each
time]. In this case, set this to the `application_staging/xml` directory in
your copy of the Orchestrator repository. The Orchestrator should respond, and
you should see (with your path):

~~~ {.bash}
POETS>task /path = "/path_to_orchestrator_repository/application_staging/xml"
POETS> 08:49:01.44:  23(I) task /path = "/path_to_orchestrator_repository/application_staging/xml"
POETS> 08:49:01.44: 102(I) Task graph default file path is || ||
POETS> 08:49:01.44: 103(I) New path is ||/path_to_orchestrator_repository/application_staging/xml||
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
task /load = "plate_3x3.xml"
~~~

which will print:

~~~ {.bash}
POETS>task /load = "plate_3x3.xml"
POETS> 08:49:18.01:  23(I) task /load = "plate_3x3.xml"
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

    |Task       |Supervisor |Linked   |Devices  |Channels |Declare    |PoL? | PoL type   |Parameters
    +-----------+-----------+---------+---------+---------+-----------+-----+ -----------+------------+----....
  0 | plate_3x3 |plate_3x3_supervisorNode_inst |      no |      10 |      38| plate_heat |User |           |/path_to_orchestrator_repository/application_staging/xml/plate_3x3.xml  |
    +-----------+-----------+---------+---------+---------+-----------+-----+ -----------+------------+----....
Default display filepath ||/path_to_orchestrator_repository/application_staging/xml||

POETS> 08:57:18.53:  23(I) task /show
~~~

This output is a table (which is difficult to typeset). This output shows that:

 - The Orchestrator has parsed the XML, so the task has been loaded.

 - Tasks have names (in this case, the name is `plate_3x3`, as shown in the
   `Task` column.

 - The Orchestrator knows whether or not a task has been linked (a linked task
   is a task that the Orchestrator has successfully mapped onto a model of the
   hardware).

 - The Orchestrator knows how many nodes and edges the task graph has.

As a user, you should verify that the information displayed by `task /show` is
correct for your task. Last minute verification is valuable! Now that you have
successfully loaded your task, you can run your task on the hardware.

### Defining hardware topology in the Orchestrator

In order to run an application on the POETS engine, the Orchestrator needs to
know the topology of the hardware the application is to run on. If you received
the "Topology loaded" message from the execution section previously, then the
Orchestrator already has a loaded topology, and you need not do anything
more. However, for the purposes of this example, we will overwrite the loaded
topology.

For a one-box system, command:

~~~ {.bash}
topology /set1
~~~

The Orchestrator should respond simply with (may also include a "Clearing"
message if a topology was previously loaded):

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
POETS> 09:24:59.63:  23(I) topology /dump = "./my_topology_dump"
~~~

The file contains a hierarchical description of the topology, and is mostly
useful for debugging suspicious behaviour.

### Mapping the devices in the task graph to the hardware graph (linking)

With both a task graph (loaded application), and a hardware graph (POETS engine
topology), the Orchestrator can map the former onto the latter. Command:

~~~ {.bash}
link /link = "plate_3x3"
~~~

where the name of your task (in our case, `plate_3x3`) can be obtained from
`task /show` in the `Task` column. The Orchestrator prints:

~~~ {.bash}
POETS>link /link = "plate_3x3"
XLinking device O_.plate_3x3.plate_3x3_graph.c_0_1 with id 0 to thread O_.Set1.Bx0096.Bo0097.Co0098.Th0101
XLinking device O_.plate_3x3.plate_3x3_graph.c_0_2 with id 1 to thread O_.Set1.Bx0096.Bo0097.Co0098.Th0101
...
XLinking device O_.plate_3x3.plate_3x3_graph.c_2_2 with id 1 to thread O_.Set1.Bx0096.Bo0097.Co0136.Th0139
POETS> 09:32:39.98:  23(I) link /link = "plate_3x3"
~~~

Each device defined in the task graph is one-to-one mapped to a thread in the
POETS engine. Note that threads are identified in a hierarchical manner for
debugging purposes; one can interpret `O_.Set1.Bx0096.Bo0097.Co0098.Th0101` as
"The thread with UUID '0101' on the core with UUID '0098' on the FPGA board
with ID '0097' in the POETS box with ID '0096' as described by the 'Set1'
topology". Different topologies may use different naming conventions, but this
output will always be hierarchical. For diagnostic information, this mapping,
and its inverse, can be dumped by commanding `link /dump = "file"`.

### Building binaries for devices and supervisors (compilation)

The task definition is comprised of the task graph (how devices are connected
to each other, and how they communicate), and the device logic (the C fragments
that define what each device does). Given the hardware mapping from the linking
step, the Orchestrator can now produce binary files to execute on the cores of
the POETS engine, and binary files to act as supervisor devices. To build these
binaries in an idempotent manner, command:

~~~ {.bash}
task /build = "plate_3x3"
~~~

This creates a directory structure at `task /path`. The code fragments defined
in the task XML are assembled here, and are compiled using the RISCV compiler
in the POETS Engine. Compilation may produce warnings or errors, which will be
printed to stdout while the command is being executed; these should not be
ignored in normal operation. Assuming no warnings or errors are printed, the
Orchestrator prints:

~~~ {.bash}
POETS> task /build = "plate_3x3"
POETS> 12:03:31.70:  23(I) task /build = "plate_3x3"
POETS> 12:03:31.70: 801(D) P_builder::Add(name=plate_3x3,file=/path_to orchestrator_repository/application_staging/xml/plate_3x3.xml)
~~~

### Loading binaries into devices for execution, and running the application

With a set of binaries to be loaded onto each core of the POETS engine, the
application can be run. Firstly, stage each binary onto its appropriate core by
commanding:

~~~ {.bash}
task /deploy = "plate_3x3"
~~~

which causes the Orchestrator to print:

~~~ {.bash}
POETS> task /deploy = "plate_3x3"
~~~

Once executed, this command provisions the cores with the binaries. To execute
the binaries on the cores, and to start the supervisor, command:

~~~ {.bash}
task /init = "plate_3x3"
~~~

Control is returned to the user once this initialisation command is sent,
though there is no acknowledgement when all of the cores have
initialised. Assuming that the cores now wait behind a barrier for the operator
to start the job. Commanding:

~~~ {.bash}
task /run = "plate_3x3"
~~~

will start the application once the cores have been initialised; the
application will not start before the cores have been initialised. While they
are running, jobs can be stopped by commanding:

~~~ {.bash}
task /stop = "plate_3x3"
~~~

## Interactive Usage Summary

This section has demonstrated how to execute the Orchestrator, and an example
session for running an application on the POETS engine. The example session
demonstrates rudimentary Orchestrator operation, and is sufficient to execute
most tasks of interest.

# Usage (Batch)

You can pass a UTF-8-encoded script file to the orchestrator for batch
execution. For instance, the interactive usage example could have been run by
commanding (without stop!):

~~~ {.bash}
./orchestrate.sh -f /absolute/path/to/batch/script
~~~

Where the file `/absolute/path/to/batch/script` contains:

~~~ {.bash}
system /show
task /path = "/path_to_orchestrator_repository/application_staging/xml"
task /load = "plate_3x3.xml"
task /show
topology /set1
topology /dump = "./my_topology_dump"
link /link = "plate_3x3"
task /build = "plate_3x3"
task /deploy = "plate_3x3"
task /init = "plate_3x3"
task /run = "plate_3x3"
~~~

Note that you will need to exit the Orchestrator once your job has finished, by
commanding `exit` (this cannot be scripted, and would likely result in
premature termination of your job).

For reference, here's a more concise script that Mark uses to run his jobs,
which does less printing and dumping:

~~~ {.bash}
task /path = "/home/mv1g18/repos/orchestrator/application_staging/xml"
task /load = "plate_3x3.xml"
link /link = "plate_3x3"
task /build = "plate_3x3"
task /deploy = "plate_3x3"
task /init = "plate_3x3"
task /run = "plate_3x3"
~~~

# Further Reading

 - The launcher documentation, which explains the different switches for
   `orchestrate.sh`, and how it works and what it does.

 - The implementation documentation (big word document). Seriously, do read
   this.
