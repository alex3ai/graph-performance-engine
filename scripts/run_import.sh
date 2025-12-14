#!/bin/bash

# ===================================================================
# GRAPH PERFORMANCE ENGINE - Automated Import Runner
# Automatiza a ingestão de dados no Neo4j com robustez e observabilidade.
# ===================================================================

set -e  # Interrompe o script se qualquer comando retornar erro (Exit Code != 0)

# --- CONFIGURAÇÃO (12-Factor App compliant) ---
# Usa valores padrão, mas permite override via variáveis de ambiente
CONTAINER_NAME="${CONTAINER_NAME:-neo4j_perf}"
DB_USER="${NEO4J_USER:-neo4j}"
DB_PASS="${NEO4J_PASSWORD:-test123}"

CYPHER_FILE="scripts/import.cypher"
LOG_FILE="import.log"
TIMEOUT_SEC=60  # Tempo máximo para aguardar o banco (segundos)

echo "=================================================="
echo "🚀 GRAPH PERFORMANCE ENGINE - DATA IMPORT"
echo "=================================================="
echo "📝 Configuração Ativa:"
echo "   Container: $CONTAINER_NAME"
echo "   User:      $DB_USER"
echo "   Log File:  $LOG_FILE"
echo ""

# --- 1. PRE-FLIGHT CHECKS ---

# Verifica se o container está rodando
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ ERRO: O container '$CONTAINER_NAME' não está rodando!"
    echo "   Solução: Execute 'make start' ou 'docker-compose up -d'."
    exit 1
fi

# Verifica se o arquivo Cypher existe
if [ ! -f "$CYPHER_FILE" ]; then
    echo "❌ ERRO: Arquivo de importação não encontrado: $CYPHER_FILE"
    echo "   Certifique-se de executar o script da raiz do projeto."
    exit 1
fi

# --- 2. HEALTH CHECK COM TIMEOUT ---
echo "⏳ Aguardando Neo4j inicializar (Timeout: ${TIMEOUT_SEC}s)..."

START_TIME=$(date +%s)
while true; do
    # Tenta rodar uma query leve
    if docker exec "$CONTAINER_NAME" cypher-shell -u "$DB_USER" -p "$DB_PASS" "RETURN 1" &>/dev/null; then
        echo "✅ Neo4j está online e autenticado!"
        break
    fi

    # Verifica Timeout
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ "$ELAPSED" -gt "$TIMEOUT_SEC" ]; then
        echo "❌ ERRO: Timeout aguardando Neo4j iniciar ($ELAPSED segundos)."
        echo "   Verifique os logs do container: docker logs $CONTAINER_NAME"
        exit 1
    fi

    echo "   ...aguardando ($ELAPSED/${TIMEOUT_SEC}s)"
    sleep 2
done
echo ""

# --- 3. EXECUÇÃO DA IMPORTAÇÃO (COM LOGGING) ---
echo "📥 Executando pipeline de importação..."
echo "   Origem: $CYPHER_FILE"
echo "   Saída:  Gravando em $LOG_FILE (use 'tail -f $LOG_FILE' para acompanhar)"
echo "   ----------------------------------------"

# Pipe com 'tee' para stdout E arquivo de log (Observabilidade)
cat "$CYPHER_FILE" | docker exec -i "$CONTAINER_NAME" \
    cypher-shell -u "$DB_USER" -p "$DB_PASS" --format verbose 2>&1 | tee "$LOG_FILE"

echo ""
echo "=================================================="
echo "✅ IMPORTAÇÃO CONCLUÍDA COM SUCESSO!"
echo "=================================================="
echo ""
echo "📊 Acesse o Dashboard:"
echo "   URL:  http://localhost:7474"
echo "   User: $DB_USER"
echo "   Pass: (Oculto - verifique .env)"
echo ""