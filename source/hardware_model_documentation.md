% The Hardware Model and its Interfaces

# The Hardware Model
This document introduces the design of the hardware model, and explains
relevant data structures. Each class described in this section is supplemented
by a definition in Appendix A. Three desirable features of the Orchestrator
are:

 - Engine Flexibility: The Orchestrator must be able to run on a variety of
   POETS Engine (hardware stack) configurations, without particular input from
   the operator (person scripting/commanding the Orchestrator).

 - Efficient Placement: The Orchestrator must be able to efficiently map
   multiple application graphs (from XML files) onto the POETS Engine.

 - Robustness to Hardware Failure: The Orchestrator must react to failures or
   misconfigurations in hardware, so that compute jobs complete successfully in
   reasonable time.

To support these features, the Orchestrator requires an accurate model of the
hardware because, without such a model, the application graph cannot be mapped
to the POETS Engine, so tasks cannot be run efficiently. Figure 1 shows a
simplified schematic of the hardware model used in the Orchestrator, where each
green box is a hardware construct, represented in the Orchestrator by a class:

![A simplified schematic of the hardware model used in the Orchestrator. Edges
indicate containment.](images/engine_structure_simple.pdf)

 - The "Engine" (`P_engine`) is the primary interface for the hardware model,
   and encapsulates its components in a hierarchy. One Engine is owned by
   OrchBase (`OrchBase->pE`). The Engine holds a set of boxes that comprise the
   POETS Engine, and also contains a graph describing the location of FPGA
   boards throughout the Engine.

 - A "Box" (`P_box`) represents a physical box in the hardware stack. An Engine
   contains multiple boxes, which in turn contain a set of compute FPGA boards.

 - A "Board" (`P_board`) represents a compute FPGA board in the hardware stack,
   which contains a graph of mailboxes.

 - A "Mailbox" (`P_mailbox`) is a non-physical component of compute FPGA
   boards, and is partly responsible for routing packets traversing the POETS
   Engine. Mailboxes are "defined" when the board is synthesized. Mailboxes
   service a series of cores.

 - A "Core" (`P_core`) is a compute core in an FPGA board, serviced by a
   mailbox. Cores are responsible for the compute in the POETS engine, and
   support a subset of the RV32IMF profile (see the Tinsel documentation for
   what is excluded). When a task is initialised (with `task /init`), the
   Mothership process sends instruction and data binaries to each core through
   the `HostLink` interface.

 - Each "Thread" in a given core (`P_thread`) supports concurrent execution of
   devices (nodes in the application graph). The binaries that a core is
   provisioned with defines the Softswitch behaviour that runs on each thread
   of the core.

## Containment
Central to the implementation of the hardware model is the notion of
containment. Each container indexes the component it contains by the relevant
component ($C$) of the hardware address[^butnotP_boardv] (see the following
section). The following structures feature as edges in Figure 1, and exist to
facilitate containment:

[^butnotP_boardv]: Each container indexes by the component of the hardware
    address, with the exception of `P_box::P_boardv` which, as a
    `std::vector<P_board*>` does not map keys to its values.

 - `P_engine::G`, which contains boards. This container is a graph, which holds
   the board topology, so that the "distance" between boards can be computed.

 - `P_engine::P_boxm`, which contains boxes. Boxes are not connected in the
   model, because traffic between normal devices in the compute fabric does not
   traverse this connection. As such, boxes simply hold collections of boards,
   and `P_engine::G` models the inter- and intra-board connections.

 - `P_box::P_boardv`, which contains boards. Boxes do not hold board
   connectivity information; this is held in the Engine containing the board.

 - `P_board::G`, which contains mailboxes. As with `P_engine::G`, this
   container is a graph, which maintains the topology of mailboxes within the
   board.

 - `P_mailbox::P_corem`, which lists the cores serviced by the mailbox, with a
   constant communication cost within a mailbox.

 - `P_core::P_threadm`, which contains threads in the same way.

Threads also contain devices in a list (`P_thread::P_devicel`), but this member
does not use the containment mechanism to hold or order devices.

Each item in the Engine hierarchy defines a `contain` method if it can contain
another item in the hierarchy, and also defines a `on_being_contained_hook`
method if it can be contained. For example, a `P_board` can be donated an
unowned `P_mailbox` via the method `void P_board::contain(AddressComponent,
P_mailbox*)`, where the first argument is the mailbox component of the hardware
address ($C_{\mathrm{MAILBOX}}$, see the following section), and the second
argument is the address of the mailbox to contain. This method will internally
call `void P_mailbox::on_being_contained_hook(P_board*)`, to register the board
as the parent of the mailbox. If containment fails, for example if the
containee is already owned, an `OwnershipException` is raised.

## Addressing Hardware
In addition to representing physical hardware, the Orchestrator needs to
understand how the Tinsel communicates with items on the hardware stack. Tinsel
addresses threads using the following hierarchical address
scheme:[^tinseladdress]

[^tinseladdress]: This may not reflect current Tinsel functionality. It is only
    included here to demonstrate that some translation has to occur between the
    Tinsel address and the Hardware address in the Orchestrator.

$$T_{\mathrm{BOARD,Y}}\cdot T_{\mathrm{BOARD,X}}\cdot T_{\mathrm{CORE}}\cdot
T_{\mathrm{THREAD}}$$

where the address is a 32-element bit array, $T$ represents a component of the
Tinsel hardware address, and "$\cdot$" represents concatenation. The
Orchestrator generalizes this concept of an address to:

$$C_{\mathrm{BOX}}\cdot C_{\mathrm{BOARD}}\cdot C_{\mathrm{MAILBOX}}\cdot
C_{\mathrm{CORE}}\cdot C_{\mathrm{THREAD}}$$

which is again a 32-element bit array, and where $C$ represents a component of
the hardware address in the Orchestrator. Each component has a fixed width $W$
for the lifetime of the Orchestrator (e.g. $W_{\mathrm{MAILBOX}}$), and is
buffered by zeroes so that each component does not overrun into any other
component. By way of example, the source name of component $C_{\mathrm{BOX}}$
is `HardwareAddress::boxComponent`, and the source name of the width
$W_{\mathrm{MAILBOX}}$ is `HardwareAddressFormat::mailboxWordLength`.

Figure 2 shows the class structure of how components of the hardware model
interact with the addressing system. Each item in the Engine hierarchy (apart
from the Engine itself) inherits from the `AddressableItem` class, which
abstracts the behaviours of "being addressable". The `AddressableItem` class
holds a `HardwareAddress` instance, which is comprised of `AddressComponent`s
(which are `uint32_t`s). Instances of `HardwareAddress` also point to a
`HardwareAddressFormat`, which holds the widths of each component[^whyformat].

![Class structure diagram showing how items in the hardware model maintain
addressing capabilities. The `HardwareAddressFormat` is effectively a "master
copy" that applies over the items in the engine. Green boxes are classes
representing items in the hardware model. Red boxes are classes supporting
addressing behaviours. Blue boxes are sets of members.
](images/addressing_structure.pdf)

[^whyformat]: Because a system can have many threads, cores, mailboxes, boards,
    and boxes, `HardwareAddress` is designed to have as low a data footprint as
    reasonably possible. Consequently, the bit widths are not stored on a
    per-address basis, and are instead stored in a `HardwareAddressFormat`,
    which is common to all addresses in an Engine. A `HardwareAddress` reads
    the spacings in its `HardwareAddressFormat` when it is instructed to output
    a 32-bit hardware address.

## How OrchBase and the Operator fit in
The hardware model is central to the operator's successful usage of the
Orchestrator. The operator needs to be able to:

 - define the hardware model in the Orchestrator in order to facilitate
   placement and to populate SBase (in NameServer and on Motherships).

 - redefine the hardware model with a replacement.

 -  be able to easily diagnose potential issues with the hardware model, and
    its interactions with the rest of the Orchestrator (though admittedly this
    is more of a developer role).

The operator's interactions with the hardware model are shown in Figure 3. The
operator can define the model in two ways:

 - From a default configuration: The operator can command `topology /set1` or
   `topology /set2` in the POETS shell to initialise a default hardware
   configuration. In response to this command, Root clears its existing engine
   (`pE`), and creates a new one dynamically. Root then statically creates an
   `AesopDeployer` (or a `MultiAesopDeployer`) object, which are
   pre-provisioned `Dialect1Deployer` classes. The created object is then used
   to deploy the default configuration to the engine (`pE`). The default
   configurations are:

    - Set 1: Deploys a one-box Aesop-like system, which contains one box, which
      contains three boards connected in a row, which each contain sixteen
      mailboxes connected in a row, which each contain four cores, which each
      contain sixteen threads.

    - Set 2: As with Set 1, but with two boxes instead of one, connected on the
      short edge.

   these configurations are suitable for testing small applications and for
   rudimentary testing.

 - Input file: The operator can command `topology /load =
   topology_description.poets` to load the topology described in the file
   `topology_description.poets` (alternative paths can be specified). Root
   first clears and recreates its engine as before, then statically creates a
   `HardwareFileParser` object, loads the file, uses it to populate a
   statically-created `Dialect1Deployer` object. As before, this deployer
   object then deploys its configuration (which was loaded from the file) to
   the engine owned by Root. See Appendix B for a description of how input
   topology files must be constructed.

Once an Engine has been populated, the operator can then interact with the
engine through the following POETS console commands:

 - `topology /clear`, which clears the topology, deleting all of the
   dynamically-created items within the engine, freeing each container
   structure, then deleting the engine itself.

 - `topology /dump`, which dumps the engine and its contents to stdout, if an
   engine has been defined. Optionally, `topology /dump = file` can be used to
   write to a file instead.

![Hardware model interaction diagram. The operator interacts with the hardware
model (Engine, `OrchBase->pE`) through topology commands. Certain commands
(`/set1`, `/set2`, and `/load`) statically create one or more intermediate
objects, which are used to define the Engine. None of these command-transient
objects persist after the command has completed. Other commands (`/dump`,
`/clear`) interact directly with the Engine in some
way.](images/interaction_diagram.pdf)

## Graphs
Graphs are used in the hardware model to represent collections of items
connected in a topology, in order to inform the placement of application
devices onto threads in the hardware model. All graphs in the hardware model
use nodes to represent items (boards, mailboxes, etc.), edges to represent
communication costs, and do not meaningfully use pins (for now). All graphs
defined in this way are simple (no loop edges or duplicate edges), connected
(each vertex is indirectly connected to each other vertex), and
undirected[^undirected]. Due to the `pdigraph` structure they are based on,
hardware model graphs are tripartite[^tripartite]. `P_link` objects are used to
represent edges by holding edge weights, which indicate the "communication
cost" of a packet traversing that edge. Pins are represented by `P_port`
objects, which are stubs. `P_link` and `P_port` objects in these graphs are
indexed atomically per graph instance. Figure 4 shows an example graph of
boards, connected to `P_port` pins, which are in turn connected by `P_link`
edges. For more information on graphs, see the `pdigraph` documentation in the
source.

[^undirected]: Although the data representation is a digraph, the undirected
    nature of the graph is captured using complement edges.

[^tripartite]: All nodes in the graph (items and `P_port`s) can be partitioned
    into three different independent sets (graph colouring).

![Example graph of six boards (i.e. `P_engine::G`). Each board (`P_board`) is
connected (grey edges) to one pin (`P_port`, black-grey circle) for each board
it is "adjacent to". Pins connect boards together over special edges
(`P_link`s, black edges). Board connection in this way may be arbitrary; the
graph does not need to be Manhattan, and can contain cycles (but not
loops). This description extends to the graph of mailboxes
`P_board::G`.](images/generic_graph.pdf)

## Iteration
As an Orchestrator developer, it is often useful to iterate over different
items in the Engine. The `HardwareIterator` class supports iterating over
different levels of the hardware hierarchy for a given Engine, though note that
`HardwareIterator` is not an iterator in the sense of an STL iterator (though
it uses them), and does not attempt to replicate the STL iterator
interface. Iteration exploits the fact that all of the container objects are
ordered. A `HardwareIterator` is initialised against a fully defined
`P_engine`[^fullyDefinedEngine], operates without changing the state of that
Engine, and assumes that the Engine does not change while it is in scope. A
`HardwareIterator` holds four (private) iterators:

[^fullyDefinedEngine]: A `P_engine` is fully defined if it contains at least
    one board (and consequently at least one box), and if all of the non-box
    items within the Engine that can contain at least one item do
    so. Effectively, each board must contain at least one mailbox, each mailbox
    must contain at least one core, and each core must contain at least one
    thread. This condition is required for a `HardwareIterator` because the
    behaviour of `HardwareIterator::next_thread` is unintuitive; for example,
    if the iterator traverses a core with no threads, it traverses "more
    slowly" than if `HardwareIterator::next_core` is called, which is not
    normally the case.

 - `boardIterator`, which iterates over each board in the Engine.

 - `mailboxIterator`, which iterates over each mailbox in the Engine (even
   across boards).

 - `coreIterator` (you get where this is going), and

 - `threadIterator`

These iterators, which are initialised on the first thread in the first core
serviced by the first mailbox in the first board (the origin thread), allow
`HardwareIterator` to:

 - Increment itself on a thread, core, mailbox, or board level (e.g. by using
   `HardwareIterator::next_X` method, where `X` is either `thread`, `core`,
   `mailbox`, or `board`). If `HardwareIterator::next_thread` is called while
   the `HardwareIterator` is on the final thread of a core, it will increment
   its `coreIterator`, then set `threadIterator` to the first thread in that
   core. This can "set off" chains of iteration over multiple levels of the
   hierarchy.

 - Loop over the hardware model. By way of example, if `HardwareIterator` is
   pointing to the final thread in the final core serviced by the final mailbox
   on the final board (the ultimate thread), calling
   `HardwareIterator::next_thread` will cause the iterator to loop back to the
   origin thread[^orderReminder].

[^orderReminder]: Recall that each of the containers in the Engine is ordered,
    so the concept of a sequence of items in this way is well defined.

 - Allow the developer to determine whether the item on a given level has
   changed, by calling the appropriate `HardwareIterator::has_X_changed`
   method. The developer can also determine whether the `HardwareIterator` has
   wrapped around the Engine via `HardwareIterator::has_wrapped`. These methods
   read the internal state of the `HardwareIterator` and check it with
   last-known information, meaning subsequent calls to this method will always
   return `false` if the iterator has not moved.

 - Allow the developer to reset the iterators to the first item on their
   respective level of the hierarchy.

