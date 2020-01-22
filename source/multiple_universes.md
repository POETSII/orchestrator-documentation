% Connecting to Other MPI Universes

# About

This content, written by ADR on commit
`c0cd500029c20f71b4cf847640db1c4f7bdcf88f`, was extracted from the Orchestrator
README on commit `d250dc343b51afe7016465c3a7b9bbf880c66487`. While valid, it is
not currently part of the Orchestrator workflow, but is preserved here, in
verbatim (with markup), for future intended use.

# Source

Provided an Orchestrator universe has been started up containing a root, you
can subsequently link it to other Orchestrator universes either started
beforehand or subsequently, using the system /conn command. One potential use
of this would be to allow Motherships (which take control of Tinsel hardware)
to be dynamically started and stopped independently of the rest of the
Orchestrator, and possibly be connected to by several other Orchestrator
instances. This requires the following additional setup:

You have to start up a hydra nameserver process. Assuming the mpich bin
directory is in your path, you can do this by typing

~~~ {.bash}
hydra_nameserver &
~~~

If any mpiexec command you run is operating on a different host machine than
the one you started up `hydra_nameserver`, you need the following additional
switch in your `mpiexec.hydra` command

~~~ {.bash}
-nameserver {host_name}
~~~

This switch should probably go right after the specification of the library
directories (i.e. before any `-n {x} {executable}` clauses).

This should be done BEFORE attempting to connect to any universes you might
wish to.

Once this has been done, you can link the 2 universes, making them appear as
one large Orchestrator system, by typing

~~~ {.bash}
system /conn = {service name}
~~~

where service name is the text string indicating the universe to which you want
to connect. Currently the default service name is `POETS_MPI_Master`. This can
be changed on the server universe (the one you are connecting to) provided root
has been started in that universe, by typing

~~~ {.bash}
system /svcn = {service name}
~~~

Once connected you should be able to execute all commands seamlessly and the
Orchestrator will work out where to direct the result.
