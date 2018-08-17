# Makes PDFs from all markdown files in the root directory.

# Requires pandoc (https://pandoc.org), but you can just read the plaintext if
# you want.

BUILDER := "pandoc"
BUILDER_FLAGS := "--number-sections"
SOURCES_DIR := source
TARGETS_DIR := build
TARGETS := $(patsubst $(SOURCES_DIR)/%.md,\
                      $(TARGETS_DIR)/%.pdf,\
                      $(wildcard $(SOURCES_DIR)/*.md))
PDF_FRONTMATTER := $(SOURCES_DIR)/include/latex.md

all: $(TARGETS)

clean:
	$(RM) $(TARGETS)

# Builds one PDF from one markdown file, using the frontmatter (dependency
# order matters).
$(TARGETS_DIR)/%.pdf:: $(SOURCES_DIR)/%.md $(PDF_FRONTMATTER)
	mkdir --parents "$(TARGETS_DIR)"
	"$(BUILDER)" "$(BUILDER_FLAGS)" --output="$@" $^

.PHONY: all clean
