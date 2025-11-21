#!/usr/bin/env python3
"""
Script para generar resumen estadístico de resultados de benchmarking
de multiplicación de matrices paralela con MPI

Autor: [Tu nombre]
Fecha: Noviembre 2024
"""

import pandas as pd
import sys

def generate_summary(csv_file):
    """
    Genera un resumen estadístico de los resultados del benchmark
    
    Args:
        csv_file: Ruta al archivo CSV con los resultados
    """
    try:
        # Leer el archivo CSV
        df = pd.read_csv(csv_file)
        
        print("\n" + "="*70)
        print("                    RESUMEN ESTADÍSTICO")
        print("="*70 + "\n")
        
        # Agrupar por tamaño de matriz y número de procesos
        grouped = df.groupby(['Tamano_Matriz', 'Num_Procesos'])
        
        # Calcular estadísticas de tiempo
        time_stats = grouped['Tiempo_Segundos'].agg(['mean', 'std', 'min', 'max'])
        time_stats.columns = ['Media', 'Desv_Est', 'Minimo', 'Maximo']
        
        # Calcular media de GFLOPS
        gflops_stats = grouped['GFLOPS'].agg(['mean'])
        gflops_stats.columns = ['GFLOPS_Media']
        
        # Combinar estadísticas
        final_summary = pd.concat([time_stats, gflops_stats], axis=1)
        
        # Mostrar resumen
        print(final_summary.to_string())
        print("\n" + "="*70)
        
        # Calcular speedup (comparado con 1 proceso)
        print("\n" + "="*70)
        print("                    ANÁLISIS DE SPEEDUP")
        print("="*70 + "\n")
        
        for size in df['Tamano_Matriz'].unique():
            print(f"\nMatriz {size}x{size}:")
            size_data = df[df['Tamano_Matriz'] == size]
            grouped_size = size_data.groupby('Num_Procesos')['Tiempo_Segundos'].mean()
            
            base_time = grouped_size[1]  # Tiempo con 1 proceso
            
            print(f"  {'Procesos':<12} {'Tiempo(s)':<12} {'Speedup':<12} {'Eficiencia(%)':<15}")
            print(f"  {'-'*12} {'-'*12} {'-'*12} {'-'*15}")
            
            for procs in sorted(grouped_size.index):
                time = grouped_size[procs]
                speedup = base_time / time
                efficiency = (speedup / procs) * 100
                print(f"  {procs:<12} {time:<12.4f} {speedup:<12.2f} {efficiency:<15.2f}")
        
        print("\n" + "="*70 + "\n")
        
        # Guardar resumen en archivo
        output_file = csv_file.replace('.csv', '_resumen.txt')
        with open(output_file, 'w') as f:
            f.write("="*70 + "\n")
            f.write("                    RESUMEN ESTADÍSTICO\n")
            f.write("="*70 + "\n\n")
            f.write(final_summary.to_string())
            f.write("\n\n")
            
            f.write("="*70 + "\n")
            f.write("                    ANÁLISIS DE SPEEDUP\n")
            f.write("="*70 + "\n\n")
            
            for size in df['Tamano_Matriz'].unique():
                f.write(f"\nMatriz {size}x{size}:\n")
                size_data = df[df['Tamano_Matriz'] == size]
                grouped_size = size_data.groupby('Num_Procesos')['Tiempo_Segundos'].mean()
                
                base_time = grouped_size[1]
                
                f.write(f"  {'Procesos':<12} {'Tiempo(s)':<12} {'Speedup':<12} {'Eficiencia(%)':<15}\n")
                f.write(f"  {'-'*12} {'-'*12} {'-'*12} {'-'*15}\n")
                
                for procs in sorted(grouped_size.index):
                    time = grouped_size[procs]
                    speedup = base_time / time
                    efficiency = (speedup / procs) * 100
                    f.write(f"  {procs:<12} {time:<12.4f} {speedup:<12.2f} {efficiency:<15.2f}\n")
            
            f.write("\n" + "="*70 + "\n")
        
        print(f"Resumen guardado en: {output_file}\n")
        
    except FileNotFoundError:
        print(f"Error: No se encontró el archivo {csv_file}")
        sys.exit(1)
    except Exception as e:
        print(f"Error al procesar el archivo: {e}")
        sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print("Uso: python3 generate_summary.py <archivo_csv>")
        print("Ejemplo: python3 generate_summary.py resultados/benchmark_20241120.csv")
        sys.exit(1)
    
    csv_file = sys.argv[1]
    generate_summary(csv_file)

if __name__ == "__main__":
    main()