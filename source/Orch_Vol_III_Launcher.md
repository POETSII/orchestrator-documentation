% Orchestrator Documentation Volume III Annex: The Launcher
\thispagestyle{fancy}

# Overview

The Orchestrator is a heterogeneous MPI program designed to run off multiple
individual computers. As such, starting the Orchestrator correctly as an
operator is non-trivial. The Launcher exists to make this process easier for an
operator. Specifically, the Launcher allows:

 - Paths for executables and libraries that are defined at compile-time to be
   easily passed to the Orchestrator processes that need it.

 - An arbitrary number of Motherships to be spawned either on different
   machines or on the local machine.

 - A batch script to be executed on the root process once all processes have
   been initialised and have responded to an initial communication check.

 - Developers to point Valgrind and Gdb at locally-running processes to
   diagnose problems.

All of these features are achieved through combinations of different
command-line switches. Command-line help can be obtained by starting the
Launcher with the `/h` switch (i.e. "`orchestrate /h`" or "`./orchestrate.sh
/h`").

## Launcher Components

The Launcher is comprised of two components, the **Setup Script**, and the
**Launcher Proper**:

 - **Setup Script**: A script that sets up the environment for use on POETS
   boxes (Cambridge hardware), and which propagates input arguments to the
   **Launcher Proper**. This script also performs some rudimentary conversion
   from any GNU-style parameters passed in, to the Windows-style used by the
   **Launcher Proper**. The script is generated at compile time, and is placed
   in the root directory of the Orchestrator repository with the name
   "`orchestrate.sh`". It's pretty self-explanatory.

 - **Launcher Proper**: A C++ executable that constructs a distributed,
   heterogeneous MPI command, and passes that command to `system` so that it
   can be executed. This executable also deploys compiled binaries to other
   computers. This executable is generated at compile time, and is placed in
   the `bin` directory of the Orchestrator repository (along with the other
   executables) with the name `orchestrate`. It's quite complicated, hence this
   documentation.

See the "Setup" section in the usage documentation for more information on how
to build these Launcher components.

## Switches (options, command-line arguments)

To see a list of supported flags, call either the **Launcher Proper** or the
**Setup Script** with the `/h` switch.

I expect most people will come to this document looking for this information,
but for DRY, I'm not going to write it out again here.

# Launcher Proper Program Flow

The **Launcher Proper** follows this rough program flow, once it enters
`Launcher::Launch` from `main`:

## Parse the arguments

The **Launcher Proper** initialises by parsing the arguments from the
command-line via `Launcher::ParseArgs`. To do this, it uses the `Cli` class
(`Generics/Cli.{cpp,h}`), documented in the `Generics` directory of the
Orchestrator. This is also where help is printed if requested. The Launcher
fails fast if the command-line arguments are malformed.

## Determine the set of hosts to spawn Motherships on

The Launcher follows this logic, breaking after each "If so" clause:

 - Has the caller explicitly said they don't want Mothership processes? If so,
   the Launcher won't start any.

 - Then, has the caller provided an override host for Mothership processes? If
   so, the Launcher will start exactly one Mothership process on that host.

 - Then, has the caller provided a hardware description file path? If so, read
   it to get the hosts to spawn Mothership processes on via
   `Launcher::GetHosts`, failing fast if the file doesn't exist or is
   malformed. See the hardware description file documentation for information
   on how these hosts are stored.

 - Then, is there a hardware description file at the default path (presently\
   `/local/orchestrator-common/hdf.uif`) If so, read it to get the hosts to
   spawn Mothership processes on using the mechanism outlined in the previous
   point.

 - If all else fails, just spawn one Mothership process on this box instead,
   and warn the user if this box is not a POETS box.

## Deploy binaries to remote hosts

Since the Launcher runs a distributed MPI command, the executables used by that
MPI command need to be present on the remote hosts. The
`Launcher::DeployBinaries` method uses the SSH helper library to drop the
binaries to a staging directory (presently `$HOME/.orchestrator/launcher`) for
execution, and stores the full path to that new directory[^sshwhygodwhy]. This
fails fast if one of the hosts can't be reached, or if the remote disk is full.

[^sshwhygodwhy]: You may ask "Why does the Launcher need to store these paths?"
    This is because the MPI launcher requires an absolute path to execute
    binaries (and for the `-wdir` switch) on remote machines, otherwise it will
    use the username from the local machine in the path which may not always be
    right (`$HOME` is a function of `$USER` on most machines).

## Build and run the Command

Once the binaries are deployed, the Launcher constructs an MPI command to start
the Orchestrator (using `Launcher::BuildCommand`). The command uses the Hydra
model of execution (processes split by "`:`"s). Each remote process is executed
with `-wdir` set explicitly. The `-hostlist` argument is used, together with
the ordering of the processes, to map hosts to processes.

If you want to learn how this works, the best way, in my view, is to call the
Launcher with the "Don't start the Orchestrator" switch (i.e. `./orchestrate.sh
/d`), which prints the command without executing it. Try varying the switches
and arguments you pass to the Launcher to see how the command varies. Marvel at
my brilliance[^until].

The command is then executed using `system` (if `/d` was not specified).

[^until]: Until it breaks of course, then you should submit an issue on the
    issue tracker like a good user.

### Example

This is an example to show off the command generation. It might be out of date,
but should give the general idea. Lets say I run the following on my non-POETS
machine:

~~~ {.bash}
./orchestrate.sh /d /g = root /b = call_file.poets /o = byron
~~~

Then, the following is printed to screen (`<SNIP>` is a truncation, for
brevity):

~~~ {.bash}
mpiexec.hydra -genv LD_LIBRARY_PATH "/local/orchestrator-common/<SNIP>" -hostlist march-soton:3,byron:1 -n 1 /usr/bin/gdb --args /home/mark/repos/orchestrator/bin/root /batch=\"/home/mark/repos/orchestrator/call_file.poets\" : -n 1 /home/mark/repos/orchestrator/bin/logserver : -n 1 /home/mark/repos/orchestrator/bin/rtcl : -n 1 -wdir ~/.orchestrator/launcher ./mothership
~~~

The inputs:

 - `./orchestrate.sh`: Path to the **Setup Script** created by the build
   process.

 - `/d`: I don't want to start the Orchestrator, merely print the command that
   would be run.

 - `/g = root`: I want to spawn root under gdb (presumably to diagnose a
   problem).

 - `/b = call_file.poets`: I want the following batch command to run when I
   start the Orchestrator.

 - `/o = byron`: I want to start one Mothership process on Byron, and no other
   Mothership processes. I've configured an entry for `byron` in my SSH
   configuration file (`.ssh/config`) as per the usage documentation.

The outputs:

 - `mpiexec.hydra`: It's an MPI command after all. The **Setup Script** has
   populated the `$PATH` environment variable so that the **Launcher Proper**
   knows where `mpiexec.hydra` is.

 - `-genv LD_LIBRARY_PATH "/local/orchestrator-common/<SNIP>"`: Load paths
   (separated by "':'"s) for children to be aware of. This is defined by the
   **Setup Script**, and is passed to the **Launcher Proper** as an additional
   argument.

 - `-hostlist march-soton:3,byron:1`: Hosts to run processes on. The first
   three processes will run on my machine (`march-soton`), and the last process
   will run on `byron`.

 - `-n 1 /usr/bin/gdb --args /home/mark/repos/orchestrator/bin/root`\
   `/batch=\"/home/mark/repos/orchestrator/call_file.poets\"`: Let's break this
   down further:

   - `-n 1`: Spawn one process on the next host (`march-soton`).

   - `/usr/bin/gdb --args`: It'll run under GDB (MPI information is propagated
     to the executable).

   - `/home/mark/repos/orchestrator/bin/root`: Path to the Orchestrator process
     to run (in this case, Root).

   - `/batch=\"/home/mark/repos/orchestrator/call_file.poets\"`: Path to the
     batch script to run once everything has settled.

 - `: -n 1 /home/mark/repos/orchestrator/bin/logserver`: Spawn one Logserver
   process on the next host (`march-soton`)

 - `: -n 1 /home/mark/repos/orchestrator/bin/rtcl`: Spawn one Clock process on
   the next host (`march-soton`).

 - `: -n 1 -wdir ~/.orchestrator/launcher ./mothership`: Spawn one Mothership
   process on the next host (`byron`), but change directory to
   `~/.orchestrator/launcher` before executing.

