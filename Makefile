# Makes PDFs from all markdown files in the root directory.

# Requires pandoc (https://pandoc.org), but you can just read the plaintext if
# you want.

BUILDER := "pandoc"
BUILDER_FLAGS := "--number-sections"
SOURCES := $(wildcard ./*.md)
TARGETS := $(patsubst ./%.md,./%.pdf,$(SOURCES))

all: $(TARGETS)

clean:
	rm --force $(TARGETS)

# Builds one PDF from one markdown file.
%.pdf:: %.md
	"$(BUILDER)" "$(BUILDER_FLAGS)" --output="$@" "$^"

.PHONY: all clean
