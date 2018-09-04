# Makes PDFs from all markdown files in the root directory.

# General requirements:
#  - pandoc (https://pandoc.org).
#
# Build-specific requirements:
#  - PDF: requires LaTeX (texlive is fine).

BUILDER := "pandoc"
BUILDER_FLAGS := "--number-sections --highlight-style tango"
SOURCES_DIR := source
TARGETS_DIR := build

# Defines targets using a given extension. Arguments:
#  - $1: Desired extension (e.g. "doc").
define targets_for_filetype
    $(patsubst $(SOURCES_DIR)/%.md,\
	    $(TARGETS_DIR)/%.$1,\
        $(wildcard $(SOURCES_DIR)/*.md))
endef

# Build a document using pandoc. Use only in a rule definition. Takes no
# arguments.
define pandoc_build
	mkdir --parents "$(TARGETS_DIR)"
	"$(BUILDER)" "$(BUILDER_FLAGS)" --output="$@" $^
endef

# Define targets and backmatter dependencies. Backmatter dependencies are stuck
# on the end of markdown files (literally cat-style) before pandoc parses them.
DOCX_TARGETS := $(call targets_for_filetype,docx)
PDF_TARGETS := $(call targets_for_filetype,pdf)
PDF_BACKMATTER := $(SOURCES_DIR)/include/latex.md
ALL_TARGETS := $(DOCX_TARGETS) $(PDF_TARGETS)

# General targets
all: $(ALL_TARGETS)

clean:
	$(RM) $(ALL_TARGETS)

# Targets for document types.
docx: $(DOCX_TARGETS)

pdf: $(PDF_TARGETS)

# Builds one PDF from one markdown file, using the backmatter (dependency
# order matters).
$(TARGETS_DIR)/%.pdf:: $(SOURCES_DIR)/%.md $(PDF_BACKMATTER)
	$(call pandoc_build)

# Builds one DOCX file from one markdown file, using no backmatter.
$(TARGETS_DIR)/%.docx:: $(SOURCES_DIR)/%.md
	$(call pandoc_build)

.PHONY: all clean docx pdf
