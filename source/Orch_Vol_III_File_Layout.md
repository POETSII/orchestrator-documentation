% Orchestrator Documentation Volume III Annex: File Layout
\thispagestyle{fancy}

# Overview

This document shows the file layout for the Orchestrator. This layout
describes:

 - source files used to compile the Orchestrator
 - binary and dependency files created as part of compilation
 - binary files created as part of application composition and deployment
 - runtime-configuration files
 - unit and integration test files
 - continuous integration files
 - documentation files

# Layout

The listing below shows the layout for everything except the Orchestrator
documentation, where:

 - entries ending in a solidus (`/`) denote directories.
 - entries ending in a question mark (`?`) may be altered in run-time
   configuration, from `Config/Orchestrator.ocfg`, which itself must exist.
 - entries ending in a tilde (`~`) are created by compilation. Entries created
   by the Make/GCC build process are shown here.
 - entries ending in a caret (`^`) are created by application composition or
   deployment, or from usual Orchestrator operation.
 - entries between less-than and greater-than symbols (`<` and `>`) have names
   defined during Orchestrator run-time.

Layout subject to change.

```
From the root directory of the Orchestrator:

Batch/?                         # User-generated batch files invoked from here.
bin/~                           # Executable binaries placed here by the build process:
    dummy~                      # - process for stress-testing
    injector~                   # - process for advanced C&C
    logserver~                  # - process for centralised logging
    mothership~                 # - process for application deployment and C&C
    orchestrate~                # - launcher metaprocess
    root~                       # - process for managing the Orchestrator
    rtcl~                       # - process for resolving clock events
Build/                          # Compilation/linking logic for Orchestrator executables:
    Borland/                    # - build profiles for the Borland toolchain
        Objects/                #   - compiled objects are written here
    gcc/                        # - build profiles for the Make/GCC toolchain
        Dependency_lists/~      #   - procedurally-generated source dependency
                                #     lists
        Objects/~               #   - compiled objects are written here
        Resources/              #   - script templates
        Makefile                #   - defines rules for the build process
        Makefile.dependencies   #   - defines software dependencies
        Makefile.executable_prerequisites  # - defines file prerequisites
        Makefile.test_prerequisites        # - as above, for tests
.ci/                            # Scripts used for continuous integration
Config/                         # Holds various configuration files:
    OrchestratorMessages.ocfg?  # - log message format strings
    Orchestrator.ocfg           # - master configuration (defines all '?'s)
    POETSHardwareOneBox.ocfg?   # - default hardware model
    V4Grammar3.ocfg?            # - application XML grammar
Generics/                       # Useful, project-agnostic tools...
    docs/                       # ...and their documentation.
orchestrate.sh~                 # Convenience script to set up the environment for the Launcher.
Output/                         # Component-specific outputs.
    Composer/?
    Microlog/?
    Placement/?
    POETS.log?^
README.md                       # Introductory readme
Source/
    Common/                     # Source used by multiple MPI processes
    Dummy/                      # Process for stress-testing
    Injector/                   # Process for advanced C&C
    Launcher/                   # Launcher metaprocess
    LogServer/                  # Process for centralised logging
    Monitor/                    # Process for displaying activity (WIP)
    Mothership/                 # Process for application deployment and C&C
    NameServer/                 # Process holding database of names (WIP)
        AddressBook/
    OrchBase/                   # Base class for Root:
        AppStructures/
        Handlers/
        HardwareConfigurationDeployment/
        HardwareFileReader/
        HardwareModel/
        Placement/
        XMLProcessing/
    RemoteIO/                   # Component of UserIO
    Root/                       # Process for operator-facing actions
    RTCL/                       # Process for real-time clock operation
    Softswitch/                 # Deployed-to-chip POETS code components
        inc/
        src/
    Supervisor/                 # Deployed-to-x86 POETS code components
    UserIO/                     # Process for online communication (WIP)
Tests/                          # Contains unit tests
    catch.hpp                   # All-in-one include file for testing framework.
    Placement/
    ReferenceXML/
    StaticResources/

From the home directory on a Mothership host machine:

.orchestrator/app_binaries/?^   # Holds binaries deployed to this Mothership...
    <APPNAME>/^                 # ...on a per-application basis.
        libSupervisor.so
        softswitch_<ID>.elf
        softswitch_code_<ID>.v
.orchestrator/app_output/?^     # Output files from applications running on this Mothership.
```

## Documentation Layout

The listing below shows the layout for the Orchestrator documentation. Layout
subject to change.

```
pdf/                            # PDFs created from both Word and Pandoc.
    Orch_Vol_I.pdf
    Orch_Vol_II.pdf
    Orch_Vol_III.pdf
    Orch_Vol_III_File_Layout.pdf
    Orch_Vol_III_Hardware_Description_Format_and_Reader.pdf
    Orch_Vol_III_Hardware_Model.pdf
    Orch_Vol_III_Launcher.pdf
    Orch_Vol_III_Mothership.pdf
    Orch_Vol_III_Packet_Format.pdf
    Orch_Vol_III_Placement.pdf
    Orch_Vol_III_Softswitches_Supervisor_and_Composer.pdf
    Orch_Vol_IV.pdf
repo/                           # A clone of the Orchestrator documentation
                                #     repository, containing Pandoc and Word
                                #     files matching with those in ../pdf.
    [...]                       # Various directories, described in the
                                #     Orchestrator documentation repository.
    source/                     # Pandoc source files (*.md)
    word-processed/             # Word files (*.doc)
```

![](images/white_px.png)
