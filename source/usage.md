% Orchestrator Usage

# Overview

This document acts as a walkthrough for getting the Orchestrator running on
POETS hardware, running on (mostly) POSIX-compliant operating
systems. Prerequisite reading:

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
   may also wish to build in parallel, using the `-j N` flag ("N" build slaves
   will be used). A `debug` build is also supported.

The build process creates a series of disparate executables in the `bin`
directory in the Orchestrator repository. If this process fails, or raises
warnings, please alert an Orchestrator developer, who will (hopefully) either
fix these instructions, or fix the mistake in the build process. Once you have
successfully completed the build, you are ready to use the Orchestrator on
POETS hardware.

# Interactive Usage

## Execution

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

at which commands can be executed. Once you are finished with your Orchestrator
session, command:

~~~ {.bash}
exit
~~~

then hit any key to end the Orchestrator process. Note that this will
effectively disown any jobs running on the Engine, so you will be unable to
reconnect to any jobs started in this way.

When starting the Orchestrator, you may also encounter a pair of messages
similar to:

~~~ {.bash}
POETS> 11:50:38.02:  20(I) The microlog for the command 'load /engine = "/local/orchestrator-common/hdf.uif"' will be written to '../Output/Microlog/Microlog_2020-10-02T11-50-38p0.plog'.
POETS> 11:50:38.02: 140(I) Topology loaded from file ||/local/orchestrator-common/hdf.uif||.
~~~

in which case, the developer that has set up this machine has installed a
default topology file, which you can later override if desired.

If your session terminates with:

~~~ {.bash}
Failed to acquire HostLink lock: Resource temporarily unavailable
~~~

then the Mothership process was unable to connect to the API that allows it to
another Mothership process[^hl] is already running on this box; only one
Mothership process can run on a box in the Engine at a time. Until that process
ends, you will not be able to use the Orchestrator. This error may also be
raised when the disk runs out of space, which you can check by commanding `df
-h`.

[^hl]: or another HostLink process

While your session is running, if you include the Logserver component, a log
file will be written in the `bin` directory containing details of the
Orchestrator session.

## Help

Command `./orchestrate.sh --help`.

## Commands, Logging, and I/O

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
POETS> 13:11:17.37:  20(I) The microlog for the command 'test /echo = "Hello world"' will be written to '../Output/Microlog/Microlog_2020-10-02T13-11-17p0.plog'.
POETS> 13:11:17.37:   1(I) Hello world
~~~

This output from the Orchestrator is created by the LogServer, and is written
both to your prompt (on `stdout`) and to a log file at `Output/POETS.log`. Each
line corresponds to a different logging entry. Using the first line of the
above as an example:

 - `13:11:17.37` is a timestamp (obviously)

 - `23(I)` is the ID of the message, corresponding to entries in
   `Config/OrchestratorMessages.ocfg` (not user-facing).

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
02/10/2020 13:09:20.42 file ../Output/Microlog/Microlog_2020-10-02T13-09-20p0.plog
command [test /echo = "Hello world"]
from console
==================================================================================

Hello world
~~~

