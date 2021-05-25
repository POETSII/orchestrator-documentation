% Orchestrator Documentation Volume IV: User Guide

# Overview

This document assumes that you have a working knowledge of the POETS project,
and introduces the Orchestrator from the perspective of a user. It defines what
the Orchestrator is, and some of its components. This document then provides a
walkthrough for setting up the Orchestrator running on POETS hardware, and a
walkthrough demonstrating basic usage. For a more developer-facing view of the
Orchestrator, or for information on more advanced Orchestrator usage, consult
Volume II (implementation documentation).

This document does not:

 - Describe how to get an account on a POETS machine (speak to a project member
   if you wish to set this up).

 - Describe compilation outside of POETS machines (a Makefile is provided).

 - Describe how compilation and execution can be adapted to run on non-POETS
   machines.

# Orchestrator Introduction

Figure 1 shows the POETS stack; POETS consists of major three layers, one of
which is the Orchestrator. The other layers are:

 - Application Layer: The application is domain-specific problem (with
   context), which is to be solved on the POETS Engine. The role of the
   Application Layer is provide an interface for the user to translate their
   problem into an application, which is a contextless graph of connected
   devices. These devices are units of compute that can send signals to other
   devices in the graph to solve a problem.

 - Engine Layer: The highly-distributed hardware on which the application is
   solved. The POETS Engine (or just "Engine") has no idea about context. The
   Engine Layer consists of a POETS box, which contains some interconnected
   FPGA boards, and an x86 machine used to control them.

![Layers in the POETS stack](images/stack.png "The POETS Stack"){width=40%}

With only these two layers, POETS still requires a way to map the application
(Application Layer) onto the hardware (Engine Layer). POETS also lacks any way
for the user to start, stop, observe, get results from, or otherwise generally
interact with the Engine during operation.

## Features of the Orchestrator

The Orchestrator is a middleware that interfaces between the Application Layer
and the Engine Layer, and between the user and the Engine Layer. The core
responsibilities of the Orchestrator are:

 - To load and manage applications passed in from the application layer.

 - To identify the Engine it is operating on.

 - To efficiently map the application onto the Engine.

 - To deploy and "undeploy" applications onto the Engine.

 - To allow the user to start and stop applications running on the Engine.

 - To allow the user to view the current state of the Engine.

 - To allow the user to retrieve results computed by the Engine.

## Components of the Orchestrator

The Orchestrator consists of disparate components, which are logically arranged
to achieve the objectives of the Orchestrator as a whole, while maintaining a
sensible degree of modularity. Components essential to the running of
applications include:

 - "Root": While the Orchestrator is comprised of a series of modular
   components, the "Root" uses these components to achieve the features of the
   Orchestrator. The Root component:

   - Interfaces with the operator via a command prompt.

   - Manages an internal model of the Engine (the "hardware graph" of how
     cores, threads, mailboxes, FPGA boards, and supervisors are
     connected).

   - Can, on command, map an application onto the internal model of the Engine
     in an efficient manner (placement).

   - Can, on command, build binaries to be executed on the cores of the Engine,
     and to stage them for execution on those cores.

 - "LogServer": The LogServer component records logging messages sent to it
   from other components, either for post-mortem purposes, or for elementary
   real-time system observation.

 - "Mothership": The Orchestrator plays host to a number of mothership
   processes, which must operate on the various boxes of the Engine. The
   Mothership process is primarily responsible for managing communications
   between the Orchestrator processes (MPI), and the hardware (packets), and
   for loading and unloading of binaries passed to it from the Root process.