### Iteration Example
In bucket-filling placement, devices are mapped to threads in order (like
pouring water into a succession of buckets). This placement method must respect
the constraint that core pairs can only contain the same type of device
(because their instruction memory spaces are shared).

Without using `HardwareIterator`, this can be achieved through the following
naive[^naive] pseudocode:

[^naive]: This of course does not perform any other constraint management, and
    only assumes one application is being mapped. It is only included to
    justify the existence of `HardwareIterator`. Bear with me.

```
for each device type (devType):
    for each board in the Engine (iBoard):
        for each mailbox in iBoard (iMailbox):
            for each core in iMailbox (iCore):

                if the first thread of iCore has no devices:
                    for each instance of this device type (iDevice):
                        for each thread in iCore (iThread):
                            if iThread is full:
                                continue
                            else:
                                link iDevice to iThread
                            endif
                        endfor (threads)
                    endfor (device instances)
                endif (is core empty)
                if there are no more instances of this device type:
                    break up to "for each device type"
                endif

            endfor (cores)
        endfor (mailboxes)
    endfor (boards)
endfor (device types)
```

With a `HardwareIterator`, this simplifies to:

```
iterator = HardwareIterator(*engine)  // Initialises to the origin thread
for each device type (devType):
    if the first thread of iterator.get_core() has no devices:
        for each instance of this device type (iDevice):
            if iterator.get_thread() is full:
                iterator.next_thread()
            else:
                link iDevice to iterator.get_thread()
            endif
        endfor (device instances)
    else:
        iterator.next_core()  // Sets the thread to the first in this core
    endif (is core empty)
endfor (device types)
```

The second implementation, which uses the iterator, is superior because it:

 - Does not require any knowledge about irrelevant components of the
   hardware stack (boards and mailboxes),

 - Maintains a lower nesting depth, making reading and maintenance easier.

 - Is more modular (can be easily decomposed into functions and tested).

 - Is more adaptable, in that is easier to implement multiple-application
   support. This is because the shared-core instruction behaviour can be
   overcome by two calls to `iterator.next_core`, and because the
   implementation can easily be adapted, using `iterator.has_wrapped`, to
   elegantly identify when the hardware has run out of space.

For an example using the source, the test suite contains a set of simple
examples which are suitable for a first look.

## Tests
The hardware model, including the items, containment, addressing mechanism,
input file reader, and the iterator, are all supported by a suite of unit tests
in the `Tests` directory of the Orchestrator. These unit tests are driven by
the Catch2 (1.x, classic) testing framework, described by the file
`Tests/catch.hpp`. The tests can be built using GCC in a similar manner to the
Orchestrator build process, by commanding `make tests`. This will compile the
source with debugging enabled (and debugging symbols).

Each file in `Tests/*.cpp` produces a file once compiled with the Catch2
header. These files can be executed to determine whether or not the source
functions as intended, along with output describing what went wrong. Each test
can also be called with a memory checker (I use Valgrind) to verify the
integrity of the structures under test. For example, if the hardware model
tests (Tests/TestHardwareModel.cpp) are compiled and run, and all pass,
something like the following is printed to the standard output (JUnit output
can also be produced for CI):

```
$ ./TestHardwareModel.test
===============================================================================
All tests passed (67 assertions in 18 test cases)
```

Or, with Valgrind, something like (this is good output):

```
$ valgrind --track-origins=yes --leak-check=full ./TestHardwareModel.test
==20767== Memcheck, a memory error detector
==20767== Copyright (C) 2002-2017, and GNU GPL'd, by Julian Seward et al.
==20767== Using Valgrind-3.14.0 and LibVEX; rerun with -h for copyright info
==20767== Command: ./TestHardwareModel.test
==20767==
===============================================================================
All tests passed (67 assertions in 18 test cases)

==20767==
==20767== HEAP SUMMARY:
==20767==     in use at exit: 18,572 bytes in 6 blocks
==20767==   total heap usage: 1,474 allocs, 1,468 frees, 230,292 bytes allocated
==20767==
==20767== LEAK SUMMARY:
==20767==    definitely lost: 0 bytes in 0 blocks
==20767==    indirectly lost: 0 bytes in 0 blocks
==20767==      possibly lost: 0 bytes in 0 blocks
==20767==    still reachable: 18,572 bytes in 6 blocks
==20767==         suppressed: 0 bytes in 0 blocks
==20767== Reachable blocks (those to which a pointer was found) are not shown.
==20767== To see them, rerun with: --leak-check=full --show-leak-kinds=all
==20767==
==20767== For counts of detected and suppressed errors, rerun with: -v
==20767== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)
```

Mark has a script for running each of these tests on its own and with a memory
checker. If that's of interest to anyone, get in touch, and I'll share it or
make it available in the repository.

## Future Work
The hardware model is designed to be adaptable to potential changes in the
hardware configuration the Orchestrator operates on. This adaptability also
supports the addition of certain features. This section outlines features that
are planned for addition in future, as well as how their addition will manifest
in changes to the hardware model.

 - *Higher dialect parsers*: POETS Engines will have heterogeneities in their
   structure in future; an Engine may be comprised of multiple boxes with
   different board layouts for example. The current hardware model
   implementation supports heterogeneity throughout the data structure (each
   item is represented by an individual region in memory). However, the current
   hardware file reading mechanism is limited to homogeneous configurations. An
   extension to `HardwareFileParser` is planned, to support a variety of
   dialects of input files, so that heterogeneous systems can be
   described. These dialects are defined in Appendix B.

 - *Incorporate the bridge board in the board graph*: In order for a packet to
   be sent from a normal device (compute device running on a thread in the
   POETS Engine) to a supervisor device, that packet is routed through the
   network of compute FPGA boards in the Engine, to the nearest "bridge
   board". The topology of an example box with a bridge board is shown in
   Figure 5. A bridge board brokers the communication between the Engine
   proper, and the supervisor devices running on the Mothership Orchestrator
   process. If the hardware model is extended to incorporate bridge boards, the
   communication cost between a normal device and a supervisor device can be
   estimated more accurately, improving placement for applications where a
   large amount of communication is done in this way.

 - *Mailbox links across boards*: In order for packets to traverse the POETS
   Engine across the network of boards, packets must first traverse the graph
   of mailboxes, as shown in Figure 6. Packet traversal between boards is
   achieved using a multiplexing mechanism, so the mailbox that a packet
   "arrives at" on a given board is a function of where it leaves the first
   board. The present implementation of the hardware model does not account for
   this, and models the cost of traversing from one board to another as fixed,
   with respect to the mailboxes used. This feature could be supported by the
   addition of "multiplexer mailboxes", which exist in the mailbox graph
   `P_board::G`, and by including pins on the outer mailboxes. These
   multiplexer mailboxes would store a map of these pins, so that placement can
   exploit this traversal information. This extension would result in more
   informative placement for problems spanning multiple boards.

 - *Hardware discovery*: The "Engine Flexibility" feature described at the
   beginning of this section mandates that the Orchestrator must be able to run
   on a variety of POETS Engine configurations without particular operator
   input. To satisfy this, the operator must be able to command the
   Orchestrator to discover the hardware it is running on. Furthermore, the
   "Robustness to Hardware Failure" feature also requires the Orchestrator to
   support a mechanism where the POETS Engine detects and reports its state to
   the Orchestrator in response to changes. The discovery mechanism would be
   for the Orchestrator to release a "discovery packet swarm" over the POETS
   Engine to identify its topology.

![Schematic showing, in one box, how the bridge board facilitates the
connection between compute FPGA boards and supervisor devices running on the
Mothership. This is how the POETS Engine currently operates (though the compute
boards may be arranged differently), and is not how the Orchestrator models
traffic. The bridge board facilitates this communication, and can be accounted
for during placement, as devices on `B20` and `B21` will have a lower
supervisor communication cost than the other compute
boards.](images/bridge_board.pdf)

![Schematic showing how packets traverse both the mailbox (circles with "M")
and board graphs. This is how the POETS Engine currently operates, and is not
how the Orchestrator models traffic. In order for a packet to travel from one
of the marked mailboxes to the other (red circles), it must leave the board
through a multiplexed SFP+ connection. This connection carries the packet onto
a specific mailbox on the other board.](images/mailbox_board_interaction.pdf)

# Appendix A: Source definitions
This Appendix describes the methods and members of each class defined as part
of the hardware model ecosystem described in the Overview section. The
following classes inherit from `NameBase`:

 - `P_engine`
 - `P_box`
 - `P_board`
 - `P_mailbox`
 - `P_core`
 - `P_thread`
 - `P_link`
 - `P_port`

The following classes inherit from `DumpChan`, and define `void Dump(FILE*)`
methods:

 - `P_engine`
 - `P_box`
 - `P_board`
 - `P_mailbox`
 - `P_core`
 - `P_thread`
 - `P_link`
 - `P_port`
 - `HardwareAddress`
 - `HardwareAddressFormat`

The following classes inherit from `AddressableItem`, and therefore contain a
(possibly incomplete) hardware address:

 - `P_box`
 - `P_board`
 - `P_mailbox`
 - `P_core`
 - `P_thread`

A description of the members and methods of each class, including these
containment methods, follows.

## P_engine
`P_engine` represents a model of the POETS Engine on which the Orchestrator is
operating. It is a self-contained model of the hardware stack, and is the
primary way in which other components of the Orchestrator interface with the
hardware model.

Members:

 - `HardwareAddressFormat addressFormat`: Holds the spacings for hardware
   addresses in this engine.

 - `OrchBase* parent`: Defines `OrchBase`, and consequently Root, as its
   logical parent. This, and the `NameBase` parent, is defined by the owner of
   the `P_engine` object (an `OrchBase`).

 - `std::map<AddressComponent, P_box*> P_boxm`: Data structure that holds each
   box in the POETS Engine. Boxes are indexed by the box component
   ($C_{\mathrm{BOX}}$) of their hardware address.

 - `pdigraph<AddressComponent, P_board*, unsigned, P_link*, unsigned, P_port*>
   G`: Data structure that holds all boards in the POETS Engine. Boards are
   indexed by the board component ($C_{\mathrm{BOARD}}$) of their hardware
   address. Note that boards in `P_engine::G` must be owned by a box in
   `P_engine::P_boxm` (i.e., you can't have an FPGA board floating in space
   within an Engine). For more information about graphs in the hardware model,
   see the Graphs section.

 - `std::string author`: If the Engine has been created from a configuration
   file, this string represents the author as stated in the metadata section of
   that file. If not, this represents the author of the deployer object used to
   create this Engine.

 - `long long datetime`: If the Engine has been created from a configuration
   file, this string represents the datetime as stated in the metadata section
   of that file. If not, this represents the datetime of when the deployer
   object used to create this Engine was written.

 - `std::string version`: If the Engine has been created from a configuration
   file, this string represents the version as stated in the metadata section
   of that file. The version indicates the version of the input file language
   used to generate the Engine. If the Engine was not created from a
   configuration file, this will be the greatest input file version.

 - `std::string fileOrigin`: If the Engine has been created from a
   configuration file, this string represents the origin of the file, as stated
   in the metadata section of that file. If not, `fileOrigin` represents the
   origin of the deployer used to create the Engine.

 - `float costExternalBox`: Indicates the cost of communicating with an
   external device from any box in the Engine. This effectively models the cost
   of communicating over the Internet from a box, and is a wild estimate.

 - `unsigned int arcKey`: Placeholder variable to support indexing `P_link`
   objects in `P_engine::G`. This begins at zero, and is incremented after each
   new `P_link` is added.

 - `unsigned int portKey`: Placeholder variable to support indexing `P_port`
   objects in `P_engine::G`. This begins at zero, and is incremented after each
   new `P_port` is added.

Methods:

 - `P_engine::P_engine(std::string name)`: Engine constructor. This
   constructor:

   - Sets the `NameBase` name of this Engine, using input argument `name`.

   - Configures callback functions for `P_engine::G`. These callbacks are used
     to support `P_engine::Dump(FILE*)`, when dumping to a particular
     file. Callback methods are `static void` methods that print relevant
     information about the `P_board`, `P_link`, or node key, or edge key,
     depending on which method is called.

   - Populates default values for `author`, `datetime`, `version`, and
     `fileOrigin`. Deployers will override these defaults after creating the
     `P_engine`.

 - `P_engine::~P_engine()`: Engine destructor, see `P_engine::clear()`.

 - `void P_engine::clear()`: Clears all dynamically-allocated datastructures in
   this engine, recursively. This explicitly deletes all `P_box` instances in
   `P_engine::P_boxm`, and all `P_link`, `P_port`, and `P_board` instances in
   `P_engine::G`. It also clears the graph object.

 - `void P_engine::contain(AddressComponent addressComponent, P_box* box)`: If
   the box `box` is not owned by another Engine, this method adds `box` to
   `P_engine::P_boxm`, using `addressComponent` as the index. It also calls
   `box->on_being_contained_hook()`, and supplies `box` with a
   `HardwareAddress` based off `P_engine::addressFormat`. If the box is already
   owned, or if the box is not owned by the Engine after claiming it, an
   `OwnershipException` is thrown.

 - `void P_engine::contain(AddressComponent addressComponent, P_board* board)`:
   If the board `board` is owned by a box, which in turn is owned by this
   Engine, then this method inserts `board` as a node in `P_engine::G`, with
   `addressComponent` as the index. Otherwise, an `OwnershipException` is
   thrown. Also, if `P_engine::G` does not insert `board` successfully (because
   it is already owned by this engine), an `OwnershipException` is thrown. This
   method does not add any arcs (edges) to `P_engine::G`.

 - `void P_engine::connect(AddressComponent start, AddressComponent end, float
   weight, bool oneWay=false)`: Creates and inserts a `P_link` instance as an
   arc in `P_engine::G`, which connects the boards keyed by the `start` and
   `end` keys in the graph's node map. The `P_link` object is supplied with
   `weight`, which represents the cost of communication over the arc. By
   default, this connection is bidirectional (`oneWay` is used to reduce code
   duplication, as `oneWay=false` causes the method to call itself with
   `oneWay=true` with the `start` and `end` arguments reversed). This method
   throws an `OwnershipException` if either `start` or `end` are not keys in
   the node map of `P_engine::G`.

 - `bool P_engine::is_empty()`: Returns `true` if the engine has no items
   (boxes, boards, etc.), and `false` otherwise.

