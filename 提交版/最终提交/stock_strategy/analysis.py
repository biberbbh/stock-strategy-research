# -*- coding: utf-8 -*-
"""
结果分析与可视化模块
- 收益率分布直方图
- 持有周期对比折线图
- 策略×周期 胜率热力图
- 单股票累计收益曲线 (修正版：按交易实际收益复利)
- 参数敏感性分析
- 信号时间分布分析
- 统计显著性可视化
- 结果表格保存
"""

import os
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")  # 非交互后端，避免 GUI 依赖
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

from typing import Dict, Optional, List

# ---- 中文字体配置 ----
try:
    plt.rcParams["font.sans-serif"] = ["SimHei", "Microsoft YaHei", "DejaVu Sans"]
    plt.rcParams["axes.unicode_minus"] = False
except Exception:
    pass

from config import RESULT_DIR, FIGURE_DPI, FIGURE_FIGSIZE


# ============================================================
# 辅助：创建输出目录
# ============================================================
def _ensure_result_dir():
    os.makedirs(RESULT_DIR, exist_ok=True)


# ============================================================
# 图表 1：收益率分布直方图（一个策略 + 一个持有周期）
# ============================================================

def plot_return_distribution(trades_df: pd.DataFrame,
                             strategy_name: str,
                             hold_days: int,
                             return_col: str = "net_return_pct",
                             save: bool = True) -> str:
    """
    绘制单策略单周期的收益率分布直方图。
    """
    _ensure_result_dir()

    if trades_df.empty:
        print(f"  [跳过] {strategy_name} 持有 {hold_days} 天: 无交易数据")
        return ""

    returns = trades_df[return_col].values
    fig, axes = plt.subplots(1, 2, figsize=(16, 6))

    # 子图 1: 直方图 + 密度曲线
    ax = axes[0]
    ax.hist(returns, bins=80, color="steelblue", edgecolor="white",
            alpha=0.85, density=True)
    ax.axvline(0, color="red", linestyle="--", linewidth=1.2, label="零收益线")
    ax.axvline(np.mean(returns), color="darkorange", linestyle="-",
               linewidth=1.5, label=f'均值={np.mean(returns):.2f}%')
    ax.set_xlabel("收益率 (%)", fontsize=12)
    ax.set_ylabel("密度", fontsize=12)
    ax.set_title(f"{strategy_name} | 持有 {hold_days} 天 | "
                 f"交易 {len(trades_df)} 次", fontsize=14)
    ax.legend(fontsize=10)
    ax.grid(axis="y", alpha=0.3)

    # 子图 2: 累积分布函数 (CDF)
    ax2 = axes[1]
    sorted_returns = np.sort(returns)
    cdf = np.arange(1, len(sorted_returns) + 1) / len(sorted_returns)
    ax2.plot(sorted_returns, cdf, color="steelblue", linewidth=2)
    ax2.axvline(0, color="red", linestyle="--", linewidth=1.2, label="零收益线")
    ax2.axhline(0.5, color="gray", linestyle=":", linewidth=0.8, label="中位数")
    ax2.set_xlabel("收益率 (%)", fontsize=12)
    ax2.set_ylabel("累积概率", fontsize=12)
    ax2.set_title(f"{strategy_name} — 累积分布函数", fontsize=14)
    ax2.legend(fontsize=10)
    ax2.grid(alpha=0.3)

    fig.tight_layout()
    filepath = os.path.join(RESULT_DIR,
                            f"hist_{strategy_name}_hold{hold_days}.png")
    fig.savefig(filepath, dpi=FIGURE_DPI, bbox_inches="tight")
    plt.close(fig)
    print(f"  已保存: {filepath}")
    return filepath


# ============================================================
# 图表 2：持有周期对比折线图（所有策略）
# ============================================================

