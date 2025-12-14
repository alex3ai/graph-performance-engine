# 🎯 JMeter Load Test Setup Guide

## 📋 Visão Geral
Este guia detalha a configuração completa do Apache JMeter para executar testes de carga contra o Neo4j Graph Database, simulando padrões de acesso realistas e medindo a degradação de performance conforme a complexidade algorítmica ($O(b^d)$) aumenta.

---

## 🔧 Pré-requisitos

### 1. Instalação do JMeter
**Download:**
```bash
# Linux/macOS (via Homebrew)
brew install jmeter

# Ou download manual
wget https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.6.3.tgz
tar -xzf apache-jmeter-5.6.3.tgz
```

**Verificação:**
```bash
jmeter --version
# Esperado: Apache JMeter 5.6.3 ou superior
```

### 2. Validar Ambiente
Antes de configurar o JMeter, certifique-se de que:
- ✅ Neo4j está rodando: `docker ps | grep neo4j_perf`
- ✅ Dados foram importados: `make import`
- ✅ CSV de entrada existe: `ls jmeter/users_jmeter.csv`

---

## 🏗️ Estrutura do Test Plan

### Hierarquia de Componentes
```text
Load Test Plan (Raiz)
├── User Defined Variables (Config Global)
├── HTTP Header Manager (Auth + Content-Type)
├── CSV Data Set Config (Input de UserIDs)
├── Thread Group: Depth 1 (Baseline)
│   ├── HTTP Request: Friends Direct
│   └── Listeners (Response Time, Aggregate)
├── Thread Group: Depth 2 (Escalabilidade)
│   └── HTTP Request: Friends of Friends
├── Thread Group: Depth 3 (Breaking Point)
│   └── HTTP Request: Extended Network
└── Thread Group: Hybrid Query (Recomendação)
    └── HTTP Request: Social Recommendations
```

---

## 📝 Configuração Passo a Passo

### Etapa 1: Criar Test Plan
1. Abra o JMeter GUI: `jmeter`
2. Clique com botão direito em **Test Plan** → **Add** → **Config Element** → **User Defined Variables**
3. Adicione as variáveis:

| Nome | Valor | Descrição |
|------|-------|-----------|
| `NEO4J_HOST` | `localhost` | Endereço do servidor |
| `NEO4J_PORT` | `7474` | Porta HTTP |
| `NEO4J_USER` | `neo4j` | Usuário (Base64: `bmVvNGo=`) |
| `NEO4J_PASS` | `test123` | Senha (Base64: `dGVzdDEyMw==`) |

---

### Etapa 2: HTTP Header Manager (Global)
**Caminho:** Test Plan → Add → Config Element → HTTP Header Manager

**Headers obrigatórios:**
| Nome | Valor |
|------|-------|
| `Content-Type` | `application/json` |
| `Accept` | `application/json` |
| `Authorization` | `Basic bmVvNGo6dGVzdDEyMw==` |

> **Nota:** O valor Base64 acima corresponde a `neo4j:test123`. Para credenciais diferentes, use:
> ```bash
> echo -n "usuario:senha" | base64
> ```

---

### Etapa 3: CSV Data Set Config
**Caminho:** Test Plan → Add → Config Element → CSV Data Set Config

**Configurações:**
| Campo | Valor | Descrição |
|-------|-------|-----------|
| **Filename** | `${__BeanShell(System.getProperty("user.dir"))}/jmeter/users_jmeter.csv` | Caminho absoluto |
| **Variable Names** | `userId` | Nome da variável acessível nos samplers |
| **Delimiter** | `,` | Separador CSV |
| **Recycle on EOF** | `True` | Reinicia do início quando acabar |
| **Stop thread on EOF** | `False` | Continua executando |
| **Sharing mode** | `All threads` | Compartilha entre todas as threads |

**Validação:**
- O arquivo `users_jmeter.csv` contém 5.000 IDs de usuários (gerado pelo `data_gen.py`)
- Formato: um ID por linha, sem cabeçalho

---

### Etapa 4: Thread Group - Depth 1 (Baseline)

**Caminho:** Test Plan → Add → Threads → Thread Group

**Configurações de Carga:**
| Parâmetro | Valor | Justificativa |
|-----------|-------|---------------|
| **Number of Threads** | `50` | Simula 50 usuários concorrentes |
| **Ramp-Up Period** | `10` | Aumenta carga gradualmente (5 users/s) |
| **Loop Count** | `100` | Cada thread faz 100 requests |
| **Duration** | (vazio) | Controlado por Loop Count |

**HTTP Request Sampler:**
1. Botão direito no Thread Group → Add → Sampler → HTTP Request
2. Configurações:

| Campo | Valor |
|-------|-------|
| **Name** | `Query: Depth 1 - Direct Friends` |
| **Protocol** | `http` |
| **Server Name** | `${NEO4J_HOST}` |
| **Port** | `${NEO4J_PORT}` |
| **Method** | `POST` |
| **Path** | `/db/neo4j/tx/commit` |
| **Body Data** | (Ver JSON abaixo) |

**Body Data (JSON):**
```json
{
  "statements": [
    {
      "statement": "MATCH (u:User {id: $userId})-[:FRIEND]->(f) RETURN count(f) as friendCount",
      "parameters": {
        "userId": ${userId}
      }
    }
  ]
}
```

---

### Etapa 5: Thread Group - Depth 2 (Escalabilidade)

**Replicar Depth 1 com ajustes:**
- **Name:** `Thread Group: Depth 2`
- **Number of Threads:** `30` (reduzir para evitar sobrecarga precoce)
- **Loop Count:** `50`

