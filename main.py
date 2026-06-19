# -*- coding: utf-8 -*-
"""
股票特征建模与买入时机研究 — 根目录启动脚本

用法:
    python main.py                          # 使用默认配置运行
    python main.py --max-stocks 100         # 限制股票数量（快速测试）
    python main.py --walk-forward           # 启用 Walk-Forward 样本外验证
    python main.py --no-costs               # 不计交易成本（调试用）
"""

import os
import sys
import argparse
import time

# 将 stock_strategy 模块加入路径
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "stock_strategy"))

from config import (
    DATA_DIR, RESULT_DIR, HOLD_DAYS,
    MA_WINDOWS, BOX_LENGTHS, MACD_FAST, MACD_SLOW, MACD_SIGNAL,
    RSI_PERIOD, KDJ_PERIOD, VOL_MA_WINDOW,
    MAX_STOCKS,
)
import config as cfg
from data_loader import load_all_stocks, get_data_summary
from features import calculate_all_features
from strategy import generate_all_signals, get_all_strategies
from backtest import run_full_backtest, split_train_test, walk_forward_validation
from analysis import (
    run_all_visualizations,
    save_results,
    save_results_excel,
)


def main():
    parser = argparse.ArgumentParser(description="股票特征建模与买入时机研究 — 回测系统")
    parser.add_argument("--data", type=str, default=None,
                        help="股票 CSV 数据目录路径")
    parser.add_argument("--output", type=str, default=None,
                        help="结果输出目录")
    parser.add_argument("--max-stocks", type=int, default=None,
                        help="限制回测股票数量")
    parser.add_argument("--no-costs", action="store_true",
                        help="不计交易成本")
    parser.add_argument("--walk-forward", action="store_true",
                        help="启用 Walk-Forward 滚动窗口验证")
    parser.add_argument("--train-test-split", action="store_true",
                        help="启用 训练集/测试集 划分验证")
    args = parser.parse_args()

    start_time = time.time()

    # 确定数据目录
    data_dir = os.environ.get("STOCK_DATA_DIR", "")
    if args.data:
        data_dir = args.data
    if not data_dir or not os.path.isdir(data_dir):
        data_dir = DATA_DIR
    if not os.path.isdir(data_dir):
        for candidate in [os.path.join(os.getcwd(), "day"),
                          os.path.join(os.getcwd(), "data"),
                          os.path.join(os.path.dirname(__file__), "day")]:
            if os.path.isdir(candidate):
                data_dir = candidate
                break

    if not os.path.isdir(data_dir):
        print(f"错误: 数据目录不存在: {data_dir}")
        print("请使用 --data 参数指定，或设置 STOCK_DATA_DIR 环境变量")
        return

    # 确定输出目录
    if args.output:
        cfg.RESULT_DIR = args.output
    os.makedirs(cfg.RESULT_DIR, exist_ok=True)

    max_stocks = args.max_stocks if args.max_stocks else MAX_STOCKS
    include_costs = not args.no_costs

    print("=" * 60)
    print("  股票特征建模与买入时机研究 — 回测系统")
    print("=" * 60)
    print(f"  数据目录: {data_dir}")
    print(f"  输出目录: {cfg.RESULT_DIR}")
    if max_stocks:
        print(f"  股票数量: 最多 {max_stocks} 只")
    print(f"  交易成本: {'计入' if include_costs else '不计'}")
    if args.walk_forward:
        print(f"  验证模式: Walk-Forward 滚动窗口")
    if args.train_test_split:
        print(f"  验证模式: 训练集/测试集划分")
    print("=" * 60)

    # ==========================================
    # 阶段 1：数据加载
    # ==========================================
    print("\n" + "=" * 60)
    print("阶段 1/5: 数据加载")
    print("=" * 60)

    stock_data = load_all_stocks(data_dir, max_stocks=max_stocks)
    if not stock_data:
        print("未加载到任何股票数据，退出")
        return

    summary = get_data_summary(stock_data)
    print(f"\n数据概览:")
    print(f"  股票数量: {len(stock_data)}")
    print(f"  日期范围: {summary['start_date'].min().date()} ~ "
          f"{summary['end_date'].max().date()}")
    print(f"  平均每只股票 {summary['rows'].mean():.0f} 个交易日")

    # ==========================================
    # 阶段 2：特征计算
    # ==========================================
    print("\n" + "=" * 60)
    print("阶段 2/5: 特征计算")
    print("=" * 60)

    feat_start = time.time()
    for i, (code, df) in enumerate(stock_data.items()):
        stock_data[code] = calculate_all_features(
            df,
            ma_windows=MA_WINDOWS,
            box_lengths=BOX_LENGTHS,
            macd_params=(MACD_FAST, MACD_SLOW, MACD_SIGNAL),
            rsi_period=RSI_PERIOD,
            kdj_period=KDJ_PERIOD,
            vol_ma_window=VOL_MA_WINDOW,
        )
        if (i + 1) % 1000 == 0:
            print(f"  特征计算进度: {i + 1}/{len(stock_data)}")

    print(f"特征计算完成，耗时 {time.time() - feat_start:.1f} 秒")

    # ==========================================
    # 阶段 3：策略信号生成
    # ==========================================
    print("\n" + "=" * 60)
    print("阶段 3/5: 策略信号生成")
    print("=" * 60)

    strategies = get_all_strategies()
    for key, (_, name) in strategies.items():
        print(f"  - {name} ({key})")

    for code, df in stock_data.items():
        stock_data[code] = generate_all_signals(df, strategies)

    total_signals = {key: 0 for key in strategies}
    for code, df in stock_data.items():
        for key in strategies:
            total_signals[key] += int(df[f"signal_{key}"].sum())
    print("\n各策略总信号数:")
    for key, (_, name) in strategies.items():
        print(f"  {name}: {total_signals[key]}")

    # ==========================================
    # 阶段 4：回测验证
    # ==========================================
    print("\n" + "=" * 60)
    print("阶段 4/5: 回测验证")
    print("=" * 60)

    # --- 全样本回测 ---
    print("\n--- 全样本回测 ---")
    summary_df = run_full_backtest(stock_data, strategies, HOLD_DAYS,
                                   include_costs=include_costs)

    # --- 样本外验证 (可选) ---
    wf_result = None
    train_test_result = None

    if args.train_test_split:
        print("\n--- 训练/测试集划分验证 ---")
        train_data, test_data = split_train_test(stock_data)
        print(f"  训练集: {len(train_data)} 只, 测试集: {len(test_data)} 只")
        if test_data:
            # 在测试集上回测
            for code in test_data:
                test_data[code] = generate_all_signals(test_data[code], strategies)
            train_test_result = run_full_backtest(test_data, strategies, HOLD_DAYS,
                                                   include_costs=include_costs,
                                                   verbose=False)
        else:
            print("  [警告] 测试集为空，跳过")

    if args.walk_forward:
        print("\n--- Walk-Forward 滚动窗口验证 ---")
        wf_result = walk_forward_validation(stock_data, strategies, HOLD_DAYS)
        if not wf_result.empty:
            # 保存 Walk-Forward 结果
            wf_path = os.path.join(cfg.RESULT_DIR, "walk_forward_summary.csv")
            wf_result.to_csv(wf_path, index=False, encoding="utf-8-sig")
            print(f"\nWalk-Forward 结果已保存: {wf_path}")

    # 打印汇总表
    print("\n" + "=" * 60)
    print("回测结果汇总表 (全样本)")
    print("=" * 60)

    fmt_header = "{:<14s} {:>6s} {:>8s} {:>10s} {:>12s} {:>8s} {:>8s} {:>8s}"
    fmt_row = "{:<14s} {:>6d} {:>8d} {:>9.1f}% {:>11.2f}% {:>7.2f} {:>7.2f} {:>7.2f}"

    for strategy_name in summary_df["策略名称"].unique():
        sub = summary_df[summary_df["策略名称"] == strategy_name]
        print(f"\n--- {strategy_name} ---")
        cols = ["持有天", "交易次", "胜率>0", "平均收益", "夏普", "最大回撤", "盈亏比"]
        print(fmt_header.format("", *cols))
        for _, row in sub.iterrows():
            sharpe = row.get("夏普比率", np.nan)
            drawdown = row.get("最大回撤(%)", np.nan)
            profit_factor = row.get("盈亏比", np.nan)
            print(fmt_row.format(
                "",
                int(row["持有天数"]),
                int(row["交易次数"]),
                row["胜率(>0%)"],
                row["平均收益率(%)"],
                sharpe if not np.isnan(sharpe) else 0,
                drawdown if not np.isnan(drawdown) else 0,
                profit_factor if not np.isnan(profit_factor) else 0,
            ))

    # 如果包含交易成本，同时输出扣除前后的对比
    if include_costs:
        print("\n--- 交易成本影响分析 ---")
        best_row = summary_df.loc[summary_df["胜率(>0%)"].idxmax()]
        print(f"  最优策略 (按胜率): {best_row['策略名称']}, "
              f"持有 {int(best_row['持有天数'])} 天")
        print(f"  净收益: {best_row['平均收益率(%)']:.2f}%, "
              f"夏普比率: {best_row.get('夏普比率', np.nan):.2f}, "
              f"最大回撤: {best_row.get('最大回撤(%)', np.nan):.1f}%")

    # 保存结果
    print("\n保存回测结果...")
    save_results(summary_df)
    try:
        save_results_excel(summary_df)
    except Exception as e:
        print(f"  Excel 保存失败: {e}")

    # ==========================================
    # 阶段 5：可视化分析
    # ==========================================
    print("\n" + "=" * 60)
    print("阶段 5/5: 可视化分析")
    print("=" * 60)

    run_all_visualizations(summary_df, stock_data, strategies, HOLD_DAYS)

    # ==========================================
    # 完成
    # ==========================================
    total_elapsed = time.time() - start_time
    print("\n" + "=" * 60)
    print(f"全部完成！总耗时 {total_elapsed:.1f} 秒 "
          f"({total_elapsed / 60:.1f} 分钟)")
    print(f"结果保存于: {os.path.abspath(cfg.RESULT_DIR)}")
    print("=" * 60)


if __name__ == "__main__":
    main()
