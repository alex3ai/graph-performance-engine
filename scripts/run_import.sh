#!/bin/bash

# ===================================================================
# GRAPH PERFORMANCE ENGINE - Automated Import Runner
# Automatiza a ingestão de dados no Neo4j (Compatível com Windows/Git Bash)
# ===================================================================

set -e  # Interrompe se houver erro

# --- CONFIGURAÇÃO ---
CONTAINER_NAME="${CONTAINER_NAME:-neo4j_perf}"
DB_USER="${NEO4J_USER:-neo4j}"
DB_PASS="${NEO4J_PASSWORD:-test1234}" # Senha atualizada
CYPHER_FILE="scripts/import.cypher"
LOG_FILE="import.log"
TIMEOUT_SEC=120  # Aumentado para 120s (Windows costuma ser mais lento)

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}🚀 GRAPH PERFORMANCE ENGINE - DATA IMPORT${NC}"
echo -e "${BLUE}==================================================${NC}"

# --- 1. PRE-FLIGHT CHECKS ---
# Verifica se container roda
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}❌ ERRO: O container '$CONTAINER_NAME' não está rodando!${NC}"
    echo "   Solução: Execute 'make start'."
    exit 1
fi

# Verifica se os arquivos CSV existem localmente
for f in scripts/users.csv scripts/products.csv scripts/edges_friends.csv scripts/edges_likes.csv; do
    if [ ! -f "$f" ]; then
        echo -e "${RED}❌ ERRO: Arquivo não encontrado: $f${NC}"
        echo "   Solução: Execute 'make generate'."
        exit 1
    fi
done

# --- 2. HEALTH CHECK ---
echo -e "${BLUE}⏳ Aguardando Neo4j inicializar (Timeout: ${TIMEOUT_SEC}s)...${NC}"
START_TIME=$(date +%s)
while true; do
    if docker exec "$CONTAINER_NAME" cypher-shell -u "$DB_USER" -p "$DB_PASS" "RETURN 1" &>/dev/null; then
        echo -e "${GREEN}✅ Neo4j está online e autenticado!${NC}"
        break
    fi
    
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ "$ELAPSED" -gt "$TIMEOUT_SEC" ]; then
        echo -e "${RED}❌ Timeout aguardando Neo4j.${NC}"
        exit 1
    fi
    sleep 2
done

# --- 3. COPIA DE ARQUIVOS (CRÍTICO PARA DOCKER NO WINDOWS) ---
echo -e "${BLUE}🐳 Copiando CSVs para o container...${NC}"
# Usamos caminhos relativos para evitar erros com espaços no Windows
docker cp scripts/users.csv "$CONTAINER_NAME":/var/lib/neo4j/import/
docker cp scripts/products.csv "$CONTAINER_NAME":/var/lib/neo4j/import/
docker cp scripts/edges_friends.csv "$CONTAINER_NAME":/var/lib/neo4j/import/
docker cp scripts/edges_likes.csv "$CONTAINER_NAME":/var/lib/neo4j/import/

# --- 4. EXECUÇÃO DA IMPORTAÇÃO ---
echo -e "${BLUE}📥 Executando pipeline Cypher...${NC}"
echo "   Log: $LOG_FILE"

# Executa e grava log simultaneamente
cat "$CYPHER_FILE" | docker exec -i "$CONTAINER_NAME" \
    cypher-shell -u "$DB_USER" -p "$DB_PASS" --format verbose 2>&1 | tee "$LOG_FILE"

echo ""
echo -e "${GREEN}✅ IMPORTAÇÃO CONCLUÍDA!${NC}"
echo -e "${BLUE}📊 Dashboard: http://localhost:7474${NC}"