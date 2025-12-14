#!/usr/bin/env python3
"""
Graph Performance Engine - Results Analyzer
Analisa logs do JMeter (.jtl), calcula métricas de SRE e gera gráficos de evidência.
Otimizado para detecção de outliers (GC Spikes) e correlação de falhas.
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path
import argparse
import sys

# Configuração de estilo para gráficos profissionais
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (12, 8)
plt.rcParams['axes.titlesize'] = 14
plt.rcParams['axes.labelsize'] = 12

def load_jtl_file(filepath: Path) -> pd.DataFrame:
    """Carrega arquivo JTL do JMeter com tratamento de timestamps e validação"""
    try:
        print(f"📂 Carregando: {filepath} ...")
        # Lê o CSV. O JMeter pode usar vírgula ou tabulação, assume CSV padrão aqui.
        df = pd.read_csv(filepath)
        
        # Limpeza de colunas
        df.columns = df.columns.str.strip()
        
        # Validação de colunas críticas
        required_cols = {'timeStamp', 'elapsed', 'success', 'label'}
        if not required_cols.issubset(df.columns):
            missing = required_cols - set(df.columns)
            raise ValueError(f"Colunas obrigatórias ausentes no JTL: {missing}")

        # Conversão de timestamp
        df['timestamp'] = pd.to_datetime(df['timeStamp'], unit='ms')
        df = df.sort_values('timeStamp')
        
        # Tempo relativo em segundos (start = 0) para gráficos temporais
        df['elapsed_sec'] = (df['timeStamp'] - df['timeStamp'].min()) / 1000
        
        return df
    except Exception as e:
        print(f"❌ Erro crítico ao carregar JTL: {e}")
        sys.exit(1)

def calculate_metrics(df: pd.DataFrame) -> dict:
    """Calcula métricas estatísticas detalhadas (SRE Gold Signals)"""
    # IMPORTANTE: Métricas de latência devem considerar apenas sucessos.
    # Falhas imediatas (ex: Connection Refused) distorcem a média para baixo.
    success_df = df[df['success'] == True]
    
    total_reqs = len(df)
    duration = (df['timeStamp'].max() - df['timeStamp'].min()) / 1000
    
    metrics = {
        'total_requests': total_reqs,
        'successful_requests': len(success_df),
        'failed_requests': total_reqs - len(success_df),
        'error_rate': ((total_reqs - len(success_df)) / total_reqs * 100) if total_reqs > 0 else 0,
        'duration_sec': duration,
        
        # Throughput efetivo (apenas sucessos)
        'throughput': len(success_df) / duration if duration > 0 else 0,
        
        # Latência (ms) - Baseada apenas em sucessos
        'avg_latency': success_df['elapsed'].mean(),
        'p50_latency': success_df['elapsed'].median(),
        'p90_latency': success_df['elapsed'].quantile(0.90),
        'p95_latency': success_df['elapsed'].quantile(0.95),
        'p99_latency': success_df['elapsed'].quantile(0.99),
        'max_latency': success_df['elapsed'].max()
    }
    return metrics

def print_summary(metrics: dict):
    """Exibe relatório no terminal"""
    print("\n" + "="*60)
    print("📊 RELATÓRIO DE PERFORMANCE (SRE SUMMARY)")
    print("="*60 + "\n")
    
    print(f"📉 VOLUME & ERROS")
    print(f"   Total Requests:     {metrics['total_requests']:,}")
    print(f"   Success Rate:       {100 - metrics['error_rate']:.2f}%")
    print(f"   Duration:           {metrics['duration_sec']:.1f}s")
    print(f"   Throughput (Eff):   {metrics['throughput']:.2f} req/s")
    
    print(f"\n⏱️  LATÊNCIA (ms) - (Apenas Sucessos)")
    print(f"   Avg:      {metrics['avg_latency']:.2f}")
    print(f"   P50:      {metrics['p50_latency']:.2f}")
    print(f"   P95:      {metrics['p95_latency']:.2f}  <-- Foco SRE")
    print(f"   P99:      {metrics['p99_latency']:.2f}  <-- Tail Latency")
    print(f"   Max:      {metrics['max_latency']:.2f}")
    print()

def plot_latency_over_time(df: pd.DataFrame, output_dir: Path):
    """Plot: Evolução da Latência (Identifica GC Pauses)"""
    plt.figure(figsize=(14, 6))
    
    # Filtrar apenas sucessos para o gráfico de latência real
    success_df = df[df['success'] == True].copy()
    
    # Bucketização (Janela de 5s)
    success_df['bucket'] = (success_df['elapsed_sec'] // 5) * 5
    grouped = success_df.groupby('bucket')['elapsed'].agg(['mean', 'max'])
    
    # Plotagem
    plt.plot(grouped.index, grouped['mean'], label='Avg Latency', linewidth=2, color='#1f77b4')
    plt.plot(grouped.index, grouped['max'], label='Max Latency (Spikes)', alpha=0.6, linestyle='--', color='#d62728', linewidth=1)
    
    plt.xlabel('Tempo de Teste (s)')
    plt.ylabel('Latência (ms)')
    plt.title('Latência ao Longo do Tempo (Detecção de Degradação/GC)')
    plt.legend()
    
    outfile = output_dir / 'latency_time_series.png'
    plt.savefig(outfile, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"✅ Gráfico salvo: {outfile.name}")

def plot_throughput(df: pd.DataFrame, output_dir: Path):
    """Plot: Vazão (Throughput)"""
    plt.figure(figsize=(14, 6))
    
    # Consideramos apenas requisições com sucesso para o throughput útil
    success_df = df[df['success'] == True].copy()
    
    success_df['bucket'] = (success_df['elapsed_sec'] // 5) * 5
    
    # Divide count por 5 para ter req/s (pois o bucket é de 5s)
    throughput = success_df.groupby('bucket').size() / 5
    
    plt.fill_between(throughput.index, throughput.values, alpha=0.4, color='green')
    plt.plot(throughput.index, throughput.values, color='darkgreen', label='Successful Req/s')
    
    plt.xlabel('Tempo de Teste (s)')
    plt.ylabel('Throughput (req/s)')
    plt.title('Throughput Efetivo do Sistema')
    plt.legend()
    
    outfile = output_dir / 'throughput.png'
    plt.savefig(outfile, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"✅ Gráfico salvo: {outfile.name}")

def plot_comparison_boxplot(df: pd.DataFrame, output_dir: Path):
    """Plot: Comparativo por Profundidade com Outliers (GC Pressure Evident)"""
    if 'label' not in df.columns:
        return

    plt.figure(figsize=(12, 7))
    
    # Filtrar apenas sucessos
    success_df = df[df['success'] == True]
    
    # showfliers=True é CRUCIAL para SRE: mostra os picos de latência (GC)
    sns.boxplot(x='label', y='elapsed', data=success_df, showfliers=True, hue='label', palette="viridis", legend=False)
    
    plt.title('Impacto da Profundidade na Latência (O(b^d)) - Com Outliers')
    plt.ylabel('Tempo de Resposta (ms)')
    plt.xlabel('Tipo de Query (Label)')
    plt.grid(True, axis='y', linestyle='--', alpha=0.7)
    
    outfile = output_dir / 'latency_by_depth_boxplot.png'
    plt.savefig(outfile, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"✅ Gráfico salvo: {outfile.name}")

def main():
    parser = argparse.ArgumentParser(description='Graph Performance Analyzer')
    parser.add_argument('jtl_file', type=str, help='Caminho do arquivo .jtl')
    parser.add_argument('--output', type=str, default='./analysis', help='Pasta de saída')
    args = parser.parse_args()
    
    jtl_path = Path(args.jtl_file)
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    if not jtl_path.exists():
        print(f"❌ Arquivo não encontrado: {jtl_path}")
        sys.exit(1)
        
    # Pipeline de Análise
    df = load_jtl_file(jtl_path)
    metrics = calculate_metrics(df)
    print_summary(metrics)
    
    print("📊 Gerando visualizações...")
    plot_latency_over_time(df, output_dir)
    plot_throughput(df, output_dir)
    plot_comparison_boxplot(df, output_dir)
    
    print(f"\n✨ Análise completa! Verifique a pasta: {output_dir.absolute()}\n")

if __name__ == "__main__":
    main()