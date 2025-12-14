# 📊 Performance Analysis Guide

## 🎯 Objetivo
Este documento estabelece o framework para análise dos resultados de testes de performance no **Graph Performance Engine**. O foco é correlacionar a **Complexidade Algorítmica** de travessias em grafos com a saturação de **Recursos de Sistema** (CPU, Heap Memory, I/O).

---

## 📐 Modelo Teórico vs Empírico

### A Matemática da "Explosão Combinatória"
Em bancos de dados orientados a grafos, a performance de leitura é ditada pelo número de nós visitados, não pelo tamanho total do banco.

Para um grafo com **Branching Factor médio ($b$)** e **Profundidade ($d$)**, a complexidade é exponencial:

$$
\text{Complexidade} = O(b^d)
$$

### Exemplo Prático (Simulação Social)
Considerando nosso dataset sintético onde cada usuário tem em média 10 amigos ($b \approx 10$):

| Profundidade | Fórmula | Nós Visitados (Upper Bound)* | Impacto no Sistema |
|:-------------|:--------|:-----------------------------|:-------------------|
| **Depth 1** | $10^1$ | ~10 | **Trivial** (CPU Cache) |
| **Depth 2** | $10^2$ | ~100 | **Baixo** (PageCache Hit) |
| **Depth 3** | $10^3$ | ~1.000 | **Médio** (Alocação de Objetos) |
| **Depth 4** | $10^4$ | ~10.000+ | **Crítico** (GC Pressure / Latência) |

> *\*Nota: Em grafos sociais reais, o número de nós únicos visitados é ligeiramente menor devido a ciclos (amigos em comum), mas o custo de travessia permanece alto.*

---

## 🔬 Metodologia de Teste

### 1. Baseline (Depth 1 - Amigos Diretos)
- **Objetivo:** Validar saúde da infraestrutura e índices.
- **Query:** `MATCH (u)-[:FRIEND]->(f) RETURN count(f)`
- **Meta SRE:** Latência P95 < 10ms | Throughput > 500 req/s.
- **Falha indica:** Índices ausentes ou Overhead de Rede.

### 2. Escalabilidade (Depth 2 - Amigos de Amigos)
- **Objetivo:** Medir crescimento quadrático.
- **Meta SRE:** Latência P95 < 100ms.
- **Falha indica:** PageCache insuficiente (I/O Bound).

### 3. Breaking Point (Depth 3+ - Rede Estendida)
- **Objetivo:** Encontrar o limite físico do hardware (Heap 768MB).
- **Meta SRE:** Sobreviver sem OOM (Out Of Memory). Latência < 1s.
- **Falha indica:** **Garbage Collection (GC) Thrashing** (CPU Bound por gestão de memória).

---

## 📊 Métricas Críticas (SRE Gold Signals)

### 1. Latência (Response Time)
| Percentil | Significado | Limite Aceitável | Ação se Exceder |
|:----------|:------------|:-----------------|:----------------|
| **P50** | Mediana (Usuário Típico) | < 50ms | Verificar locks ou I/O |
| **P95** | Cauda Curta | < 500ms | Otimizar Queries |
| **P99** | **Tail Latency (Outliers)** | < 2s | **Investigar GC Pauses** |

> **Red Flag:** Se P99 > 10x P50, o sistema sofre de pausas "Stop-the-world" do GC.

### 2. Throughput (Vazão)
$$
\text{Throughput} = \frac{\text{Reqs Sucesso}}{\text{Tempo (s)}}
$$

- **Baixo + CPU Baixa:** I/O Bound (Disco lento ou PageCache Miss).
- **Baixo + CPU Alta:** CPU Bound (Cálculo de travessia ou GC).

### 3. PageCache Hit Ratio
Métrica vital para performance em grafos. Indica se o grafo cabe na RAM.

$$
\text{Hit Ratio} = \frac{\text{Page Hits}}{\text{Page Hits} + \text{Page Faults}}
$$

- **Alvo:** > 98%
- **Diagnóstico:** Se < 90%, aumente `NEO4J_server_memory_pagecache_size`.

---

## 🔍 Diagnóstico e Causa Raiz

### Cenário 1: Latência Alta (P95 > 500ms)