def plot_hold_period_comparison(summary_df: pd.DataFrame,
                                save: bool = True) -> str:
    """
    绘制不同持有天数下的平均收益率和胜率趋势折线图。
    每个策略一条线。
    """
    _ensure_result_dir()

    strategies = summary_df["策略名称"].unique()
    fig, axes = plt.subplots(2, 2, figsize=(16, 12))

    # 子图 1：平均收益率
    ax1 = axes[0, 0]
    for s in strategies:
        sub = summary_df[summary_df["策略名称"] == s]
        ax1.plot(sub["持有天数"], sub["平均收益率(%)"], marker="o", linewidth=2, label=s)
    ax1.axhline(0, color="gray", linestyle="--", linewidth=0.8)
    ax1.set_xlabel("持有天数", fontsize=12)
    ax1.set_ylabel("平均收益率 (%)", fontsize=12)
    ax1.set_title("平均收益率 vs 持有天数", fontsize=14)
    ax1.legend(fontsize=9)
    ax1.grid(alpha=0.3)

    # 子图 2：胜率 (>0)
    ax2 = axes[0, 1]
    for s in strategies:
        sub = summary_df[summary_df["策略名称"] == s]
        ax2.plot(sub["持有天数"], sub["胜率(>0%)"], marker="s", linewidth=2, label=s)
    ax2.axhline(50, color="gray", linestyle="--", linewidth=0.8, label="50% 基准")
    ax2.set_xlabel("持有天数", fontsize=12)
    ax2.set_ylabel("胜率 (>0%)", fontsize=12)
    ax2.set_title("胜率 vs 持有天数", fontsize=14)
    ax2.legend(fontsize=9)
    ax2.grid(alpha=0.3)

    # 子图 3：夏普比率 (如果有该列)
    if "夏普比率" in summary_df.columns:
        ax3 = axes[1, 0]
        for s in strategies:
            sub = summary_df[summary_df["策略名称"] == s]
            ax3.plot(sub["持有天数"], sub["夏普比率"], marker="^", linewidth=2, label=s)
        ax3.axhline(0, color="gray", linestyle="--", linewidth=0.8)
        ax3.set_xlabel("持有天数", fontsize=12)
        ax3.set_ylabel("夏普比率", fontsize=12)
        ax3.set_title("夏普比率 vs 持有天数", fontsize=14)
        ax3.legend(fontsize=9)
        ax3.grid(alpha=0.3)

    # 子图 4：最大回撤 (如果有该列)
    if "最大回撤(%)" in summary_df.columns:
        ax4 = axes[1, 1]
        for s in strategies:
            sub = summary_df[summary_df["策略名称"] == s]
            ax4.plot(sub["持有天数"], sub["最大回撤(%)"], marker="D", linewidth=2, label=s)
        ax4.set_xlabel("持有天数", fontsize=12)
        ax4.set_ylabel("最大回撤 (%)", fontsize=12)
        ax4.set_title("最大回撤 vs 持有天数", fontsize=14)
        ax4.legend(fontsize=9)
        ax4.grid(alpha=0.3)

    fig.tight_layout()
    filepath = os.path.join(RESULT_DIR, "hold_period_comparison.png")
    fig.savefig(filepath, dpi=FIGURE_DPI, bbox_inches="tight")
    plt.close(fig)
    print(f"  已保存: {filepath}")
    return filepath


# ============================================================
# 图表 3：热力图（策略 × 持有天数 → 胜率/平均收益率/夏普比率）
# ============================================================

def plot_heatmap(summary_df: pd.DataFrame, metric: str = "胜率(>0%)",
                 save: bool = True) -> str:
    """
    绘制策略 × 持有天数的热力图。
    """
    _ensure_result_dir()

    pivot = summary_df.pivot_table(
        index="策略名称", columns="持有天数", values=metric
    )

    # 动态色阶范围
    vmin_val = max(0, pivot.min().min() * 0.9) if not pivot.empty else 0
    vmax_val = pivot.max().max() * 1.1 if not pivot.empty else 100

    fig, ax = plt.subplots(figsize=(12, len(pivot.index) * 1.2 + 2))
    im = ax.imshow(pivot.values, aspect="auto", cmap="RdYlGn",
                   vmin=vmin_val, vmax=vmax_val)

    ax.set_xticks(range(len(pivot.columns)))
    ax.set_xticklabels(pivot.columns, fontsize=11)
    ax.set_yticks(range(len(pivot.index)))
    ax.set_yticklabels(pivot.index, fontsize=11)
    ax.set_xlabel("持有天数", fontsize=12)
    ax.set_title(f"策略 × 持有天数 — {metric} 热力图", fontsize=14)

    # 在格内标注数值
    for i in range(len(pivot.index)):
        for j in range(len(pivot.columns)):
            val = pivot.values[i, j]
            text = f"{val:.1f}" if not np.isnan(val) else "N/A"
            ax.text(j, i, text, ha="center", va="center",
                    fontsize=9, color="black")

    fig.colorbar(im, ax=ax, shrink=0.85)
    fig.tight_layout()

    metric_safe = metric.replace(">", "gt").replace("<", "lt").replace("(", "").replace(")", "").replace("%", "pct")
    filepath = os.path.join(RESULT_DIR, f"heatmap_{metric_safe}.png")
    fig.savefig(filepath, dpi=FIGURE_DPI, bbox_inches="tight")
    plt.close(fig)
    print(f"  已保存: {filepath}")
    return filepath