One consequence of running this command is that `byron` now has copies of the
binaries from `march-soton`, at `~/.orchestrator/launcher`. These binaries will
be clobbered the next time I use the Launcher to run a process on Byron.

# The SSH Helper Library

SSH (Secure SHell) is used to deploy binaries on remote machines and perform
rudimentary commands at launch-time. All SSH operations are encapsulated in the
SSH helper library, at `Source/Launcher/SSH{cpp,h}`[^libssh]. Due to it's lack
of sophistication, it imposes the following requirements:

[^libssh]: You may ask "Why did you not use libssh? After all, it's a
    well-established open-source C library that's fully compliant with your
    code, and can manage authentication. It's also a lot more sophisticated
    than your library, and is better documented." You're correct, but my
    library took very little time to implement. "Jam tomorrow", to pilfer ADB's
    parlance.

 - The SSH "User" that is calling the Launcher is either the same as the
   remote, or is configured in the SSH configuration for the remote.

 - There is an unexpired, secure keypair that permits the connection (or some
   kind of SSH-agent daemon).

 - The host is known (i.e. exists in your known_hosts file).

The one good thing about it is it's error reporting; you should get all of the
errors that SSH throws back if you do something wrong (or if I've made a
mistake).

# Debug mode

The Launcher can also be compiled to run in Debug mode, either by setting the
`ORCHESTRATOR_DEBUG` macro to 1, or by making with the debug option (i.e. `make
debug`), which ultimately does the same thing. Debug mode:

 - Makes the Launcher more verbose, by spitting your arguments back to you,
   informing you of how it has interpreted your arguments, and generally giving
   you more explanation of what you are doing.

 - Prepends the process number to Orchestrator standard output (by passing the
   `-l` switch in the MPI command).

# Future Work

 - Better Windows compatibility (I ran out of time, and get the impression that
   this is not a priority). The areas that need to be addressed are:

   - Basically everything in `Launcher::DeployBinaries`. Getting paths is not
     implemented correctly (we can't just use the filesystem library because
     it's C++17), and actually copying binaries requires SSH, which will
     require a different command-line string on Windows.

   - The MPI command uses GNU-style switches instead of Windows ones (pretty
     trivial to fix).

 - Better valgrind/gdb interplay. The current implementation is naive, but will
   work in most cases. Most people don't want to combine valgrind and gdb
   anyway, but for those that do:
   http://valgrind.org/docs/manual/manual-core-adv.html (or Google).

 - Use a proper SSH library (libssh). I just ran out of time.

![](images/white_px.png)
