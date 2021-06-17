% Addresses in the Orchestrator

# Overview

This document introduces address formats used for device-to-device
communication of applications in the Orchestrator. Detailed understanding of
how applications are represented as a set of devices and pins is assumed.

Three types of device exist, each of which can participate as part of a POETS
application running on the Orchestrator:

 - Normal device: Compute devices deployed onto threads in Tinsel cores,
   serviced by a softswitch.

 - Supervisor device: A device run on the Mothership (an x86 machine).

 - External device: A device run on any hardware, which communicates with other
   devices through the UserIO process and the Mothership (not yet implemented).

All non-trivial applications run using the Orchestrator consist of at least one
normal device (but usually many more) and at least one supervisor device (a
default supervisor is used if one is not defined by the application
writer). Devices communicate using destination-routed packets, with:

 - A header (96 bits), consisting of:

   - A Hardware address (32 bits), which uniquely identifies the compute thread
     in the POETS Engine to send the message to (documented in
     "hardware_model.pdf"). This addresses is used by the Engine to direct the
     packet.

   - A Software address (32 bits), which uniquely identifies a device in that
     thread, with some space dedicated to exceptional softswitch operations
     (documented in the Software Addresses section).

   - A pin target (32 bits), which uniquely identifies the pin on the target
     device, with some space dedicated to exceptional device operations
     (documented in the Pin Targets section).

 - A payload (56 bytes)[^This size is designed to hold exactly six
   double-precision fields and a four byte label, which can neatly represent
   e.g. position and velocity data for a single point in three-dimensional
   space.], populated by the sending device created by the application writer,
   and read by the corresponding receiving device.

# Software Addresses

Software addresses are 32-bit binary strings. Together, a software address and
a hardware address are sufficient to uniquely identify a device deployed as
part of a POETS application. Unlike hardware addresses, software addresses are
defined by a series of fixed-at-compile-time-width fields. Software addresses
are of the form (MSB to LSB):

$$C_{\mathrm{MOTHERSHIP}}\cdot C_{\mathrm{CNC}}\cdot C_{\mathrm{TASK}}\cdot
C_{\mathrm{OPCODE}}\cdot C_{\mathrm{DEVICE}}$$

where $\cdot$ represents a concatenation, and where each address component $C$
is denoted by Table 1. Table 2 shows, for each device type, how address
components may vary.

-------------------------------------------------------------------------------
Component  Bit range Description
$C$
---------- --------- ----------------------------------------------------------
MOTHERSHIP 0 (1b)    Is 1 if the hardware address that accompanies this
                     software address is the Tinsel address of a Mothership,
                     and 0 otherwise. The existence of this bit, together with
                     $C_{\mathrm{CNC}}$, allows the device type to be
                     determined from the software address (see Table 2).

CNC        1 (1b)    Is 1 if a device is a command-and-control (CNC) device,
                     and 0 otherwise. The existence of this bit, together with
                     $C_{\mathrm{MOTHERSHIP}}$, allows the device type to be
                     determined from the software address (see Table 2). If a
                     normal device is targeted with $C_{\mathrm{CNC}}=1$, its
                     `OnCtl` handler is invoked.

TASK       2-7 (6b)  Denotes the Orchestrator task that this device is
                     associated with. This value ranges in $[0,63]$ (where
                     $63=2^6-1$).

OPCODE     8-15 (8b) Denotes an operation code for messages to CNC devices or
                     handlers. This component is zero if $C_{\mathrm{CNC}}=0$.

DEVICE     16-31     Denotes the ID of a device.
           (16b)
-------------------------------------------------------------------------------

Table: Bit ranges for each software address component (MSB to LSB).

------------------------------------------------
Device type    MOTHERSHIP CNC TASK OPCODE DEVICE
-------------- ---------- --- ---- ------ ------
Normal         0          0   ...  0      ...

External       1          0   ...  0      ...

Supervisor     1          1   ...  ...    0