# ============================================================
# 图表 4：单股票累计收益曲线（修正版：按实际交易复利计算）
# ============================================================

def plot_cumulative_returns(df: pd.DataFrame,
                            signal_col: str,
                            strategy_name: str,
                            hold_days: int,
                            save: bool = True) -> Optional[str]:
    """
    绘制某只代表性股票的买入持有 vs 策略累积收益曲线。

    修正说明：
      - 不再使用线性分摊日收益
      - 每笔交易独立贡献，在卖出日结算
      - 累积净值 = ∏ (1 + 交易收益)，持有期间净值不变

    Returns:
        文件路径，若无信号则返回 None
    """
    _ensure_result_dir()

    if signal_col not in df.columns or df[signal_col].sum() == 0:
        return None

    from backtest import backtest_single_stock
    trades = backtest_single_stock(df, signal_col, hold_days,
                                   include_costs=True)
    if trades.empty:
        return None

    df = df.sort_values("day").reset_index(drop=True)
    n = len(df)

    # 策略累积净值：初始 1.0，在卖出日结算收益
    strat_cum = np.ones(n)
    initialized = np.zeros(n, dtype=bool)  # 标记哪些位置已被交易覆盖

    for _, trade in trades.iterrows():
        buy_idx = int(trade["buy_idx"])
        sell_idx = int(trade["sell_idx"])
        net_ret = trade.get("net_return_pct", trade.get("return_pct", 0)) / 100.0

        # 持有期间复制前一日净值，卖出日应用收益
        for k in range(buy_idx, sell_idx + 1):
            if k >= n:
                continue
            if k == sell_idx:
                prev_val = strat_cum[k - 1] if k > 0 else 1.0
                strat_cum[k] = prev_val * (1.0 + net_ret)
                initialized[k] = True
            elif k == buy_idx:
                if k > 0:
                    strat_cum[k] = strat_cum[k - 1]
                initialized[k] = True
            else:
                strat_cum[k] = strat_cum[k - 1]
                initialized[k] = True

    # 填充未初始化的区间（未参与任何交易的日期）
    for k in range(1, n):
        if not initialized[k]:
            strat_cum[k] = strat_cum[k - 1]

    # 基准：买入持有
    base_close = df["close"].values[0]
    bh_cum = df["close"].values / base_close

    fig, ax = plt.subplots(figsize=FIGURE_FIGSIZE)
    dates = df["day"].values

    ax.plot(dates, bh_cum, label="买入持有基准", color="gray",
            linewidth=1.5, alpha=0.7)
    ax.plot(dates, strat_cum, label=f"{strategy_name} (持有{hold_days}天, 净收益)",
            color="steelblue", linewidth=1.8)

    # 标注买入点
    buy_indices = trades["buy_idx"].values.astype(int)
    valid_buy = [i for i in buy_indices if i < n]
    if valid_buy:
        ax.scatter(dates[valid_buy], strat_cum[valid_buy],
                   marker="^", color="green", s=30, zorder=5, label="买入点")
    # 标注卖出点
    sell_indices = trades["sell_idx"].values.astype(int)
    valid_sell = [i for i in sell_indices if i < n]
    if valid_sell:
        ax.scatter(dates[valid_sell], strat_cum[valid_sell],
                   marker="v", color="red", s=20, zorder=5, label="卖出点", alpha=0.6)

    ax.set_xlabel("日期", fontsize=12)
    ax.set_ylabel("累积净值", fontsize=12)
    ax.set_title(f"累积收益曲线 — {strategy_name} ({hold_days}天持有)", fontsize=14)
    ax.legend(fontsize=9)
    ax.grid(alpha=0.3)
    ax.yaxis.set_major_formatter(mticker.FormatStrFormatter('%.2f'))

    fig.tight_layout()

    stock_code = df["stock_code"].iloc[0] if "stock_code" in df.columns else "sample"
    filepath = os.path.join(RESULT_DIR,
                            f"cumret_{stock_code}_{strategy_name}_hold{hold_days}.png")
    fig.savefig(filepath, dpi=FIGURE_DPI, bbox_inches="tight")
    plt.close(fig)
    return filepath