To demonstrate how multiple clauses and parameters typically interact, command
(forgive my syntax highlighting, I'm only human):

~~~ {.bash}
test /echo = "Hello","world" /echo = "Rise to vote sir" /echo = "test /echo = 'what,','why,','how?'"
~~~

which displays:

~~~ {.bash}
POETS> 13:46:48.82:  23(I) test /echo = "Hello","world" /echo = "Rise to vote sir" /echo = "test /echo = 'what,','why,','how?'"
POETS> 13:46:48.82:  20(I) The microlog for the command 'test /echo = "Hello","world" /echo = "Rise to vote sir" /echo = "test /echo = 'what,','why,','how?'"' will be written to '../Output/Microlog/Microlog_2020-10-02T13-46-48p0.plog'.
POETS> 13:46:48.82:   1(I) Hello world
POETS> 13:46:48.82:   1(I) Rise to vote sir
POETS> 13:46:48.82:   1(I) test /echo = 'what,','why,','how?'
~~~

and prints to the microlog:

~~~ {.bash}
======================================================================================
02/10/2020 13:46:48.82 file ../Output/Microlog/Microlog_2020-10-02T13-46-48p0.plog
command [test /echo = "Hello","world" /echo = "Rise to vote sir" /echo = "test /echo = 'what,','why,','how?'"]
from console
======================================================================================

Hello world
Rise to vote sir
test /echo = 'what,','why,','how?'
~~~

Note that each clause "invokes" the command once (there are three "`1`"
messages), with each parameter passed to it.

## An Exemplary Orchestrator Session

This section presents an examplar Orchestrator session, where we will simulate
the flow of heat across a plate. This requires you to:

 - Have built the Orchestrator successfully on a POETS machine.

 - Obtain an XML description of the heated plate example (from
   https://github.com/poetsii/Orchestrator_examples), in `plate_heat`. For this
   demonstration, we will be using the premade 3x3 example. Place the XML file
   in the root directory in the Orchestrator repository on the POETS machine.

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

### Verifying all Orchestrator Components are Loaded

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
exist on the same MPI communicator.

### Loading an Application, and Type-Linking (XML)

To load an application file (XML), command (at the `POETS>` prompt):

~~~ {.bash}
load /app = +"plate_3x3.xml"
~~~

The `+` operator informs the Orchestrator to look in the configured directory
(the root directory of the Orchestrator in the default configuration) for the
application file. The Orchestrator should respond with something like:

~~~ {.bash}
POETS> 14:06:47.57: 235(I) Application file ../plate_3x3.xml loading...
POETS> 14:06:47.57:  65(I) Application file ../plate_3x3.xml loaded in 7565 ms.
~~~

Application files consist of (zero or more) application graph types
(`GraphType` element in the XML), and (zero or more) application graph
instances (`GraphInstance` element in the XML). When the file is loaded, graph
types and graph instances are not linked.

Once your application file is loaded, type-link your graph instance to your
graph type by commanding:

~~~ {.bash}
tlink /app = "plate_heat::plate3x3"
~~~

where:

 - The text before the "`::`" in the parameter string denotes the application
   name (defined by the `appname` attribute in the `Graphs` element)

 - The text after the "`::`" element in the parameter string denotes the graph
   instance name (defined by the `id` attribute in the `GraphInstance`
   element).

Any typelinking errors are written to the microlog generated by the command.

#### Aside: Application graph instances as parameters

In the above example, we commanded

~~~ {.bash}
tlink /app = "plate_heat::plate3x3"
~~~

which uniquely type-links the `plate3x3` graph instance loaded from the
`plate_heat` application. Alternatively, we could have commanded:

~~~ {.bash}
tlink /app = "plate_heat"
~~~

which links all graph instances loaded from the `plate_heat` application in
sequence. More generally, we could have commanded:

~~~ {.bash}
tlink /app = *
~~~

which links all graph instances loaded from all application files in
sequence. This syntax is accepted for all commands where an application graph
instance is accepted as a parameter. We adopt this last notation going forward
in this guide (for brevity's sake).

### Mapping Application Graph Instances to Hardware (Placement))

With a typelinked application graph instance (from XML), and a hardware graph
(loaded automatically, in this case), the Orchestrator can map the former onto
the latter. Command:

~~~ {.bash}
place /bucket = *
~~~

The Orchestrator prints:

~~~ {.bash}
POETS> 14:45:14.77: 309(I) Attempting to place graph instance 'plate_3x3' using the 'buck' method...
POETS> 14:45:14.77: 302(I) Graph instance 'plate_3x3' placed successfully.
~~~

This command invokes the bucket-filling algorithm in the placement system. Each
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

### Building binaries for devices and supervisors (compilation)

The application definition is comprised of the application graph instance (how
devices are connected to each other, and how they communicate), and the device
logic (the C fragments that define what each device does). Given the hardware
mapping from the placement step, the Orchestrator can now produce binary files
to execute on the cores of the POETS engine, and binary files to act as
supervisor devices. To build these binaries in an idempotent manner, command:

~~~ {.bash}
build /app = *
~~~

This creates a directory structure in the `build` path defined in the
Orchestrator configuration. The code fragments defined in the task XML are
assembled here, and are compiled using the RISCV compiler in the POETS
Engine. Compilation may produce warnings or errors, which... <!>

What does the Orchestrator print? <!>

### Loading binaries into devices for execution, and running the application

With a set of binaries to be loaded onto each core of the POETS engine, the
application can be run. Firstly, stage each binary onto its appropriate core by
commanding:

~~~ {.bash}
build /deploy = *
~~~

Once executed, this command provisions the cores with the binaries. To execute
the binaries on the cores, and to start the supervisor, command:

~~~ {.bash}
build /init = *
~~~

To start the application immediately when all cores report they are ready,
commanding:

~~~ {.bash}
build /run = "plate_3x3"
~~~

will start the application once the cores have been initialised; the
application will not start before all cores have been initialised. While they
are running, jobs can be stopped by commanding:

~~~ {.bash}
build /stop = "plate_3x3"
~~~

## Interactive Usage Summary

This section has demonstrated how to execute the Orchestrator, and an example
session for running an application on the POETS engine. The example session
demonstrates rudimentary Orchestrator operation, and is sufficient to execute
most tasks of interest.

# Batch Usage

You can pass a UTF-8-encoded script file to the orchestrator for batch
execution. For instance, the essential steps of the prior interactive usage
example could have been run by commanding (in the shell):

~~~ {.bash}
./orchestrate.sh -b /absolute/path/to/batch/script
~~~

Where the file `/absolute/path/to/batch/script` contains:

~~~ {.bash}
load /app = +"plate_3x3.xml"
tlink /app = *
place /bucket = *
build /app = *
build /deploy = *
build /init = *
build /run = *
~~~

Note that you will need to exit the Orchestrator once your job has finished, by
commanding `exit` (this cannot be scripted, as it would result in premature
termination of your job).

# Further Reading

 - The launcher documentation, which explains the different switches for
   `orchestrate.sh`, and how it works and what it does.

 - Appendix A and the Placement documentation for more commands.

 - The implementation documentation (big word document). Seriously, do read
   this.

# Appendix A: Command List

What follows is a list of the most useful operator commands supported by the
present working version of the Orchestrator. Other commands exist, though are
either internally used by other systems (`*`, `return`), or are for testing
(basically everything in `system`). For the comprehensive list of commands
(present and future), consult the implementation document (big Word document).

## Build (`build`)

 - `build /app`: Given a placed application graph instance (or multiple),
   produces instruction and data binaries to be loaded onto the POETS Engine,
   and produces a binary representation of the application supervisor.

 - `build /deploy`: Given a built application graph instance (or multiple),
   deploys its binaries to Motherships. This command informs the Mothership of
   the existence of an application.

 - `build /initialise`: Given a placed application graph instance (or
   multiple), informs all Motherships that host the application that its
   binaries are to be pushed to each core in the POETS Engine, and the
   Supervisor device for the application is to be started, once deployment
   (from `build /deploy`) is complete.

 - `build /run`: Given a placed application graph instance (or multiple),
   informs all Motherships that host the application that it is to be started
   once it is fully initialised (from `build /initialise`). An application is
   fully initialised when all cores report they are ready to begin, and once
   the supervisor device has started.

 - `build /stop`: Given a placed application graph instance (or multiple),
   informs all Motherships that host the application that it is to be stopped,
   once started (from `build /run`). If the application is already running, it
   is stopped immediately. Stopping an application also stops any supervisor
   devices for that application.

 - `build /recl`: Given a placed application graph instance (or multiple),
   informs all Motherships that host the application to forget about it
   completely, unless it is running (it will need to be stopped first).

## Call (`call`)

Call commands interact with the batch subsystem.

 - `call /echo`: If the first parameter is `on`, commands executed from the
   batch subsystem are echoed to the operator. If `off`, they are not.

 - `call /file`: Given an absolute path to a batch file, queues each command in
   that batch file in turn. If the parameter is prefixed with the "`+`"
   operator, the path is used relative to the configured batch file loading
   directory.

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
   "`2_box_prototype`" can be passed as parameters to load baked-in default
   configurations for testing purposes.

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

 - `path /place`: Sets default path to store placement information to.

 - `path /reset`: Resets pathing information from configuration.

 - `path /stage`: Sets default path to store compiled binaries to.

 - `path /ulog`: Sets default path to store micrologs to.

 - `path /mshp`: Sets default path to store Mothership deployment files to.

## Place (`place`)

Place commands operate on the placement subsystem of the Orchestrator. See the
placement documentation for a comprehensive list of commands.

## Return (`return`)

The return command skips the rest of the commands from the calling file. Is a
no-operation unless called form a batch file.

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

## System (`system`)

Lower-level system commands.

 - `system /time`: Logs the date and time.

 - `system /show`: Displays a terse list of running MPI processes.

## Test (`test`)

For information.

 - `test /echo`: Logs and micrologs a message passed as one or more parameters.

## TLink (`tlink`)

 - `tlink /app`: Given a loaded application graph instance (or multiple),
   type-links them. Type-linking a graph instance (loaded from XML) defines the
   types of devices, edges, pins, and the graph instance itself from a graph
   type (also loaded from XML).

## Unload (`unload`)

 - `unload /app`: Given a loaded application graph instance, or a loaded
   application, (or `*`, denoting all applications), removes information about
   that item/those items from the Orchestrator. Clears placement information
   and composer information.

 - `unload /engine`: Clears the hardware model and all placement information.