Normal (onCtl) 0          1   ...  ...    ...
------------------------------------------------

Table: Enforced encodings for fields as a function of the device they point
to. A 1 or a 0 in a field indicates an encoding identity for that device type,
where an ellipsis (...) indicates that the component is free to vary, as long
as the address as a whole uniquely identifies a device.

## Examples

This section presents some example software addresses, where $\cdot$ represents
a concatenation.

### Example 1: Normal device

$$0\mathrm{b}\cdot0\cdot0\cdot000011\cdot00000000\cdot0000001000000001
=0\mathrm{x}03000201
=0\mathrm{d}0050332161$$

This address corresponds to a normal device ($C_\mathrm{MOTHERSHIP}$ and
$C_\mathrm{CNC}$ are both zero) operating as part of task
$0\mathrm{b}000011=0\mathrm{d}3$. The device is number
$0\mathrm{b}0000001000000001=0\mathrm{d}513$ on the thread given by the
hardware address. This address may be part of a packet sent to this device by
another compute device (either another normal device, or an external),
containing context-sensitive data with which computation will be performed.

### Example 2: Supervisor device

$$0\mathrm{b}\cdot1\cdot1\cdot000000\cdot00000100\cdot0000000000000000
=0\mathrm{x}\mathrm{C}0040000
=0\mathrm{d}3221487616$$

This address corresponds to a supervisor device ($C_\mathrm{MOTHERSHIP}$ and
$C_\mathrm{CNC}$ are both one) operating as part of task
$0\mathrm{b}000011=0\mathrm{d}3$. The operation code
$0\mathrm{b}00000100=0\mathrm{d}4$ will be accessible to the "onCtl"
method. This address may be part of a packet sent to the supervisor to perform
a specific control action (or not, it could be anything really, depending on
what the supervisor is programmed to do).

### Example 3: External device

$$0\mathrm{b}\cdot1\cdot0\cdot111111\cdot00000000\cdot0011011000010101
=0\mathrm{x}\mathrm{BF}003615
=0\mathrm{d}3204462101$$

This address corresponds to an external device ($C_\mathrm{MOTHERSHIP}=1$ and
$C_\mathrm{CNC}=0$) operating as part of task
$0\mathrm{b}111111=0\mathrm{d}63$. The ID of this external device is
$0\mathrm{b}0011011000010101=0\mathrm{d}13845$.

### Example 4: Normal device with command-and-control instruction

$$0\mathrm{b}\cdot0\cdot1\cdot001000\cdot00000001\cdot0000001111101000
=0\mathrm{x}480103\mathrm{E}8
=0\mathrm{d}1208026088$$

This address corresponds to a normal device ($C_\mathrm{MOTHERSHIP}=0$ and
$C_\mathrm{CNC}=1$) operating as part of task
$0\mathrm{b}001000=0\mathrm{d}8$. The device is number
$0\mathrm{b}0000001111101000=0\mathrm{d}1000$ on the thread given by the
hardware address. The packet this address is attached to is a
command-and-control message ($C_\mathrm{CNC}=1$), and so will be handled by the
"onCtl" handler of this device, to which the operation code
$0\mathrm{b}00000001=0\mathrm{d}1$ will be accessible.

### Example 5: An invalid address

$$0\mathrm{b}\cdot1\cdot1\cdot111111\cdot11111111\cdot1111111111111111
=0\mathrm{xFFFFFFFF}
=0\mathrm{d}4294967295$$

This address is invalid because it appears to target a supervisor device
($C_\mathrm{MOTHERSHIP}$ and $C_\mathrm{CNC}$ are both one), but the device
component $C_\mathrm{DEVICE}$ is nonzero. This is unacceptable as per Table 2.

## Implementation