# ============================================================
# 图表 5：参数敏感性分析
# ============================================================

def plot_parameter_sensitivity(summary_df: pd.DataFrame,
                               param_name: str = "持有天数",
                               metrics: List[str] = None,
                               save: bool = True) -> str:
    """
    绘制参数敏感性分析图 —— 展示各策略在参数变化下的表现稳定性。

    参数:
        summary_df: 回测汇总表（需含不同参数值的结果）
        param_name: 参数列名（如 "持有天数"）
        metrics:    要展示的指标列表
        save:       是否保存

    返回:
        文件路径
    """
    if metrics is None:
        available = [c for c in ["胜率(>0%)", "平均收益率(%)", "夏普比率", "盈亏比"]
                     if c in summary_df.columns]
        metrics = available

    _ensure_result_dir()

    n_metrics = len(metrics)
    fig, axes = plt.subplots(1, n_metrics, figsize=(6 * n_metrics, 5))
    if n_metrics == 1:
        axes = [axes]

    strategies = summary_df["策略名称"].unique()

    for i, metric in enumerate(metrics):
        ax = axes[i]
        for s in strategies:
            sub = summary_df[summary_df["策略名称"] == s].sort_values(param_name)
            ax.plot(sub[param_name], sub[metric], marker="o", linewidth=2, label=s)
        ax.set_xlabel(param_name, fontsize=11)
        ax.set_ylabel(metric, fontsize=11)
        ax.set_title(f"{metric} 随 {param_name} 变化", fontsize=12)
        ax.legend(fontsize=8)
        ax.grid(alpha=0.3)

    fig.tight_layout()
    filepath = os.path.join(RESULT_DIR, f"sensitivity_{param_name}.png")
    fig.savefig(filepath, dpi=FIGURE_DPI, bbox_inches="tight")
    plt.close(fig)
    print(f"  已保存: {filepath}")
    return filepath


# ============================================================
# 图表 6：信号时间分布分析
# ============================================================

