# -*- coding: utf-8 -*-
"""中等规模测试：200只股票，全流程"""

import sys, time
sys.path.insert(0, "stock_strategy")

import config
config.MAX_STOCKS = 200
config.RESULT_DIR = "E:/数学实验项目/results_200"

from data_loader import load_all_stocks
from features import calculate_all_features
from strategy import generate_all_signals, get_all_strategies
from backtest import run_full_backtest
from config import HOLD_DAYS, MA_WINDOWS, BOX_LENGTHS

print("=" * 60)
print("200只股票测试")
print("=" * 60)

t0 = time.time()

# 1. Load
print("\n[1] Loading data...")
stock_data = load_all_stocks("E:/数学实验项目/day", max_stocks=200)
print(f"Loaded {len(stock_data)} stocks")

# 2. Features
print("\n[2] Calculating features...")
for i, (code, df) in enumerate(stock_data.items()):
    stock_data[code] = calculate_all_features(df,
        ma_windows=MA_WINDOWS,
        box_lengths=BOX_LENGTHS,
    )
    if (i + 1) % 50 == 0:
        print(f"  {i + 1}/{len(stock_data)}")
print("Features done.")

# 3. Signals
print("\n[3] Generating signals...")
strategies = get_all_strategies()
for code, df in stock_data.items():
    stock_data[code] = generate_all_signals(df, strategies)
# Stats
for key, (_, name) in strategies.items():
    total = sum(df[f"signal_{key}"].sum() for df in stock_data.values())
    print(f"  {name}: {int(total)} signals")

# 4. Backtest
print("\n[4] Running backtest...")
summary_df = run_full_backtest(stock_data, strategies, HOLD_DAYS)
print("\n" + str(summary_df.to_string()))

# 5. Save
from analysis import save_results, save_results_excel, run_all_visualizations
save_results(summary_df)
try:
    save_results_excel(summary_df)
except Exception as e:
    print(f"Excel save failed: {e}")
run_all_visualizations(summary_df, stock_data, strategies, HOLD_DAYS)

t1 = time.time()
print(f"\nTotal: {t1 - t0:.1f}s")
