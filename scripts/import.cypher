// ===================================================================
// GRAPH PERFORMANCE ENGINE - IMPORT SCRIPT (WINDOWS I/O OPTIMIZED)
// Estratégia: Batch Balanceado (5000) + Timeout Longo
// ===================================================================

// === 1. CONSTRAINTS (CRÍTICO) ===
CREATE CONSTRAINT user_id IF NOT EXISTS FOR (u:User) REQUIRE u.id IS UNIQUE;
CREATE CONSTRAINT product_id IF NOT EXISTS FOR (p:Product) REQUIRE p.id IS UNIQUE;

// Aguarda índices ficarem online (Essencial)
CALL db.awaitIndexes(300);

// === 2. LOAD USERS (Batch 10k) ===
LOAD CSV WITH HEADERS FROM 'file:///users.csv' AS row
CALL {
  WITH row
  CREATE (:User {
    id: toInteger(row.userId),
    name: row.name,
    country: row.country,
    // Fix Data: ISO 8601
    created_at: datetime(replace(row.created_at, ' ', 'T'))
  })
} IN TRANSACTIONS OF 10000 ROWS;

MATCH (u:User) RETURN count(u) as CHECK_TOTAL_USERS;

// === 3. LOAD PRODUCTS (Batch 10k) ===
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

// === 4. LOAD FRIENDSHIPS (OTIMIZADO) ===
// Aumentado para 5000. 
// Com o timeout de 2h, o banco tem tempo de processar esse lote 
// sem cair a conexão, reduzindo o gargalo de disco do Windows.
LOAD CSV WITH HEADERS FROM 'file:///edges_friends.csv' AS row
CALL {
  WITH row
  MATCH (u1:User {id: toInteger(row.u1)})
  MATCH (u2:User {id: toInteger(row.u2)})
  
  CREATE (u1)-[:FRIEND]->(u2)
  CREATE (u2)-[:FRIEND]->(u1)
} IN TRANSACTIONS OF 5000 ROWS;

MATCH ()-[r:FRIEND]->() RETURN count(r) as CHECK_TOTAL_FRIENDSHIPS;

// === 5. LOAD LIKES ===
// Batch 5000
LOAD CSV WITH HEADERS FROM 'file:///edges_likes.csv' AS row
CALL {
  WITH row
  MATCH (u:User {id: toInteger(row.userId)})
  MATCH (p:Product {id: toInteger(row.productId)})
  
  CREATE (u)-[:LIKES {timestamp: datetime(replace(row.timestamp, ' ', 'T'))}]->(p)
} IN TRANSACTIONS OF 5000 ROWS;

MATCH ()-[r:LIKES]->() RETURN count(r) as CHECK_TOTAL_LIKES;

// === 6. ÍNDICES SECUNDÁRIOS ===
CREATE INDEX user_country_idx IF NOT EXISTS FOR (u:User) ON (u.country);
CREATE INDEX product_category_idx IF NOT EXISTS FOR (p:Product) ON (p.category);

CALL db.awaitIndexes(300);