The functionality of the software address is encapsulated in the
`SoftwareAddress` class, which stores the address as a whole in
`SoftwareAddress::raw`, and stores "which components have been defined" in
`SoftwareAddress::definitions` (see the design notes). Getters and setters are
implemented around these members, along with methods to check whether
components have been defined. The intended usage of this class is to operate on
`SoftwareAddress` with the getters and setters, and checking whether or not
components are defined using the `is_X_defined` methods detailed below. The
following type definitions are introduced:

 - `SoftwareAddressInt -> uint32_t`: the entire address is a 32-bit binary
   string.

 - `IsMothershipComponent -> bool`: it either is, or is not.

 - `IsCncComponent -> bool`: it either is, or is not.

 - `TaskComponent -> uint8_t`: as the task component is only six bits in width,
   the two most-significant bits are unused.

 - `OpCodeComponent -> uint8_t`: fits perfectly.

 - `DeviceComponent -> uint16_t`: fits perfectly.

`SoftwareAddress` defines the following members:

 - `SoftwareAddressInt SoftwareAddress::raw`: Holds the software address, as
   defined by Section 1. Is initialised to `0` in the constructors.

 - `uint8_t SoftwareAddress::definitions`: Holds information on which
   components have been defined, where each bit represents a different
   component. If all five bits are `1`, then all components of the address have
   been defined. Is initialised to `0` in the constructors.

Given these type definitions, `SoftwareAddress` defines the following methods:

 - `SoftwareAddress::SoftwareAddress(IsMothershipComponent isMothership,
   IsCncComponent isCnc, TaskComponent task, OpCodeComponent opcode,
   DeviceComponent device)`: Constructs a software address from the components
   passed as arguments. Note that this calls
   `SoftwareAddres::set_task(TaskComponent value)`, which throws an
   `InvalidAddressException` if the task component passed in does not fit in
   six bits.

 - `SoftwareAddress::SoftwareAddress()`: Constructs a zero software address,
   and sets `definitions` to zero (because nothing has been defined
   yet). Calling `SoftwareAddress::as_uint()` on an address constructed in this
   way without first defining the components will return zero.

 - Various getters, which retrieve individual defined components:

   - `IsMothershipComponent SoftwareAddress::get_ismothership()`
   - `IsCncComponent SoftwareAddress::get_iscnc()`
   - `TaskComponent SoftwareAddress::get_task()`
   - `OpCodeComponent SoftwareAddress::get_opcode()`
   - `DeviceComponent SoftwareAddress::get_device()`

   these "get" operations are performed by shifting and masking
   `SoftwareAddress::raw`.

 - Various setters, which set individual defined components:

   - `void SoftwareAddress::set_ismothership(IsMothershipComponent value)`
   - `void SoftwareAddress::set_iscnc(IsCncComponent value)`
   - `void SoftwareAddress::set_task(TaskComponent value)`
   - `void SoftwareAddress::set_opcode(OpCodeComponent value)`
   - `void SoftwareAddress::set_device(DeviceComponent value)`

   these "set" operations are performed by clearing the component of
   `SoftwareAddress::raw` with a mask, shifting `value`, then applying it to
   `SoftwareAddress::raw`. Note that `set_task(TaskComponent value)` will throw
   an `InvalidAddressException` if `value` does not fit in six bits
   (e.g. `value` $>63)$.

 - `SoftwareAddressInt SoftwareAddress::get_software_address()`: returns
   `SoftwareAddress::raw`.

 - `SoftwareAddressInt SoftwareAddress::as_uint()`: is a synonym of
   `get_software_address`.

 - `bool SoftwareAddress::is_fully_defined()`: returns `true` if each component
   in this `SoftwareAddress` has been fully defined, and `false` otherwise.

 - Methods to check whether or not components have been defined. These return
   `true` if the component has been defined, and `false` otherwise:

   - `bool SoftwareAddress::is_ismothership_defined()`
   - `bool SoftwareAddress::is_iscnc_defined()`
   - `bool SoftwareAddress::is_task_defined()`
   - `bool SoftwareAddress::is_opcode_defined()`
   - `bool SoftwareAddress::is_device_defined()`

 - `void SoftwareAddress::set_defined()`: A convenience method for defining
   individual bits of `SoftwareAddress::definitions`.

