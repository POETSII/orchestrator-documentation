% Design of the Orchestrator Placement System (2019-09-24)

# Placement Overview and Design Requirements
This document defines the design of the placement system in the
Orchestrator. The "placement problem" has been well explored in the literature,
though there is novelty in POETS placement, as the hardware model is
hierarchical in nature, thus resulting in an unusual search
codomain[^programmableRouting]. Placing an application requires knowledge of
the hardware model, as well as the structure and properties of the application.

[^programmableRouting]: With programmable routing in the pipeline, it's become
    a lot more publishable.

Explicitly, the "placement problem" in POETS is the mapping of the application
(digraph) onto the hardware (simple weighted graph), such that the following
are minimised/compromised, subject to a finite set of constraints:

 - The weights on the edges of the application graph imposed by the hardware
   graph.

 - The number of devices (`DevI_t`s) placed on threads (`P_thread`s), to avoid
   overloading cores.

 - The number of edges in the application graph that overlay each given edge in
   the hardware graph.

Such constraints may include:

 - Imposing upper or lower bounds on the number of devices placed on each
   thread.

 - Pinning certain devices to certain threads.

though many more may be contrived. With this in mind, the design requirements
 for the placement system in the Orchestrator are:

 - To support different algorithms, selectable at run time by the Orchestrator
   operator. In early iterations, bucket filling and simulated annealing is
   sufficient, but the design of the placement system should allow algorithms
   to be added easily in future iterations to exploit properties specific to
   the POETS placement problem (papers!).

 - To support run-time decisions about how the placement can be constrained,
   using a "walled-garden" set of constraints that can be
   parameterised. Application-level (from XML), hardware-level (from a
   configuration file) must both be supported, as well as constraints specified
   by the operator at run-time.

 - To support placement of multiple applications in sequence, independently of
   each other.

 - To support detailed diagnostics (dumps) for problem diagnosis, to support
   algorithm development and implementation, and to motivate algorithm
   modifications.

# Data Structures
This design proposes the introduction of several new data structures in the
placement system, as well as the modification of some in `OrchBase`. This
section outlines those structures. A map of the proposed structure is shown in
Figure 1.

![Data structure diagram, showing how placement may be conducted in the
Orchestrator](images/placement_design_data_structure.pdf)

## Placer
The `Placer` encapsulates placement behaviour in the Orchestrator. The
`OrchBase` class holds a `Placer` member (with name `placer`). When the
`P_engine` stored by `OrchBase` is changed (i.e. `topology /load`), then
`OrchBase` replaces its `OrchBase::placer` member.

`Placer` instances hold two public maps - one which maps device addresses to
thread addresses, and one which maps thread addresses to a list of device
addresses:

~~~ {.cpp}
std::map<P_thread*, std::list<DevI_t*>> Placer::threadToDevices
std::map<DevI_t*, P_thread*> Placer::deviceToThread
~~~

These maps are the primary output of placement, describe the placement of all
applications in the Orchestrator, and are read by the binary builder to
establish the relationship between the application and the hardware. This is
contrary to the current design of the Orchestrator, where `P_thread` objects
have a vector within which corresponding `DevI_t*` values are stored, and each
`DevI_t` holds the corresponding `P_thread`. Advantages of the two-map approach
over the previous approach are:

 - Encapsulation: `Placer` instances do not modify hardware or application data
   structures. Also makes teardown a little simpler.

 - Modularity, local storage of information.

The disadvantage is that any operation that involves looking up placement
behaviour as a function of device `DevI_t`, for all devices, is slower (a map
lookup versus a dereference). Once such case is when a application is
"un-placed".

### Placer and Applications/Algorithms/Constraints

`Placer` objects hold a map of applications that have been placed on them,
along with the `Algorithm` object that performed the placement
(`std::map<P_task*, Algorithm> placedTasks`). Each application may be placed
only once without being "unplaced". This map is interacted with by the `float
Placer::place(P_engine*, P_task*, string)`, which:

 - Creates an entry in `placedTasks` with the `P_task*` passed as an argument,
   and a new `Algorithm` instance, which is determined by the string passed as
   an argument.

 - Runs the algorithm on the application.

 - Performs an integrity check (using
   `Placer::check_all_devices_mapped(P_engine*, P_task*)`), which would ensure
   that all devices for a application have been placed.

 - If all is well, returns the placement score from the algorithm. Otherwise,
   propagates an error back to the caller.