Other components include:

 - "RTCL": The "Real-Time Clock" component manages an internal clock. A unit of
   functionality of this clock is to support a rudimentary "delay" command,
   which can be used as part of a command batch. This allows the user to stage
   a series of packets to be added to the Engine at a given time, to support
   controlled "bursts" of activity.

 - "Injector": The Root component allows the Orchestrator to be controlled by a
   batch of commands. The Injector component is a developer tool that supports
   this functionality, but where the batch of commands is run in the context of
   the Orchestrator. This allows developers to "script" the behaviour of the
   Orchestrator in response to changes in the state of the Orchestrator, as
   opposed to a naive batch.

 - "NameServer": In the Orchestrator, devices in the Engine are referred to by
   flat numeric addresses. The NameServer stores a mapping between these
   addresses, and colloquial, hierarchy-based device identifiers. User-facing
   components in the Orchestrator can query this component to determine a
   correct address for a packet they may wish to send. The NameServer also
   enables lookup in either direction.

 - "Monitor": The Monitor component displays information about the current
   activity of the Engine, and other useful details from the Orchestrator. Not
   yet implemented.

 - "User Input and User Output": The User Input component handles inputs from
   the application frontend, by translating them into instructions (messages)
   for other components to execute. The User Output component handles messages
   from components to be displayed in the application frontend. Not yet
   implemented

All of these components exist as separate processes reachable in the same MPI
(Message-Passing Interface) communicator, so that each component is able to
communicate with each other component.

## Key Points

- The Orchestrator is a middleware that interfaces between the Application
  Layer and the Engine Layer, and between the user and the Engine Layer.

- The Orchestrator allows tasks (contextless descriptions of applications) to
  be mapped onto the Engine, to start and stop tasks on the engine, to view the
  state of the Engine, and to retrieve results computed by the Engine.

- The Orchestrator is a modular system; it is divided into a series of
  components each responsible for a unit of functionality.

# Setup

As a user, you will need to build the Orchestrator from its sources in order to
use it. This Section describes the process for building the Orchestrator on
traditional POETS hardware, and potential "gotchas" users have encountered in
building on other platforms.

## Setup on a POETS Machine

