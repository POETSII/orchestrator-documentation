% Orchestrator Documentation Volume III Annex: Hardware Description Mechanism
\thispagestyle{fancy}

# Overview
This document defines the input file (hardware description file) format for
describing the hardware stack on which the Orchestrator operates, and how the
file is read by the Orchestrator. I recommend reading the hardware model
documentation before proceeding. The hardware file reader mechanism is
supplemented by a reference definition in Appendix A.

Figure 1 shows the variety of ways in which the hardware model can be
populated. This document is describes the `HardwareFileReader` pathway,
triggered by `task /load`.

![Hardware model interaction diagram. The operator loads a file using `topology
\load`. Dialect 1 files provision a `Dialect1Deployer`, which creates and
populates an Engine. Dialect 3 files are used to provision an Engine
directly. Dialect 2 files are not supported.](images/interaction_diagram.png)

# The Orchestrator's Hardware File Reader
The `HardwareFileReader` class reads hardware description files, and creates
and populates a `P_engine` on the heap from the information in the file. It
inherits from `JNJ`, which is a class that generates parse trees from UIF
files. A high-level description of the loading procedure follows:

 - The file is loaded, and parsed using the logic in `JNJ`. This generates a
   parse tree, and performs syntactic validation which will throw a
   `HardwareSyntaxException` on failure.

 - The parse tree is explored by `HardwareFileReader` logic, which validates
   the semantics of the input file, defines the `P_engine`, and creates and
   defines the items in the hardware stack. This semantic validation fails
   slow, and throws a `HardwareSemanticException` on failure.

A minimal, unsafe use of the reader is:

```
P_engine* engine = new P_engine("My engine");
reader = HardwareFileReader("/path/to/my/file.uif", engine);
// You can use your engine now!
```

This is unsafe because it does not check the result of the parse; if the input
file contains mistakes, an uncaught exception would be thrown. A better way is:

```
P_engine* engine = new P_engine("My engine");
reader = HardwareFileReader;
try
{
    reader.load_file("/path/to/my/file.uif");
    reader.populate_hardware_model(engine);
    // You can use your engine now.
}
catch (OrchestratorException& exception)
{
    printf("%s\n", exception.what())
    delete engine;
    // Something went wrong. You can't use your engine.
}
```

This logic is used when the operator commands `task /load =
"/path/to/my/file.uif"`.

## What is not validated

The `HardwareFileReader` will attempt to save you from yourself to a reasonable
degree, but will not catch every case. Things that are not validated by the
Dialect 1 validator include:

 - Lines within a section that are simply one word, without the assignment
   operator (=) or the prefix (+). These are simply ignored.

 - Multidimensional input components are not matched against their respective
   address word lengths, either using their dimensionality or their value. This
   will cause an `OrchestratorException` to be thrown by the function
   that populates address components.

 - Repeatedly-defined values within a section - only the last defined value
   is used.

 - Probably more, it was developed as a stopgap. Use at your own risk, and
   prefer Dialect 3 for any serious work.

Things that are not validated by the Dialect 3 validator include:

 - Address components of items. If invalid address components are provided, an
   `OrchestratorException` will be thrown, exactly like the Dialect 1
   validator.

 - Invalid properties in item declarations are ignored. For example, you can
   declare a box with the line `MyBox(octopus,quack(duck),boards(MyBoard))` and
   the validator will not complain.

 - You can declare many values for item properties, and only the first will be
   used. For example, you can declare a board with the LHS line
   `MyBox(board(MyBoard),type(IAm,Not,Very,Decisive))`. This issue affects edge
   costs and item types, but not item addresses.

 - You can declare duplicate properties for a given item, and only the first
   will be used. For example, you can declare a mailbox with the LHS line
   `MyMailbox(type(TYPEa),type(TYPEb))`, and only `TYPEa` will be used. This
   affects all properties.

 - Probably more, but more care, attention, and time has gone into this
   validator than the Dialect 1 one.

## Dialect 3 Semantic Parser/Validator Call Graph

Figure 2 shows a call graph that I made this during the design process. May it
be of use to you.

![Dialect 3 semantic parser/validator call graph. Green ellipses denote
class-level data, where edges to/from indicate data write/read
dependencies. Boxes denote methods in `HardwareFileReader` prefixed with `d3_`,
where an edge to another box indicates that the method in the first box calls
the method in the second. Yellow boxes denote methods that examine sub-trees of
the parse graph. Validation methods are not shown (for
simplicity).](images/d3_call_graph.png)

# Input File Format (0.5.1)
This section defines the file format used by the Orchestrator to define its
internal model of the POETS Engine. The input files satisfy the general
"Universal Interface Format" (UIF) file format[^uifdocs]. The format supports
three dialects, which define the POETS Engine on different levels of
granularity. When the Orchestrator dumps a machine-readable output of its model
of the POETS Engine as part of the discovery process (once it is implemented),
that dump will be given in the most precise dialect version (dialect 3). This
section defines attributes that are common to all dialects in the Common
Attributes Section, then defines:

