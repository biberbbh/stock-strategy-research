# -*- coding: utf-8 -*-
"""快速测试：加载20只股票，计算特征，生成信号"""

import sys
sys.path.insert(0, "stock_strategy")

from config import *
import config
config.MAX_STOCKS = 20
config.RESULT_DIR = "E:/数学实验项目/results_test"

from data_loader import load_all_stocks
stock_data = load_all_stocks("E:/数学实验项目/day", max_stocks=20)
print(f"\nLoaded {len(stock_data)} stocks\n")

# Test feature calculation on one stock
from features import calculate_all_features
code = list(stock_data.keys())[0]
df = calculate_all_features(stock_data[code])
print(f"Features calculated for {code}: {len(df.columns)} columns")
print(f"Columns: {list(df.columns)}")
print(f"Non-null MA5: {df['MA5'].notna().sum()}")
print(f"Non-null RSI14: {df['RSI14'].notna().sum()}")
print(f"Non-null DIF: {df['DIF'].notna().sum()}")
print(f"Non-null box_pos_60: {df['box_pos_60'].notna().sum()}")
print(f"Non-null K: {df['K'].notna().sum()}")

# Test signal generation
from strategy import generate_all_signals, get_all_strategies
strategies = get_all_strategies()
df = generate_all_signals(df, strategies)
for key, (_, name) in strategies.items():
    sig_col = f"signal_{key}"
    n_signals = df[sig_col].sum()
    print(f"Signals for {name}: {int(n_signals)}")

# Test backtest
from backtest import backtest_single_stock, calculate_metrics
for key, (_, name) in strategies.items():
    sig_col = f"signal_{key}"
    trades = backtest_single_stock(df, sig_col, hold_days=10)
    metrics = calculate_metrics(trades)
    print(f"\n{name} (hold 10d): {metrics['trade_count']} trades, "
          f"win_rate(>0)={metrics['win_rate_gt0']}%, "
          f"avg_return={metrics['avg_return']}%")

print("\n=== Test passed! ===")