An example dump (`SoftwareAddress::Dump()`) of a supervisor device
follows. Note that the device component remains unset at the valid value $0$.

```
Software address at 0x00007ffc5d80ca70 ++++++++++++++++++++++++++++++++++++++++
raw: 0xc20b0000
isMothership: true
isCnc: true
task: 2
opCode: 11
device: 0 (not defined)
Software address at 0x00007ffc5d80ca70 ----------------------------------------
```

The `SoftwareAddress` class is tested by the `TestSoftwareAddress.cpp` catch
test suite.

## Design Notes

 - The bit ranges are flexible - there are a bunch of spare bits in the device
   field that are unlikely to be used. Bits from there can be pilfered and
   given to another field if it is necessary later.

 - The $C_\mathrm{TASK}$ component of the software address is particularly
   relevant for supervisor devices; as supervisor devices on the same box have
   the same hardware address, because they all run on the same
   Mothership. Since many tasks may be deployed within the same box, this field
   allows supervisor devices to be distinguished.

 - Multiple instances of the `SoftwareAddress` class are going to be produced
   when a given application is used by the Orchestrator, so the data footprint
   of the `SoftwareAddress` class should be kept as low as reasonably
   possible. The 32-bit binary string `SoftwareAddress::raw` stores the
   components in the most condensed form possible, while
   `SoftwareAddress::definitions` stores whether or not the address components
   have been defined efficiently.

 - Note that the `SoftwareAddress` class does not check for invalid address
   combinations (i.e. $C_\mathrm{CNC}=0$ and $C_\mathrm{OPCODE}\ne0$). This is
   to allow address components to be set in stages to support copy
   construction. If validation of this sort is needed in future, we could
   implement classes for each device type to restrict these combinations.

# Pin Targets

Pin targets, like software addresses, are 32-bit binary strings. Together, a
pin target, a software address, and a hardware address are sufficient to
identify a receiving device and the pin it must receive on, which exposes the
handler to call in response to receiving the message, and the properties and
state information associated with the edge attached to that pin. All of this
information is necessary to correctly execute the `OnReceive` handler defined
for the input pin.

**The form of pin targets differs depending on the sending device, the
receiving device, and whether or not the packet is a command-and-control
packet.** For normal packet traffic (i.e. not command-and-control traffic)
between devices, pin targets are of the form (MSB to LSB):

$$C_{\mathrm{EDGE}}\cdot C_{\mathrm{PIN}}$$

where $\cdot$ represents a concatenation, and where each address component $C$
is denoted by Table 3.

-------------------------------------------------------------------------------
Component  Bit range  Description
$C$
---------- ---------- ---------------------------------------------------------
EDGE       0-23 (24b) Index identifying the edge instance in the application,
                      from the perspective of the device receiving the packet
                      (defines certain properties and state information).

PIN        24-31 (8b) Index identifying the pin instance on the device
                      receiving the packet (determines the handler to invoke).
-------------------------------------------------------------------------------

Table: Bit ranges for each pin target component (MSB to LSB).

For command-and-control traffic from a Softswitch to its corresponding
Mothership, the two fields $C_{\mathrm{EDGE}}\cdot C_{\mathrm{PIN}}$ are
combined, and are used to store the 32-bit hardware address of the sending
device^[Being destination-routed, there is no other way to identify who sent a
packet, other than through edge/pin information (which is previously encoded),
or through a hardware address. This is necessary for exfiltrating
instrumentation data from a softswitch, for example.].

# A Note from GMB

There are a couple of cases where I would like to be able to populate this
(sic, "pin targets") on a message to a supervisor. The most significant one is
for log messages from a device. It is easy enough to get the source hardware
address (by usurping the Pin Target), but short of adding a header that reduces
the log payload size, there is nowhere to put the source device address. I
would like (for specific op codes) to be able to use Device to indicate the
source device address rather than being forced to 0.
