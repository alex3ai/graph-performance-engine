// ===================================================================
// GRAPH PERFORMANCE ENGINE - TEST SUITE (OPTIMIZED FOR LOAD TESTING)
// ===================================================================
// INSTRUÇÕES DE USO:
// 1. No Neo4j Browser: Defina o parametro antes de rodar: :param userId => 100
// 2. No JMeter: Substitua $userId pela variável do CSV: ${userId}
// 3. PROFILE: Mantido comentado. Use apenas para debug manual de índices.
// ===================================================================

// ===================================================================
// 1. ANÁLISE EXPLORATÓRIA (Pré-Teste)
// ===================================================================

// Distribuição de Grau (Degree Distribution)
// Ajuda a identificar "Super Nodes" que podem causar outliers nos testes
MATCH (u:User)
WITH u, size((u)-[:FRIEND]->()) AS degree
RETURN degree, count(*) AS users_with_degree
ORDER BY degree DESC
LIMIT 10;

// Top Influencers (Candidatos a "Hot Spots" no cache)
MATCH (u:User)
WITH u, size((u)-[:FRIEND]->()) AS connections
RETURN u.id, u.name, connections
ORDER BY connections DESC
LIMIT 5;

// ===================================================================
// 2. TESTES DE PROFUNDIDADE (Validar O(b^d))
// ===================================================================

// --- DEPTH 1: Baseline (Amigos Diretos) ---
// Expectativa: < 10ms | Custo: Linear
// PROFILE
MATCH (u:User {id: $userId})-[:FRIEND]->(f:User)
RETURN count(f) AS friend_count;

// --- DEPTH 2: Friends of Friends (FoF) ---
// Expectativa: Crescimento Quadrático
// PROFILE
MATCH (u:User {id: $userId})-[:FRIEND]->(:User)-[:FRIEND]->(fof:User)
WHERE fof.id <> $userId
RETURN count(DISTINCT fof) AS fof_count;

// --- DEPTH 3: Heavy Load (O Ponto de Estresse) ---
// Expectativa: Explosão Cúbica. Aqui veremos o GC (Garbage Collector) atuar.
// PROFILE
MATCH (u:User {id: $userId})-[:FRIEND*3]-(distant:User)
WHERE distant.id <> $userId
RETURN count(DISTINCT distant) AS depth3_count;

// --- DEPTH 4: Danger Zone (Stress Test Extremo) ---
// ALERTA: Alto risco de Timeout em Heap de 768MB. Use com cautela.
// PROFILE
MATCH (u:User {id: $userId})-[:FRIEND*4]-(extreme:User)
WHERE extreme.id <> $userId
RETURN count(DISTINCT extreme) AS depth4_count
LIMIT 10000;

// ===================================================================
// 3. QUERIES DE RECOMENDAÇÃO (Cenário Realista)
// ===================================================================

// Colaborativa Simples: "Amigos de amigos que não são meus amigos"
MATCH (u:User {id: $userId})-[:FRIEND]->(f:User)-[:FRIEND]->(fof:User)
WHERE NOT (u)-[:FRIEND]->(fof) AND fof.id <> $userId
RETURN fof.name, count(*) AS mutual_friends
ORDER BY mutual_friends DESC
LIMIT 10;

// Híbrida (Conteúdo + Social): "Produtos que amigos curtem e eu não"
// Otimizada para retornar campos úteis sem overhead excessivo
MATCH (u:User {id: $userId})-[:FRIEND]->(f:User)-[:LIKES]->(p:Product)
WHERE NOT (u)-[:LIKES]->(p)
RETURN p.id, p.name, p.category, count(f) AS relevance
ORDER BY relevance DESC
LIMIT 20;