An example dump (`P_engine::Dump()`) of a one-box, three-board system
follows. It was generated by calling `topology /set1` followed by `topology
/dump` in the POETS shell.

```
P_engine O_.Aesop [1 box] +++++++++++++++++++++++++++++++++++++++++++++++++++++
NameBase dump+++++++++++++++++++++++++++++++
this           0x558b5b799af0
Name           Aesop [1 box]
Id                      2(0x00000002)
Parent         0x558b5b77acc0
Recursion trap Unset
Unique id      3985
NameBase id    Name
 ** No map entries **
NameBase dump-------------------------------

Author: Mark Vousden
Configuration datetime (YYYYMMDDHHmmss): 201901101712
Written for parser version: 0.3.1
Read from file: AesopDeployer.cpp
Board connectivity ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Pdigraph topological dump ===================================++++++++++++++++++++
Node index (3 entries):
   1 (0:O_.Aesop [1 box].Box000000.Board000000)
  Fanin arcs (1 entries)
     1 ^|2~0.000000|^   -> ((5~0x0000558b5b79a400))
  Fanout arcs (1 entries)
     1 ((0~0x0000558b5b79a030))         -> ^|0~0.000000|^
===

   2 (1:O_.Aesop [1 box].Box000000.Board000001)
  Fanin arcs (2 entries)
     1 ^|0~0.000000|^   -> ((1~0x0000558b5b79a080))
     2 ^|3~0.000000|^   -> ((7~0x0000558b5b79a5f0))
  Fanout arcs (2 entries)
     1 ((2~0x0000558b5b79a1c0))         -> ^|1~0.000000|^
     2 ((4~0x0000558b5b79a3b0))         -> ^|2~0.000000|^
===

   3 (2:O_.Aesop [1 box].Box000000.Board000002)
  Fanin arcs (1 entries)
     1 ^|1~0.000000|^   -> ((3~0x0000558b5b79a210))
  Fanout arcs (1 entries)
     1 ((6~0x0000558b5b79a5a0))         -> ^|3~0.000000|^
===

Arc index (4 entries):
   1 (0~O_.Aesop [1 box].Box000000.Board000000)((0~0x0000558b5b79a030)) ->
 ^|0~0.000000|^         ->
 ((1~0x0000558b5b79a080))(1~O_.Aesop [1 box].Box000000.Board000001)

   2 (1~O_.Aesop [1 box].Box000000.Board000001)((2~0x0000558b5b79a1c0)) ->
 ^|1~0.000000|^         ->
 ((3~0x0000558b5b79a210))(2~O_.Aesop [1 box].Box000000.Board000002)

   3 (1~O_.Aesop [1 box].Box000000.Board000001)((4~0x0000558b5b79a3b0)) ->
 ^|2~0.000000|^         ->
 ((5~0x0000558b5b79a400))(0~O_.Aesop [1 box].Box000000.Board000000)

   4 (2~O_.Aesop [1 box].Box000000.Board000002)((6~0x0000558b5b79a5a0)) ->
 ^|3~0.000000|^         ->
 ((7~0x0000558b5b79a5f0))(1~O_.Aesop [1 box].Box000000.Board000001)

Pdigraph topological dump ===================================--------------------
Board connectivity ------------------------------------------------------------
Boxes in this engine ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        <a recursive dump of all boxes in the engine goes here>
Boxes in this engine ----------------------------------------------------------
P_engine O_.Aesop [1 box] -----------------------------------------------------
```

## P_box
`P_box` represents a box in the POETS Engine, and contains information about
the boards it hosts, and supervisor properties.

Members:

 - `P_engine* parent`: Defines an Engine as this box's logical parent. This
   is defined when this box is contained.

 - `std::vector<P_board*> P_boardv`: Holds each board contained in this box.

 - `std::vector<P_super*> P_superv`: Holds each supervisor that is hosted by
   this box.

 - `unsigned int supervisorMemory`: Amount of memory available for hosting
   supervisors.

 - `float costBoxBoard`: Indicates the cost of communicating with a board from
   this box, for use when placing ordinary (compute) devices to communicate
   with an external device[^costboxboard].

[^costboxboard]: This will be superseded when the bridge board connection is
    incorporated into the hardware model, as its location in the board mesh is
    relevant for deducing this cost (see Future Work section).

Methods:

 - `P_box::P_box(std::string name)`: Box constructor, sets the `NameBase` name
   using the input argument `name`.

 - `P_box::~P_box()`: Box destructor, see `P_box::clear()`.

 - `void P_box::clear()`: Unlike other `clear()` methods defined by items in
   the hardware model, this method only `delete`s the pointers contained by
   `P_boardv`, and not the data at that memory address. `P_board`s are cleared
   by `void P_engine::clear()`. This method also clears `P_box::P_boardv`.

 - `void P_box::contain(AddressComponent addressComponent, P_board* board)`: If
   the board `board` is not owned by another box, this method adds `board` to
   `P_box::P_boardv`. It also calls `board->on_being_contained_hook()` and, if
   `board` does not have an address, this method supplies `board` with a
   `HardwareAddress` based off the `addressComponent` and the address of this
   box. If the board is already owned, or if the board is not owned by the box
   after claiming it, and `OwnershipException` is thrown.

 - `void P_box::on_being_contained_hook(P_engine* container)`: Sets the parent
   of this box to the engine containing it.

An example dump (`P_box::Dump()`) of a box follows.

```
P_box O_.Aesop [1 box].Box000000 ++++++++++++++++++++++++++++++++++++++++++++++
NameBase dump+++++++++++++++++++++++++++++++
this           0x558b5b796560
Name           Box000000
Id                      3(0x00000003)
Parent         0x558b5b799af0
Recursion trap Unset
Unique id      3985
NameBase id    Name
 ** No map entries **
NameBase dump-------------------------------

Boards in this box ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        <a recursive dump of all boards in this box goes here>
Boards in this box ------------------------------------------------------------
P_box O_.Aesop [1 box] --------------------------------------------------------
```

## P_board
`P_board` represents a compute FPGA board, contained in a box, as
part of an Engine.

Members:

 - `P_box* parent`: Defines a box as this board's logical parent. This is
   defined when this board is contained.

 - `pdigraph<AddressComponent, P_mailbox*, unsigned, P_link*, unsigned,
   P_port*> G`: Data structure that holds all mailboxes in this
   board. Mailboxes are indexed by the mailbox component
   ($C_{\mathrm{MAILBOX}}$) of their hardware address. For more information
   about graphs in the hardware model, see the Graphs section.

 - `std::vector<unsigned> sup_offv`: Data structure to identify supervisors
   hosted on this board. At time of writing, supervisors exist at the box-level
   of the hardware hierarchy, though there are moves to integrate a board with
   supervisor-hosting capabilities in future. At that time, this vector will
   contain indeces to supervisors (`P_super*` instances) stored on the box
   level in `P_box::P_superv`, which will indicate the supervisors hosted on
   this board.

 - `unsigned int dram`: Total amount of DRAM available on this board.

 - `unsigned int supervisorMemory`: Amount of memory available for hosting
   supervisors (see `P_board::sup_offv`).

 - `float costBoardMailbox`: Indicates the cost of communicating with a mailbox
   from this board[^costboardmailbox].

[^costboardmailbox]: This will be superseded when the mailbox connectivity
    across boards is respected (see Future Work section).

 - `unsigned int arcKey`: Placeholder variable to support indexing `P_link`
   objects in `P_board::G`. This begins at zero, and is incremented after each
   new `P_link` is added.

 - `unsigned int portKey`: Placeholder variable to support indexing `P_port`
   objects in `P_board::G`. This begins at zero, and is incremented after each
   new `P_port` is added.

Methods:

 - `P_board::P_board(std::string name)`: Board constructor. This constructor
   sets the `NameBase` name of this Engine, using input argument `name`. This
   constructor also configures callback functions for `P_board::G`. These
   callbacks are used to support `P_board::Dump(FILE*)`, when dumping to a
   particular file. Callback methods are `static void` methods that print
   relevant information about the `P_board`, `P_link`, or node key, or edge
   key, depending on which method is called.

 - `P_board::~P_board()`: Board destructor, see `P_board::clear()`.

 - `void P_board::clear()`: Clears all dynamically-allocated datastructures in
   this board, recursively. This explicitly deletes all `P_link`, `P_port`, and
   `P_mailbox` instances in `P_board::G`. It also clears the graph object and
   `P_board::sup_offv`.

 - `void P_board::contain(AddressComponent addressComponent, P_mailbox*
   mailbox)`: This method inserts `mailbox` as a node in `P_board::G`, with
   `addressComponent` as the index. It also calls
   `mailbox->on_being_contained_hook()` and, if `mailbox` does not have an
   address, this method supplies `mailbox` with a `HardwareAddress` based off
   `addressComponent` and the address of this box. If the mailbox is already
   owned, or if the mailbox is not owned by the board after claiming it, and
   `OwnershipException` is thrown.

 - `void P_board::connect(AddressComponent start, AddressComponent end, float
   weight, bool oneWay=false)`: Creates and inserts a `P_link` instance as an
   arc in `P_board::G`, which connects the boards keyed by the `start` and
   `end` keys in the graph's node map. The `P_link` object is supplied with
   `weight`, which represents the cost of communication over the arc. By
   default, this connection is bidirectional (`oneWay` is used to reduce code
   duplication, as `oneWay=false` causes the method to call itself with
   `oneWay=true` with the `start` and `end `arguments reversed). This method
   throws an `OwnershipException` if either `start` or `end` are not keys in
   the node map of `P_board::G`.

An example dump (`P_board::Dump()`) of a board with sixteen mailboxes connected
in a line with zero-weight arcs follows.