#### 1. Verificar Uso de Índices (Explain Plan)
Execute no Neo4j Browser:
```cypher
PROFILE MATCH (u:User {id: 100}) RETURN u;
```

**Interpretação:**
- ✅ **Bom:** `NodeIndexSeek` (Busca O(log n))
- ❌ **Ruim:** `NodeByLabelScan` (Full Scan O(n))
  - **Ação:** `CREATE CONSTRAINT user_id_unique FOR (u:User) REQUIRE u.id IS UNIQUE;`

#### 2. Verificar Garbage Collection (GC)
Como não usamos APOC, monitore via logs do container:
```bash
docker logs neo4j_perf 2>&1 | grep -i "GC"
```

**Sintomas:**
- Logs frequentes de `G1 Young Generation` ou `G1 Old Generation`.
- **Causa:** Heap (768MB) saturado por objetos temporários de travessias profundas.

#### 3. Verificar Métricas Nativas
Consulte o arquivo CSV gerado (configurado no `docker-compose.yml`):
```bash
tail -f metrics/neo4j_metrics.csv
```

**Colunas relevantes:**
- `neo4j.page_cache.hit_ratio` (Alvo: > 0.98)
- `neo4j.vm.heap.used` (Alerta se > 90% do max)
- `neo4j.transaction.active` (Detecta queries travadas)

---

### Cenário 2: Erros HTTP 500 / Timeouts

**Causa:** Query excede o tempo limite de transação.
- **Configuração:** `NEO4J_db_transaction_timeout` (Default: 30s no projeto).
- **Mitigação:** Adicionar `LIMIT` na query ou otimizar o modelo.

**Exemplo de correção:**
```cypher
// ❌ Query problemática
MATCH (u)-[:FRIEND*3]-(f) RETURN f;

// ✅ Query otimizada
MATCH (u)-[:FRIEND*3]-(f) RETURN f LIMIT 1000;
```

---

## 📈 Matriz de Comparação (Resultados Esperados)

| Configuração | Depth 1 (P95) | Depth 2 (P95) | Depth 3 (P95) | Throughput |
|:-------------|:--------------|:--------------|:--------------|:-----------|
| **Com Índices (Baseline)** | 8ms | 85ms | 450ms | ~520 req/s |
| **Sem Índices** | 250ms | 3.5s | Timeout | ~12 req/s |
| **Heap Restrito (768MB)** | 10ms | 120ms | 800ms+ | ~380 req/s |
| **Heap Otimizado (2GB)** | 7ms | 70ms | 380ms | ~600 req/s |

---

## 🛠️ Recomendações de Tuning

### Nível 1: Query Tuning (Zero Custo)

#### 1. Sempre use Labels
```cypher
// ❌ Lento (escaneia todos os nós)
MATCH (u {id: 100}) RETURN u;

// ✅ Rápido (usa índice)
MATCH (u:User {id: 100}) RETURN u;
```

#### 2. Limite a Explosão Combinatória
```cypher
MATCH (u)-[:FRIEND*3]-(f) 
RETURN f LIMIT 100;  // Impede processamento de milhões de nós
```

#### 3. Evite retornar nós inteiros
```cypher
// ❌ Ruim (serializa todos os atributos)
RETURN f

// ✅ Bom (retorna apenas o necessário)
RETURN f.id, f.name
```

---

### Nível 2: Infraestrutura (Neo4j Conf)

#### PageCache Sizing
**Regra:** Deve caber os arquivos de store (`neostore.nodestore.db`, etc).
```bash
# Calcular tamanho necessário
docker exec neo4j_perf du -sh /data/databases/neo4j/
# Exemplo: 450MB

# Configurar no docker-compose.yml
NEO4J_server_memory_pagecache_size=600M  # DB size + 20%
```

#### Heap Memory
**Cuidado:** Heap muito grande (> 32GB) causa pausas de GC longas.

**Recomendação:**
- **Dev/Test:** 768MB - 2GB
- **Produção (< 1M nós):** 4GB - 8GB
- **Produção (> 1M nós):** 16GB (com G1GC tuning)

**No container:**
```yaml
NEO4J_server_memory_heap_max__size=4G
```

---

### Nível 3: Modelagem de Dados