In this way, the result of the `Algorithm` can be queried by the operator if
desired. Applications can also be unplaced with `Placer::unplace(P_engine*,
P_task*)`, which[^load]:

 - Iterates through all of the `DevI_t` instances in the application graph and
   removes them from the placement maps.

 - Removes all constraints associated with that application.

 - Removes the entry for that application from `placedTasks`.

[^load]: Clearly this process involves a lot of work (indexing a map for each
    device), but it doesn't matter too much because this operation is
    sufficiently rare.

`Placer` objects hold a list of constraints `std::list<Constraint>
constraints`, which `Algorithm` objects can query during placement. This list
is populated by `Placer:load_constraint_file(std::string)`.

## Constraints
As per the design requirements, constraints can be introduced from three
sources:

 - From a configuration file, applied system-wide (see Appendix A for a
   format).

 - From an application file, applied to that application only (see Appendix B
   for a format).

 - From the command prompt, applied system-wide (see the "Interaction" section
   for how this might work).

Each individual constraint is represented as a `Constraint` object. Constraints
have the following associated with them:

 - A `constraintCategory`, which is an enumeration. This is included to
   facilitate filtering on a list of constraints (such as the one held by the
   `Placer`) for constraints of a certain "type".

 - A pointer to the `P_task` it was loaded from, if it was introduced from an
   application file. This is necessary to check which application it applies
   to.

 - A boolean (`satisfied`) to store previous computation of whether or not the
   constraint is satisfied. This is necessary to ease the computation of the
   fitness delta (see the Simulated Annealing section).

 - A method `bool Constraint::is_satisfied(Placer*)` that examines the current
   placement structure, and returns a boolean denoting whether or not the
   constraint has been satisfied. This updates the `satisfied` field. This
   method will be expensive if a global search is required (i.e. constraining
   the maximum number of devices that can be placed on a thread), but will be
   cheap otherwise (i.e. fixing a device by name to a thread by address).

 - A method `bool Constraint::is_satisfied_delta(Placer*,
   std::vector<DevI_t*>)` that examines the devices passed as argument, and
   returns a boolean denoting whether or not these devices have "internally"
   broken the constraint. This is useful to avoid iterating through the entire
   placement structure on each fitness delta evaluation. Idempotence!

 - A cost penalty to impose on the algorithm if broken.

 - A boolean (`mandatory`), which causes the algorithm to automatically reject
   states that fail this constraint (it's up to the algorithm to respect this).

Possible constraints include (this is by no means an exhaustive list):

 - Restricting the maximum number of devices that can be placed on a thread.

 - Fix device (by name) to thread (debugging, timing).

 - Restricting two devices to exist on the same thread/core/mailbox/board/box.

 - Set the cost between all connected devices to not exceed a certain value
   (distances are relative, but might be useful...).

## Algorithms
Algorithms represent "placement methods", like bucket filling, or simulated
annealing. Algorithms control the placement of devices in a given application
onto the engine, without disrupting the placement of devices from other
applications (recall that algorithms should act on one application and not be
predictive, from the design requirements). All algorithms inherit from an
`Algorithm` class, and they must define the `float Algorithm::do_it(P_engine*,
P_task*, Placer*)` method. Since `Placer` objects expose the placement
information maps and all constraints, the algorithm has sufficient information
to do its business. This method returns an arbitrary "score" - the context of
this is dependent on the algorithm used.

Algorithm instances store (in a `Result` structure):

 - The datetime of when placement was completed.

 - The placement "score".

 - The maximum amount of devices placed on a thread for this application.

 - The greatest "cost" between connected placed devices (stored for easier
   lookup at dump-time)

One may initially elect to represent placement algorithms as `Placer` methods,
as opposed to classes in their own right. The motivation for defining them as
classes is to facilitate the use of the command pattern to log a history of
algorithms-applied-to-applications, so that dumping can be meaningful (i.e. the
operator can see the order things were placed, what algorithm put them there,
etc.)

Algorithms store edge weights in `P_task->pD.G` (i.e. in the pdigraph object
stored in the D_graph object) during computation. The `MsgT_t` class must be
extended with a `float weight` member to accommodate this[^hypocrisy].

[^hypocrisy]: Now I hear you cry "you were going on about modularity earlier,
    and here you are writing to the application object!", and you would
    absolutely be correct to call me a hypocrite. However, there are a lot of
    devices, and it's convenient to look up the costs from both node-pairs
    (fitness delta) and an edge (fitness total), which `pdigraph` allows us to
    do pretty quickly (remember, it's maps all the way down...).

# How the Operator Interacts with the Placement System
Here's a speculative list of commands for how the Orchestrator operator would
interact with the placement system:

 - `placement /ALGORITHM = APPLICATIONNAME`: Performs the `ALGORITHM` algorithm
   to place the application named `APPLICATIONNAME` onto the hardware
   model. Writes an error to the operator if:

   - There is no application loaded with the name APPLICATIONNAME.

   - There is no hardware model loaded.

   - The application could not fit into the hardware model.

   - A application with the name APPLICATIONNAME has already been placed (tells
     the operator to unplace the application before proceeding).

   Writes warnings to the operator for each constraint that could not be
   satisfied. If there were no errors, writes to the operator confirming the
   completion of placement, along with the time taken.

   `ALGORITHM` could be "bucket", "sa" or something else that's implemented
   [^algorithmName]

[^algorithmName]: Just don't call your algorithm "dump", or "place" (please).

 - `placement /dump = APPLICATIONNAME`: Dumps placement information for the
   application named `APPLICATIONNAME`, specifically:

   - Information on how each device in the application has been placed on the
     hardware, line by line. Each record is of the form
     "`<DEVICENAME>\t<THREADNAME>`" (where `<THREADNAME>` is
     hierarchical). This information is dumped to
     `placement_task_to_hardware_<APPLICATIONNAME>_<ISO8601DT>.txt`.

   - Diagnostic information from the algorithm object, dumped to\
     `placement_diagnostics_<APPLICATIONNAME>_<ISO8601DT>.txt`. This
     information includes:

     - When the application was placed.

     - The algorithm type used to place the application.

     - The placement score (supplied by the algorithm).

     - The greatest "distance" between connected placed devices (supplied by
       the algorithm).

     - The maximum amount of devices placed on a thread for this application
       (supplied by the algorithm).

     - Detailed information about "cost" between each application graph edge
       (supplied by the `MsgT_t`s in the application), line by line. Each
       record is of the form `<DEVICENAME>\t<DEVICENAME>\t<COST>`, and is
       dumped to\
       `placement_task_edges_<APPLICATIONNAME>_<ISO8601DT>.txt`.

   I'd prefer it if the operator could specify paths on the command line, but I
   can't see an elegant way of doing this using the command infrastructure we
   have.

   Writes an error to the operator if no application with name APPLICATIONNAME
   has been placed.

 - `placement /unplace = APPLICATIONNAME`: Completely clears placement
   information for a application with name `APPLICATIONNAME`. Writes an error
   to the operator if no application with that name has been placed.

 - `placement /reset`: Completely clears placement information and constraints,
   and unlinks the hardware stack from all devices.

 - `placement /constraint = TYPE(ARGS, ...)`: Add a system-wide constraint to
   the placer, with a set of arguments.

 - `placement /constraint = PATH`: Loads a system-wide constraint configuration
   file (using `Placer:load_constraint_file(std::string)`).

# Implementing Simulated Annealing
Simulated annealing is a search method that allows, in the general case,
exploration of a solution space and selection of a guaranteed local optimum,
with some concession for global search. This method transitions from
exploratory behaviour into exploitary behaviour as solution count
increases. These characteristics make simulated annealing a suitable candidate
for a "second-crack" POETS placement algorithm. This section does not explain
simulated annealing in depth, but instead explains how it might be implemented
given the placement framework outlined above, with a little algorithm-specific
augmentation. Fundamentally, simulated annealing is:

 1. **Initialisation**: Set state $s=s_0$ and $n=0$.

 2. **Selection**: Select neighbouring state $s_{\mathrm{new}}=\delta(s)$.

 3. **Fitness Evaluation**: Compute $E(s_{\mathrm{new}})$, given $E(s)$.

 4. **Determination**: If $E(s_{\mathrm{new}}) < E(s)$, then

    - set $s=s_{\mathrm{new}}$.

    Otherwise, if $E(s_{\mathrm{new}})\geq E(s)$, then

    - if $P(E(s),E(s_{\mathrm{new}}),T(n))$, then

      - set $s=s_{\mathrm{new}}$.

 6. **Termination**: If not $F(s,n)$, then go to 2.

 7. The output is $s$.

where:

 - $s_0\in S$ is an intelligently-chosen initial state (in POETS, this is a
   graph mapping).

 - $S$ is the set of possible mappings (i.e. the state space).

 - $n\in\mathbb{Z}$ is a step (iteration) counter.

 - $\delta(s)\in S$ is an atomic transformation on state $s$ (see the
   "Selection" section).

 - $E(s)\in\mathbb{R}$ is the fitness of state $s$ (i.e. how are the criteria
   at the top of this document satisfied?)

 - $T(n)\in\mathbb{R}$ is some disorder parameter analogous to temperature in
   traditional annealing. Must decrease monotonically from one to zero with
   increasing $n$, until some maximum step counter. A high $T$ value
   corresponds to exploratory behaviour, and a low $T$ value corresponds to
   exploitary behaviour.

 - $P(E(s),E(s_{\mathrm{new}}),T(n))\in[0,1]$ is an acceptance probability
   function, which determines whether or not a worse solution is accepted as a
   function of the disorder parameter.

 - $F(s,n)\in\{\text{true},\text{false}\}$ is a termination condition (could be
   bound by a maximum step, a derivative of the state, or something else).

## Initialisation

### Hardware Communication Matrices
Before performing optimisation, the simulated annealing algorithm
(`SimulatedAnnealing::Algorithm`) would populate a
`std::map<std::pair<P_mailbox*, P_mailbox*>, float> hardwareCosts`, which
stores the communication cost of going from each mailbox to each mailbox. It
would also populated `std::map<P_mailbox*, float> supervisorCosts`, which
stores the communication cost from each mailbox to its supervisor. These costs
would assume the shortest path, and be populated using the Floyd-Warshall
algorithm.

One might assume the former map would use up "a lot" of memory, but I
disagree. For the eight-box system, 16 mailboxes-per-board $\times$ 6
boards-per-box $\times$ 8 boxes $=$ 768 mailboxes. Given a four-byte floats and
an eight-byte pointers, the values (floats) in the map will claim
$768\times768\times4\text{bytes}\approx2.4\text{Mbytes}$ of memory, where the
values (pairs of pointers) will claim
$768\times768\times8\text{bytes}\approx4.7\text{Mbytes}$ of memory. Even
incorporating STL overheads, these aren't particularly large numbers (I wrote a
test program!).

### Starting State
"Random" placement is sufficient for this, but I suspect a "smart random"
placement would be a better starting point - perhaps one which accounts for
constraints. We could even use a bucket-fill placement as an initial state -
it's cheap to compute.

A point on random placement - core-pairs share instruction memory. As such, we
maintain a `std::map<DevT_t*, std::list<P_core*>> validCoresForDeviceType`,
which initially allows all normal devices to be placed on all cores, but cores
are removed (or added) as devices are moved around.

However the starting state is created, its fitness must be computed to
establish a baseline. We can quantify fitness as the sum of:

 - The cost of each device graph edge (found by summing the appropriate
   `hardwareCosts` or `supervisorCosts` entry with the thread-to-core and
   core-to-thread cost).

 - The penalty from all broken constraints (the state is outright rejected if
   any mandatory constraints are broken).

though I realise that this is overly reductionist, as it doesn't account
for:

 - Communication congestion (i.e. same links being used multiple times, see the
   Extensions section)

 - Context switching (i.e. overworked, underpaid softswitches, but we can
   constrain this)

Point is, this approach is pretty expensive, so we only want to do it as few
times as possible. This is stored in `SimulatedAnnealing.result.score` during
computation, and is done by calling `Placer:compute_fitness(P_task*)`.

## Selection - Swap and Move Operations
Simulated annealing mandates that the selection operation must choose a
neighbouring state. It can be proven that a combination of move and swap
operations, both of which select neighbouring states, are sufficient to explore
the state space.

This mechanism would randomly select a device in the application, a core in the
hardware model that is valid for devices of this type (from
`validCoresForDeviceType`), a thread index in the core, and an index `i` in
[0,1023]. If there aren't `i` devices in the target thread, we move the
selected device to that thread. If there are `i` devices in the target thread,
the position of the `i`th device is swapped with the position of the selected
device.

## Fitness Evaluation of Selected State
In short, compute the delta, and assume we're running in serial.

We could compute the fitness of the entire solution on each change, but that's
expensive. Instead, since simulated annealing only cares about the fitness
difference between the original solution and the selected solution, we only
need to compute the delta. The delta between two solutions is equal to the
delta of the sum of the edges affected by the swap or move process - so only
those need to be recomputed and compared.

Constraints should also be reevaluated using their `is_satisfied_delta` method
(and constraints associated with a different application are ignored). If a
mandatory constraint is broken, the state is discarded, returning to
"Selection"[^nincrement]. For example, if a `MaxDevicesPerThread` constraint:

[^nincrement]: Whether or not $n$ is incremented in response to a state being
discarded is up for debate. If $n$ is not incremented, the algorithm may get
stuck when it is in a state where all transformations result in a failed
mandatory constraint, and when the termination condition is not satisfied. If
$n$ is incremented, termination may be premature.

 - was already satisfied, it only needs to check the changed threads to
   evaluate whether or not it has been broken.

 - was not satisfied, and the changed threads themselves break the constraint,
   then the algorithm does not need to go through checking all the threads
   because the constraint is clearly broken.

In this way, constraint evaluation is cheap for simple cases.

## Determination
Simply put, better solutions are always accepted if they're better, and
sometimes accepted (as a function of the disorder parameter
`SimulatedAnnealing.disorder`). To accept a solution, the data may change:

 - SimulatedAnnealing.result.score

 - MsgT_t.weight (some of them)

 - Placer.deviceToThread (some of them)

 - Placer.threadToDevice (some of them)

 - SimulatedAnnealing.validCoresForDeviceType

## Termination
Suitable termination detection is a black art - there are many metrics one can
use, and they'll all fail in certain cases. We could terminate when:

 - Wallclock exceeds a certain threshold.

 - Iteration count $n$ exceeds a certain threshold.

 - Fitness reaches a certain value as a proportion of the initial value.

 - The rate of fitness reduction (over a perious of time) subceeds a certain
   threshold.

I'll probably use a wallclock threshold as a termination condition to start
with.

## Extensions

### Network Congestion
As a design assumption, I'm ignoring the "value" of network congestion.  I
realise this is a bit thick, but we can extend this to cope by adding a "uses"
pre-computed matrix, which we could multiply the fitness by to penalise
connection overuse. For a four-edge example, where:

 - `MsgT_t` 1 uses hardware edge 1 with cost 4.

 - `MsgT_t` 2 uses hardware edge 2 with cost 2.

 - `MsgT_t` 3 uses hardware edge 3 with cost 3.

 - `MsgT_t` 4 uses hardware edges 1 and 2 (with costs 4 and 2)

The communication cost fitness in the current representation would be:

 - `MsgT_t` 1: 4

 - `MsgT_t` 2: 2

 - `MsgT_t` 3: 3

 - `MsgT_t` 4: 4 + 2 = 6

 - Total: 4 + 2 + 3 + 6 = **19**

However, if we penalise multiple edge use, the fitness might be:

 - `MsgT_t` 1: 4 $\times$ 2 = 8 (cost of four $\times$ two "users" of this
   edge)

 - `MsgT_t` 2: 2 $\times$ 2 = 2 (cost of two $\times$ two "users" of this edge)

 - `MsgT_t` 3: 3 $\times$ 1 = 3 (cost of three $\times$ one "user" of this
   edge)

 - `MsgT_t` 4: 4 $\times$ 2 + 2 $\times$ 2 = 12

 - Total: 8 + 2 + 3 + 12 = **25**

Recall that these fitness values are arbitrary, but hopefully you "get my
idea". I think we can get decent results without this extension, but let's see.

### Batched Selection
Support multiple sequenced (batch) selection operations when disorder is
high. This might be useful (and would be relatively easy to implement in this
framework) if we find we're getting overly stuck in local optima.

### Frustrated Selection
Introduce a "frustration"[^frustration] parameter to `DevI_t`s, which allows
more frustrated members to be selected. `DevI_t`s may be reselected if they are
not frustrated enough for the given solution count.

[^frustration]: I'm borrowing this term from condensed matter physics, where a
"thing" is "frustrated" if it's stuck in a high-energy state. It's not really
appropriate, because "frustration" implies that the "thing" is stuck in a local
optimum, where it does not necessarily need to be so here.

### Parallel SA
Would be pretty cool, eh ADB.

# Roadmap
This section outlines when Mark expects certain implementation milestones to be
reached. The dates are (fairly wild) guesses based off when Mark is away, and
how long he expects certain jobs to take.

: When Mark expects he'll do things by.

+------------+----------------------------------------------------------------+
| When done  | Job                                                            |
+============+================================================================+
| 2019-10-07 | Finalise the design of components design of the placement      |
|            | system, and have it reviewed by relevant people.\              |
|            |                                                                |
+------------+----------------------------------------------------------------+
| 2019-10-21 | Implement "fundamental" placement data structures, and connect |
|            | them to existing Orchestrator infrastructure                   |
|            | (`P_builder`). This includes:                                  |
|            |                                                                |
|            |  - `Placer`                                                    |
|            |  - `Constraint` (and some derivatives, hard-coding their       |
|            |    (de)activation)                                             |
|            |  - `constraintCategory`                                        |
|            |  - `Algorithm` (and bucket-filling)                            |
|            |  - `Result`                                                    |
+------------+----------------------------------------------------------------+
| 2019-10-29 | Implement a fitness evaluator, which accounts for the edges of |
|            | the application graph, and the costs of any broken             |
|            | constraints. \                                                 |
|            |                                                                |
+------------+----------------------------------------------------------------+
| 2019-11-14 | Simulated annealing implementation, with:                      |
|            |                                                                |
|            |  - Precomputation of mailbox-mailbox communication matrix.     |
|            |  - Sensible initial placement (probably bucket-filling).       |
|            |  - Selection operations (swap and move)                        |
|            |  - Fitness delta computation                                   |
|            |  - Some elementary termination logic                           |
+------------+----------------------------------------------------------------+
| 2019-11-29 | Improve placement accuracy with the time that's left:          |
|            |                                                                |
|            | - Divine an accurate communication model                       |
|            | - Introduce the notion of mailbox-board ports to the hardware  |
|            |   model, to facilitate more accurate placement calculation.    |
+------------+----------------------------------------------------------------+
| 2019-12-16 | Advisory board preparation, tell a good story.\                |
|            |                                                                |
+------------+----------------------------------------------------------------+
| Later      | Implement constraint file parser (formally).\                  |
|            |                                                                |
+------------+----------------------------------------------------------------+
| Later      | Support placement according to supervisor and external         |
|            | devices. Do this by introducing the notion of a "supervisor    |
|            | board" to the hardware model, analogous to Tinsel's bridge     |
|            | board. Include links between supervisor devices and normal     |
|            | devices in fitness computation.\                               |
|            |                                                                |
+------------+----------------------------------------------------------------+
| Later      | Design the interface for introducing application constraints   |
|            | (from XML) and operator constraints (from command line), and   |
|            | implement this interface.\                                     |
|            |                                                                |
+------------+----------------------------------------------------------------+
| Later      | Various simulated annealing extensions (not yet).
+------------+----------------------------------------------------------------+

# Appendix A: System-wide Constraint File Format (0.0.0)
This section defines the file format to be used by the Orchestrator to
incorporate system-wide constraints. The input files satisfy the general
"Universal Interface Format" (UIF) file format[^uifdocs]. Input files must be
ASCII encoded, and support a comment syntax:

[^uifdocs]: The UIF documentation can be found in the Orchestrator repository,
    in the `Generics` directory.

~~~ {.ini}
// All text after two consecutive forward slash symbols (//) on a line must be
// ignored by the reader. Comments cannot be escaped.

// Also note that empty lines do not affect file parsing, though whitespace
// within a non-comment line matters.
~~~

System-wide constraint files contain sections (e.g. `[header]`,
`[deviceDensityUpperLimit(Bob)]`). Each section, aside from the `[header]`
section, corresponds to a constraint. The ordering of sections in the file, and
variables in each section, does not matter.

## Header Section
All system-wide constraint files contain exactly one `[header]` section. For
example:

~~~ {.ini}
[header]
author="Mark Vousden"    // Perhaps I'm an imposter
datetime=20190924141000  // YYYYMMDDhhmmss
version="0.0.0"
file="my_first_constraint_file.uif"
~~~

Points to note:

 - The line `author="Mark Vousden"` is a variable definition; specifically
   binding the value `Mark Vousden` as a string to the `author` variable in the
   `[header]` section.

 - The `[header]` section is mandatory, and must define the following variables
    (in any order):

   - `datetime`: Creation time of this file, in ISO8601 "basic datetime" format
     (YYYYMMDDhhmmss), without timezone information.

   - `version`: The version of the file format (which you can extract from this
     example). Must be Semantic Versioning 2.0.0 compatible.

 - The following variables may optionally be defined:

   - `author`: The name of the individual who has created this file, in
     straight double quotes.

   - `file`: The handle of the file in the filesystem[^fileMismatchWarning].

[^fileMismatchWarning]: The design intent being that the Orchestrator will warn
the operator if this field match the name of the file passed in.

## Constraint Sections
Each constraint is defined by a section. Each of these sections may be
accompanied by a name, e.g. `[deviceDensityUpperLimit]` could be named
`[deviceDensityUpperLimit(Bob)]`, which will cause the name `Bob` to be used in
Orchestrator error/warning generation. If no name is defined, a name will be
generated by the Orchestrator. The name must satisfy the regular expression
`[a-zA-Z0-9]{2,32}`, and must be unique across all constraints defined in the
file. All constraint sections may explicitly define one or both of the
following variables:

 - `cost`: A float denoting the cost penalty to impose on the solution fitness
   if this constraint is violated.

 - `mandatory`: Either `false` or `true`. If `true`, and selection breaks this
   constraint, the selected solution cannot be used[^infiniteFitness].

[^infiniteFitness]: Setting `mandatory` equal to true is different from setting
    cost equal to some effecively infinite number for methods that rely on
    gradient descent.

What follows is a list of all constraint types supported by the system-wide
constraint parser, the fields they require, and any other special case
behaviour.

 - `deviceDensityLowerLimit`: Enforces a lower limit, with value `parameter`,
   on the number of devices that can be placed on a given non-empty
   thread. Fields: `parameter` (integer).

 - `deviceDensityUpperLimit`: Enforces an upper limit, with value `parameter`,
   on the number of devices that can be placed on a given thread. Fields:
   `parameter` (integer).

 - `pinDevicesOnSameThread`: As with `pinDevicesOnSameThread`, but that the
   devices are placed on the same core. Fields: `parameter` (comma-separated
   strings).

 - `pinDevicesOnSameThread`: Enforces that all devices with a name in
   `parameter` are placed on the same thread
   (i.e. `parameter="apple","banana","pear"` will pin together all devices
   named `apple`, `banana`, and `pear`). Fields: `parameter` (comma-separated
   strings).

 - `pinDeviceToThread`: Enforces that all devices with the name `devicename`
   are placed on the thread with name `threadname`. Fields: `devicename`
   (string), `threadname` (string).

### System-Wide Constraint File Example

~~~ {.ini}
[header]  // Because we're good people.
author="Mark Vousden"
datetime=20190924141000  // YYYYMMDDhhmmss
version="0.0.0"
file="example_constraint_file.uif"

// Impose an upper and a lower limit on the device density to encourage a more
// even distribution of workers.
[deviceDensityLowerLimit]
parameter=5
mandatory=true
[deviceDensityUpperLimit]
parameter=500
mandatory=true

// Put these devices on the same thread, but it's not game over if you
// don't do it.
[pinDevicesOnSameThread(applePinner)]
parameter="apple1","apple2","apple3"
cost=500.4  // Arbitrary
~~~

# Appendix B: Application (XML) Constraint Format (TODO)
Some kind of metadata, though where and what format? I note that version 4 of
the application description XML supports metadata in a variety of places, so
there's lots of flexibility to be exploited here.

# Appendix C: Proof that Movement and Swapping are Sufficient Selection Operations (TODO)
It's pretty simple - just demonstrate that the space of solutions (described as
an ordered set of unordered size-bound sets of devices, where the order
determines the thread that a device is placed on) can be fully traversed by
move operations (described as moving a device from one of the contained sets to
another), given that there's an "empty space" to move to (adhering to the
size-bound restriction of the contained sets). Introduce the swap operation to
resolve the "empty space" case, which completes the proof.