```
P_board O_.Aesop [1 box].Box000000.Board000000 ++++++++++++++++++++++++++++++++
NameBase dump+++++++++++++++++++++++++++++++
this           0x558b5b796400
Name           Board000000
Id                      4(0x00000004)
Parent         0x558b5b796560
Recursion trap Unset
Unique id      3985
NameBase id    Name
 ** No map entries **
NameBase dump-------------------------------

Mailbox connectivity ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Pdigraph topological dump ===================================++++++++++++++++++++
Node index (16 entries):
   1 (0:O_.Aesop [1 box].Box000000.Board000000.Mailbox000000)
  Fanin arcs (1 entries)
     1 ^|2~0.000000|^   -> ((5~0x0000558b5b79cae0))
  Fanout arcs (1 entries)
     1 ((0~0x0000558b5b79c6b0))         -> ^|0~0.000000|^
===

   2 (1:O_.Aesop [1 box].Box000000.Board000000.Mailbox000001)
  Fanin arcs (2 entries)
     1 ^|0~0.000000|^   -> ((1~0x0000558b5b79c700))
     2 ^|4~0.000000|^   -> ((9~0x0000558b5b79cec0))
  Fanout arcs (2 entries)
     1 ((2~0x0000558b5b79c8a0))         -> ^|1~0.000000|^
     2 ((4~0x0000558b5b79ca90))         -> ^|2~0.000000|^
===

   3 (2:O_.Aesop [1 box].Box000000.Board000000.Mailbox000002)
  Fanin arcs (2 entries)
     1 ^|1~0.000000|^   -> ((3~0x0000558b5b79c8f0))
     2 ^|6~0.000000|^   -> ((13~0x0000558b5b79d2a0))
  Fanout arcs (2 entries)
     1 ((6~0x0000558b5b79cc80))         -> ^|3~0.000000|^
     2 ((8~0x0000558b5b79ce70))         -> ^|4~0.000000|^
===

   4 (3:O_.Aesop [1 box].Box000000.Board000000.Mailbox000003)
  Fanin arcs (2 entries)
     1 ^|3~0.000000|^   -> ((7~0x0000558b5b79ccd0))
     2 ^|8~0.000000|^   -> ((17~0x0000558b5b79d680))
  Fanout arcs (2 entries)
     1 ((10~0x0000558b5b79d060))        -> ^|5~0.000000|^
     2 ((12~0x0000558b5b79d250))        -> ^|6~0.000000|^
===

   5 (4:O_.Aesop [1 box].Box000000.Board000000.Mailbox000004)
  Fanin arcs (2 entries)
     1 ^|5~0.000000|^   -> ((11~0x0000558b5b79d0b0))
     2 ^|10~0.000000|^  -> ((21~0x0000558b5b79da60))
  Fanout arcs (2 entries)
     1 ((14~0x0000558b5b79d440))        -> ^|7~0.000000|^
     2 ((16~0x0000558b5b79d630))        -> ^|8~0.000000|^
===

   6 (5:O_.Aesop [1 box].Box000000.Board000000.Mailbox000005)
  Fanin arcs (2 entries)
     1 ^|7~0.000000|^   -> ((15~0x0000558b5b79d490))
     2 ^|12~0.000000|^  -> ((25~0x0000558b5b79de40))
  Fanout arcs (2 entries)
     1 ((18~0x0000558b5b79d820))        -> ^|9~0.000000|^
     2 ((20~0x0000558b5b79da10))        -> ^|10~0.000000|^
===

   7 (6:O_.Aesop [1 box].Box000000.Board000000.Mailbox000006)
  Fanin arcs (2 entries)
     1 ^|9~0.000000|^   -> ((19~0x0000558b5b79d870))
     2 ^|14~0.000000|^  -> ((29~0x0000558b5b79e220))
  Fanout arcs (2 entries)
     1 ((22~0x0000558b5b79dc00))        -> ^|11~0.000000|^
     2 ((24~0x0000558b5b79ddf0))        -> ^|12~0.000000|^
===

   8 (7:O_.Aesop [1 box].Box000000.Board000000.Mailbox000007)
  Fanin arcs (2 entries)
     1 ^|11~0.000000|^  -> ((23~0x0000558b5b79dc50))
     2 ^|16~0.000000|^  -> ((33~0x0000558b5b79e600))
  Fanout arcs (2 entries)
     1 ((26~0x0000558b5b79dfe0))        -> ^|13~0.000000|^
     2 ((28~0x0000558b5b79e1d0))        -> ^|14~0.000000|^
===

   9 (8:O_.Aesop [1 box].Box000000.Board000000.Mailbox000008)
  Fanin arcs (2 entries)
     1 ^|13~0.000000|^  -> ((27~0x0000558b5b79e030))
     2 ^|18~0.000000|^  -> ((37~0x0000558b5b79e9e0))
  Fanout arcs (2 entries)
     1 ((30~0x0000558b5b79e3c0))        -> ^|15~0.000000|^
     2 ((32~0x0000558b5b79e5b0))        -> ^|16~0.000000|^
===

  10 (9:O_.Aesop [1 box].Box000000.Board000000.Mailbox000009)
  Fanin arcs (2 entries)
     1 ^|15~0.000000|^  -> ((31~0x0000558b5b79e410))
     2 ^|20~0.000000|^  -> ((41~0x0000558b5b79edc0))
  Fanout arcs (2 entries)
     1 ((34~0x0000558b5b79e7a0))        -> ^|17~0.000000|^
     2 ((36~0x0000558b5b79e990))        -> ^|18~0.000000|^
===

  11 (10:O_.Aesop [1 box].Box000000.Board000000.Mailbox000010)
  Fanin arcs (2 entries)
     1 ^|17~0.000000|^  -> ((35~0x0000558b5b79e7f0))
     2 ^|22~0.000000|^  -> ((45~0x0000558b5b79f1a0))
  Fanout arcs (2 entries)
     1 ((38~0x0000558b5b79eb80))        -> ^|19~0.000000|^
     2 ((40~0x0000558b5b79ed70))        -> ^|20~0.000000|^
===

  12 (11:O_.Aesop [1 box].Box000000.Board000000.Mailbox000011)
  Fanin arcs (2 entries)
     1 ^|19~0.000000|^  -> ((39~0x0000558b5b79ebd0))
     2 ^|24~0.000000|^  -> ((49~0x0000558b5b79f580))
  Fanout arcs (2 entries)
     1 ((42~0x0000558b5b79ef60))        -> ^|21~0.000000|^
     2 ((44~0x0000558b5b79f150))        -> ^|22~0.000000|^
===

  13 (12:O_.Aesop [1 box].Box000000.Board000000.Mailbox000012)
  Fanin arcs (2 entries)
     1 ^|21~0.000000|^  -> ((43~0x0000558b5b79efb0))
     2 ^|26~0.000000|^  -> ((53~0x0000558b5b79f960))
  Fanout arcs (2 entries)
     1 ((46~0x0000558b5b79f340))        -> ^|23~0.000000|^
     2 ((48~0x0000558b5b79f530))        -> ^|24~0.000000|^
===

  14 (13:O_.Aesop [1 box].Box000000.Board000000.Mailbox000013)
  Fanin arcs (2 entries)
     1 ^|23~0.000000|^  -> ((47~0x0000558b5b79f390))
     2 ^|28~0.000000|^  -> ((57~0x0000558b5b79fd40))
  Fanout arcs (2 entries)
     1 ((50~0x0000558b5b79f720))        -> ^|25~0.000000|^
     2 ((52~0x0000558b5b79f910))        -> ^|26~0.000000|^
===

  15 (14:O_.Aesop [1 box].Box000000.Board000000.Mailbox000014)
  Fanin arcs (2 entries)
     1 ^|25~0.000000|^  -> ((51~0x0000558b5b79f770))
     2 ^|29~0.000000|^  -> ((59~0x0000558b5b79ff30))
  Fanout arcs (2 entries)
     1 ((54~0x0000558b5b79fb00))        -> ^|27~0.000000|^
     2 ((56~0x0000558b5b79fcf0))        -> ^|28~0.000000|^
===

  16 (15:O_.Aesop [1 box].Box000000.Board000000.Mailbox000015)
  Fanin arcs (1 entries)
     1 ^|27~0.000000|^  -> ((55~0x0000558b5b79fb50))
  Fanout arcs (1 entries)
     1 ((58~0x0000558b5b79fee0))        -> ^|29~0.000000|^
===

Arc index (30 entries):
   1 (0~O_.Aesop [1 box].Box000000.Board000000.Mailbox000000)((0~0x0000558b5b79c6b0))   ->
 ^|0~0.000000|^         ->
 ((1~0x0000558b5b79c700))(1~O_.Aesop [1 box].Box000000.Board000000.Mailbox000001)

   2 (1~O_.Aesop [1 box].Box000000.Board000000.Mailbox000001)((2~0x0000558b5b79c8a0))   ->
 ^|1~0.000000|^         ->
 ((3~0x0000558b5b79c8f0))(2~O_.Aesop [1 box].Box000000.Board000000.Mailbox000002)

   3 (1~O_.Aesop [1 box].Box000000.Board000000.Mailbox000001)((4~0x0000558b5b79ca90))   ->
 ^|2~0.000000|^         ->
 ((5~0x0000558b5b79cae0))(0~O_.Aesop [1 box].Box000000.Board000000.Mailbox000000)

   4 (2~O_.Aesop [1 box].Box000000.Board000000.Mailbox000002)((6~0x0000558b5b79cc80))   ->
 ^|3~0.000000|^         ->
 ((7~0x0000558b5b79ccd0))(3~O_.Aesop [1 box].Box000000.Board000000.Mailbox000003)

   5 (2~O_.Aesop [1 box].Box000000.Board000000.Mailbox000002)((8~0x0000558b5b79ce70))   ->
 ^|4~0.000000|^         ->
 ((9~0x0000558b5b79cec0))(1~O_.Aesop [1 box].Box000000.Board000000.Mailbox000001)

   6 (3~O_.Aesop [1 box].Box000000.Board000000.Mailbox000003)((10~0x0000558b5b79d060))  ->
 ^|5~0.000000|^         ->
 ((11~0x0000558b5b79d0b0))(4~O_.Aesop [1 box].Box000000.Board000000.Mailbox000004)

   7 (3~O_.Aesop [1 box].Box000000.Board000000.Mailbox000003)((12~0x0000558b5b79d250))  ->
 ^|6~0.000000|^         ->
 ((13~0x0000558b5b79d2a0))(2~O_.Aesop [1 box].Box000000.Board000000.Mailbox000002)

   8 (4~O_.Aesop [1 box].Box000000.Board000000.Mailbox000004)((14~0x0000558b5b79d440))  ->
 ^|7~0.000000|^         ->
 ((15~0x0000558b5b79d490))(5~O_.Aesop [1 box].Box000000.Board000000.Mailbox000005)

   9 (4~O_.Aesop [1 box].Box000000.Board000000.Mailbox000004)((16~0x0000558b5b79d630))  ->
 ^|8~0.000000|^         ->
 ((17~0x0000558b5b79d680))(3~O_.Aesop [1 box].Box000000.Board000000.Mailbox000003)

  10 (5~O_.Aesop [1 box].Box000000.Board000000.Mailbox000005)((18~0x0000558b5b79d820))  ->
 ^|9~0.000000|^         ->
 ((19~0x0000558b5b79d870))(6~O_.Aesop [1 box].Box000000.Board000000.Mailbox000006)

  11 (5~O_.Aesop [1 box].Box000000.Board000000.Mailbox000005)((20~0x0000558b5b79da10))  ->
 ^|10~0.000000|^        ->
 ((21~0x0000558b5b79da60))(4~O_.Aesop [1 box].Box000000.Board000000.Mailbox000004)

  12 (6~O_.Aesop [1 box].Box000000.Board000000.Mailbox000006)((22~0x0000558b5b79dc00))  ->
 ^|11~0.000000|^        ->
 ((23~0x0000558b5b79dc50))(7~O_.Aesop [1 box].Box000000.Board000000.Mailbox000007)

  13 (6~O_.Aesop [1 box].Box000000.Board000000.Mailbox000006)((24~0x0000558b5b79ddf0))  ->
 ^|12~0.000000|^        ->
 ((25~0x0000558b5b79de40))(5~O_.Aesop [1 box].Box000000.Board000000.Mailbox000005)

  14 (7~O_.Aesop [1 box].Box000000.Board000000.Mailbox000007)((26~0x0000558b5b79dfe0))  ->
 ^|13~0.000000|^        ->
 ((27~0x0000558b5b79e030))(8~O_.Aesop [1 box].Box000000.Board000000.Mailbox000008)

  15 (7~O_.Aesop [1 box].Box000000.Board000000.Mailbox000007)((28~0x0000558b5b79e1d0))  ->
 ^|14~0.000000|^        ->
 ((29~0x0000558b5b79e220))(6~O_.Aesop [1 box].Box000000.Board000000.Mailbox000006)

  16 (8~O_.Aesop [1 box].Box000000.Board000000.Mailbox000008)((30~0x0000558b5b79e3c0))  ->
 ^|15~0.000000|^        ->
 ((31~0x0000558b5b79e410))(9~O_.Aesop [1 box].Box000000.Board000000.Mailbox000009)

  17 (8~O_.Aesop [1 box].Box000000.Board000000.Mailbox000008)((32~0x0000558b5b79e5b0))  ->
 ^|16~0.000000|^        ->
 ((33~0x0000558b5b79e600))(7~O_.Aesop [1 box].Box000000.Board000000.Mailbox000007)

  18 (9~O_.Aesop [1 box].Box000000.Board000000.Mailbox000009)((34~0x0000558b5b79e7a0))  ->
 ^|17~0.000000|^        ->
 ((35~0x0000558b5b79e7f0))(10~O_.Aesop [1 box].Box000000.Board000000.Mailbox000010)

  19 (9~O_.Aesop [1 box].Box000000.Board000000.Mailbox000009)((36~0x0000558b5b79e990))  ->
 ^|18~0.000000|^        ->
 ((37~0x0000558b5b79e9e0))(8~O_.Aesop [1 box].Box000000.Board000000.Mailbox000008)

  20 (10~O_.Aesop [1 box].Box000000.Board000000.Mailbox000010)((38~0x0000558b5b79eb80)) ->
 ^|19~0.000000|^        ->
 ((39~0x0000558b5b79ebd0))(11~O_.Aesop [1 box].Box000000.Board000000.Mailbox000011)

  21 (10~O_.Aesop [1 box].Box000000.Board000000.Mailbox000010)((40~0x0000558b5b79ed70)) ->
 ^|20~0.000000|^        ->
 ((41~0x0000558b5b79edc0))(9~O_.Aesop [1 box].Box000000.Board000000.Mailbox000009)

  22 (11~O_.Aesop [1 box].Box000000.Board000000.Mailbox000011)((42~0x0000558b5b79ef60)) ->
 ^|21~0.000000|^        ->
 ((43~0x0000558b5b79efb0))(12~O_.Aesop [1 box].Box000000.Board000000.Mailbox000012)

  23 (11~O_.Aesop [1 box].Box000000.Board000000.Mailbox000011)((44~0x0000558b5b79f150)) ->
 ^|22~0.000000|^        ->
 ((45~0x0000558b5b79f1a0))(10~O_.Aesop [1 box].Box000000.Board000000.Mailbox000010)

  24 (12~O_.Aesop [1 box].Box000000.Board000000.Mailbox000012)((46~0x0000558b5b79f340)) ->
 ^|23~0.000000|^        ->
 ((47~0x0000558b5b79f390))(13~O_.Aesop [1 box].Box000000.Board000000.Mailbox000013)

  25 (12~O_.Aesop [1 box].Box000000.Board000000.Mailbox000012)((48~0x0000558b5b79f530)) ->
 ^|24~0.000000|^        ->
 ((49~0x0000558b5b79f580))(11~O_.Aesop [1 box].Box000000.Board000000.Mailbox000011)

  26 (13~O_.Aesop [1 box].Box000000.Board000000.Mailbox000013)((50~0x0000558b5b79f720)) ->
 ^|25~0.000000|^        ->
 ((51~0x0000558b5b79f770))(14~O_.Aesop [1 box].Box000000.Board000000.Mailbox000014)

  27 (13~O_.Aesop [1 box].Box000000.Board000000.Mailbox000013)((52~0x0000558b5b79f910)) ->
 ^|26~0.000000|^        ->
 ((53~0x0000558b5b79f960))(12~O_.Aesop [1 box].Box000000.Board000000.Mailbox000012)

  28 (14~O_.Aesop [1 box].Box000000.Board000000.Mailbox000014)((54~0x0000558b5b79fb00)) ->
 ^|27~0.000000|^        ->
 ((55~0x0000558b5b79fb50))(15~O_.Aesop [1 box].Box000000.Board000000.Mailbox000015)

  29 (14~O_.Aesop [1 box].Box000000.Board000000.Mailbox000014)((56~0x0000558b5b79fcf0)) ->
 ^|28~0.000000|^        ->
 ((57~0x0000558b5b79fd40))(13~O_.Aesop [1 box].Box000000.Board000000.Mailbox000013)

  30 (15~O_.Aesop [1 box].Box000000.Board000000.Mailbox000015)((58~0x0000558b5b79fee0)) ->
 ^|29~0.000000|^        ->
 ((59~0x0000558b5b79ff30))(14~O_.Aesop [1 box].Box000000.Board000000.Mailbox000014)

Pdigraph topological dump ===================================--------------------
Mailbox connectivity ----------------------------------------------------------
Mailboxes in this board +++++++++++++++++++++++++++++++++++++++++++++++++++++++
        <a recursive dump of all mailboxes in this board goes here>
Mailboxes in this board -------------------------------------------------------
P_board O_.Aesop [1 box].Box000000.Board000000 --------------------------------

```

## P_mailbox
`P_mailbox` represents a mailbox in a compute FPGA board as part of an Engine.

Members:

 - `P_board* parent`: Defines a board as this mailbox's logical parent. This is
   defined when this mailbox is contained.

 - `std::map<AddressComponent, P_core*> P_corem`: Data structure that holds all
   cores serviced by this mailbox. Cores are indexed by the core component
   ($C_{\mathrm{CORE}}$) of their hardware address. Since the communication
   between cores is brokered by the mailbox, there is no explicit core-to-core
   link; each core is considered equidistant from each other core serviced by
   this mailbox.

 - `float costCoreCore`: Indicates the cost of communicating between cores
   serviced by this mailbox.

 - `float costMailboxCore`: Indicates the cost of communicating to the mailbox
   level from any of the cores, and the reverse.

