// ===================================================================
// GRAPH PERFORMANCE ENGINE - IMPORT SCRIPT (CORRIGIDO)
// Foco: Compatibilidade Data Gen, Formato de Data ISO-8601 & Memória
// ===================================================================

// === 1. CONSTRAINTS (CRÍTICO) ===
// Cria índices únicos essenciais para performance do LOAD (evita Scans)
CREATE CONSTRAINT user_id IF NOT EXISTS FOR (u:User) REQUIRE u.id IS UNIQUE;
CREATE CONSTRAINT product_id IF NOT EXISTS FOR (p:Product) REQUIRE p.id IS UNIQUE;

// Aguarda índices ficarem online antes de carregar dados
CALL db.awaitIndexes(300);

// === 2. LOAD USERS ===
// Arquivo: users.csv | Headers: id, name, age, gender, created_at
LOAD CSV WITH HEADERS FROM 'file:///users.csv' AS row
CALL {
  WITH row
  CREATE (:User {
    id: toInteger(row.id),         // Ajustado de userId para id
    name: row.name,
    age: toInteger(row.age),       // Ajustado de country para age (conforme gerador)
    gender: row.gender,            // Adicionado campo gender
    // FIX: Substitui espaço por T para formato ISO 8601
    created_at: datetime(replace(row.created_at, ' ', 'T'))
  })
} IN TRANSACTIONS OF 10000 ROWS;

// Validação leve
MATCH (u:User) RETURN count(u) as CHECK_TOTAL_USERS;

// === 3. LOAD PRODUCTS ===
// Arquivo: products.csv | Headers: id, name, category, price
LOAD CSV WITH HEADERS FROM 'file:///products.csv' AS row
CALL {
  WITH row
  CREATE (:Product {
    id: toInteger(row.id),         // Ajustado de productId para id
    name: row.name,
    category: row.category,
    price: toFloat(row.price)
  })
} IN TRANSACTIONS OF 10000 ROWS;

MATCH (p:Product) RETURN count(p) as CHECK_TOTAL_PRODUCTS;

// === 4. LOAD FRIENDSHIPS ===
// Arquivo: edges_friends.csv | Headers: source, target, created_at
LOAD CSV WITH HEADERS FROM 'file:///edges_friends.csv' AS row
CALL {
  WITH row
  MATCH (u1:User {id: toInteger(row.source)})  // Ajustado de u1 para source
  MATCH (u2:User {id: toInteger(row.target)})  // Ajustado de u2 para target
  
  // Cria relação bidirecional (A é amigo de B, e B é amigo de A)
  MERGE (u1)-[:FRIEND {since: datetime(replace(row.created_at, ' ', 'T'))}]->(u2)
  MERGE (u2)-[:FRIEND {since: datetime(replace(row.created_at, ' ', 'T'))}]->(u1)
} IN TRANSACTIONS OF 2000 ROWS; 
// Nota: Reduzi o batch de friends para 2000 para evitar travamento em relações duplas

MATCH ()-[r:FRIEND]->() RETURN count(r) as CHECK_TOTAL_FRIENDSHIPS;

// === 5. LOAD LIKES ===
// Arquivo: edges_likes.csv | Headers: source, target, created_at
LOAD CSV WITH HEADERS FROM 'file:///edges_likes.csv' AS row
CALL {
  WITH row
  MATCH (u:User {id: toInteger(row.source)})   // Ajustado de userId para source
  MATCH (p:Product {id: toInteger(row.target)}) // Ajustado de productId para target
  CREATE (u)-[:LIKES {timestamp: datetime(replace(row.created_at, ' ', 'T'))}]->(p)
} IN TRANSACTIONS OF 5000 ROWS;

MATCH ()-[r:LIKES]->() RETURN count(r) as CHECK_TOTAL_LIKES;

// === 6. ÍNDICES SECUNDÁRIOS ===
// Otimização para queries de filtro no JMeter
CREATE INDEX user_gender_idx IF NOT EXISTS FOR (u:User) ON (u.gender);
CREATE INDEX product_category_idx IF NOT EXISTS FOR (p:Product) ON (p.category);

// Garante que tudo esteja pronto
CALL db.awaitIndexes(300);