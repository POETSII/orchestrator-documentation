# Makes PDFs from all markdown files in the root directory.

# General requirements:
#  - pandoc (https://pandoc.org).
#
# Build-specific requirements:
#  - PDF:
#    - requires LaTeX (I use texlive, texlive-latex-extra is sufficient).
#    - requires fvextra (you can get this from
#      https://github.com/gpoore/fvextra.git)


DOC_BUILDER := "pandoc"
DOC_BUILDER_FLAGS := "--number-sections --highlight-style tango"
DOC_SOURCES_DIR := source
DOC_TARGETS_DIR := build

GRAPH_BUILDER := "dot"
GRAPH_SOURCES_DIR := images/source
GRAPH_TARGETS_DIR := images

# Defines targets using a given extension. Arguments:
#  - $1: Desired extension (e.g. "doc").
define targets_for_filetype
    $(patsubst $(DOC_SOURCES_DIR)/%.md,\
	    $(DOC_TARGETS_DIR)/%.$1,\
        $(wildcard $(DOC_SOURCES_DIR)/*.md))
endef

# Build a document using pandoc. Use only in a rule definition. Takes no
# arguments.
define pandoc_build
	mkdir --parents "$(DOC_TARGETS_DIR)"
	"$(DOC_BUILDER)" "$(DOC_BUILDER_FLAGS)" --output="$@" $(filter %.md, $^)
endef

# Define images to build.
ALL_IMAGE_TARGETS := $(GRAPH_TARGETS_DIR)/addressing_structure.pdf \
                     $(GRAPH_TARGETS_DIR)/bridge_board.pdf \
                     $(GRAPH_TARGETS_DIR)/dialect_2.pdf \
                     $(GRAPH_TARGETS_DIR)/dialect_3.pdf \
                     $(GRAPH_TARGETS_DIR)/engine_structure_simple.pdf \
                     $(GRAPH_TARGETS_DIR)/generic_graph.pdf \
                     $(GRAPH_TARGETS_DIR)/interaction_diagram.pdf \
                     $(GRAPH_TARGETS_DIR)/mailbox_board_interaction.pdf
.NOT_INTERMEDIATE: $(ALL_IMAGE_TARGETS)

# Define targets and backmatter dependencies. Backmatter dependencies are stuck
# on the end of markdown files (literally cat-style) before pandoc parses them.
DOCX_TARGETS := $(call targets_for_filetype,docx)
PDF_TARGETS := $(call targets_for_filetype,pdf)
PDF_BACKMATTER := $(DOC_SOURCES_DIR)/include/latex.md
ALL_TARGETS := $(DOCX_TARGETS) $(PDF_TARGETS)

# General targets
all: $(ALL_TARGETS)

clean:
	$(RM) $(ALL_DOC_TARGETS) $(ALL_IMAGE_TARGETS)

# Targets for document types.
docx: $(DOCX_DOC_TARGETS)

pdf: $(PDF_DOC_TARGETS)

# Builds one PDF from one markdown file, using the backmatter (dependency
# order matters).
$(DOC_TARGETS_DIR)/%.pdf: $(DOC_SOURCES_DIR)/%.md $(PDF_BACKMATTER) $(ALL_IMAGE_TARGETS)
	$(call pandoc_build)

# Builds one DOCX file from one markdown file, using no backmatter.
$(DOC_TARGETS_DIR)/%.docx: $(DOC_SOURCES_DIR)/%.md $(ALL_IMAGE_TARGETS)
	$(call pandoc_build)

# Builds one PDF from one dot (graph) file.
$(GRAPH_TARGETS_DIR)/%.pdf: $(GRAPH_SOURCES_DIR)/%.dot
	mkdir --parents "$(GRAPH_TARGETS_DIR)"
	"$(GRAPH_BUILDER)" -Tpdf "$^" -o "$@"

.PHONY: all clean docx pdf
