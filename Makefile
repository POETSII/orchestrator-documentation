# Makes PDFs from all markdown files in the root directory.

# Requirements:
#  - pandoc (https://pandoc.org).
#  - A dot processor (I use graphviz). Syntax must be compatible with the
#    'dot_build' routine,
#  - PDF builds require:
#    - LaTeX (I use texlive, texlive-latex-extra is almost sufficient).
#    - fvextra (you can get this from https://github.com/gpoore/fvextra.git)

BUILDER := "pandoc"
BUILDER_FLAGS := "--toc --number-sections --highlight-style tango --metadata author="Compiled: `date --iso-8601=date`. Revision: `git rev-parse --short HEAD`""
TEXT_SOURCES_DIR := source
TEXT_TARGETS_DIR := build

GRAPH_BUILDER := "dot"
GRAPH_SOURCES_DIR := images/source
GRAPH_TARGETS_DIR := images

MD := mkdir --parents
PRINT := printf

# Defines targets using a given extension. Arguments:
#  - $1: Desired extension (e.g. "pdf").
define targets_for_filetype
    $(patsubst $(TEXT_SOURCES_DIR)/%.md,\
	    $(TEXT_TARGETS_DIR)/%.$1,\
        $(wildcard $(TEXT_SOURCES_DIR)/*.md))
endef

# Build a document using pandoc. Use only in a rule definition. Takes no
# arguments.
define pandoc_build
	@$(PRINT) "[....] Building \"$@\"..."
	@$(MD) "$(TEXT_TARGETS_DIR)"
	@$(BUILDER) "$(BUILDER_FLAGS)" --output="$@" $(filter %.md, $^)
	@$(PRINT) "\r[DONE] Building \"$@\".\n"
endef

# Build a graph image using your dot builder of choice. Use only in a rule
# definition. Note that this generates a non-vector image. MS word can't
# understand pdf images in docx at half past four on a Sunday, gs font
# configuration is poorly integrated in most Linuxes so epstopdf produces
# warnings on every platform I've tried. So we're using PNGs. Nobody is happy
# to make everybody happy, I suppose.
#
# Takes no arguments.
define dot_build
	@$(PRINT) "[....] Building \"$@\"..."
	@$(MD) "$(GRAPH_TARGETS_DIR)"
	@$(GRAPH_BUILDER) -Tpng -Gdpi=300 "$^" -o "$@"
	@$(PRINT) "\r[DONE] Building \"$@\".\n"
endef

# Define images to build.
ALL_IMAGE_TARGETS := $(GRAPH_TARGETS_DIR)/addressing_structure.png \
                     $(GRAPH_TARGETS_DIR)/bridge_board.png \
                     $(GRAPH_TARGETS_DIR)/d3_call_graph.png \
                     $(GRAPH_TARGETS_DIR)/dialect_2.png \
                     $(GRAPH_TARGETS_DIR)/dialect_3.png \
                     $(GRAPH_TARGETS_DIR)/engine_structure_simple.png \
                     $(GRAPH_TARGETS_DIR)/generic_graph.png \
                     $(GRAPH_TARGETS_DIR)/interaction_diagram.png \
                     $(GRAPH_TARGETS_DIR)/mailbox_board_interaction.png \
                     $(GRAPH_TARGETS_DIR)/mothership_data_structure.png \
                     $(GRAPH_TARGETS_DIR)/mothership_producer_consumer.png \
                     $(GRAPH_TARGETS_DIR)/placement_data_structure.png
.NOT_INTERMEDIATE: $(ALL_IMAGE_TARGETS)

# Define targets and backmatter dependencies. Backmatter dependencies are stuck
# on the end of markdown files (literally cat-style) before pandoc parses them.
PDF_TARGETS := $(call targets_for_filetype,pdf)
PDF_BACKMATTER := $(TEXT_SOURCES_DIR)/include/latex.md
ALL_TARGETS := $(PDF_TARGETS)

# General targets
all: $(ALL_TARGETS)

clean:
	@$(PRINT) "[....] Clearing..."
	@$(RM) $(ALL_TARGETS) $(ALL_IMAGE_TARGETS)
	@$(PRINT) "\r[DONE] Clearing.\n"

# Targets for document types.
pdf: $(PDF_TARGETS)

# Builds one PDF from one markdown file, using the backmatter (dependency
# order matters).
$(TEXT_TARGETS_DIR)/%.pdf: $(TEXT_SOURCES_DIR)/%.md $(PDF_BACKMATTER) \
	$(ALL_IMAGE_TARGETS)
	$(call pandoc_build)

# Builds one PNG from one dot (graph) file.
$(GRAPH_TARGETS_DIR)/%.png: $(GRAPH_SOURCES_DIR)/%.dot
	$(call dot_build)

.PHONY: all clean pdf
