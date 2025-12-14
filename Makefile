# ===================================================================
# GRAPH PERFORMANCE ENGINE - AUTOMATION SUITE
# Ferramentas de Orquestração, Teste e Observabilidade
# ===================================================================

.PHONY: help setup start stop clean generate import test analyze destroy monitor status report

# Configuração de Ambiente
VENV_BIN=.venv/bin
PYTHON=$(VENV_BIN)/python
PIP=$(VENV_BIN)/pip

# Variáveis de Execução (Timestamps e Caminhos)
TIMESTAMP := $(shell date +%Y-%m-%d_%H-%M-%S)
RESULTS_DIR := jmeter/results
CURRENT_JTL := $(RESULTS_DIR)/results_$(TIMESTAMP).jtl
CURRENT_REPORT := $(RESULTS_DIR)/report_$(TIMESTAMP)

# Cores para UX
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[1;33m
BLUE=\033[0;34m
NC=\033[0m # No Color

help: ## Mostra esta mensagem de ajuda
	@echo "$(BLUE)=================================================$(NC)"
	@echo "$(GREEN)🚀 Graph Performance Engine - CLI$(NC)"
	@echo "$(BLUE)=================================================$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "$(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'

setup: ## Cria virtualenv e instala dependências Python
	@echo "$(BLUE)📦 Configurando ambiente Python...$(NC)"
	python3 -m venv .venv
	$(PIP) install -r requirements.txt
	@echo "$(GREEN)✅ Dependências instaladas!$(NC)"

start: ## Inicia infraestrutura Docker (Neo4j)
	@echo "$(BLUE)🐳 Verificando containers...$(NC)"
	docker-compose up -d
	@echo "$(YELLOW)⏳ Aguardando Healthcheck do Neo4j...$(NC)"
	@timeout 60s bash -c 'until docker ps | grep "neo4j_perf" | grep "(healthy)"; do sleep 2; done' || echo "$(RED)⚠️ Timeout aguardando healthcheck (verifique logs)$(NC)"
	@echo "$(GREEN)✅ Neo4j online: http://localhost:7474$(NC)"

stop: ## Para a infraestrutura
	@echo "$(YELLOW)🛑 Parando serviços...$(NC)"
	docker-compose stop
	@echo "$(GREEN)✅ Serviços parados.$(NC)"

generate: ## Gera dataset padrão (100k Users)
	@echo "$(BLUE)🐍 Gerando dados sintéticos...$(NC)"
	$(PYTHON) scripts/data_gen.py
	@echo "$(GREEN)✅ Dados gerados em ./scripts/$(NC)"

generate-small: ## Gera dataset pequeno para dev (10k Users)
	@echo "$(BLUE)🐍 Gerando dataset reduzido...$(NC)"
	$(PYTHON) scripts/data_gen.py --users 10000 --products 1000 --friendships 50000 --likes 100000
	@echo "$(GREEN)✅ Dados (Small) prontos.$(NC)"

# Dependência: Garante que o container esteja rodando antes de importar
import: start ## Executa pipeline de importação (Bash + Cypher)
	@echo "$(BLUE)📥 Iniciando ingestão no Neo4j...$(NC)"
	@chmod +x scripts/run_import.sh
	@./scripts/run_import.sh
	@echo "$(GREEN)✅ Ingestão concluída.$(NC)"

validate: ## Valida contagem de nós e relações
	@echo "$(BLUE)🔍 Validando integridade do grafo...$(NC)"
	@docker exec neo4j_perf cypher-shell -u neo4j -p test123 \
		"MATCH (n) RETURN labels(n)[0] as Label, count(n) as Count UNION ALL MATCH ()-[r]->() RETURN type(r) as Label, count(r) as Count;"

# Dependência: Garante que os dados foram importados recentemente antes de testar
test-jmeter: import ## Executa Teste de Carga e gera Dashboard HTML
	@echo "$(YELLOW)⚡ Executando JMeter (Stress Test)...$(NC)"
	@mkdir -p $(RESULTS_DIR)
	@echo "   📁 Log: $(CURRENT_JTL)"
	@echo "   📊 Report: $(CURRENT_REPORT)"
	@# Executa JMeter: -n (non-gui), -t (plan), -l (log), -e -o (html report)
	@jmeter -n -t jmeter/load_test.jmx -l $(CURRENT_JTL) -e -o $(CURRENT_REPORT)
	@echo "$(GREEN)✅ Teste finalizado.$(NC)"
	@# Cria link simbólico para 'latest' para facilitar acesso rápido
	@rm -f $(RESULTS_DIR)/latest_report
	@ln -s $(PWD)/$(CURRENT_REPORT) $(RESULTS_DIR)/latest_report
	@echo "$(BLUE)👉 Relatório disponível em: $(RESULTS_DIR)/latest_report/index.html$(NC)"

# Dependência: Garante que um teste novo foi rodado antes de analisar
analyze: test-jmeter ## Gera gráficos customizados Python do último teste
	@echo "$(BLUE)📊 Processando métricas com Python...$(NC)"
	$(PYTHON) scripts/analyze_results.py $(CURRENT_JTL) --output analysis/
	@echo "$(GREEN)✅ Análise Python gerada em ./analysis/$(NC)"

report: ## Abre o último relatório HTML gerado (Cross-platform)
	@echo "$(BLUE)🌎 Abrindo relatório no navegador...$(NC)"
	@if [ "$$(uname)" = "Darwin" ]; then open $(RESULTS_DIR)/latest_report/index.html; \
	elif [ "$$(expr substr $$(uname -s) 1 5)" = "Linux" ]; then xdg-open $(RESULTS_DIR)/latest_report/index.html; \
	else echo "$(YELLOW)⚠️ Sistema não detectado automaticamente. Abra: $(RESULTS_DIR)/latest_report/index.html$(NC)"; fi

monitor: ## Monitora memória do container em tempo real
	@echo "$(BLUE)📈 Monitorando Recursos (Ctrl+C para sair)...$(NC)"
	@docker stats neo4j_perf --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

clean: ## Limpa dados gerados e resultados
	@echo "$(YELLOW)🧹 Limpando artefatos temporários...$(NC)"
	rm -rf scripts/*.csv jmeter/users_jmeter.csv jmeter/results/* analysis/*
	@echo "$(GREEN)✅ Limpeza concluída.$(NC)"

destroy: stop ## Remove containers e volumes (Reset Total)
	@echo "$(RED)💥 PERIGO: Isso apagará todo o banco de dados!$(NC)"
	@read -p "Tem certeza? [y/N] " confirm && [ "$$confirm" = "y" ]
	docker-compose down -v
	@echo "$(GREEN)✅ Ambiente resetado.$(NC)"

quickstart: setup generate analyze ## 🚀 Setup e execução completa (Do zero ao relatório)
	@echo ""
	@echo "$(GREEN)✅ CICLO COMPLETO EXECUTADO!$(NC)"
	@echo "$(BLUE)Execute 'make report' para ver os detalhes.$(NC)"