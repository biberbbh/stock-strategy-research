# -*- coding: utf-8 -*-
"""
交易策略模块
定义多个买入策略，每个策略返回布尔类型的买入信号 Series。

约定：
  - 信号日 i: 满足买入条件的交易日
  - 买入日: 信号日下一个交易日 (i+1)，以收盘价买入
  - 信号值为 1 表示该日收盘后触发买入信号
  - 所有策略仅使用当前及历史数据，无未来信息泄露
"""

import pandas as pd
import numpy as np
from typing import Dict, Callable, Any


# ---- 策略类型 ----
StrategyFunc = Callable[[pd.DataFrame, Dict[str, Any]], pd.Series]


# ============================================================
# 策略 1：均线金叉 + 量能确认
# 条件：
#   1) MA5 上穿 MA10 (金叉)
#   2) RSI14 ∈ [30, 70]
#   3) 当日成交量 > 5日均量 × vol_ratio_min
# ============================================================
def strategy_ma_cross(df: pd.DataFrame, params: dict = None) -> pd.Series:
    """
    均线金叉 + 量能确认策略。
    当短期均线上穿长期均线且量能放大时，视为买入信号。
    """
    if params is None:
        from config import STRATEGY_PARAMS
        params = STRATEGY_PARAMS["strategy1_ma_cross"]

    rsi_min = params.get("rsi_min", 30)
    rsi_max = params.get("rsi_max", 70)
    vol_ratio_min = params.get("vol_ratio_min", 1.0)

    # 检查必要列
    required = ["ma5_cross_ma10", "RSI14", "vol_ratio"]
    for col in required:
        if col not in df.columns:
            raise ValueError(f"缺少必要列: {col}，请先运行 features.calculate_all_features()")

    signal = pd.Series(0, index=df.index, dtype=int)

    cond1 = df["ma5_cross_ma10"] == 1
    cond2 = (df["RSI14"] >= rsi_min) & (df["RSI14"] <= rsi_max)
    cond3 = df["vol_ratio"] > vol_ratio_min

    mask = cond1 & cond2 & cond3
    signal[mask] = 1

    return signal


# ============================================================
# 策略 2：箱体底部反弹
# 条件：
#   1) 箱体位置 < box_position_max (默认 0.2，即在箱体底部 20%)
#   2) 满足以下任一：
#      - MACD 金叉
#      - 前一日 zdf < zdf_trigger（急跌反弹，默认 -2%）
# ============================================================
def strategy_box_reversal(df: pd.DataFrame, params: dict = None) -> pd.Series:
    """
    箱体底部反弹策略。
    当股价处于箱体底部且出现反转信号时买入。
    """
    if params is None:
        from config import STRATEGY_PARAMS
        params = STRATEGY_PARAMS["strategy2_box_reversal"]

    box_pos_max = params.get("box_position_max", 0.2)
    zdf_trigger = params.get("zdf_trigger", -2.0)
    box_col = "box_pos_60"  # 使用 60 日箱体作为主箱体

    required = [box_col, "macd_golden_cross", "zdf"]
    for col in required:
        if col not in df.columns:
            raise ValueError(f"缺少必要列: {col}，请先运行 features.calculate_all_features()")

    signal = pd.Series(0, index=df.index, dtype=int)

    cond1 = df[box_col] < box_pos_max
    cond2a = df["macd_golden_cross"] == 1
    cond2b = df["zdf"].shift(1) < zdf_trigger  # 前一日急跌
    cond2 = cond2a | cond2b

    mask = cond1 & cond2
    signal[mask] = 1

    return signal