Given that you have an account on a POETS machine, to set up the Orchestrator,
perform the following actions on the POETS machine from your user account
(assuming rudimentary `sh` knowledge):

 - **Obtain the sources:** Clone the Orchestrator Git repository, at
   https://github.com/poetsii/Orchestrator, and check out the `development`
   branch.

 - **Setup environment:** In the file `Build/gcc/Makefile.dependencies` in the
   Orchestrator repository, confirm that the directory pointed to by the
   `ORCHESTRATOR_DEPENDENCIES_DIR` variable exists. If it does not, complain to
   an Orchestrator developer, and:

   - **Install dependencies:**
     (https://github.com/poetsii/orchestrator-dependencies/releases) navigate
     to the Orchestrator Dependencies repository, download the latest tarball
     from the releases list, extract it (`tar -zxf <TARBALL>`), and modify the
     `ORCHESTRATOR_DEPENDENCIES_DIR` variable in
     `Build/gcc/Makefile.dependencies` to point to its root directory. If you
     want to help your fellow users and you're on a POETS box, you can extract
     it to `/local/orchestrator-dependencies/`.

 - **Build the Orchestrator:** From the `Build/gcc` directory in the
   Orchestrator repository, command `make all` to build the Orchestrator. You
   may also wish to build in parallel, using the `-j N` flag ("N" parallel
   workers will be used). A `debug` build is also supported, accessible by
   building instead with `make debug`.

The build process creates executables in the `bin` directory in the
Orchestrator repository, as well as a startup script in the root directory of
the Orchestrator repository. Once you have successfully completed the build,
you are ready to use the Orchestrator on POETS hardware.

## Gotchas for Compiling on Other Platforms

 - The Orchestrator is designed to be compatible with 32-bit and 64-bit
   architectures. Large applications will require a 64-bit architecture to
   operate, though 32-bit architectures can be used for smaller applications
   and development.

 - The Orchestrator, being a multi-process system, requires multiple individual
   executables to be created (see the "Components of the Orchestrator"
   Section). These processes each have a `main` function defined in
   `Source/PROCESS_NAME`.

 - All processes need to be linked against MPI to facilitate communication (the
   example in the previous Section builds using MPICH). Under MSMPIv6, the
   preprocessor macros with identifiers `MSMPI_NO_DEPRECATE_20` and
   `MSMPI_NO_SAL` must be defined. Using MSVC also requires `_TIMESPEC_DEFINED`
   and `_CRT_SECURE_NO_WARNINGS` to be defined in the same way.

 - The Orchestrator can be compiled either under either C++98 or C++11
   standards. Post-modern standards are not supported.

 - The `dl` library is required by most Linux systems for Orchestrator
   compilation.

 - The `pthreads` library is also required for Orchestrator compilation,
   regardless of platform.

 - Note that Borland C++ and MSVC use different formats for library files (this
   applies particularly to `pthreads` and MPI). Both libraries (.lib) are
   shipped in the Common Object File Format (COFF). For use with Borland C++
   and Embarcadero C++ (at least), these need to be translated to Object Module
   Format (OMF). The utility `COFF2OMF` is freely available (and is included
   with Borland C++).

# Usage

## Interactive Usage

### Execution

Once built, change directory into the root directory of the Orchestrator
repository. The script `orchestrate.sh` is created by the build process
invoked in the previous section. To run the Orchestrator, command:

~~~ {.bash}
./orchestrate.sh
~~~

Once executed, the Orchestrator waits at the Orchestrator operator prompt:

~~~ {.bash}
POETS>
~~~

at which commands can be executed. If `rlwrap` is installed on the machine,
command history will be remembered, and can be recalled by pressing
`<UP>`. Once you are finished with your Orchestrator session, command:

~~~ {.bash}
exit
~~~

which ends the Orchestrator process. Note that this will effectively disown any
jobs running on the Engine, so you will be unable to reconnect to any jobs
started in this way.

When starting the Orchestrator, you may also encounter a pair of messages
similar to:

~~~ {.bash}
POETS> 11:50:38.02:  20(I) The microlog for the command 'load /engine = "../Config/POETSHardwareOneBox.ocfg"' will be written to '../Output/Microlog/Microlog_2020_10_02T11_50_38p0.plog'.
POETS> 11:50:38.02: 140(I) Topology loaded from file ||../Config/POETSHardwareOneBox.ocfg||.
~~~

in which case, the developer that has set up this machine has installed a
default topology file, which you can later override if desired.

If your session terminates with:

~~~ {.bash}
Failed to acquire HostLink lock: Resource temporarily unavailable
~~~

then the Mothership process was unable to connect to the underlying POETS
Engine, as another Mothership process[^hl] is running on your box; only one
Mothership process can run on a box in the Engine at a time. Until that process
ends, you will not be able to use the Orchestrator. This error may also be
raised when the disk runs out of space, which you can check by commanding `df
-h` in the shell.

[^hl]: or another HostLink process

While your session is running, if you include the Logserver component, a log
file will be written in the `Output` directory containing details of the
Orchestrator session.

### Help

Command `./orchestrate.sh --help`.

### Commands, Logging, and I/O

Orchestrator operator commands take the form "`Command /Clause =
OperatorParameter`". Multiple parameters can be passed to a given clause
(`Command /Clause = Operator0Parameter0, Operator1Parameter1`), and multiple
clauses can be bassed to a given command (`Command /Clause0 = Parameter0
/Clause1 = Parameter1`).

As an example, command the following at the `POETS>` prompt:

~~~ {.bash}
test /echo = "Hello world"
~~~

The `test` command with the `echo` clause writes its parameters back to the
operator. The command causes the Orchestrator to print something like:

~~~ {.bash}
POETS> 13:11:17.37:  23(I) test /echo = "Hello world"
POETS> 13:11:17.37:  20(I) The microlog for the command 'test /echo = "Hello world"' will be written to '../Output/Microlog/Microlog_2020_10_02T13_11_17p0.plog'.
POETS> 13:11:17.37:   1(I) Hello world
~~~

This output from the Orchestrator is created by the LogServer, and is written
both to your prompt (on `stdout`) and to a log file at `Output/POETS.log`. Each
line corresponds to a different logging entry. Using the first line of the
above as an example:

 - `13:11:17.37` is a timestamp

 - `23(I)` is the ID of the message^[These messages correspond to entries in
   `Config/OrchestratorMessages.ocfg`, which is not intended to be
   user-facing.].

 - `test /echo = "Hello world"` is the text of the log message.

Each command issued to the Orchestrator prompt prints a "`23`" message,
effectively echoing the command back to you. Each command also has a microlog
associated with it - each command writes to a different file as shown by the
"`20`" message, though not all commands populate their microlog. Finally, the
"`1`" message is from the `test /echo` command (echoing your argument back to
you). The execution of "`test /echo`" also writes content to the microlog in
the file shown by the "`20`" message:

~~~ {.bash}
==================================================================================
02/10/2020 13:09:20.42 file ../Output/Microlog/Microlog_2020_10_02T13_09_20p0.plog
command [test /echo = "Hello world"]
from console
==================================================================================

Hello world
~~~

To demonstrate how multiple clauses and parameters typically interact, command:

~~~ {.bash}
test /echo = "Hello","world" /echo = "Rise to vote sir" /echo = "test /echo = 'what,','why,','how?'"
~~~

which displays:

~~~ {.bash}
POETS> 13:46:48.82:  23(I) test /echo = "Hello","world" /echo = "Rise to vote sir" /echo = "test /echo = 'what,','why,','how?'"
POETS> 13:46:48.82:  20(I) The microlog for the command 'test /echo = "Hello","world" /echo = "Rise to vote sir" /echo = "test /echo = 'what,','why,','how?'"' will be written to '../Output/Microlog/Microlog_2020_10_02T13_46_48p0.plog'.
POETS> 13:46:48.82:   1(I) Hello world
POETS> 13:46:48.82:   1(I) Rise to vote sir
POETS> 13:46:48.82:   1(I) test /echo = 'what,','why,','how?'
~~~

and which prints to the microlog:

~~~ {.bash}
======================================================================================
02/10/2020 13:46:48.82 file ../Output/Microlog/Microlog_2020_10_02T13_46_48p0.plog
command [test /echo = "Hello","world" /echo = "Rise to vote sir" /echo = "test /echo = 'what,','why,','how?'"]
from console
======================================================================================

Hello world
Rise to vote sir
test /echo = 'what,','why,','how?'
~~~

Note that each clause "invokes" the command once (there are three "`1`"
messages), with each parameter passed to it.

### An Exemplary Orchestrator Session

This section presents an examplar Orchestrator session, where we will pass a
packet around a devices in the POETS Engine, and track its progress using a
supervisor device. This requires you to:

 - Have built the Orchestrator successfully on a POETS machine.

 - Obtain an XML description of the ring test example (from Appendix A of
   Volume II). Place the XML file, entitled "`ring_test.xml`", in the root
   directory in the Orchestrator repository on the POETS machine.

This session will, in order (using a single POETS box):

 1. Verify that all components of the Orchestrator have been loaded in the
    current session.

 2. Load an application (XML), and generate an application graph instance.

 3. Map the devices in the application graph instance to the hardware graph
    using the Orchestrator (placement).

 4. Generate binary files, from the sources defined in the XML, which will run
    on the RISCV cores of the POETS engine and as a Supervisor device.

 5. How to load these binary files onto their respective cores, and to start an
    application once the binary files have been loaded.

#### Verifying all Orchestrator Components are Loaded

Once built, you may wish to verify that the components of the Orchestrator have
been started correctly, and can be communicated with. At the `POETS>` prompt,
command:

~~~ {.bash}
system /show
~~~

which will print something like:

~~~ {.bash}
Orchestrator processes
Rank 00,            Root:OrchBase:CommonBase, created 10:28:19 Apr 16 2020
Rank 01,                LogServer:CommonBase, created 10:28:19 Apr 16 2020
Rank 02,                     RTCL:CommonBase, created 10:28:19 Apr 16 2020
Rank 03,               Mothership:CommonBase, created 10:28:19 Apr 16 2020
~~~

In this case, the Root, RTCL, LogServer, and Mothership components of the
Orchestrator have been started. Note that all components of the Orchestrator
exist on the same MPI communicator. More information about these processes is
written to the command's microlog.

#### Loading an Application, and Type-Linking (XML)

To load an application file (XML), command (at the `POETS>` prompt):

~~~ {.bash}
load /app = +"ring_test.xml"
~~~

The `+` operator informs the Orchestrator to look in the configured directory
(the root directory of the Orchestrator in the default configuration) for the
application file. The Orchestrator should respond with something like:

~~~ {.bash}
POETS> 14:06:47.57: 235(I) Application file ../ring_test.xml loading...
POETS> 14:06:47.57:  65(I) Application file ../ring_test.xml loaded in 7565 ms.
~~~

Application files consist of (zero or more) application graph types
(`GraphType` element in the XML), and (zero or more) application graph
instances (`GraphInstance` element in the XML). When the file is loaded, graph
types and graph instances are not linked. Type-linking permits multiple graph
instances to be linked to a graph type, so definitions can be shared across
different configurations (e.g. size) of a "problem type".

Once your application file is loaded, type-link your graph instance to your
graph type by commanding:

~~~ {.bash}
tlink /app = "ring_test"::"ring_test_instance"
~~~

where:

 - The text before the "`::`" in the parameter string denotes the application
   name (defined by the `appname` attribute in the `Graphs` element)

 - The text after the "`::`" element in the parameter string denotes the graph
   instance name (defined by the `id` attribute in the `GraphInstance`
   element).

Any typelinking errors are written to the microlog generated by the command.

##### Aside: Tildes in Paths on Unix-likes

Note that the Orchestrator does not respect the `~` character when defining
absolute paths to files and directories.

##### Aside: Application graph instances as parameters

In the above example, we commanded

~~~ {.bash}
tlink /app = "ring_test"::"ring_test_instance"
~~~

which uniquely type-links the `ring_test_instance` graph instance loaded from
the `ring_test` application. Alternatively, we could have commanded:

~~~ {.bash}
tlink /app = "ring_test"
~~~

which links all graph instances loaded from the `ring_test` application in
sequence. This is useful when the application definition contains multiple
instances, and the user wishes to type link all of them. More generally, we
could have commanded:

~~~ {.bash}
tlink /app = *
~~~

which links all graph instances loaded from all application files in
sequence. This syntax is accepted for all commands where an application graph
instance is accepted as a parameter. For the sake of brevity, we adopt this
last notation going forward.

Also note that, in the current iteration of the Orchestrator, multiple graph
instances cannot be deployed (or executed) at the same time. This will change
in a future version of the Orchestrator.

#### Mapping Application Graph Instances to Hardware (Placement))

With a typelinked application graph instance (from XML), and a hardware graph
(loaded automatically by the Orchestrator, in this case), the Orchestrator can
map the former onto the latter. Command:

~~~ {.bash}
place /tfill = *
~~~

The Orchestrator prints:

~~~ {.bash}
POETS> 14:45:14.77: 309(I) Attempting to place graph instance 'test_ring_instance' using the 'tfil' method...
POETS> 14:45:14.77: 302(I) Graph instance 'test_ring_instance' placed successfully.
~~~

This command invokes the thread-filling algorithm in the placement system. Each
device defined in the application graph instance is one-to-many mapped to a
thread in the POETS engine. For information about the placement performed,
command:

~~~ {.bash}
place /dump = *
~~~

Which writes a series of files to `Output/Placement` (under default
configuration). For more information on how to interpret these dumps, and for a
comprehensive explanation of placement algorithms, consult the placement
documentation.

#### Building binaries for devices and supervisors (compilation)

The application definition is comprised of the application graph instance (how
devices are connected to each other, and how they communicate), and the device
logic (the C fragments that define what each device does). See Volume II of the
documentation for more information on defining POETS applications for the
Orchestrator. Given the hardware mapping from the placement step, the
Orchestrator can now produce binary files to execute on the cores of the POETS
engine, and binary files to act as supervisor devices. To build these binaries
in an idempotent manner, command:

~~~ {.bash}
compose /app = *
~~~

This creates a directory structure in the `build` path defined in the
Orchestrator configuration. The code fragments defined in the task XML are
generated here, and are compiled using the RISCV compiler in the POETS
Engine. Compilation may produce warnings or errors, which are written to the
microlog of the command.

#### Loading binaries into devices for execution, and running the application

With a set of binaries to be loaded onto each core of the POETS engine, the
application can be run. Firstly, stage each binary onto its appropriate core by
commanding:

~~~ {.bash}
deploy /app = *
~~~

Once executed, this command provisions the cores with the binaries. To execute
the binaries on the cores, and to start the supervisor, command:

~~~ {.bash}
initialise /app = *
~~~

To start the application immediately when all cores report they are ready,
commanding:

~~~ {.bash}
run /app = *
~~~

will start the application once the cores have been initialised; the
application will not start before all cores have been initialised. While they
are running, jobs can be stopped by commanding:

~~~ {.bash}
stop /app = *
~~~

You can confirm that the application has executed successfully by checking the
"`ring_test_output`" file in the `bin` directory relative to the root directory
of the Orchestrator. If that file contains a "1", the application has executed
successfully. See the example in Volume II for more information on how the ring
test application operates.

### Interactive Usage Summary

This section has demonstrated how to execute the Orchestrator, and an example
session for running an application on the POETS engine. The example session
demonstrates rudimentary Orchestrator operation, and is sufficient to execute
most tasks of interest.

## Batch Usage

You can pass a UTF-8-encoded script file to the orchestrator for batch
execution. For instance, the essential steps of the prior interactive usage
example could have been run by commanding (in the shell):

~~~ {.bash}
./orchestrate.sh -b /absolute/path/to/batch/script
~~~

Where the file `/absolute/path/to/batch/script` contains:

~~~ {.bash}
load /app = +"ring_test.xml"
tlink /app = *
place /tfill = *
compose /app = *
deploy /app = *
initialise /app = *
run /app = *
~~~

Note that you will need to exit the Orchestrator once your job has finished, by
commanding `exit` (this cannot be scripted, as it would result in premature
termination of your job). It is possible to nest batch files using the `call
/file` command, and it is possible to prematurely end execution of a batch file
by calling `return` (from within a batch file).

# Appendix A: Useful Command List

What follows is a list of the most useful operator commands supported by the
present working version of the Orchestrator. Other commands exist, though are
either internally used by other systems (`*`, `return`), or are for testing
(basically everything in `system`). For a more detailed, developer-facing
description of the more complicated commands, consult Volume II (implementation
documentation).

## Call (`call`)

Call commands interact with the batch subsystem.

 - `call /echo`: If the first parameter is `on`, commands executed from the
   batch subsystem are echoed to the operator. If `off`, they are not.

 - `call /file`: Given an absolute path to a batch file, queues each command in
   that batch file in turn. If the parameter is prefixed with the "`+`"
   operator, the path is used relative to the configured batch file loading
   directory.

## Compose (`compose`)

Compose commands interact with the composer subsystem, which is responsible for
assembling translation units from parsed source fragments, and compiling those
translation units using a (external) compiler. Composer output is placed in the
configured staging directory (`Output/Composer` in the default configuration).

 - `compose /app`: Given a placed application graph instance (or multiple),
   produces instruction and data binaries to be loaded onto the POETS Engine,
   and produces a binary representation of the application supervisor. It
   performs the generation and build steps in sequence.

 - `compose /clean`: Given a placed application graph instance (or multiple),
   clear any compiled binaries composed for that application.

 - `compose /decompose`: Given a placed application graph instance (or
   multiple), clear any compiled binaries and generated source files composed
   for that application.

 - `compose /degenerate`: Given a placed application graph instance (or
   multiple), clear any generated source files composed for that application.

 - `compose /generate`: Given a placed application graph instance (or
   multiple), generates translation units (source code) from the loaded XML, to
   be compiled into application binaries (both for normal devices and
   supervisor devices).

 - `compose /compile`: Given a generated application graph instance (or
   multiple), compiles instruction and data binaries to be loaded onto the POETS
   Engine, and produces a binary representation of the application supervisor.

 - `compose /bypass`: Bypasses most of the compose process provided that the
   compiled binaries for the application already exist, allowing the operator
   to reuse binaries from a previous run or to use binaries compiled elsewhere. 
   The loaded application must be identical in terms of definition and placement 
   for this to work - there are no checks beyond binary existance.

 - `compose /args`: Allows the operator to pass additional arguments to the
   compiler(s) used to build the application binaries.

 - `compose /dump`: Dumps diagnostic data regardign the Composer to the microlog.

## Deploy (`deploy`)

 - `deploy /app`: Given a built application graph instance (or multiple),
   deploys its binaries to Motherships. This command informs the Mothership of
   the existence of an application.

## Dump (`dump`)

Provides various developer-facing diagnostic information.

 - `dump /apps`: Dumps information about loaded applications to the file passed
   as parameter. If no parameter is passed, the dump is written to standard
   output instead.

 - `dump /engine`: Dumps information about the POETS Engine (hardware model) to
   the file passed as parameter. If no parameter is passed, the dump is written
   to standard output instead.

 - `dump /placer`: Dumps information about the placement subsystem pertaining
   to all placed tasks to the configured placement output directory.

## Exit (`exit`)

Exits the Orchestrator. Cannot be used (meaningfully) inside a batch file.

## Initialise (`initialise`)

 - `initialise /app`: Given a placed application graph instance (or multiple),
   informs all Motherships that host the application that its binaries are to
   be pushed to each core in the POETS Engine, and the Supervisor device for
   the application is to be started, once deployment (from `deploy /app`) is
   complete.

## Load (`load`)

Load commands inject information into the Orchestrator from files.

 - `load /app`: Given the path to an application file (XML) as a parameter,
   loads that application file into the Orchestrator. If the parameter is
   prefixed with the "`+`" operator, the path is used relative to the
   configured application loading directory.

 - `load /engine`: Given the path to a hardware description file as a
   parameter, loads that file into the Orchestrator as the model of the Engine,
   clobbering any existing model. If the parameter is prefixed with the "`+`"
   operator, the path is used relative to the configured hardware model loading
   directory. Alternatively, the special strings "`1_box_prototype`" or
   "`2_box_prototype`" can be passed as parameters, prefixed with the "`?`"
   operator, to load baked-in default configurations for testing purposes.

## Path (`path`)

Path commands override the default configured paths (defined in
`Config/Orchestrator.ocfg`). Each of these commands (except `clear`, `log`, and
`reset`) accepts a single path to a directory (with a trailing slash) as an
argument, and these paths are relative to the `bin` directory.

 - `path /apps`: Sets default path to load applications from.

 - `path /batch`: Sets default path to load batch files from.

 - `path /clear`: Clears all pathing information.

 - `path /engine`: Sets default path to load hardware description files from.

 - `path /log`: Given a path to a file, sets the default path to log to.

 - `path /mout`: Sets the root directory for supervisors to (optionally) store
   user files to.

 - `path /mshp`: Sets the path to store Mothership deployment files to.

 - `path /place`: Sets default path to store placement information to.

 - `path /reset`: Resets pathing information from configuration.

 - `path /stage`: Sets default path to store generated source files and
   compiled binaries to.

 - `path /ulog`: Sets default path to store micrologs to.

## Place (`place`)

Place commands operate on the placement subsystem of the Orchestrator, which is
responsible for mapping applications to the compute hardware. See the placement
documentation for a more detailed description of the commands that follow.

 - `placement /app`: Synonym for `placement /tfill`.

 - `placement /bucket`: Synonym for `placement /tfill`.

 - `placement /constraint`: Given a constraint type and a set of arguments,
   imposes a system-wide hard constraint onto future placed applications:
   Currently-supported constraints include:

   - `placement /constraint = "MaxDevicesPerThread", ARG`: Defines an upper
     limit on the number of devices that the placer will place on any thread in
     the engine. A default limit of 256 is imposed here.

   - `placement /constraint = "MaxThreadsPerCore", ARG`: Defines an upper limit
     on the number of threads that the placer will place devices on within any
     core in the hardware model. By default, the entire hardware model is used
     for placement.

 - `placement /dump`: Given a typelinked application graph (or multiple), dumps
   information about the placement of that application to the default output
   path (presently `Output/Placement`), including the mapping, when the
   application was placed, what algorithm was used to place it, its placement
   "score", the maximum local hardware loading, and a "cost" of communication
   between all device pairs, amongst other things.

 - `placement /gc`: Given a typelinked application graph (or multiple), places
   it using a gradient-less climbing algorithm (with a random initial
   condition). This is similar to `placement \sa`, but only accepts superior
   mappings.

 - `placement /rand`: Given a typelinked application graph (or multiple),
   places it by mapping devices to threads at random.

 - `placement /sa`: Given a typelinked application graph (or multiple), places
   it using simulated annealing (with a random initial condition). The number
   of iterations can be defined at compile time (and will later be more easily
   configurable).

 - `placement /spread`: Given a typelinked application graph (or multiple),
   places it as evenly as possible over all threads in the entire engine.

 - `placement /tfill`: Given a typelinked application graph (or multiple),
   places it onto the hardware by filling each thread in sequence.

 - `placement /unplace`: Given a typelinked application graph (or multiple),
   removes placement information for that application (effectively undoing a
   placement operation).

 - `placement /reset`: Completely clears all placement information and loaded
   constraints.

## Recall (`recall`)

 - `recall /app`: Given a placed application graph instance (or multiple),
   informs all Motherships that host the application to recall it (forget about
   it completely), unless it is running (it will need to be stopped first).

## Return (`return`)

The return command skips the rest of the commands from the calling file. Is a
no-operation unless called from a batch file.

## Run (`run`)

 - `run /app`: Given a placed application graph instance (or multiple), informs
   all Motherships that host the application that it is to be started once it
   is fully initialised (from `initialise /app`). An application is fully
   initialised when all cores report they are ready to begin, and once the
   supervisor device has started.

## Show (`show`)

Expose various pieces of information about the Orchestrator in microlog files.

 - `show /apps`: Writes information about loaded applications to microlog.

 - `show /batch`: Writes information about the batch subsystem to microlog.

 - `show /engine`: Writes information about the POETS Engine (hardware model)
   to microlog.

 - `show /parser`: Writes information about the XML parser to microlog.

 - `show /path`: Writes pathing information to microlog.

 - `show /system`: Writes (detailed) information about running MPI processes to
   microlog.

## Stop (`stop`)

 - `stop /app`: Given a placed application graph instance (or multiple),
   informs all Motherships that host the application that it is to be stopped,
   once started (from `run /app`). If the application is already running, it is
   stopped immediately. Stopping an application also stops any supervisor
   devices for that application.

## System (`system`)

Lower-level system commands.

 - `system /time`: Logs the date and time.

 - `system /show`: Displays a terse list of running MPI processes, and writes
   more detailed information to the microlog.

## Test (`test`)

For information.

 - `test /echo`: Logs and micrologs a message passed as one or more parameters.

## Typelink (`tlink`)

 - `tlink /app`: Given a loaded application graph instance (or multiple),
   type-links them. Type-linking a graph instance (loaded from XML) defines the
   types of devices, edges, pins, and the graph instance itself from a graph
   type (also loaded from XML).

## Unload (`unload`)

 - `unload /app`: Given a loaded application graph instance (or multiple),
   removes information about that item/those items from the
   Orchestrator. Clears placement information and composer information.

 - `unload /engine`: Clears the hardware model and all placement information.

## Untypelink (`untypelink`)

 - `untypelink /app`: Given an application graph instance (or multiple),
   removes all typelinks associated with them, if any are defined.
