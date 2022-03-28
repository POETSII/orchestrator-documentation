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

The listing below shows the layout, which is subject to change, where:

 - entries ending in a solidus (`/`) denote directories
 - entries ending in a question mark (`?`) may be altered in run-time
   configuration, from `Orchestrator.ocfg`
 - entries ending in a tilde (`~`) are created by compilation. Entries created
   by the Make/GCC build process are shown here.
 - entries ending in a caret (`^`) are created by application composition or
   deployment, or from usual Orchestrator operation.

```
From the root directory of the Orchestrator:

Batch/?                         # User-generated batch files invoked from here.
bin/~                           # Executable binaries placed here:
    dummy~                      # - process for stress-testing 
    injector~                   # - process for advanced C&C
    logserver~                  # - process for centralised logging
    mothership~                 # - process for application deployment and C&C
    orchestrate~                # - launcher metaprocess
    root~                       # - process for managing the Orchestrator
    rtcl~                       # - process for resolving clock events
Build/                          # Compilation/linking logic for Orchestrator
                                # executables:
    Borland/                    # - build profiles for the Borland toolchain
    gcc/                        # - build profiles for the Make/GCC toolchain
        Dependency_lists/~      #   - procedurally-generated source dependency
                                #     lists
        Objects/~               #   - compiled objects are written here
        Resources/              #   - script templates
.ci/                             
Config/
    OrchestratorMessages.ocfg?  
    Orchestrator.ocfg
    POETSHardwareOneBox.ocfg?
    V4Grammar3.ocfg?
Generics/
    docs/
orchestrate.sh~
Output/
    Composer/?
    Microlog/?
    Placement/?
    POETS.log?^
README.md
Source/
    Common/
    Dummy/
    Injector/
    Launcher/
    LogServer/
    Monitor/
    Mothership/
    NameServer/
    OrchBase/
    RemoteIO/
    Root/
    RTCL/
    Softswitch/
    Supervisor/
    UserIO/
Tests/
    catch.hpp
    Placement/
    ReferenceXML/
    StaticResources/

From the home directory on a Mothership host machine:

.orchestrator/app_binaries/?^
.orchestrator/app_output/?^
```

<!> Documentation?

![](images/white_px.png)