**Body Data (Depth 2):**
```json
{
  "statements": [
    {
      "statement": "MATCH (u:User {id: $userId})-[:FRIEND*2]-(fof) WHERE fof.id <> $userId RETURN count(DISTINCT fof) as fofCount",
      "parameters": {
        "userId": ${userId}
      }
    }
  ]
}
```

---

### Etapa 6: Thread Group - Depth 3 (Breaking Point)

**Configurações Agressivas:**
- **Number of Threads:** `20` (carga pesada)
- **Ramp-Up:** `20s` (1 user/s)
- **Loop Count:** `20`

**Body Data (Depth 3 com LIMIT):**
```json
{
  "statements": [
    {
      "statement": "MATCH (u:User {id: $userId})-[:FRIEND*3]-(distant) WHERE distant.id <> $userId RETURN count(DISTINCT distant) as distantCount LIMIT 2000",
      "parameters": {
        "userId": ${userId}
      }
    }
  ]
}
```

> **Nota:** O `LIMIT 2000` evita OOM (Out of Memory) no Neo4j com Heap de 768MB.

---

### Etapa 7: Thread Group - Hybrid Query (Recomendação)

**Configurações:**
- **Threads:** `40`
- **Loop:** `100`

**Body Data (Social Recommendations):**
```json
{
  "statements": [
    {
      "statement": "MATCH (u:User {id: $userId})-[:FRIEND]->(f)-[:LIKES]->(p:Product) WHERE NOT (u)-[:LIKES]->(p) RETURN p.name, count(f) as relevance ORDER BY relevance DESC LIMIT 10",
      "parameters": {
        "userId": ${userId}
      }
    }
  ]
}
```

---

## 📊 Listeners (Coleta de Métricas)

### 1. View Results Tree (Debug)
**Uso:** Validação inicial - **DESABILITAR em produção** (alto overhead).
- Caminho: Thread Group → Add → Listener → View Results Tree

### 2. Aggregate Report (Estatísticas)
**Métricas coletadas:**
- Average, Median, 90%, 95%, 99% Percentile
- Min/Max Response Time
- Error %
- Throughput (req/s)

**Caminho:** Test Plan → Add → Listener → Aggregate Report

### 3. Simple Data Writer (Arquivo .jtl)
**OBRIGATÓRIO para análise automatizada.**

**Configurações:**
| Campo | Valor |
|-------|-------|
| **Filename** | `jmeter/results/result_${__time(yyyyMMdd-HHmmss)}.jtl` |
| **Configure** | Marcar: `Save as XML = false` (CSV é mais eficiente) |

**Colunas essenciais para salvar:**
- `timeStamp`, `elapsed`, `label`, `responseCode`, `success`, `bytes`, `sentBytes`, `latency`

---

## 🚀 Execução

### Modo GUI (Desenvolvimento)
1. Configure o Test Plan
2. **Salve:** File → Save Test Plan As → `jmeter/load_test.jmx`
3. Execute: **Run → Start** (Ctrl+R)
4. Monitore no Aggregate Report

### Modo Headless (Produção)
**Comando otimizado:**
```bash
jmeter -n \
  -t jmeter/load_test.jmx \
  -l jmeter/results/result_$(date +%s).jtl \
  -e -o jmeter/reports/html_report_$(date +%s) \
  -Jjmeter.save.saveservice.output_format=csv \
  -Jjmeter.reportgenerator.overall_granularity=1000
```

**Flags:**
- `-n`: Modo não-GUI
- `-t`: Test Plan
- `-l`: Log de resultados (.jtl)
- `-e -o`: Gera relatório HTML automaticamente
- `-J`: Define propriedades JMeter

---

## 🔍 Validação e Troubleshooting

### Checklist Pré-Execução
```bash
# 1. Neo4j está respondendo?
curl -u neo4j:test123 http://localhost:7474/db/neo4j/tx/commit \
  -H "Content-Type: application/json" \
  -d '{"statements":[{"statement":"RETURN 1"}]}'

# 2. CSV existe e tem conteúdo?
wc -l jmeter/users_jmeter.csv  # Deve retornar ~5000

# 3. JMeter pode acessar o CSV?
cd graph-performance-engine  # Executar do diretório raiz
```

### Erros Comuns

| Erro | Causa | Solução |
|------|-------|---------|
| `401 Unauthorized` | Credenciais incorretas no Header Manager | Verificar Base64 do Authorization |
| `FileNotFoundException: users_jmeter.csv` | Caminho relativo incorreto | Usar caminho absoluto com `${__BeanShell(...)}` |
| `Connection Refused` | Neo4j não iniciado ou porta errada | `docker ps` e verificar porta 7474 |
| `Timeout` em Depth 3 | Query muito pesada para Heap 768MB | Adicionar `LIMIT` na query Cypher |

---

## 📈 Interpretação de Resultados

### Métricas de Sucesso (SLA)
| Query | P95 Latency | Throughput | Error Rate |
|-------|-------------|------------|------------|
| Depth 1 | < 50ms | > 400 req/s | < 0.1% |
| Depth 2 | < 200ms | > 150 req/s | < 1% |
| Depth 3 | < 1000ms | > 50 req/s | < 5% |

### Sinais de Alerta
- **P99 > 10x P95:** GC Thrashing (pausas de Garbage Collection)
- **Error Rate > 5%:** Timeouts ou OOM
- **Throughput decrescente:** Saturação de CPU ou I/O

---

## 📚 Referências
- [JMeter User Manual](https://jmeter.apache.org/usermanual/index.html)
- [Neo4j HTTP API](https://neo4j.com/docs/http-api/current/)
- [Best Practices for Load Testing](https://jmeter.apache.org/usermanual/best-practices.html)