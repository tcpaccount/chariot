PANDOC := pandoc
PANDOC_FLAGS := --from markdown --to pdf --pdf-engine=xelatex \
    -V geometry:margin=1in \
    -V fontsize=11pt \
    -V documentclass=article \
    -V colorlinks=true \
    -V linkcolor=blue \
    -V urlcolor=blue \
    -V header-includes='\usepackage{fancyhdr}\pagestyle{fancy}\fancyhead[L]{CHARIOT — DFIR IR Framework}\fancyhead[R]{\today}'

EXPORT_DIR := export

SOP_SRCS := $(wildcard sops/*.md)
SOP_PDFS := $(patsubst sops/%.md,$(EXPORT_DIR)/sops-%.pdf,$(SOP_SRCS))

PLAYBOOK_SRCS := $(wildcard playbooks/*.md)
PLAYBOOK_PDFS := $(patsubst playbooks/%.md,$(EXPORT_DIR)/playbooks-%.pdf,$(PLAYBOOK_SRCS))

TEMPLATE_SRCS := $(wildcard templates/*.md)
TEMPLATE_PDFS := $(patsubst templates/%.md,$(EXPORT_DIR)/templates-%.pdf,$(TEMPLATE_SRCS))

.PHONY: all sops playbooks templates clean

all: sops playbooks templates

sops: $(SOP_PDFS)

playbooks: $(PLAYBOOK_PDFS)

templates: $(TEMPLATE_PDFS)

$(EXPORT_DIR)/sops-%.pdf: sops/%.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR)/playbooks-%.pdf: playbooks/%.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR)/templates-%.pdf: templates/%.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR):
	mkdir -p $(EXPORT_DIR)

clean:
	rm -f $(EXPORT_DIR)/*.pdf