Methods:

 - `P_mailbox::P_mailbox(std::string name)`: Mailbox constructor, sets the
   `NameBase` name using the input argument `name`.

 - `P_mailbox::~P_mailbox()`: Mailbox destructor, see `P_mailbox::clear()`.

 - `void P_mailbox::clear()`: Deletes all `P_core` objects pointed to by
   `P_corem`, and clears `P_corem`.

 - `void P_mailbox::contain(AddressComponent addressComponent, P_core* core)`:
   If the core `core` is not owned by another mailbox, this method adds `core`
   to `P_mailbox::P_corem`. It also calls `core->on_being_contained_hook()`
   and, if `core` does not have an address, this method supplies `core` with a
   `HardwareAddress` based off the `addressComponent` and the address of this
   mailbox. If the core is already owned, or if the core is not owned by the
   mailbox after claiming it, and `OwnershipException` is thrown.

 - `void P_mailbox::on_being_contained_hook(P_board* container)`: Sets the
   parent of this mailbox to the board containing it.

An example dump (`P_mailbox::Dump()`) of a mailbox follows.

```
P_mailbox O_.Aesop [1 box].Box000000.Board000000.Mailbox000000 ++++++++++++++++
NameBase dump+++++++++++++++++++++++++++++++
this           0x558b5b79a740
Name           Mailbox000000
Id                     19(0x00000013)
Parent         0x558b5b796400
Recursion trap Unset
Unique id      3985
NameBase id    Name
 ** No map entries **
NameBase dump-------------------------------

Cores in this mailbox +++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        <a recursive dump of all cores in this mailbox goes here>
Cores in this mailbox ---------------------------------------------------------
P_mailbox O_.Aesop [1 box].Box000000.Board000000.Mailbox000000 ----------------
```

## P_core
`P_core` represents a core in the Engine. In the Mothership, `P_core` holds
binary data (to be)/deployed to each core.

Members:

 - `P_mailbox* parent`: Defines a mailbox as this core's logical parent. This
   is defined when this core is contained.

 - `std::map<AddressComponent, P_thread*> P_threadm`: Data structure that holds
   all threads that can be run by this core. Threads are indexed by the thread
   component ($C_{\mathrm{THREAD}}$) of their hardware address.

 - `Bin* dataBinary`: Holds a data binary (to be)/deployed to this core.

 - `Bin* instructionBinary`: Holds an instruction binary (to be)/deployed to
   this core.

 - `unsigned int dataMemory`: Amount of memory available for a data binary.

 - `unsigned int instructionMemory`: Amount of memory available for an
   instruction binary.

 - `float costCoreThread`: Indicates the cost of communicating to the core
   level from any of the threads, and the reverse (will typically be
   negligible).

 - `float costThreadThread`: Indicates the cost of communicating between
   threads run on this core.

Methods:

 - `P_core::P_core(std::string name)`: Core constructor, sets the `NameBase`
   name using the input argument `name`. Also dynamically initialises
   `dataBinary` and `instructionBinary` with empty `Bin` objects.

 - `P_core::~P_core()`: Core destructor, see `P_core::clear()`.

 - `void P_core::clear()`: Deletes all `P_thread` objects pointed to by
   `P_threadm`, clears `P_threadm`, and calls `P_core::clear_binaries`.

 - `void P_core::clear_binaries()`: Deletes the dynamically-allocated binaries
   in an idempotent manner.

 - `void P_core::contain(AddressComponent addressComponent, P_thread* thread)`:
   If the thread `thread` is not owned by another core, this method adds
   `thread` to `P_core::P_threadm`. It also calls
   `thread->on_being_contained_hook()` and, if `thread` does not have an
   address, this method supplies `thread` with a `HardwareAddress` based off
   the `addressComponent` and the address of this core. If the thread is
   already owned, or if the thread is not owned by the core after claiming it,
   and `OwnershipException` is thrown.

 - `void P_core::on_being_contained_hook(P_mailbox* container)`: Sets the
   parent of this core to the mailbox containing it.

An example dump (`P_core::Dump()`) of a core with no binary data follows.

```
P_core O_.Aesop [1 box].Box000000.Board000000.Mailbox000000.Core000000 ++++++++
NameBase dump+++++++++++++++++++++++++++++++
this           0x55769be87a40
Name           Core000000
Id                    149(0x00000095)
Parent         0x55769be7c420
Recursion trap Unset
Unique id      3797
NameBase id    Name
 ** No map entries **
NameBase dump-------------------------------

No data binary assigned to this core.
No instruction binary assigned to this core.
Threads in this core ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        <a recursive dump of all threads in this core goes here>
Threads in this core ----------------------------------------------------------
P_core O_.Aesop [1 box].Box000000.Board000000.Mailbox000000.Core000000 --------
```

## P_thread
`P_thread` represents a thread running on a core in the Engine.

Members:

 - `P_core* parent`: Defines a core as this thread's logical parent. This is
   defined when this thread is contained.

 - `std::list<P_device*> P_devicel`: Data structure that holds devices assigned
   to work on this thread. This is populated when a task is placed onto the
   hardware model. This is not populated using the containment mechanism.

 - `unsigned int dataMemoryAddress`: Address of the start of the data memory
   segment used by this thread, with respect to the host core.

 - `unsigned int instructionMemoryAddress`: Address of the start of the
   instruction memory segment used by this thread, with respect to the host
   core.

Methods:

 - `P_thread::P_thread(std::string name)`: Thread constructor, sets the
   `NameBase` name using the input argument `name`.

 - `void P_thread::on_being_contained_hook(P_core* container)`: Sets the parent
   of this thread to the core running it.

An example dump (`P_thread::Dump()`) of a thread with no devices follows. If a
thread has devices, "The device map is empty" is replaced with a recursive dump
of all devices in the thread.

```
P_thread O_.Aesop [1 box].Box000000.Board000000.Mailbox000000.Core000000.Thread000000 +
NameBase dump+++++++++++++++++++++++++++++++
this           0x55769be76b00
Name           Thread000000
Id                    725(0x000002d5)
Parent         0x55769be87a40
Recursion trap Unset
Unique id      3797
NameBase id    Name
 ** No map entries **
 NameBase dump-------------------------------

Devices in this thread ++++++++++++++++++++++++++++++++++++++++++++++++++++++++
The device map is empty.
Devices in this thread --------------------------------------------------------
```

## P_link
`P_link` objects represent the connections between boards in the board graph
`P_engine::G`, and the connections between mailboxes in the mailbox graphs
`P_board::G`. Links hold edge weights, which can be used by the placement
method to determine the optimal position for application devices in the POETS
Engine.

Members:

 - `float weight`: Defines the cost of communicating over the edge marked by
   this `P_link`.

Methods:

 - `P_link::P_link(float weight)`: Constructor, sets `weight`.

 - `P_link::P_link(float weight, NameBase* parent)`: Constructor, sets `weight`
   and a `NameBase` parent using the input argument `name` (`P_link`s are
   typically autonamed).

An example dump (`P_link::Dump()`) follows.

```
P_link O_._3986 +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Edge weight: 5.000000
NameBase dump+++++++++++++++++++++++++++++++
this           0x556e6c7bdf90
Name           _3986
Id                   3986(0x00000f92)
Parent         0x556e6c79ecc0
Recursion trap Unset
Unique id      3986
NameBase id    Name
 ** No map entries **
NameBase dump-------------------------------

P_link O_._3986 ---------------------------------------------------------------
```

## P_port
`P_port` objects represent placeholder pin objects in the board graph
`P_engine::G` and in the mailbox graphs `P_board::G`. `P_port` objects are
largely stubs, but will become useful when trying to unify `P_engine::G` and
`P_board::G` for placement. `P_port` has no members.

Methods:

 - `P_port::P_port()`: Empty constructor.

 - `P_port::P_port(NameBase* parent)`: Constructor, sets a `NameBase` parent
   using the input argument `parent`, and autonames this `P_port`.

An example dump (`P_port::Dump()`) follows.

```
P_port O_._3987 +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
NameBase dump+++++++++++++++++++++++++++++++
this           0x556e6c7bdf90
Name           _3987
Id                   3987(0x00000f93)
Parent         0x556e6c79ecc0
Recursion trap Unset
Unique id      3987
NameBase id    Name
 ** No map entries **
 NameBase dump-------------------------------

P_port O_._3987 ---------------------------------------------------------------
```

## HardwareAddress
`HardwareAddress` represents the hardware address of an `AddressableItem` (a
box, or a board, etc.) in the Engine hierarchy. The `HardwareAddress` stores
the components of the addresses as defined in the Addressing Hardware section,
as well as information on which components have been defined, and how to
produce the address as a 32-bit unsigned.

Note that `HardwareAddressInt` is a `uint32_t`, like `AddressComponent`.

Members:

 - `HardwareAddressFormat* format`: Points to the hardware address format
   instance used to define address spacings. A `P_engine` contains a
   `HardwareAddressFormat`, which is applied to the `HardwareAddress` object
   held by each item in the Engine. The hardware address format is used to hold
   the spacing between each component in the hardware address, so that the
   32-bit unsigned address can be computed.

 - `AddressComponent boxComponent`: Holds the box component of this hardware
   address.

 - `AddressComponent boardComponent`: Holds the board component of this
   hardware address.

 - `AddressComponent mailboxComponent`: Holds the mailbox component of this
   hardware address.

 - `AddressComponent coreComponent`: Holds the core component of this hardware
   address.

 - `AddressComponent threadComponent`: Holds the thread component of this
   hardware address.

 - `unsigned definitions`: Holds information on which components have been
   defined, where each bit represents a different component. If all five bits
   are `1`, then all components of the address have been defined. Is
   initialised to `0` in the constructor.

Methods:

 - `HardwareAddress::HardwareAddress(HardwareAddressFormat* format,
   AddressComponent boxComponent, AddressComponent boardComponent,
   AddressComponent mailboxComponent, AddressComponent coreComponent,
   AddressComponent threadComponent)`: Constructor, defines each component of
   the constructed address, and defines the address format.

 - `HardwareAddress::HardwareAddress(HardwareAddressFormat* format)`:
   Constructor, only defines the address format, and none of the components of
   the address.

 - `HardwareAddressInt HardwareAddress::as_uint()`: Synonym of
   `get_hardware_address()`.

 - `AddressComponent HardwareAddress::get_box()`: Returns the box component of
   the address.

 - `AddressComponent HardwareAddress::get_board()`: Returns the board component
   of the address.

 - `AddressComponent HardwareAddress::get_mailbox()`: Returns the mailbox
   component of the address.

 - `AddressComponent HardwareAddress::get_core()`: Returns the core component
   of the address.

 - `AddressComponent HardwareAddress::get_thread()`: Returns the thread
   component of the address.

 - `void HardwareAddress::set_box(AddressComponent value)`: Defines the box
   component of the address, throwing an `InvalidAddressException` if the
   component does not fit the format defined by `HardwareAddress::format`.

 - `void HardwareAddress::set_board(AddressComponent value)`: Defines the board
   component of the address, throwing an `InvalidAddressException` if the
   component does not fit the format defined by `HardwareAddress::format`.

 - `void HardwareAddress::set_mailbox(AddressComponent value)`: Defines the
   mailbox component of the address, throwing an `InvalidAddressException` if
   the component does not fit the format defined by `HardwareAddress::format`.

 - `void HardwareAddress::set_core(AddressComponent value)`: Defines the core
   component of the address, throwing an `InvalidAddressException` if the
   component does not fit the format defined by `HardwareAddress::format`.

 - `void HardwareAddress::set_thread(AddressComponent value)`: Defines the
   thread component of the address, throwing an `InvalidAddressException` if
   the component does not fit the format defined by `HardwareAddress::format`.

 - `HardwareAddressInt HardwareAddress::get_hardware_address()`: Computes and
   returns the hardware address using the components and
   `HardwareAddress::format`.

 - `void HardwareAddress::populate_a_software_address(P_addr* target, bool
   resetFirst)`: Defines the `P_addr` at `target` using the components of this
   `HardwareAddress`, optionally resetting it first. This exists as a means for
   the hardware model to interface with other components of the
   Orchestrator. With my design hat on, I plan to remove `P_addr` in the long
   term wherever it is used. However, since the source is tightly coupled to
   it, providing a translation method is the next-best thing.

 - `void HardwareAddress::populate_from_software_address(P_addr* source)`:
   Component-wise definition of this `HardwareAddress` from the `P_addr` at
   `source`. Only defines the components of this `HardwareAddress` if they are
   defined in `source` also. Note that, since this calls `set_box`, `set_board`
   etc, it will propagate exceptions thrown from those methods.

 - `bool HardwareAddress::is_fully_defined()`: Returns `true` if each component
   in this `HardwareAddress` has been defined, and `false` otherwise.

 - `bool HardwareAddress::is_box_defined()`: Returns `true` if the box
   component in this `HardwareAddress` has been defined, and `false` otherwise.

 - `bool HardwareAddress::is_board_defined()`: Returns `true` if the board
   component in this `HardwareAddress` has been defined, and `false` otherwise.

 - `bool HardwareAddress::is_mailbox_defined()`: Returns `true` if the mailbox
   component in this `HardwareAddress` has been defined, and `false` otherwise.

 - `bool HardwareAddress::is_core_defined()`: Returns `true` if the core
   component in this `HardwareAddress` has been defined, and `false` otherwise.

 - `bool HardwareAddress::is_thread_defined()`: Returns `true` if the thread
   component in this `HardwareAddress` has been defined, and `false` otherwise.

 - `void HardwareAddress::set_defined()`: A convenience method for defining
   individual bits of `HardwareAddress::definitions`.

An example dump (`HardwareAddress::Dump()`) follows.

```
Hardware address at 0x00007ffe680218a0 ++++++++++++++++++++++++++++++++++++++++
boxComponent:     0
boardComponent:   2
mailboxComponent: 8
coreComponent:    14
threadComponent:  0 (not defined)
Hardware address at 0x00007ffe680218a0 ----------------------------------------
```

## HardwareAddressFormat
`HardwareAddressFormat` objects simply hold the word-lengths of each component
of the hardware address for this Engine. These lengths allow an address to be
"reconstituted" into an unsigned (Tinsel-speak).

Methods:

 - `HardwareAddressFormat::HardwareAddressFormat(unsigned boxWordLength,
   unsigned boardWordLength, unsigned mailboxWordLength, unsigned
   coreWordLength, unsigned threadWordLength)`: Constructs a format with
   defined word lengths.

 - `HardwareAddressFormat::HardwareAddressFormat()`: Constructs a format
   without any word lengths defined. You won't want to use a
   `HardwareAddressFormat` constructed in this way without populating it,
   unless you're trying to make the Orchestrator fall over (you could pass it
   to a `Dialect1Deployer` for example, which would do that job for you).

