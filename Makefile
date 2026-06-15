# ============================================================
# Makefile — SOC Corporativo com Wazuh
# ============================================================
# Geração de relatórios em PDF a partir de Markdown.
#
# Os relatórios em Markdown ainda não foram gerados.
# Descomente as linhas abaixo quando criar:
#   05-resultados/relatorio-academico.md
#   05-resultados/relatorio-lgpd-anpd.md
# ============================================================

PANDOC := pandoc
PDF_ENGINE := xelatex
PANDOC_OPTS := --pdf-engine=$(PDF_ENGINE) --toc --number-sections -V toc-title="Sumário"

# RELATORIO_MD := 05-resultados/relatorio-academico.md
# RELATORIO_PDF := 05-resultados/relatorio-academico.pdf
# LGPD_MD := 05-resultados/relatorio-lgpd-anpd.md
# LGPD_PDF := 05-resultados/relatorio-lgpd-anpd.pdf

.PHONY: all pdf pdf-relatorio pdf-lgpd clean help

all:
	@echo "Nenhum PDF para gerar. Crie os arquivos .md em 05-resultados/ primeiro."

pdf: pdf-relatorio pdf-lgpd

pdf-relatorio:
	@echo "relatorio-academico.md nao existe. Crie o arquivo primeiro."

$(RELATORIO_PDF):
	@echo "relatorio-academico.md nao existe."

pdf-lgpd:
	@echo "relatorio-lgpd-anpd.md nao existe."

$(LGPD_PDF):
	@echo "relatorio-lgpd-anpd.md nao existe."

clean:
	@echo "Nada a limpar."

help:
	@echo "Uso: make <alvo>"
	@echo ""
	@echo "Alvos disponiveis:"
	@echo "  all            (placeholder - sem arquivos .md ainda)"
	@echo "  pdf            (placeholder)"
	@echo "  pdf-relatorio  (placeholder)"
	@echo "  pdf-lgpd       (placeholder)"
	@echo "  clean          (placeholder)"
	@echo ""
	@echo "Crie os arquivos .md em 05-resultados/ para ativar a geracao."
	@echo "Dependencias: pandoc, texlive-core"
	@echo ""
	@echo "  Instalar (Arch): sudo pacman -S pandoc texlive-core"
	@echo "  Instalar (Debian): sudo apt install pandoc texlive-xetex texlive-lang-portuguese"
