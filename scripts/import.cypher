// ===================================================================
// GRAPH PERFORMANCE ENGINE - IMPORT SCRIPT (DEFINITIVO)
// Mapeado para: userId, productId, u1/u2, country
// ===================================================================

// === 1. CONSTRAINTS (CRÍTICO) ===
// Garante unicidade e performance de busca
CREATE CONSTRAINT user_id IF NOT EXISTS FOR (u:User) REQUIRE u.id IS UNIQUE;
CREATE CONSTRAINT product_id IF NOT EXISTS FOR (p:Product) REQUIRE p.id IS UNIQUE;

// Aguarda índices ficarem online
CALL db.awaitIndexes(300);

// === 2. LOAD USERS ===
// CSV Headers: userId,name,country,created_at
LOAD CSV WITH HEADERS FROM 'file:///users.csv' AS row
CALL {
  WITH row
  CREATE (:User {
    id: toInteger(row.userId),      // Mapeado de userId
    name: row.name,
    country: row.country,           // Mapeado de country
    // Ajuste de Data: Substitui espaço por T
    created_at: datetime(replace(row.created_at, ' ', 'T'))
  })
} IN TRANSACTIONS OF 10000 ROWS;

MATCH (u:User) RETURN count(u) as CHECK_TOTAL_USERS;

// === 3. LOAD PRODUCTS ===
// CSV Headers: productId,name,category,price
LOAD CSV WITH HEADERS FROM 'file:///products.csv' AS row
CALL {
  WITH row
  CREATE (:Product {
    id: toInteger(row.productId),   // Mapeado de productId
    name: row.name,
    category: row.category,
    price: toFloat(row.price)
  })
} IN TRANSACTIONS OF 10000 ROWS;

MATCH (p:Product) RETURN count(p) as CHECK_TOTAL_PRODUCTS;

// === 4. LOAD FRIENDSHIPS ===
// CSV Headers: u1,u2 (SEM DATA)
LOAD CSV WITH HEADERS FROM 'file:///edges_friends.csv' AS row
CALL {
  WITH row
  MATCH (u1:User {id: toInteger(row.u1)})  // Mapeado de u1
  MATCH (u2:User {id: toInteger(row.u2)})  // Mapeado de u2
  
  // Cria relação simples (sem propriedade de data)
  MERGE (u1)-[:FRIEND]->(u2)
  MERGE (u2)-[:FRIEND]->(u1)
} IN TRANSACTIONS OF 2000 ROWS;

MATCH ()-[r:FRIEND]->() RETURN count(r) as CHECK_TOTAL_FRIENDSHIPS;

// === 5. LOAD LIKES ===
// CSV Headers: userId,productId,timestamp
LOAD CSV WITH HEADERS FROM 'file:///edges_likes.csv' AS row
CALL {
  WITH row
  MATCH (u:User {id: toInteger(row.userId)})       // Mapeado de userId
  MATCH (p:Product {id: toInteger(row.productId)}) // Mapeado de productId
  
  // Cria relação com timestamp corrigido
  CREATE (u)-[:LIKES {timestamp: datetime(replace(row.timestamp, ' ', 'T'))}]->(p)
} IN TRANSACTIONS OF 5000 ROWS;

MATCH ()-[r:LIKES]->() RETURN count(r) as CHECK_TOTAL_LIKES;

// === 6. ÍNDICES SECUNDÁRIOS ===
// Otimização para queries (Baseado nas colunas que existem: country, category)
CREATE INDEX user_country_idx IF NOT EXISTS FOR (u:User) ON (u.country);
CREATE INDEX product_category_idx IF NOT EXISTS FOR (p:Product) ON (p.category);

CALL db.awaitIndexes(300);