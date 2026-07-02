PANDOC := pandoc
IMG_DIR := playbooks/images

# --- Output format (default: pdf) ---
# Usage:  make all              → PDF (default)
#         make all FMT=docx     → DOCX
#         make all FMT=pptx     → PPTX
#         make playbooks FMT=docx
FMT ?= pdf

PANDOC_PDF_FLAGS := --from markdown --to pdf --pdf-engine=xelatex \
    -V geometry:margin=1in \
    -V geometry:headheight=52pt \
    -V fontsize=11pt \
    -V documentclass=article \
    -V colorlinks=true \
    -V linkcolor=blue \
    -V urlcolor=blue \
    -V header-includes='\usepackage{fancyhdr}\usepackage{graphicx}\pagestyle{fancy}\fancyhead[L]{\includegraphics[height=42pt]{$(IMG_DIR)/top_left.png}}\fancyhead[C]{CHARIOT — DFIR IR Framework}\fancyhead[R]{\includegraphics[height=42pt]{$(IMG_DIR)/top_right.png}}\fancyfoot[C]{\thepage}'

PANDOC_DOCX_FLAGS := --from markdown --to docx \
    --reference-doc=$(IMG_DIR)/reference.docx

PANDOC_PPTX_FLAGS := --from markdown --to pptx \
    --slide-level=2

ifeq ($(FMT),docx)
  PANDOC_FLAGS := $(PANDOC_DOCX_FLAGS)
  EXT := docx
else ifeq ($(FMT),pptx)
  PANDOC_FLAGS := $(PANDOC_PPTX_FLAGS)
  EXT := pptx
else
  PANDOC_FLAGS := $(PANDOC_PDF_FLAGS)
  EXT := pdf
endif

EXPORT_DIR := export

SOP_SRCS := $(wildcard sops/*.md)
SOP_OUTS := $(patsubst sops/%.md,$(EXPORT_DIR)/sops-%.$(EXT),$(SOP_SRCS))

PLAYBOOK_SRCS := $(wildcard playbooks/*.md)
PLAYBOOK_OUTS := $(patsubst playbooks/%.md,$(EXPORT_DIR)/playbooks-%.$(EXT),$(PLAYBOOK_SRCS))

TEMPLATE_SRCS := $(wildcard templates/*.md)
TEMPLATE_OUTS := $(patsubst templates/%.md,$(EXPORT_DIR)/templates-%.$(EXT),$(TEMPLATE_SRCS))

DOC_SRCS := $(wildcard docs/superpowers/specs/*.md) $(wildcard docs/superpowers/plans/*.md)
DOC_OUTS := $(patsubst docs/%.md,$(EXPORT_DIR)/docs-%.$(EXT),$(DOC_SRCS))

ROOT_SRCS := README.md
ROOT_OUTS := $(patsubst %.md,$(EXPORT_DIR)/%.$(EXT),$(ROOT_SRCS))

.PHONY: all sops playbooks templates docs root clean

all: sops playbooks templates docs root

sops: $(SOP_OUTS)

playbooks: $(PLAYBOOK_OUTS)

templates: $(TEMPLATE_OUTS)

docs: $(DOC_OUTS)

root: $(ROOT_OUTS)

$(EXPORT_DIR)/sops-%.$(EXT): sops/%.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR)/playbooks-%.$(EXT): playbooks/%.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR)/templates-%.$(EXT): templates/%.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR)/docs-%.$(EXT): docs/%.md | $(EXPORT_DIR)
	@mkdir -p $(dir $@)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR)/%.$(EXT): %.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR):
	mkdir -p $(EXPORT_DIR)

clean:
	rm -rf $(EXPORT_DIR)/*.pdf $(EXPORT_DIR)/*.docx $(EXPORT_DIR)/*.pptx $(EXPORT_DIR)/docs-superpowers