[^uifdocs]: The UIF documentation can be found in the Orchestrator repository,
    in the `Generics` directory.

 - Dialect 1, where items at each level of the hierarchy are the same as other
   items at that level ("horizontally homogeneous"), and where some topology
   information is assumed.

 - Dialect 2, which is as dialect 1, but allows the items contained at each
   level to vary ("horizontally heterogeneous"). For example, boxes can contain
   different numbers of boards, but must have the same properties
   otherwise. Topology is also explicitly defined in this dialect, but is
   constant at each level of the hierarchy. This dialect is not currently
   supported by the Orchestrator.

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
// ignored by the reader. Comments cannot be escaped. I'll be using
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
+datetime=20200909162500  // YYYYMMDDhhmmss
+version="0.5.1"
+file="my_first_example.uif"
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

   - `file`: The handle of the file in the file system[^fileMismatchWarning].

 - The `[header]` section may be opened with a description,
   e.g. `[header(Hafez)]` (where the description here is `Hafez`), as long as
   the description satisfies the regular expression
   `[a-zA-Z][a-zA-Z0-9]{1,31}`, and that only one header section is defined in
   a given file.

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
```

Points to note:

 - The `[packet_address_format]` section is mandatory, and must define the
   following variables (in any order):

   - `board`: The number of bits dedicated to defining the board-component of
     the address in the address word. Must be a positive integer.

   - `core`: As with `board`, but for cores.

   - `mailbox`: As with `board`, but for mailboxes.

   - `thread`: As with `board`, but for threads.

 - In this contrived example, the address is defined as a binary word, where
   the first (LSB) four bits define the thread address, the next two bits
   define the core address, the next eight bits define the mailbox address, the
   next four bits define the board address, and the next two bits define the
   box address, resulting in a $4+8+4+2=18$ bit word.

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
// The order variable definitions in a section does not matter.
+mailbox=(2,2,2)  // Three dimensions (can be one or more dimensions)
+thread=4  // Must be one-dimensional, always.
+core=2  // Must be one-dimensional, always.
+board=(4,4)  // Two dimensions (can be one or more dimensions)
```

Here, the address again defined as a binary word, where the first (LSB) four
bits define the thread address, the next two bits define the core address, the
next six bits define the mailbox address (two in each of the three dimensions),
and the next eight bits define the board address (four in each of the two
dimensions) resulting in a $4+2+(2\times3)+(4\times2)+2=22$ bit word.

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
+datetime=20200909162500
+version="0.5.1"

[packet_address_format]
+mailbox=(4,4)
+thread=4
+core=2
+board=4

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
// core in a box. Can be a float. Note that in a sane universe,
// core_core_cost is always double cost_mailbox_core, because core
// to core communications are always just
// core-to-mailbox + mailbox-to-core.
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

Appendix A contains a complete dialect 1 example file representing Coleridge.

## Dialect 2 (Horizontally-Heterogeneous, not supported)
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
(0,0):Io(addr(00),boards(B0,B1),hostname(io))
(1,0):Europa(addr(10),boards(B0,B1),hostname(europa))
(0,1):Ganymede(addr(01),boards(B0,B1),hostname(ganymede))
(1,1):Callisto(addr(11),boards(B0,B1),hostname(callisto))
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

 - Figure 3 shows the graph of the boards described by this example, along with
   their containing boxes.

 - The line `(0,0):Io(addr(00),boards(Board0,Board1),hostname(io))` in the
   `[engine_box]` section defines a box:

   - named `Io`,

   - with MPI name `io` (the hostname directive is optional),

   - at position `(0,0)` in the engine co-ordinate system[^positioning]. The
     position can be omitted, in which case the line would be
     `Io(addr(00),boards(B0,B1),hostname(io))`,

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
   this is in boxes, which are not constrained by format (and are not actually
   used in the current iteration of Tinsel).

 - The graph of mailboxes mailboxes in a board is defined similarly to the
   graph of boards in the engine, as demonstrated by the Coleridge example in
   Appendix A.

 - When edge weights are not defined explicitly in a graph, as with the line\
   `(0,0):Io(board(B0),addr(0))=Io(board(B1),cost(5)),Europa(board(B0))`, the
   value defined in `board_board_cost` is used (20 in this case). `X_X_cost` is
   used in the general case, where `X` is the level of the contained items.

 - Boxes, boards, and mailboxes can have any name as long as they match the
   regular expression `[a-zA-Z][a-zA-Z0-9]{1,31}`, and are unique within the
   item that contains them.

 - As with dialect 1, multidimensional addresses are supported. Example box
   declaration: `(0,0):Io(addr(00,01),boards(B0,B1))`.

 - Different boxes can contain different quantities of boards.

![Weighted graph of boards described by the dialect 2 example, where each board
(red) is contained in a box (blue). All boxes and all boards are of the same
"type" (see the Dialect 3 Section for information on
types).](images/dialect_2.png){width=90%}

Appendix A contains a complete dialect 2 example file representing Coleridge.