Members:

 - `unsigned boxWordLength`: Defines the number of bits dedicated to
   representing the box component of the hardware address.

 - `unsigned boardWordLength`: Defines the number of bits dedicated to
   representing the board component of the hardware address.

 - `unsigned mailboxWordLength`: Defines the number of bits dedicated to
   representing the mailbox component of the hardware address.

 - `unsigned coreWordLength`: Defines the number of bits dedicated to
   representing the core component of the hardware address.

 - `unsigned threadWordLength`: Defines the number of bits dedicated to
   representing the thread component of the hardware address.

An example dump (`HardwareAddressFormat::Dump()`) follows.

```
Hardware address format at 0x00007fffb1af6cc0 +++++++++++++++++++++++++++++++++
boxWordLength:     4
boardWordLength:   5
mailboxWordLength: 6
coreWordLength:    8
threadWordLength:  9
Hardware address format at 0x00007fffb1af6cc0 ---------------------------------
```

## AddressableItem
`AddressableItem` encapsulates the behaviours of items (`P_box`, `P_board`,
`P_mailbox`, `P_core`, or `P_thread`) relating to addressing.

Members:

 - `HardwareAddress* hardwareAddress`: Holds the hardware address.

 - `bool isAddressBound`: Is `false` if no address has been bound to this
   `AddressableItem`, and `true` otherwise.

Methods:

 - `AddressableItem::AddressableItem()`: Constructor (obviously).

 - `AddressableItem::~AddressableItem()`: Destructor, deletes any hardware
   address that hass been assigned to this item (see
   `AddressableItem::set_hardware_address`).

 - `HardwareAddress* AddressableItem::copy_hardware_address()`: Convenience
   method to dynamically create a copy of the `hardwareAddress` owned by this
   `AddressableItem` using copy construction.

 - `HardwareAddress* AddressableItem::get_hardware_address()`: Returns
   `hardwareAddress`.

 - `void AddressableItem::set_hardware_address(HardwareAddress* value)`: Binds
   `hardwareAddress` to `value`, and updates `isAddressBound`. Note that the
   `HardwareAddress` at `value` will be deleted when this `AddressableItem` is
   constructed, so the memory behind `value` should be allocated dynamically
   before passing it here.

No dump method is defined for `AddressableItem` objects; each object that
inherits from `AddressableItem` defines its own `Dump` method.

## HardwareFileParser
`HardwareFileParser` reads hardware description input files. Using the
information in one of these files, `HardwareFileParser` creates and provisions
a deployer object, which in turn is used to provision a `P_engine`. This class
inherits from `JNJ`, and hence `UIF` (both in `Generics`), which
`HardwareFileParser` uses for file parsing and holding the data from the input
file.

Members:

 - `bool isFileLoaded`: Is `true` if a hardware file has been loaded by this
   `HardwareFileParser`, and `false` otherwise. You can't provision a deployer
   without first loading a file.

 - `std::string loadedFile`: Path to the file loaded, or empty if no file is
   loaded.

Methods:

 - `HardwareFileParser::HardwareFileParser()`: Constructor, calls
   `set_uif_error_callback`.

 - `HardwareFileParser::HardwareFileParser(const char* filePath, P_engine*
   engine)`: Convenience constructor. While also setting the syntax error
   callback method as described above, this constructor also reads the hardware
   input file at `filePath`, and uses it to provision `engine`.

 - `void HardwareFileParser::load_file(const char* filePath)`: Given that the
   file at `filePath` exists, this method reads the file using `UIF`, and
   generates the `JNJ` data structure. Throws a `HardwareFileNotFoundException`
   if the file does not exist, or throws a `HardwareSyntaxException` (from
   `on_syntax_error`) if the input file contains a syntax error. This method
   does not throw anything in the event of a semantic error.

 - `void HardwareFileParser::populate_hardware_model(P_engine* engine)`: Given
   that a file has been loaded, this method creates and provisions a deployer,
   and uses it to populate `engine`. This method performs some semantic
   validation (using `validate_sections` and `provision_deployer`), throwing a
   `HardwareSemanticException` if one or more is found.

 - `bool HardwareFileParser::does_file_exist(const char* filePath)`: Returns
   `true` if a file exists at `filePath`, and `false` otherwise.

 - `void HardwareFileParser::set_uif_error_callback()`: Sets a callback method
   (`on_syntax_error`) to be called by `UIF` when a syntax error is encountered
   in an input file.

 - `static void HardwareFileParser::on_syntax_error(void* parser, void*
   uifInstance, int)`: Throws a `HardwareSyntaxException` using error
   information from `parser` and `uifInstance` (both of which are normally this
   `HardwareFileParser`).

 - `bool HardwareFileParser::validate_sections(std::string* errorMessage)`:
   Validates that each mandatory section exists, and that there are no
   duplicated sections. Appends any errors found to `errorMessage`. Returns
   `false` if any errors were found, and `true` otherwise.

 - `bool provision_deployer(Dialect1Deployer* deployer, std::string*
   errorMessage)`: Provisions `deployer` with the configuration stored in this
   parser from reading a file through a big nested set of cases. Performs
   type-checking and simple semantic validation on each field, appending any
   errors found to `errorMessage`. Returns `false` if any errors were found,
   and `true` otherwise.

 - `bool is_value_at_node_natural(UIF::Node* recordNode, UIF::Node* valueNode,
   std::string variable, std::string value, std::string sectionName,
   std::string* errorMessage)`: Returns `true` if the value at `valueNode` is a
   natural number (including zero), and `false` otherwise. The other input
   arguments are used to construct an error message if appropriate, which is
   appended to `errorMessage`.

 - `bool is_value_at_node_floating(UIF::Node* recordNode, UIF::Node* valueNode,
   std::string variable, std::string value, std::string sectionName,
   std::string* errorMessage)`: Returns `true` if the value at `valueNode` is a
   floating-point number, and `false` otherwise. The other input arguments are
   used to construct an error message if appropriate, which is appended to
   `errorMessage`.

 - `bool are_values_at_node_natural(UIF::Node* recordNode, UIF::Node*
   valueNode, std::string variable, std::string value, std::string sectionName,
   std::string* errorMessage)`: Returns `true` if the multi-valued node
   `valueNode` contains only natural numbers (including zero), and `false`
   otherwise. The other input arguments are used to construct an error message
   if appropriate, which is appended to `errorMessage`.

 - `void invalid_variable_message(std::string* errorMessage, UIF::Node*
   recordNode, std::string sectionName, std::string variable)`: Appends a
   passive-aggressive error message to `errorMessage` explaining that the
   variable name `variable` in section `sectionName` is not recognised by the
   parser. `recordNode` is used to obtain the line number for the error
   message.

No dump method is defined for `HardwareFileParser` objects. It doesn't hold
much state, and the `JNJ` data structure is better understood by interrogating
the deployer.

## I haven't written up these source definitions yet <!>
 - Dialect1Deployer
 - AesopDeployer
 - MultiAesopDeployer
 - HardwareIterator

An example dump (`HardwareIterator::Dump()`) of a newly-initialised iterator
follows.

```
Engine000.Iterator ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
NameBase dump+++++++++++++++++++++++++++++++
this           0x7ffe4ec4de10
Name           Iterator
Id                    216(0x000000d8)
Parent         0x7ffe4ec4deb0
Recursion trap Unset
Unique id      216
NameBase id    Name
 ** No map entries **
NameBase dump-------------------------------

Current board memory address:     0x000056352e245330
Current board hardware address:   0
Current mailbox memory address:   0x000056352e248cd0
Current mailbox hardware address: 0
Current core memory address:      0x000056352e2486c0
Current core hardware address:    0
Current thread memory address:    0x000056352e248810
Current thread hardware address:  0
The board has not changed since "has_board_changed" was last called.
The mailbox has not changed since "has_mailbox_changed" was last called.
The core has not changed since "has_core_changed" was last called.
The thread has not changed since "has_thread_changed" was last called.
This iterator has not wrapped.
Engine000.Iterator ------------------------------------------------------------
```

# Appendix B: Input file format (0.3.2)
This Appendix defines the file format used by the Orchestrator to define its
internal model of the POETS Engine. Elements of this format are not yet
supported in the Orchestrator's hardware model; see the Future Work section.

The input files satisfy the general "Universal Interface Format" (UIF) file
format[^uifdocs]. The format supports three dialects, which define the POETS
Engine on different levels of granularity. The complete Orchestrator will be
able to parse a file defined using any one of these three dialects. When the
Orchestrator completes a "discovery" operation or when it otherwise dumps a
machine-readable output of its model of the POETS Engine, that dump will be
given in the most precise dialect version (dialect 3). This Appendix defines
attributes that are common to all dialects in the Common Attributes Section,
then defines:

[^uifdocs]: The UIF documentation can be found in the Orchestrator repository,
    in the `Generics` directory.

 - Dialect 1, where items at each level of the hierarchy are the same as other
   items at that level ("horizontally homogeneous"), and where some topology
   information is assumed.

 - Dialect 2, which is as dialect 1, but allows the items contained at each
   level to vary ("horizontally heterogeneous"). For example, boxes can contain
   different numbers of boards, but must have the same properties
   otherwise. Topology is also explicitly defined in this dialect, but is
   constant at each level of the hierarchy.

 - Dialect 3, which is as dialect 2, but allows items within a level to vary
   using a type mechanism ("fully heterogeneous"), so that they can hold
   different topologies of items, and have different properties from other
   items on their level of the hierarchy.

Greater dialects provide more flexibility at the expense of being more
difficult to generate.

## Common Attributes

Input files must be ASCII encoded.

### Comment Syntax
All dialects support a comment syntax:

```
// All dialects support this comment syntax, where all text after
// two consecutive forward slash symbols (//) on a line must be
// ignored by the parser. Comments cannot be escaped. I'll be using
// comments throughout these snippets, appropriately, to describe
// implementation details and intentions.

// Also note that empty lines do not affect file parsing, though
// whitespace within a non-comment line matters.
```

### Header Section
All dialects support sections, which contain variable definitions. Sections can
appear in any order, but must be unique within a file. All files must contain a
`[header]` section. For example:
```
[header]  // This is a header section (with an inline comment).
+author="Mark Vousden"
+dialect=1
+datetime=20181008130324  // YYYYMMDDhhmmss
+version="0.3.2"
+file="my_first_example.txt"
```

Points to note:

 - The line `+author="Mark Vousden"` is a variable definition; specifically
   binding the value `Mark Vousden` as a string to the `author` variable in
   the `[header]` section. Note that the `+` symbol at the prefix of the
   definition shows that a binding is taking place. Values cannot contain two
   consecutive `/` characters or `"` characters.

 - The `[header]` section is mandatory, and must define the following variables
    (in any order):

   - `datetime`: Creation time of this file, in ISO8601 "basic datetime" format
     (YYYYMMDDhhmmss), without timezone information.

   - `dialect`: The index of the dialect, either 1, 2, or 3.

   - `version`: The version of the file format (which you can extract from this
     example). Must be Semantic Versioning 2.0.0 compatible.

 - The following variables may optionally be defined:

   - `author`: The name of the individual who has created this file, in
     straight double quotes.

   - `hardware`: The version of hardware used to generate this file.

   - `file`: The handle of the file in the filesystem[^fileMismatchWarning].

 - The `[header]` section may be opened with a description,
   e.g. `[header(Hafez)]` (where the description here is `Hafez`), as long
   as the description satisfies the regular expression `[a-zA-Z0-9]{2,32}`, and
   that only one header section is defined in a given file.

[^fileMismatchWarning]: The design intent being that the Orchestrator will warn
the operator if this field match the name of the file passed in.

### Address Format Section
All dialects define a format for how the POETS Engine addresses threads in the
hardware, so that the Orchestrator and the POETS Engine can interface. Each
thread in the POETS Engine is uniquely addressed by a binary word, where
different slices of the word correspond to different regions of the POETS
Engine hierarchy. These slices are defined in the `[packet_address_format]`
section, for example:

```
[packet_address_format]
+mailbox=8
+thread=4
+core=2
+board=4
+box=2
```

Points to note:

 - The `[packet_address_format]` section is mandatory, and must define the
   following variables (in any order):

   - `board`: The number of bits dedicated to defining the board-component of
     the address in the address word. Must be a positive integer.

   - `box`: As with `board`, but for boxes.

   - `core`: As with `board`, but for cores.

   - `mailbox`: As with `board`, but for mailboxes.

   - `thread`: As with `board`, but for threads.

 - In this contrived example, the address is defined as a binary word, where
   the first (LSB) four bits define the thread address, the next two bits
   define the core address, the next eight bits define the mailbox address, the
   next four bits define the board address, and the next two bits define the
   box address, resulting in a $4+2+8+4+2=20$ bit word.

 - In order for the Orchestrator to generate a POETS Engine file during the
   discovery process, it will need to query the hardware to identify the format
   of the address word through some API.

A further complexity of addressing in the POETS Engine is that, at a given
non-thread, non-core level of the hierarchy, the ID of an item at that level of
the hierarchy may not be contiguous within that section of the word. By way of
example, a two-dimensional arrangement of mailboxes may divide the first half
of the mailbox word for the "horizontal" axis, and the second half for the
"vertical" axis, so that spatially-local mailboxes may have significantly
different address words. To support such "multidimensional" words, the
`[packet_address_format]` section supports the following syntax:

```
[packet_address_format]
+box=2  // The order of variable definitions within the section does
        // not matter.
+mailbox=(2,2,2)  // Three dimensions (can be one or more dimensions)
+thread=4  // Must be one-dimensional, always.
+core=2  // Must be one-dimensional, always.
+board=(4,4)  // Two dimensions (can be one or more dimensions)
```

Here, the address again defined as a binary word, where the first (LSB) four
bits define the thread address, the next two bits define the core address, the
next six bits define the mailbox address (two in each of the three dimensions),
the next eight bits define the board address (four in each of the two
dimensions), and the next two bits define the box address, resulting in a
$4+2+(2\times3)+(4\times2)+2+2=24$ bit word.