# ============================================================
# 策略 3：连跌反弹
# 条件：
#   1) 连续 N 日下跌 (zdf < 0)
#   2) 近 N 日累计跌幅 < cumulative_zdf_max (默认 -3.0)
#   3) 当日换手率 > hsl_min (默认 1.0%)
# ============================================================
def strategy_decline_rebound(df: pd.DataFrame, params: dict = None) -> pd.Series:
    """
    连跌反弹策略。
    连续下跌后，换手率足够时博反弹。
    """
    if params is None:
        from config import STRATEGY_PARAMS
        params = STRATEGY_PARAMS["strategy3_decline_rebound"]

    n_days = params.get("consecutive_days", 3)
    cum_zdf_max = params.get("cumulative_zdf_max", -3.0)
    hsl_min = params.get("hsl_min", 1.0)

    required = ["zdf", "hsl"]
    for col in required:
        if col not in df.columns:
            raise ValueError(f"缺少必要列: {col}")

    signal = pd.Series(0, index=df.index, dtype=int)

    # 近 N 日涨跌幅
    zdf_series = df["zdf"]
    cum_zdf = zdf_series.rolling(window=n_days, min_periods=n_days).sum()

    # 近 N 日均下跌
    all_decline = pd.Series(True, index=df.index)
    for k in range(n_days):
        all_decline = all_decline & (zdf_series.shift(k) < 0)

    # 前一交易日跌幅满足条件（加速恐慌）
    last_decline = zdf_series.shift(1) < -1.0

    cond = all_decline & (cum_zdf < cum_zdf_max) & last_decline & (df["hsl"] > hsl_min)
    signal[cond] = 1

    return signal


# ============================================================
# 策略 4：多指标共振
# 条件：
#   1) MA5 上穿 MA10 (金叉)
#   2) RSI14 > rsi_min (默认 40)
#   3) 60日箱体位置 < box_position_max (默认 0.5，中位以下)
#   4) 换手率 > hsl_min (默认 2.0%)
# ============================================================
def strategy_multi_resonance(df: pd.DataFrame, params: dict = None) -> pd.Series:
    """
    多指标共振策略。
    当多个技术指标同时发出积极信号时买入。
    """
    if params is None:
        from config import STRATEGY_PARAMS
        params = STRATEGY_PARAMS["strategy4_multi_resonance"]

    rsi_min = params.get("rsi_min", 40)
    box_pos_max = params.get("box_position_max", 0.5)
    hsl_min = params.get("hsl_min", 2.0)

    required = ["ma5_cross_ma10", "RSI14", "box_pos_60", "hsl"]
    for col in required:
        if col not in df.columns:
            raise ValueError(f"缺少必要列: {col}，请先运行 features.calculate_all_features()")

    signal = pd.Series(0, index=df.index, dtype=int)

    cond1 = df["ma5_cross_ma10"] == 1
    cond2 = df["RSI14"] > rsi_min
    cond3 = df["box_pos_60"] < box_pos_max
    cond4 = df["hsl"] > hsl_min

    mask = cond1 & cond2 & cond3 & cond4
    signal[mask] = 1

    return signal


# ============================================================
# 策略注册表
# ============================================================

def get_all_strategies() -> Dict[str, tuple]:
    """
    获取所有策略函数及其显示名称。

    返回:
        dict: {策略键: (策略函数, 策略显示名称)}
    """
    return {
        "strategy1_ma_cross": (strategy_ma_cross, "均线金叉+量能确认"),
        "strategy2_box_reversal": (strategy_box_reversal, "箱体底部反弹"),
        "strategy3_decline_rebound": (strategy_decline_rebound, "连跌反弹"),
        "strategy4_multi_resonance": (strategy_multi_resonance, "多指标共振"),
    }


def generate_all_signals(df: pd.DataFrame, strategies: Dict[str, tuple] = None) -> pd.DataFrame:
    """
    生成所有策略的买入信号。

    参数:
        df:         包含全部特征列的 DataFrame
        strategies: 策略字典，默认使用 get_all_strategies()

    返回:
        DataFrame: 原始数据 + 各策略的信号列 (signal_{key})
    """
    if strategies is None:
        strategies = get_all_strategies()

    for key, (func, _) in strategies.items():
        try:
            df[f"signal_{key}"] = func(df)
        except ValueError as e:
            print(f"  [警告] 策略 {key} 生成失败: {e}")
            df[f"signal_{key}"] = 0

    return df
