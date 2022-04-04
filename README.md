# Orchestrator Documentation

This repository contains documentation on the Orchestrator component of
POETS. This documentation is a work in progress. You can download the latest
(stable) documentation from the releases tab - that documentation will align
with the development version of the Orchestrator at
https://github.com/poetsii/orchestrator/.

Build status: [![CircleCI](https://circleci.com/gh/POETSII/orchestrator-documentation.svg?style=svg)](https://circleci.com/gh/POETSII/orchestrator-documentation)

## Structure

The documentation for the Orchestrator is structured into volumes:

 - Volume I: Introduction (the big picture).

 - Volume II: Application Definition (the interface between the domain-specific
   front ends and the Orchestrator XML file specification).

 - Volume III: Orchestrator Internals (internal structure and function of the
   domain-agnostic software layer). This volume consists of a main document,
   and a series of annexes listed in that main document.

 - Volume IV: User Guide (how the operator interacts with the Orchestrator)

Some of this documentation exists in word-processing document format (`*.doc`),
while others exist in Pandoc markdown (`*.md`).

## Word-Processed Documents

Word-processing documents exist in the `word-processed` directory of this
repository, under [large file storage](https://git-lfs.github.com/), alongside
their (`*.pdf`) equivalents. Each word-processed document maintains its own
version within the document.

## Markdown

Pandoc markdown documents exist in the `source` directory, and is designed to
be built using Pandoc (https://pandoc.org) using the provided `Makefile`. A
list of build dependencies is formally maintained in that Makefile, but
generally the Makefile requires the following to function as intended:

 - A POSIX-compliant shell
 - Pandoc (obviously)
 - A dot processor for images
 - LaTeX (we use texlive)

Pandoc markdown documents use the git revision as a version, though releases
are given their own semantic version.