## Dialect 1 (Homogeneous)
This dialect allows the writer to elegantly define the components of the POETS
Engine, without the flexibility of the other dialects. It makes the assumptions
about the constituents of the POETS Engine and their connectivity,
specifically:

 - Each item is the same as each other item on its level of the hierarchy
   (i.e. each box has the same properties as each other box, and contains the
   same number of boards).

 - Items are either connected to all other items on their level of the
   hierarchy, or are connected in a hypercube topology.

A defining example follows:

```
// A simple example showcasing the features of dialect 1.
[header]
+author="Mark Vousden"
+dialect=1
+datetime=20181008130324
+version="0.3.2"

[packet_address_format]
+mailbox=(4,4)
+thread=4
+core=2
+board=4
+box=2

[engine]
// Number of boxes in this POETS Engine. Positive integer.
+boxes=2
// Number of compute FPGA boards in this POETS Engine. Positive
// integer or "hypercube". The total number of boards must divide
// into the number of boxes without remainder.
+boards=6
// Relative cost of communication for devices entering the POETS
// Engine externally. Can be a float.
+external_box_cost=50
// Relative cost of sending a packet from one board to any other
// board in a box. Can be a float.
+board_board_cost=5

[box]
// Relative cost of sending a packet "into" a board. Can be a
// float.
+box_board_cost=11
// Amount of memory available to a supervisor process on this box
// (MiB). Non-negative integer.
+supervisor_memory=4096

[board]
// Number of mailboxes in each compute FPGA. Positive integer or
// "hypercube".
+mailboxes=hypercube(+10,10)
// Relative cost of sending a packet "into" a mailbox. Can be a
// float.
+board_mailbox_cost=2
// Amount of memory available to a supervisor process on this board
// (MiB). Non-negative integer.
+supervisor_memory=0
// Relative cost of sending a packet from one mailbox to any other
// mailbox in a board. Can be a float.
+mailbox_mailbox_cost=1
// Amount of DRAM available, total (MiB). Positive integer.
+dram=4096

[mailbox]
// Number of cores in each mailbox. Positive integer.
+cores=4
// Relative cost of sending a packet "into" a core. Can be a float.
+mailbox_core_cost=0.2
// Relative cost of sending a packet from one core to any other
// core in a box. Can be a float.
+core_core_cost=0.1

[core]
// Number of threads running on a core. Positive integer.
+threads=16
// Available instruction memory (KiB). Positive integer.
+instruction_memory=512
// Available data memory (KiB). Positive integer.
+data_memory=512
// Relative cost of sending a packet from one thread to any other
// thread in a core. Can be a float.
+thread_thread_cost=0.002
// Relative cost of sending a packet "into" a thread. Can be a
// float.
+core_thread_cost=0.002
```

Note:

 - The `[engine]`, `[box]`, `[board]`, `[mailbox]`, and `[core]` sections and
   their contents are all mandatory.

 - The various `X_X_cost`-s (e.g. `board_board_cost`) are used to define the
   graph objects in the internal model.

 - Use of the `hypercube` directive in the definition of boards or mailboxes
   (for example, the line `+mailboxes=hypercube(+10,10)` in the `[board]`
   section) results in:

   - A hypercube topology (in this case, a $10\times10$ grid) being used
     instead of an "all-to-all" topology. Items are addressed in sequence along
     each dimension.

   - In this case, the boundary in the first dimension is periodic, as
     indicated by the first `+` character before the value in the first
     dimension of the hypercube. The boundary in the second dimension is open
     in this case (for both dimensions to be periodic, the definition must be
     `+mailboxes=hypercube(+10,+10)`). Items connected in this way are not
     addressed in sequence across periodic boundaries (addresses wrap around).

   - The definition of `X_X_cost`-like variables still parameterise the cost of
     sending a packet between neighbours.

 - The values in the `[packet_address_format]` section for a given variable
   must fit the number of items defined in the appropriate section. For
   example, `+thread=4` in the `[packet_address_format]` section, so
   the number of threads (`+threads` in the `[core]` section) must be
   $\le2^4=16$, which is satisfied in this example.

 - If a value in the `[packet_address_format]` section is multidimensional,
   such as `+mailbox=(4,4)` in this example, then the item definition for that
   value (`+mailboxes=hypercube(+10,10)` in the `board` section, again for this
   example) must be a hypercube of the same dimension, and each dimension of
   the item definition must "fit" in the corresponding dimension of the address
   format[^addressFitting].

[^addressFitting]: Informally, if the values of `+mailbox` define vector
$\mathbf{x}\in\mathbb{N}^n$, then if the arguments of the hypercube directive
of `+mailboxes` define vector $\mathbf{y}$, then $\mathbf{y}\in\mathbb{N}^n$,
and $\mathbf{y}\cdot\mathbf{\hat{e}}_m\le
2^{\mathbf{x}\cdot\mathbf{\hat{e}}_m}$ for each unit basis vector
$\mathbf{\hat{e}}_m$.

Appendix C contains a complete dialect 1 example file representing Coleridge.

## Dialect 2 (Horizontally-Heterogeneous)
Dialect 2 extends dialect 1 by supporting heterogeneity on each level of the
hierarchy. While each box must still be the same as each other box (and each
board the same as each other board, and so on), dialect 2 allows the writer to
define simple weighted graph topologies to contain these items. Relative to
dialect 1, dialect 2 removes support for the following definitions:

```
[engine]
boxes
boards
[board]
mailboxes
```

Instead of defining the constituents (number of items) by defining these
variables, dialect 2 mandates that the writer define the topology
explicitly. Note that the following definitions are still supported:

```
[mailbox]
cores
[core]
thread
```

These definitions remain because all cores and threads are still the same as
all other cores and threads in this dialect, so a count is still a meaningful
representation for them. Dialect 2 also mandates the use of the
`[engine_board]` section to store the simple weighted graph of boards in the
engine, and the `[engine_box]` section for the other engine properties. Also,
the `board_board_cost` variable must now be defined in the `[engine_board]`
section. Here are example `[engine_box]` and `[engine_board]` sections for
dialect 2, where the `→` character denotes a line continuation:

```
[engine_box]
// Define four boxes, each with two boards:
(0,0):Io(addr(00),boards(B0,B1))
(1,0):Europa(addr(10),boards(B0,B1))
(0,1):Ganymede(addr(01),boards(B0,B1))
(1,1):Callisto(addr(11),boards(B0,B1))
+external_box_cost=50

[engine_board]
// Boards are connected in a grid:
(0,0):Io(board(B0),addr(0))=Io(board(B1),cost(5)),Europa(board(B0))
(0,1):Io(board(B1),addr(1))=Io(board(B0),cost(5)),Ganymede(board(B0)),Europa(board(B1))
(0,0):Europa(board(B0),addr(0))=Europa(board(B1),cost(5)),Io(board(B0))
(0,1):Europa(board(B1),addr(1))=Europa(board(B0),cost(5)),Callisto(board(B0)),
 → Io(board(B1))
(0,0):Ganymede(board(B0),addr(0))=Ganymede(board(B1),cost(5)),Callisto(board(B0)),
 → Io(board(B1))
(0,1):Ganymede(board(B1),addr(1))=Ganymede(board(B0),cost(5)),Callisto(board(B1))
(0,0):Callisto(board(B0),addr(0))=Callisto(board(B1),cost(5)),Ganymede(board(B0)),
 → Europa(board(B1))
(0,1):Callisto(board(B1),addr(1))=Callisto(board(B0),cost(5)),Ganymede(board(B1))

// Default edge cost, if not defined in the topology explicitly.
+board_board_cost=20
```

Notes:

 - Figure 7 shows the graph of the boards described by this example, along with
   their containing boxes.

 - The line `(0,0):Io(addr(00),boards(Board0,Board1))` in the `[engine_box]`
   section defines a box:

   - named `Io`,

   - at position `(0,0)` in the engine co-ordinate system[^positioning]. The
     position can be omitted, in which case the line would be
     `Io(addr(00),boards(B0,B1))`,

   - with box address component `00`, and

   - containing boards named `B0` and `B1`.

   In order for this file to be valid, there must be definitions for the boards
   `Io(board(B0))` and `Io(board(B1))` in the `[engine_board]` section.

[^positioning]: The position is ignored by the Orchestrator, but may be useful
to visualisation tools.

 - The line
   `(0,0):Io(board(B0),addr(0))=Io(board(B1),cost(5)),Europa(board(B0))`
   in the `[engine_board]` section defines a board:

   - named `B0` in box `Io` (boards can have the same names across boxes,
     but not within a box),

   - at position `(0,0)` in the box co-ordinate system,

   - with board-address component `0`, and

   - is connected to the boards `Io(board(B1))` and `Europa(board(B0))`,
     whose edges have communication costs 5 and 20 respectively.

   In order for this file to be valid, there must also be lines in this section
   defining a `Io(board(B1))` board with a 5-weight edge to
   `Io(board(B0))`, and a `Europa(board(B0))` board with a 20-weight edge
   to `Io(board(B0))`.

 - Address components must be defined, and must not exceed the appropriate
   length defined in the `[packet_address_format]` section. The exception to
   this is when the length in the `[packet_address_format]` section is zero; in
   which case only one item exists, and there must be no address component. The
   Coleridge example in Appendix C demonstrates this on the box level.

 - The graph of mailboxes mailboxes in a board is defined similarly to the
   graph of boards in the engine, as demonstrated by the Coleridge example in
   Appendix C.

 - When edge weights are not defined explicitly in a graph, as with the line\
   `(0,0):Io(board(B0),addr(0))=Io(board(B1),cost(5)),Europa(board(B0))`, the
   value defined in `board_board_cost` is used (20 in this case). `X_X_cost` is
   used in the general case, where `X` is the level of the contained items.

 - Boxes, boards, and mailboxes can have any name as long as they match the
   regular expression `[a-zA-Z0-9]{2,32}`, and are unique within the item that
   contains them.

 - As with dialect 1, multidimensional addresses are supported. Example box
   declaration: `(0,0):Io(addr(00,01),boards(B0,B1))`.

 - If, on a given level of the hierarchy, there is only one item with no
   connections to items on its level, the assignment operator `=` can be
   omitted. In this case, the declaration becomes `(0,0):Io()`, or for boards,
   `(0,0):Io(board(B0))`. Note that the address component is omitted because
   there is only one item on the level.

 - Different boxes can contain different quantities of boards.

![Weighted graph of boards described by the dialect 2 example, where each board
(red) is contained in a box (blue). All boxes and all boards are of the same
"type" (see the Dialect 3 Section for information on
types).](images/dialect_2.pdf)

Appendix C contains a complete dialect 2 example file representing Coleridge.

## Dialect 3 (Fully-Heterogeneous)
Dialect 3 extends dialect 2 by supporting heterogeneity across levels of the
hierarchy, so that each box can have different properties from other boxes, and
each board can be different from each other board, and so on. Dialect 3
maintains support for the weighted graph topology introduced in dialect 2, and
extends it to support section types, to model "hardware types". By way of
example, two boards with the same type will have the same constituents and
topology (quantity and configuration) of mailboxes and packet costs associated
with them, whereas two boards of different types may not. Here are example
`[engine_box]` and `[engine_board]` sections for dialect 3, where the `→`
character denotes a line continuation:

```
[engine_box]
// Define four boxes with three different types. Note that each box
// contains two boards, apart from one box which contains one board.
(0,0):Io(addr(00),type(TYPEef752a19),boards(B0,B1))
(1,0):Europa(addr(10),type(TYPEc92e3bc1),boards(B0))
(0,1):Ganymede(addr(01),type(TYPEdcecd67b),boards(B0,B1))
(1,1):Callisto(addr(11),type(TYPEdcecd67b),boards(B0,B1))
+external_box_cost=50

[engine_board]
// Boards are connected in a grid, kind-of:
(0,0):Io(board(B0),addr(0),type(TYPEd7aefac5))=Io(board(B1),cost(5)),Europa(board(B0))
(0,1):Io(board(B1),addr(1),type(TYPEd7aefac5))=Io(board(B0),cost(5)),Ganymede(board(B0))
(0,0):Europa(board(B0),addr(0),type(TYPEb443a014))=Io(board(B0)),Callisto(board(B0))
(0,0):Ganymede(board(B0),addr(0),type(TYPEd7aefac5))=Ganymede(board(B1),cost(5)),
 → Callisto(board(B0)),Io(board(B1))
(0,1):Ganymede(board(B1),addr(1),type(TYPEd7aefac5))=Ganymede(board(B0),cost(5)),
 → Callisto(board(B1))
(0,0):Callisto(board(B0),addr(0),type(TYPEd7aefac5))=Callisto(board(B1),cost(5)),
 → Ganymede(board(B0)),Europa(board(B0))
(0,1):Callisto(board(B1),addr(1),type(TYPEb443a014))=Callisto(board(B0),cost(5)),
 → Ganymede(board(B1))
+board_board_cost=20

// These sections and their contents must be defined.
[box(TYPEef752a19)]
... // Truncation
[box(TYPEc92e3bc1)]
...
[box(TYPEdcecd67b)]
...
[board(TYPEd7aefac5)]
...
[board(TYPEb443a014)]
...
```