def plot_signal_time_distribution(stock_data: Dict[str, pd.DataFrame],
                                  strategies: Dict[str, tuple] = None,
                                  save: bool = True) -> Optional[str]:
    """
    绘制各策略信号的月度/季度分布，分析信号集中度。

    参数:
        stock_data: 含信号列的股票数据
        strategies: 策略字典
        save:       是否保存

    返回:
        文件路径
    """
    _ensure_result_dir()

    if strategies is None:
        from strategy import get_all_strategies
        strategies = get_all_strategies()

    # 收集所有信号的日期
    all_dates = {}
    for key, (_, name) in strategies.items():
        signal_col = f"signal_{key}"
        dates_list = []
        for code, df in stock_data.items():
            if signal_col in df.columns:
                sig_dates = df.loc[df[signal_col] == 1, "day"]
                if not sig_dates.empty:
                    dates_list.extend(sig_dates.tolist())
        if dates_list:
            all_dates[name] = pd.to_datetime(dates_list)

    if not all_dates:
        return None

    fig, axes = plt.subplots(len(all_dates), 1, figsize=(14, 3 * len(all_dates)))
    if len(all_dates) == 1:
        axes = [axes]

    for i, (name, dates) in enumerate(all_dates.items()):
        ax = axes[i]
        # 按月统计信号数量
        date_series = pd.Series(dates)
        monthly_grouped = date_series.groupby(date_series.dt.to_period("M")).count()
        ax.bar(range(len(monthly_grouped)), monthly_grouped.values,
               color="steelblue", alpha=0.85)
        ax.set_xticks(range(0, len(monthly_grouped), max(1, len(monthly_grouped) // 12)))
        ax.set_xticklabels([str(m) for m in monthly_grouped.index[::max(1, len(monthly_grouped) // 12)]],
                           rotation=45, ha="right", fontsize=8)
        ax.set_ylabel("信号数", fontsize=11)
        ax.set_title(f"{name} — 月度信号分布 (总计 {len(dates)} 个)", fontsize=12)
        ax.grid(axis="y", alpha=0.3)

    fig.tight_layout()
    filepath = os.path.join(RESULT_DIR, "signal_time_distribution.png")
    fig.savefig(filepath, dpi=FIGURE_DPI, bbox_inches="tight")
    plt.close(fig)
    print(f"  已保存: {filepath}")
    return filepath


# ============================================================
# 图表 7：统计显著性可视化
# ============================================================

def plot_significance_forest(summary_df: pd.DataFrame,
                             save: bool = True) -> str:
    """
    绘制各策略的置信区间森林图 (Forest Plot)。

    参数:
        summary_df: 回测汇总表（需含 收益CI下界, 收益CI上界, 胜率p值 列）
        save:       是否保存

    返回:
        文件路径
    """
    _ensure_result_dir()

    if "收益CI下界" not in summary_df.columns:
        print("  [跳过] 无置信区间数据，请先运行含统计检验的回测")
        return ""

    # 选择 60 天持有期数据
    if "持有天数" in summary_df.columns:
        plot_df = summary_df[summary_df["持有天数"] == 60].copy()
    else:
        plot_df = summary_df.copy()

    if plot_df.empty:
        return ""

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    # 子图 1: 置信区间森林图
    ax1 = axes[0]
    strategies = plot_df["策略名称"].values
    means = plot_df["平均收益率(%)"].values
    ci_lower = plot_df["收益CI下界"].values
    ci_upper = plot_df["收益CI上界"].values

    y_pos = range(len(strategies))
    ax1.errorbar(means, y_pos, xerr=[means - ci_lower, ci_upper - means],
                 fmt="o", capsize=5, capthick=2, color="steelblue",
                 markersize=8, linewidth=2)
    ax1.axvline(0, color="red", linestyle="--", linewidth=1, alpha=0.7)
    ax1.set_yticks(y_pos)
    ax1.set_yticklabels(strategies, fontsize=10)
    ax1.set_xlabel("平均收益率 (%)", fontsize=12)
    ax1.set_title("60天持有 — 平均收益率 95% Bootstrap CI", fontsize=13)
    ax1.grid(alpha=0.3, axis="x")

    # 子图 2: 胜率 vs 随机基准 (50%)
    ax2 = axes[1]
    win_rates = plot_df["胜率(>0%)"].values
    p_values = plot_df.get("胜率p值", pd.Series([np.nan] * len(plot_df))).values

    colors = ["green" if p < 0.05 else "gray" for p in p_values]
    bars = ax2.barh(y_pos, win_rates, color=colors, alpha=0.8)
    ax2.axvline(50, color="gray", linestyle="--", linewidth=1.5, label="随机基准 50%")
    ax2.set_yticks(y_pos)
    ax2.set_yticklabels(strategies, fontsize=10)
    ax2.set_xlabel("胜率 (>0%)", fontsize=12)
    ax2.set_title("60天持有 — 胜率 vs 随机基准\n(绿色 = 显著优于随机, p<0.05)", fontsize=13)

    # 添加显著性标注
    for j, (wr, p) in enumerate(zip(win_rates, p_values)):
        sig_mark = "***" if p < 0.001 else ("**" if p < 0.01 else ("*" if p < 0.05 else ""))
        if sig_mark:
            ax2.text(wr + 1, j, sig_mark, va="center", fontsize=12, color="darkgreen")

    ax2.legend(fontsize=9)
    ax2.grid(alpha=0.3, axis="x")

    fig.tight_layout()
    filepath = os.path.join(RESULT_DIR, "significance_forest.png")
    fig.savefig(filepath, dpi=FIGURE_DPI, bbox_inches="tight")
    plt.close(fig)
    print(f"  已保存: {filepath}")
    return filepath


# ============================================================
# 综合可视化
# ============================================================

def run_all_visualizations(summary_df: pd.DataFrame,
                           stock_data: Dict[str, pd.DataFrame] = None,
                           strategies: Dict[str, tuple] = None,
                           hold_days_list: list = None) -> None:
    """
    运行所有可视化分析。

    参数:
        summary_df:    回测汇总表
        stock_data:    股票数据字典（用于单股票曲线和信号分布）
        strategies:    策略字典
        hold_days_list: 持有天数列表
    """
    _ensure_result_dir()
    print("\n" + "=" * 60)
    print("生成可视化图表...")
    print("=" * 60)

    # 1. 持有周期对比折线图
    print("\n[1/7] 持有周期对比图")
    plot_hold_period_comparison(summary_df)

    # 2. 热力图 - 胜率
    print("\n[2/7] 热力图 (胜率)")
    plot_heatmap(summary_df, "胜率(>0%)")

    # 3. 热力图 - 平均收益率
    print("\n[3/7] 热力图 (平均收益率)")
    plot_heatmap(summary_df, "平均收益率(%)")

    # 4. 如果存在夏普比率列，绘制夏普比率热力图
    if "夏普比率" in summary_df.columns:
        print("\n[4/7] 热力图 (夏普比率)")
        plot_heatmap(summary_df, "夏普比率")

    # 5. 单股票累积收益曲线
    print("\n[5/7] 单股票累积收益曲线")
    if stock_data and strategies and hold_days_list:
        best_combo = summary_df.loc[summary_df["交易次数"].idxmax()]
        best_strategy_name = best_combo["策略名称"]
        best_hold = int(best_combo["持有天数"])

        strategy_key = None
        for key, (_, name) in strategies.items():
            if name == best_strategy_name:
                strategy_key = key
                break

        if strategy_key:
            signal_col = f"signal_{strategy_key}"
            for code, df in stock_data.items():
                if signal_col in df.columns and df[signal_col].sum() >= 5:
                    filepath = plot_cumulative_returns(
                        df, signal_col, best_strategy_name, best_hold
                    )
                    if filepath:
                        print(f"  使用股票: {code}")
                        break

    # 6. 参数敏感性分析
    print("\n[6/7] 参数敏感性分析")
    plot_parameter_sensitivity(summary_df)

    # 7. 统计显著性可视化
    print("\n[7/7] 统计显著性分析")
    plot_significance_forest(summary_df)

    # 额外：信号时间分布（如果数据量大）
    if stock_data and strategies and len(stock_data) <= 200:
        print("\n[额外] 信号月度分布")
        plot_signal_time_distribution(stock_data, strategies)

    print("\n可视化完成。图表保存于: " + RESULT_DIR)


# ============================================================
# 结果保存
# ============================================================

def save_results(summary_df: pd.DataFrame) -> str:
    """
    将回测汇总表保存为 CSV (UTF-8 with BOM，便于 Excel 打开)。
    """
    _ensure_result_dir()
    filepath = os.path.join(RESULT_DIR, "backtest_summary.csv")
    summary_df.to_csv(filepath, index=False, encoding="utf-8-sig")
    print(f"结果表已保存: {filepath}")
    return filepath


def save_results_excel(summary_df: pd.DataFrame) -> str:
    """
    保存为 Excel 格式（包含多个工作表，便于报告使用）。
    """
    _ensure_result_dir()
    filepath = os.path.join(RESULT_DIR, "backtest_results.xlsx")

    with pd.ExcelWriter(filepath, engine="openpyxl") as writer:
        # 完整汇总表
        summary_df.to_excel(writer, sheet_name="汇总表", index=False)

        # 按策略分表
        for strategy_name in summary_df["策略名称"].unique():
            sub = summary_df[summary_df["策略名称"] == strategy_name]
            safe_name = strategy_name[:31]
            sub.to_excel(writer, sheet_name=safe_name, index=False)

        # 按持有天数分表
        for hold_days in summary_df["持有天数"].unique():
            sub = summary_df[summary_df["持有天数"] == hold_days]
            sub.to_excel(writer, sheet_name=f"持有{int(hold_days)}天", index=False)

    print(f"Excel 结果已保存: {filepath}")
    return filepath
