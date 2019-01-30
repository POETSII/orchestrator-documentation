# Orchestrator Documentation

This repository contains documentation on the Orchestrator component of
POETS.

Two components of documentation exist: the implementation documentation, and
the user guide. Both live in this repository.

## Implementation Documentation

The implementation documentation motivates POETS and the Orchestrator, and
describes the internals and interfaces of the Orchestrator in considerable
detail. The most recent version of the implementation documentation exists in
the `implementation_documentation` directory of this repository, on the master
branch. You can download this
[here](https://github.com/POETSII/orchestrator-documentation/tree/master/implementation_documentation)
This documentation is a work in progress.

## User Guide

You can download the latest stable user guide documentation from
[here](https://github.com/POETSII/orchestrator-documentation/releases).

Build status: [![CircleCI](https://circleci.com/gh/POETSII/orchestrator-documentation.svg?style=svg)](https://circleci.com/gh/POETSII/orchestrator-documentation)

The documentation is in plain text, specifically pandoc markdown. The supported
builder is pandoc (https://pandoc.org), but you should be able to use pretty
much any builder you like. A list of dependencies is maintained in the
Makefile.

If you wish to edit this documentation, branch off development, and raise a
pull request (https://github.com/POETSII/orchestrator-documentation/compare) so
that your changes can be discussed. Please do not commit directly into the
master branch.

Changes to the documentation should go through a review process, to be
determined. For now, talk to MLV.