Notes:

 - Figure 8 shows the graph of the boards described by this example, along with
   their containing boxes, where each colour of box and each colour of board
   denotes an item of a certain type. Every item must have a type.

 - The line `(0,0):Io(addr(00),type(TYPEef752a19),boards(B0,B1))` in the
   `[engine_box]` section defines a box:

   - named `Io`, as with dialect 2,

   - at position `(0,0)` in the engine co-ordinate system, as with dialect 2,

   - with box address component `00`, as with dialect 2 (multidimensional
     addresses are supported in the same way),

   - with type `TYPEef752a19`, and

   - containing boards named `B0` and `B1`.

   In order for this file to be valid, there must be definitions for the boards
   `Io(board(B0))` and `Io(board(B1))` in the `[engine_board]` section, and a
   `[box(TYPEef752a19)]` section must exist, which will define the properties
   of boxes of this type.

 - The line
   `(0,0):Io(board(B0),addr(0),type(TYPEd7aefac5))=Io(board(B1),cost(5)),Europa(`
   `→board(B0))` in the `[engine_board]` section defines a board:

   - named `B0` in box `Io`,

   - at position `(0,0)` in the box co-ordinate system,

   - with board-address component `0`,

   - with type `TYPEd7aefac5`, and

   - is connected to the boards `Io(board(B1))` and `Europa(board(B0))`,
     whose edges have communication costs 5 and 20 respectively.

   In order for this file to be valid, there must also be lines in this section
   defining a `Io(board(B1))` board with a 5-weight edge to `Io(board(B0))`,
   and a `Europa(board(B0))` board with a 20-weight edge to `Io(board(B0))`,
   and a `[board(TYPEd7aefac5)]` section must exist, which will define the
   properties of boards of this type.

 - The boxes (and boards and mailboxes) and their types can have any name as
   long as they match the regular expression `[a-zA-Z0-9]{2,32}`, and are
   unique on a given level of the hierarchy. Types do not have to begin with
   `TYPE` (it's done here more to emphasise the point). Unlike with dialect 2,
   the extra level of heterogeneity provided by dialect 3 allows these names
   and types to be defined by unique identifiers derived from hardware.

Types can also be defined as defaults. The following two blocks are synonyms of
the previous dialect 3 example given in this section using default type
definitions:

```
[engine_box]
(0,0):Io(addr(00),type(TYPEef752a19),boards(B0,B1))
(1,0):Europa(addr(01),type(TYPEc92e3bc1),boards(B0))
(0,1):Ganymede(addr(10),boards(B0,B1))
(1,1):Callisto(addr(11),boards(B0,B1))
+type="TYPEdcecd67b"
+external_box_cost=50

[engine_board]
(0,0):Io(board(B0),addr(0))=Io(board(B1),cost(5)),Europa(board(B0))
(0,1):Io(board(B1),addr(1))=Io(board(B0),cost(5)),Ganymede(board(B0))
(0,0):Europa(board(B0),addr(0),type(TYPEb443a014))=Io(board(B0)),Callisto(board(B0))
(0,0):Ganymede(board(B0),addr(0))=Ganymede(board(B1),cost(5)),Callisto(board(B0)),
 → Io(board(B1))
(0,1):Ganymede(board(B1),addr(1))=Ganymede(board(B0),cost(5)),Callisto(board(B1))
(0,0):Callisto(board(B0),addr(0))=Callisto(board(B1),cost(5)),Ganymede(board(B0)),
 → Europa(board(B0))
(0,1):Callisto(board(B1),addr(1),type(TYPEb443a014))=Callisto(board(B0),cost(5)),
 → Ganymede(board(B1))
+type="TYPEd7aefac5"
+board_board_cost=20
```

and:

```
[default_types]
+box_type="TYPEdcecd67b"
+board_type="TYPEd7aefac5"
+mailbox_type="SomeMailboxType" // Doesn't matter for this example,
                                // and could be omitted.
[engine_box]
(0,0):Io(addr(00),type(TYPEef752a19),boards(B0,B1))
(1,0):Europa(addr(01),type(TYPEc92e3bc1),boards(B0))
(0,1):Ganymede(addr(10),boards(B0,B1))
(1,1):Callisto(addr(11),boards(B0,B1))
+external_box_cost=50

[engine_board]
(0,0):Io(board(B0),addr(0))=Io(board(B1),cost(5)),Europa(board(B0))
(0,1):Io(board(B1),addr(1))=Io(board(B0),cost(5)),Ganymede(board(B0))
(0,0):Europa(board(B0),addr(0),type(TYPEb443a014))=Io(board(B0)),Callisto(board(B0))
(0,0):Ganymede(board(B0),addr(0))=Ganymede(board(B1),cost(5)),Callisto(board(B0)),
 → Io(board(B1))
(0,1):Ganymede(board(B1),addr(1))=Ganymede(board(B0),cost(5)),Callisto(board(B1))
(0,0):Callisto(board(B0),addr(0))=Callisto(board(B1),cost(5)),Ganymede(board(B0)),
 → Europa(board(B0))
(0,1):Callisto(board(B1),addr(1),type(TYPEb443a014))=Callisto(board(B0),cost(5)),
 → Ganymede(board(B1))
+board_board_cost=20
```

Notes:

 - The type of an item is defined as follows (all items must have a defined
   type somewhere):

   - If the type is defined on the same line as that item, that type definition
     is used.

   - Otherwise, the value for `type` in the section of that item is used, if
     `type` is defined.

   - Otherwise, the value corresponding to that item in the `default_types`
     section is used.

 - Values can be defined in the `default_types` section in any order.

![Weighted graph of boards described by the dialect 3 example, where each board
is contained in a box. The colour of each item denotes its
type.](images/dialect_3.pdf)

Appendix C contains a complete dialect 3 example file representing Coleridge.

# Appendix C: Coleridge Hardware Input Files (0.3.2)
The following subsections of this document contain the content of example
hardware input files that describe Coleridge (an existing POETS Engine) as of
the datetime in their header sections. These examples are included to
demonstrate the form of the hardware files; the information contained therein
is not expected to accurately represent Coleridge in any future state.

## Coleridge in Dialect 1

```
// A representation of the Coleridge box in Dialect 1.
[header(Coleridge)]
+author="Mark Vousden"
+dialect=1
+datetime=20181127165846
+version="0.3.2"
+file="dialect_1"

[packet_address_format]
+mailbox=(2,2)
+thread=4
+core=2
+board=(2,2)
+box=0  // There is only one box in Coleridge, and since 2^0 >= 1,
        // this address component is valid.

[engine]
+boxes=1
+boards=hypercube(2,3)
+external_box_cost=*  // <!> Missing, used for externals.

[box]
+box_board_cost=*  // <!> Missing
+supervisor_memory=10240 // Coleridge has 46GB of RAM, so I'm
                         // arbitrarily reserving 10GiB here. This
                         // is measured in MiB.
+board_board_cost=8 // <!> Relative to board::mailbox_mailbox_cost

[board]
+mailboxes=hypercube(4,4)
+board_mailbox_cost=*  // <!> Missing
+supervisor_memory=0
+mailbox_mailbox_cost=1 // <!> Relative to box::board_board_cost
+dram=4096  // MiB, two DDR3 DRAM boards.

[mailbox]
+cores=4
+mailbox_core_cost=*  // <!> Missing
+core_core_cost=*  // <!> Missing

[core]
+threads=16
+instruction_memory=8  // KiB
+data_memory=*  // <!> Missing
+core_thread_cost=*  // <!> Missing
+thread_thread_cost=*  // <!> Missing
```

## Coleridge in Dialect 2

```
// A representation of the Coleridge box in Dialect 2
[header(Coleridge)]
+author="Mark Vousden"
+dialect=2
+datetime=20181127165846
+version="0.3.2"
+file="dialect_2"

[packet_address_format]
+mailbox=(2,2)
+thread=4
+core=2
+board=(2,2)
+box=0  // There is only one box in Coleridge, and since 2^0 >= 1,
        // this address component is valid.

[engine_box]
Box(boards(B0,B1,B2,B3,B4,B5))
+external_box_cost=*  // <!> Missing, used for externals.

[engine_board]
// Layout:
//
//   0 -- 1
//
//   |    |
//
//   2 -- 3
//
//   |    |
//
//   4 -- 5
//
(0,0):Box(board(B0),addr(0,00))=Box(board(B1)),Box(board(B2))
(1,0):Box(board(B1),addr(1,00))=Box(board(B0)),Box(board(B3))
(0,1):Box(board(B2),addr(0,01))=Box(board(B0)),Box(board(B3)),Box(board(B4))
(1,1):Box(board(B3),addr(1,01))=Box(board(B1)),Box(board(B2)),Box(board(B5))
(0,2):Box(board(B4),addr(0,10))=Box(board(B2)),Box(board(B5))
(1,2):Box(board(B5),addr(1,10))=Box(board(B3)),Box(board(B4))
+board_board_cost=8 // <!> Relative to board::mailbox_mailbox_cost

[box]
+box_board_cost=*  // <!> Missing
+supervisor_memory=10240 // Coleridge has 46GB of RAM, so I'm
                         // arbitrarily reserving 10GiB here. This
                         // is measured in MiB.

[board]
// Layout:
//
//   0 -- 1 -- 2 -- 3
//
//   |    |    |    |
//
//   4 -- 5 -- 6 -- 7
//
//   |    |    |    |
//
//   8 -- 9 -- A -- B
//
//   |    |    |    |
//
//   C -- D -- E -- F
//
(0,0):Mbox0(addr(00,00))=Mbox1,Mbox4
(1,0):Mbox1(addr(01,00))=Mbox0,Mbox2,Mbox5
(2,0):Mbox2(addr(10,00))=Mbox1,Mbox3,Mbox6
(3,0):Mbox3(addr(11,00))=Mbox2,Mbox7
(0,1):Mbox4(addr(00,01))=Mbox0,Mbox5,Mbox8
(1,1):Mbox5(addr(01,01))=Mbox1,Mbox4,Mbox6,Mbox9
(2,1):Mbox6(addr(10,01))=Mbox2,Mbox5,Mbox7,MboxA
(3,1):Mbox7(addr(11,01))=Mbox3,Mbox6,MboxB
(0,2):Mbox8(addr(00,10))=Mbox4,Mbox9,MboxC
(1,2):Mbox9(addr(01,10))=Mbox5,Mbox8,MboxA,MboxD
(2,2):MboxA(addr(10,10))=Mbox6,Mbox9,MboxB,MboxE
(3,2):MboxB(addr(11,10))=Mbox7,MboxA,MboxF
(0,3):MboxC(addr(00,11))=Mbox8,MboxD
(1,3):MboxD(addr(01,11))=Mbox9,MboxC,MboxE
(2,3):MboxE(addr(10,11))=MboxA,MboxD,MboxF
(3,3):MboxF(addr(11,11))=MboxB,MboxE
+board_mailbox_cost=*  // <!> Missing
+supervisor_memory=0
+mailbox_mailbox_cost=1 // <!> Relative to box::board_board_cost
+dram=4096  // MiB, two DDR3 DRAM boards.

[mailbox]
+cores=4
+mailbox_core_cost=*  // <!> Missing
+core_core_cost=*  // <!> Missing

[core]
+threads=16
+instruction_memory=8  // KiB
+data_memory=*  // <!> Missing
+core_thread_cost=*  // <!> Missing
+thread_thread_cost=*  // <!> Missing
```

## Coleridge in Dialect 3

```
// A representation of the Coleridge box in Dialect 3. Note that,
// since Coleridge is vertically homogeneous, nothing exciting
// happens with types here. However, the syntax may still be
// instructive.
[header(Coleridge)]
+author="Mark Vousden"
+dialect=3
+datetime=20181127165846
+version="0.3.2"
+file="dialect_3"

[packet_address_format]
+mailbox=(2,2)
+thread=4
+core=2
+board=(2,2)
+box=0  // There is only one box in Coleridge, and since 2^0 >= 1,
        // this address component is valid.

[default_types]
+box_type="CommonBox"
+board_type="CommonBoard"
+mailbox_type="CommonMbox"

[engine_box]
Box(boards(B0,B1,B2,B3,B4,B5))
+external_box_cost=*  // <!> Missing, used for externals.

[engine_board]
// Layout:
//
//   0 -- 1
//
//   |    |
//
//   2 -- 3
//
//   |    |
//
//   4 -- 5
//
(0,0):Box(board(B0),addr(0,00))=Box(board(B1)),Box(board(B2))
(1,0):Box(board(B1),addr(1,00))=Box(board(B0)),Box(board(B3))
(0,1):Box(board(B2),addr(0,01))=Box(board(B0)),Box(board(B3)),Box(board(B4))
(1,1):Box(board(B3),addr(1,01))=Box(board(B1)),Box(board(B2)),Box(board(B5))
(0,2):Box(board(B4),addr(0,10))=Box(board(B2)),Box(board(B5))
(1,2):Box(board(B5),addr(1,10))=Box(board(B3)),Box(board(B4))
+board_board_cost=8 // <!> Relative to board::mailbox_mailbox_cost

[box(CommonBox)]
+box_board_cost=*  // <!> Missing
+supervisor_memory=10240  // Coleridge has 46GB of RAM, so I'm
                         // arbitrarily reserving 10GiB here. This
                         // is measured in MiB.

[board(CommonBoard)]
// Layout:
//
//   0 -- 1 -- 2 -- 3
//
//   |    |    |    |
//
//   4 -- 5 -- 6 -- 7
//
//   |    |    |    |
//
//   8 -- 9 -- A -- B
//
//   |    |    |    |
//
//   C -- D -- E -- F
//
(0,0):Mbox0(addr(00,00))=Mbox1,Mbox4
(1,0):Mbox1(addr(01,00))=Mbox0,Mbox2,Mbox5
(2,0):Mbox2(addr(10,00))=Mbox1,Mbox3,Mbox6
(3,0):Mbox3(addr(11,00))=Mbox2,Mbox7
(0,1):Mbox4(addr(00,01))=Mbox0,Mbox5,Mbox8
(1,1):Mbox5(addr(01,01))=Mbox1,Mbox4,Mbox6,Mbox9
(2,1):Mbox6(addr(10,01))=Mbox2,Mbox5,Mbox7,MboxA
(3,1):Mbox7(addr(11,01))=Mbox3,Mbox6,MboxB
(0,2):Mbox8(addr(00,10))=Mbox4,Mbox9,MboxC
(1,2):Mbox9(addr(01,10))=Mbox5,Mbox8,MboxA,MboxD
(2,2):MboxA(addr(10,10))=Mbox6,Mbox9,MboxB,MboxE
(3,2):MboxB(addr(11,10))=Mbox7,MboxA,MboxF
(0,3):MboxC(addr(00,11))=Mbox8,MboxD
(1,3):MboxD(addr(01,11))=Mbox9,MboxC,MboxE
(2,3):MboxE(addr(10,11))=MboxA,MboxD,MboxF
(3,3):MboxF(addr(11,11))=MboxB,MboxE
+board_mailbox_cost=*  // <!> Missing
+supervisor_memory=0
+mailbox_mailbox_cost=1 // <!> Relative to box::board_board_cost
+dram=4096  // MiB, two DDR3 DRAM boards.

[mailbox(CommonMbox)]
+cores=4
+mailbox_core_cost=*  // <!> Missing
+core_core_cost=*  // <!> Missing

[core]
+threads=16
+instruction_memory=8  // KiB
+data_memory=*  // <!> Missing
+core_thread_cost=*  // <!> Missing
+thread_thread_cost=*  // <!> Missing
```
