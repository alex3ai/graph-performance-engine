// ===================================================================
// GRAPH PERFORMANCE ENGINE - IMPORT SCRIPT (NO-APOC VERSION)
// Foco: Compatibilidade Neo4j Community & Eficiência de Memória
// ===================================================================

// === 1. CONSTRAINTS (CRÍTICO) ===
// Cria índices únicos essenciais para performance do LOAD (evita Scans)
CREATE CONSTRAINT user_id_unique IF NOT EXISTS FOR (u:User) REQUIRE u.id IS UNIQUE;
CREATE CONSTRAINT product_id_unique IF NOT EXISTS FOR (p:Product) REQUIRE p.id IS UNIQUE;

// Aguarda índices ficarem online antes de carregar dados
CALL db.awaitIndexes(300);

// === 2. LOAD USERS ===
// Batch de 10k é seguro para nós simples
LOAD CSV WITH HEADERS FROM 'file:///users.csv' AS row
CALL {
  WITH row
  CREATE (:User {
    id: toInteger(row.userId),
    name: row.name,
    country: row.country,
    createdAt: datetime(row.created_at)
  })
} IN TRANSACTIONS OF 10000 ROWS;

// Validação leve (Sem APOC)
MATCH (u:User) RETURN count(u) as CHECK_TOTAL_USERS;

// === 3. LOAD PRODUCTS ===
LOAD CSV WITH HEADERS FROM 'file:///products.csv' AS row
CALL {
  WITH row
  CREATE (:Product {
    id: toInteger(row.productId),
    name: row.name,
    category: row.category,
    price: toFloat(row.price)
  })
} IN TRANSACTIONS OF 10000 ROWS;

MATCH (p:Product) RETURN count(p) as CHECK_TOTAL_PRODUCTS;

// === 4. LOAD FRIENDSHIPS ===
// Batch reduzido (5000) para evitar estouro de Heap (Memory Pressure)
// Criação bidirecional explícita
LOAD CSV WITH HEADERS FROM 'file:///edges_friends.csv' AS row
CALL {
  WITH row
  MATCH (u1:User {id: toInteger(row.u1)})
  MATCH (u2:User {id: toInteger(row.u2)})
  CREATE (u1)-[:FRIEND]->(u2)
  CREATE (u2)-[:FRIEND]->(u1)
} IN TRANSACTIONS OF 5000 ROWS;

// Validação: Total de arestas criadas
MATCH ()-[r:FRIEND]->() RETURN count(r) as CHECK_TOTAL_FRIENDSHIPS;

// === 5. LOAD LIKES ===
LOAD CSV WITH HEADERS FROM 'file:///edges_likes.csv' AS row
CALL {
  WITH row
  MATCH (u:User {id: toInteger(row.userId)})
  MATCH (p:Product {id: toInteger(row.productId)})
  CREATE (u)-[:LIKES {timestamp: datetime(row.timestamp)}]->(p)
} IN TRANSACTIONS OF 5000 ROWS;

MATCH ()-[r:LIKES]->() RETURN count(r) as CHECK_TOTAL_LIKES;

// === 6. ÍNDICES SECUNDÁRIOS ===
// Otimização para queries de filtro no JMeter
CREATE INDEX user_country_idx IF NOT EXISTS FOR (u:User) ON (u.country);
CREATE INDEX product_category_idx IF NOT EXISTS FOR (p:Product) ON (p.category);

// Garante que tudo esteja pronto antes de liberar o banco para testes
CALL db.awaitIndexes(300);

// === 7. SMOKE TEST (MANUAL) ===
// Copie e rode manualmente para validar se o plano usa "NodeIndexSeek"
// PROFILE MATCH (u:User {id: 100})-[:FRIEND]->(f) RETURN f.name LIMIT 5;