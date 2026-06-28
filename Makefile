PANDOC := pandoc
IMG_DIR := playbooks/images

PANDOC_FLAGS := --from markdown --to pdf --pdf-engine=xelatex \
    -V geometry:margin=1in \
    -V geometry:headheight=52pt \
    -V fontsize=11pt \
    -V documentclass=article \
    -V colorlinks=true \
    -V linkcolor=blue \
    -V urlcolor=blue \
    -V header-includes='\usepackage{fancyhdr}\usepackage{graphicx}\pagestyle{fancy}\fancyhead[L]{\includegraphics[height=42pt]{$(IMG_DIR)/top_left.png}}\fancyhead[C]{CHARIOT — DFIR IR Framework}\fancyhead[R]{\includegraphics[height=42pt]{$(IMG_DIR)/top_right.png}}\fancyfoot[C]{\thepage}'

EXPORT_DIR := export

SOP_SRCS := $(wildcard sops/*.md)
SOP_PDFS := $(patsubst sops/%.md,$(EXPORT_DIR)/sops-%.pdf,$(SOP_SRCS))

PLAYBOOK_SRCS := $(wildcard playbooks/*.md)
PLAYBOOK_PDFS := $(patsubst playbooks/%.md,$(EXPORT_DIR)/playbooks-%.pdf,$(PLAYBOOK_SRCS))

TEMPLATE_SRCS := $(wildcard templates/*.md)
TEMPLATE_PDFS := $(patsubst templates/%.md,$(EXPORT_DIR)/templates-%.pdf,$(TEMPLATE_SRCS))

DOC_SRCS := $(wildcard docs/superpowers/specs/*.md) $(wildcard docs/superpowers/plans/*.md)
DOC_PDFS := $(patsubst docs/%.md,$(EXPORT_DIR)/docs-%.pdf,$(DOC_SRCS))

ROOT_SRCS := README.md
ROOT_PDFS := $(patsubst %.md,$(EXPORT_DIR)/%.pdf,$(ROOT_SRCS))

.PHONY: all sops playbooks templates docs clean

all: sops playbooks templates docs root

sops: $(SOP_PDFS)

playbooks: $(PLAYBOOK_PDFS)

templates: $(TEMPLATE_PDFS)

docs: $(DOC_PDFS)

root: $(ROOT_PDFS)

$(EXPORT_DIR)/sops-%.pdf: sops/%.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR)/playbooks-%.pdf: playbooks/%.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR)/templates-%.pdf: templates/%.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR)/docs-%.pdf: docs/%.md | $(EXPORT_DIR)
	@mkdir -p $(dir $@)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR)/%.pdf: %.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR):
	mkdir -p $(EXPORT_DIR)

clean:
	rm -rf $(EXPORT_DIR)/*.pdf $(EXPORT_DIR)/docs-superpowers