## Dialect 3 (Fully-Heterogeneous)
Dialect 3 supports heterogeneity across levels of the hierarchy, so that each
box can have different properties from other boxes, and each board can be
different from each other board, and so on. Dialect 3 maintains support for the
weighted graph topology introduced in dialect 2, and extends it to support
section types, to model "hardware types". By way of example, two boards with
the same type will have the same constituents and topology (quantity and
configuration) of mailboxes and packet costs associated with them, whereas two
boards of different types may not. Here are example `[engine_box]` and
`[engine_board]` sections for dialect 3, where the `→` character denotes a line
continuation:

```
[engine_box]
// Define four boxes with three different types. Note that each box
// contains two boards, apart from one box which contains one board.
(0,0):Io(addr(00),type(TYPEef752a19),boards(B0,B1),hostname(io))
(1,0):Europa(addr(10),type(TYPEc92e3bc1),boards(B0),hostname(europa))
(0,1):Ganymede(addr(01),type(TYPEdcecd67b),boards(B0,B1),hostname(ganymede))
(1,1):Callisto(addr(11),type(TYPEdcecd67b),boards(B0,B1),hostname(callisto))
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

 - Figure 4 shows the graph of the boards described by this example, along with
   their containing boxes, where each colour of box and each colour of board
   denotes an item of a certain type. Every item must have a type.

 - The line `(0,0):Io(addr(00),type(TYPEef752a19),boards(B0,B1),hostname(io))`
   in the `[engine_box]` section defines a box:

   - named `Io`, as with dialect 2,

   - with MPI name `io` (the hostname directive is optional), as with dialect
     2,

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
   long as they match the regular expression `[a-zA-Z][a-zA-Z0-9]{1,31}`, and
   are unique on a given level of the hierarchy. Types do not have to begin
   with `TYPE` (it's done here more to emphasise the point). Unlike with
   dialect 2, the extra level of heterogeneity provided by dialect 3 allows
   these names and types to be defined by unique identifiers derived from
   hardware.

Types can also be defined as defaults. The following two blocks are synonyms of
the previous dialect 3 example given in this section using default type
definitions:

```
[engine_box]
(0,0):Io(addr(00),type(TYPEef752a19),boards(B0,B1),hostname(io))
(1,0):Europa(addr(01),type(TYPEc92e3bc1),boards(B0),hostname(europa))
(0,1):Ganymede(addr(10),boards(B0,B1),hostname(ganymede))
(1,1):Callisto(addr(11),boards(B0,B1),hostname(callisto))
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
(0,0):Io(addr(00),type(TYPEef752a19),boards(B0,B1),hostname(io))
(1,0):Europa(addr(01),type(TYPEc92e3bc1),boards(B0),hostname(europa))
(0,1):Ganymede(addr(10),boards(B0,B1),hostname(ganymede))
(1,1):Callisto(addr(11),boards(B0,B1),hostname(callisto))
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

Also note additional fields in mailbox sections:

```
[mailbox(SomeMailboxType)]
...
+pair_cores="true"
+core_addr_offset=3
```

The `pair_cores` field in `mailbox` sections is mandatory, and must have either
a `"true"` or `"false"` value, indicating whether or not neighbouring cores
share instruction memory in this engine. For most non-Tinsel architectures this
should be `"false"`. Note that if this is `"true"`, the value in the `cores`
field for this mailbox section must be even. The `core_addr_offset` field in
`mailbox` sections is optional, and defines the lowest value for the core
components of hardware addresses for cores in mailboxes of that type. If not
defined, the default value for `core_addr_offset` is zero.

![Weighted graph of boards described by the dialect 3 example, where each board
is contained in a box. The colour of each item denotes its
type.](images/dialect_3.png)

Appendix A contains a complete dialect 3 example file representing Coleridge.

# Appendix A: Coleridge Hardware Input Files (0.5.1)
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
+datetime=20200909162500
+version="0.5.1"
+file="dialect_1"

[packet_address_format]
+mailbox=(2,2)
+thread=4
+core=2
+board=(2,2)

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
+datetime=20200909162500
+version="0.5.1"
+file="dialect_2"

[packet_address_format]
+mailbox=(2,2)
+thread=4
+core=2
+board=(2,2)

[engine_box]
Box(addr(0),boards(B0,B1,B2,B3,B4,B5),hostname(coleridge))
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
+datetime=20200909162500
+version="0.5.1"
+file="dialect_3"

[packet_address_format]
+mailbox=(2,2)
+thread=4
+core=2
+board=(2,2)

[default_types]
+box_type="CommonBox"
+board_type="CommonBoard"
+mailbox_type="CommonMbox"

[engine_box]
Box(addr(0),boards(B0,B1,B2,B3,B4,B5),hostname(coleridge))
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
+pair_cores="true"

[core]
+threads=16
+instruction_memory=8  // KiB
+data_memory=*  // <!> Missing
+core_thread_cost=*  // <!> Missing
+thread_thread_cost=*  // <!> Missing
```
