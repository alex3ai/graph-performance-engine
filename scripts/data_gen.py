#!/usr/bin/env python3
"""
Graph Performance Engine - Data Generator (High Performance Version)
Gera datasets sintéticos otimizados para Neo4j com foco em eficiência de memória e vetorização.
"""

import pandas as pd
import numpy as np
import time
import argparse
import psutil
import os
from pathlib import Path

# === CONFIGURAÇÕES ===
DEFAULT_CONFIG = {
    'users': 100_000,
    'products': 10_000,
    'friendships': 500_000,
    'likes': 1_000_000,
    'jmeter_samples': 5_000,
    'seed': 42  # Seed of Life for reproducibility
}

def log_memory(stage: str):
    """Monitoramento de memória RSS (SRE Observability)"""
    process = psutil.Process(os.getpid())
    mem_mb = process.memory_info().rss / (1024 * 1024)
    print(f"   🧠 Memória RSS pós-{stage}: {mem_mb:.2f} MB")

def generate_users(num: int, output_dir: Path) -> pd.DataFrame:
    """Gera dataset de usuários"""
    print(f"📦 Gerando {num:,} usuários...")
    users = pd.DataFrame({
        'userId': np.arange(1, num + 1), # np.arange é mais rápido que range()
        'name': [f'User_{i}' for i in range(1, num + 1)],
        'country': np.random.choice(['BR', 'US', 'UK', 'DE', 'JP'], num),
        'created_at': pd.date_range('2020-01-01', periods=num, freq='1min')
    })
    filepath = output_dir / 'users.csv'
    users.to_csv(filepath, index=False)
    
    print(f"   ✓ Salvo: {filepath} ({filepath.stat().st_size / 1024:.1f} KB)")
    log_memory("Users")
    return users

def generate_products(num: int, output_dir: Path) -> pd.DataFrame:
    """Gera catálogo de produtos"""
    print(f"📦 Gerando {num:,} produtos...")
    products = pd.DataFrame({
        'productId': np.arange(1, num + 1),
        'name': [f'Product_{i}' for i in range(1, num + 1)],
        'category': np.random.choice(['Electronics', 'Books', 'Home', 'Sports', 'Fashion'], num),
        'price': np.round(np.random.uniform(10, 1000, num), 2)
    })
    filepath = output_dir / 'products.csv'
    products.to_csv(filepath, index=False)
    
    print(f"   ✓ Salvo: {filepath} ({filepath.stat().st_size / 1024:.1f} KB)")
    log_memory("Products")
    return products

def generate_friendships(num: int, max_user_id: int, output_dir: Path):
    """
    Gera relacionamentos FRIEND bidirecionais.
    OTIMIZAÇÃO: Usa np.minimum/maximum para normalização vetorizada (Performance boost).
    """
    print(f"🔗 Gerando {num:,} amizades...")
    
    # 1. Geração de Pares Inteiros (Muito leve em memória)
    u1 = np.random.randint(1, max_user_id + 1, num)
    u2 = np.random.randint(1, max_user_id + 1, num)
    
    # 2. Vetorização para garantir ordem (Min, Max)
    # Isso evita criar o DataFrame cedo demais. Operamos em arrays C-contiguous.
    sources = np.minimum(u1, u2)
    targets = np.maximum(u1, u2)
    
    # 3. Criação do DataFrame apenas para remover duplicatas
    friends_df = pd.DataFrame({'u1': sources, 'u2': targets})
    
    # Remove auto-loops (u1 == u2) e duplicatas
    friends_df = friends_df[friends_df['u1'] != friends_df['u2']].drop_duplicates()
    
    filepath = output_dir / 'edges_friends.csv'
    friends_df.to_csv(filepath, index=False)
    
    print(f"   ✓ Salvo: {filepath} ({len(friends_df):,} arestas únicas)")
    log_memory("Friendships")

def generate_likes(num: int, max_user_id: int, max_product_id: int, output_dir: Path):
    """Gera interações LIKES"""
    print(f"💙 Gerando {num:,} likes...")
    
    likes_df = pd.DataFrame({
        'userId': np.random.randint(1, max_user_id + 1, num),
        'productId': np.random.randint(1, max_product_id + 1, num),
        'timestamp': pd.date_range('2023-01-01', periods=num, freq='10s')
    })
    
    # Drop duplicates é memory intensive, monitoramos logo após
    likes_df = likes_df.drop_duplicates(subset=['userId', 'productId'])
    
    filepath = output_dir / 'edges_likes.csv'
    likes_df.to_csv(filepath, index=False)
    
    print(f"   ✓ Salvo: {filepath} ({len(likes_df):,} interações únicas)")
    log_memory("Likes")

def generate_jmeter_input(user_ids: np.ndarray, num_samples: int, output_dir: Path):
    """Gera arquivo CSV para o JMeter ler"""
    print(f"🎯 Gerando {num_samples:,} amostras para JMeter...")
    
    # Importante: Usar a mesma seed garante que testaremos sempre os mesmos usuários
    samples = np.random.choice(user_ids, size=num_samples, replace=True)
    
    jmeter_dir = output_dir.parent / 'jmeter'
    if jmeter_dir.exists():
        filepath = jmeter_dir / 'users_jmeter.csv'
    else:
        filepath = output_dir / 'users_jmeter.csv'
    
    pd.DataFrame(samples).to_csv(filepath, index=False, header=False)
    print(f"   ✓ Salvo: {filepath}")

def main():
    parser = argparse.ArgumentParser(description='Graph Performance Engine - High Perf Generator')
    parser.add_argument('--users', type=int, default=DEFAULT_CONFIG['users'])
    parser.add_argument('--products', type=int, default=DEFAULT_CONFIG['products'])
    parser.add_argument('--friendships', type=int, default=DEFAULT_CONFIG['friendships'])
    parser.add_argument('--likes', type=int, default=DEFAULT_CONFIG['likes'])
    parser.add_argument('--output', type=str, default='./scripts')
    args = parser.parse_args()
    
    # Configurar Seed Global (Reprodutibilidade)
    np.random.seed(DEFAULT_CONFIG['seed'])
    print(f"🎲 Seed Fixada: {DEFAULT_CONFIG['seed']}")
    
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print("\n" + "="*60)
    print("🚀 GRAPH PERFORMANCE ENGINE - DATA GENERATOR (V2.0)")
    print("="*60 + "\n")
    
    start = time.time()
    log_memory("Start")
    
    # Passamos .values para remover overhead de index do pandas onde possível
    users_df = generate_users(args.users, output_dir)
    generate_products(args.products, output_dir)
    generate_friendships(args.friendships, args.users, output_dir)
    generate_likes(args.likes, args.users, args.products, output_dir)
    
    # Passamos o array numpy direto
    generate_jmeter_input(users_df['userId'].values, DEFAULT_CONFIG['jmeter_samples'], output_dir)
    
    elapsed = time.time() - start
    print(f"\n✅ Geração concluída em {elapsed:.2f}s")
    log_memory("End")

if __name__ == "__main__":
    main()