#### Índices Compostos
Suportados na versão Community.
```cypher
CREATE INDEX user_geo FOR (u:User) ON (u.country, u.city);
```

**Quando usar:**
- Filtros frequentes em múltiplas propriedades.
- Exemplo: `MATCH (u:User) WHERE u.country = 'BR' AND u.city = 'SP'`

#### Pré-computação (Materialização)
Para Depth 3+ frequentes, salve o resultado como uma relação direta ou propriedade.

**Exemplo:**
```cypher
// Computar uma vez (job noturno)
MATCH (u:User)-[:FRIEND*3]-(distant)
WHERE u.id = 100
MERGE (u)-[:KNOWS_DISTANT {degree: 3}]->(distant);

// Query rápida (Depth 1 efetivo)
MATCH (u:User {id: 100})-[:KNOWS_DISTANT]->(d)
RETURN count(d);
```

---

## 🔬 Experimentos Práticos

### Experimento 1: Impacto de Índices
**Hipótese:** Índices reduzem latência em > 90%.

**Passos:**
1. Executar teste com índices: `make test`
2. Dropar índices: `DROP CONSTRAINT user_id_unique;`
3. Executar teste sem índices: `make test`
4. Comparar P95 no `analysis/latency_boxplot.png`

### Experimento 2: Saturação de Heap
**Hipótese:** Heap < 1GB causa GC Thrashing em Depth 3.

**Passos:**
1. Configurar Heap 512MB no `docker-compose.yml`
2. Executar apenas Thread Group Depth 3
3. Monitorar GC: `docker logs neo4j_perf | grep "GC pause"`
4. Aumentar para 2GB e repetir

---

## 📉 Antipadrões (O que NUNCA fazer)

### 1. Cartesian Products (Produto Cartesiano)
```cypher
// ❌ DESASTRE (O(n²))
MATCH (u:User), (p:Product)
WHERE NOT (u)-[:LIKES]->(p)
RETURN u, p;
```

**Correção:** Sempre especifique a relação.
```cypher
// ✅ Correto
MATCH (u:User)
MATCH (p:Product)
WHERE NOT (u)-[:LIKES]->(p)
RETURN u, p LIMIT 10;
```

### 2. Travessias Bidirecionais sem Direção
```cypher
// ❌ Lento (explora ambos os sentidos)
MATCH (u)-[:FRIEND*2]-(f) RETURN f;

// ✅ Rápido (define direção)
MATCH (u)-[:FRIEND*2]->(f) RETURN f;
```

### 3. Aggregations em Alto Volume sem Índice
```cypher
// ❌ Full Scan
MATCH (u:User)
WHERE u.country = 'BR'
RETURN count(u);

// ✅ Com índice
CREATE INDEX user_country FOR (u:User) ON (u.country);
```

---

## 📊 Dashboard de Monitoramento (Opcional)

### Métricas Essenciais para Grafana
Se expandir o projeto, monitore:

1. **Query Performance:**
   - `rate(neo4j_database_query_execution_success_total[5m])`
   - `histogram_quantile(0.95, neo4j_database_query_execution_latency_seconds_bucket)`

2. **Resource Utilization:**
   - `neo4j_vm_heap_used_bytes / neo4j_vm_heap_max_bytes`
   - `neo4j_page_cache_hit_ratio`

3. **GC Activity:**
   - `rate(neo4j_vm_gc_time_total[5m])`

---

## 📚 Referências Oficiais

1. **Neo4j Operations Manual - Performance Tuning**  
   https://neo4j.com/docs/operations-manual/current/performance/

2. **Cypher Query Tuning**  
   https://neo4j.com/docs/cypher-manual/current/query-tuning/

3. **JVM GC Tuning Guide**  
   https://docs.oracle.com/en/java/javase/17/gctuning/

4. **Indexes & Constraints**  
   https://neo4j.com/docs/cypher-manual/current/indexes-for-search-performance/

---

## 🎓 Conclusão

Este guia fornece o framework completo para:
- ✅ Entender a complexidade algorítmica de grafos
- ✅ Medir degradação de performance empiricamente
- ✅ Diagnosticar gargalos (CPU, Memória, I/O)
- ✅ Aplicar otimizações incrementais