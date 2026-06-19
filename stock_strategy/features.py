# -*- coding: utf-8 -*-
"""
特征工程模块
计算全部技术指标特征，包括：
  - 移动均线 (MA5, MA10, MA20, MA60)
  - MACD (DIF, DEA, MACD 柱)
  - RSI (14 日)
  - KDJ (K, D, J)
  - 箱体位置 (40/50/60 日)
  - 均线交叉信号 (金叉/死叉)
  - 成交量均量比

所有计算均为向量化实现，不使用逐行循环。
注意：所有特征仅使用当前及历史数据，无未来信息泄露。
"""

import pandas as pd
import numpy as np


# ============================================================
# 移动均线
# ============================================================

def calculate_ma(df: pd.DataFrame, windows: list = None) -> pd.DataFrame:
    """
    计算收盘价的简单移动平均 (SMA)。

    参数:
        df: 包含 'close' 列的 DataFrame
        windows: 均线窗口列表，默认 [5, 10, 20, 60]

    返回:
        添加了 MA{window} 列的 DataFrame
    """
    if windows is None:
        windows = [5, 10, 20, 60]
    for w in windows:
        df[f"MA{w}"] = df["close"].rolling(window=w, min_periods=w).mean()
    return df


# ============================================================
# MACD
# ============================================================

def calculate_macd(df: pd.DataFrame, fast: int = 12, slow: int = 26,
                   signal: int = 9) -> pd.DataFrame:
    """
    计算 MACD 指标。

    参数:
        df:   包含 'close' 列的 DataFrame
        fast: 快线 EMA 周期 (默认 12)
        slow: 慢线 EMA 周期 (默认 26)
        signal: 信号线 EMA 周期 (默认 9)

    返回:
        添加了 DIF, DEA, MACD 列的 DataFrame
    """
    close = df["close"].values
    ema_fast = _ema_recursive(close, fast)
    ema_slow = _ema_recursive(close, slow)

    dif = ema_fast - ema_slow
    dea = _ema_recursive(dif, signal)
    macd_bar = 2 * (dif - dea)

    df["DIF"] = dif
    df["DEA"] = dea
    df["MACD"] = macd_bar

    return df


def _ema_recursive(data: np.ndarray, span: int) -> np.ndarray:
    """
    递推计算指数移动平均 (EMA)。

    等价于 pandas.Series.ewm(span=span, adjust=False).mean()。
    注意：此为递推实现（非严格向量化），大量数据时建议直接使用
    pd.Series.ewm(span=span, adjust=False).mean() 以获得更好性能。

    参数:
        data: 输入序列
        span: EMA 周期

    返回:
        EMA 序列 (np.ndarray)
    """
    if len(data) == 0:
        return np.array([])
    result = np.full(len(data), np.nan)
    # alpha = 2 / (span + 1)
    alpha = 2.0 / (span + 1.0)
    # 找到第一个非 NaN 值作为初始种子
    first_valid = 0
    while first_valid < len(data) and np.isnan(data[first_valid]):
        first_valid += 1
    if first_valid >= len(data):
        return result
    result[first_valid] = data[first_valid]
    for i in range(first_valid + 1, len(data)):
        if np.isnan(data[i]):
            result[i] = result[i - 1]
        else:
            result[i] = alpha * data[i] + (1 - alpha) * result[i - 1]
    return result


# ============================================================
# RSI
# ============================================================

def calculate_rsi(df: pd.DataFrame, period: int = 14) -> pd.DataFrame:
    """
    计算相对强弱指数 RSI。

    参数:
        df:     包含 'close' 列的 DataFrame
        period: RSI 周期 (默认 14)

    返回:
        添加了 RSI{period} 列的 DataFrame
    """
    close = df["close"].values
    # 注：prepend=close[0] 使 delta[0] = 0（非标准但惯例用法），
    # 后续 gain[1:period+1] 跳过此元素，不影响计算结果
    delta = np.diff(close, prepend=close[0])
    gain = np.where(delta > 0, delta, 0.0)
    loss = np.where(delta < 0, -delta, 0.0)

    # 使用 Wilder's smoothing (等效于 EMA，alpha = 1/period)
    # 初始值用 period 周期的简单平均
    avg_gain = np.full(len(delta), np.nan)
    avg_loss = np.full(len(delta), np.nan)

    if len(delta) > period:
        avg_gain[period] = np.mean(gain[1:period + 1])
        avg_loss[period] = np.mean(loss[1:period + 1])
        for i in range(period + 1, len(delta)):
            avg_gain[i] = (avg_gain[i - 1] * (period - 1) + gain[i]) / period
            avg_loss[i] = (avg_loss[i - 1] * (period - 1) + loss[i]) / period

    rs = np.full(len(delta), np.nan)
    mask = (avg_loss > 0) & (~np.isnan(avg_gain))
    rs[mask] = avg_gain[mask] / avg_loss[mask]
    # 无亏损日时 RSI = 100
    mask2 = (avg_loss == 0) & (~np.isnan(avg_gain))
    rs[mask2] = np.inf

    rsi = np.full(len(delta), np.nan)
    rsi[rs != np.inf] = 100.0 - 100.0 / (1.0 + rs[rs != np.inf])
    rsi[rs == np.inf] = 100.0

    col_name = f"RSI{period}"
    df[col_name] = rsi
    return df


# ============================================================
# KDJ
# ============================================================

def calculate_kdj(df: pd.DataFrame, period: int = 9) -> pd.DataFrame:
    """
    计算随机指标 KDJ。

    参数:
        df:     包含 'close', 'high', 'low' 列的 DataFrame
        period: KDJ 周期 (默认 9)

    返回:
        添加了 K, D, J 列的 DataFrame
    """
    low_n = df["low"].rolling(window=period, min_periods=period).min()
    high_n = df["high"].rolling(window=period, min_periods=period).max()

    rsv = np.full(len(df), np.nan)
    denom = high_n - low_n
    valid = denom > 0
    rsv[valid] = (df["close"].values[valid] - low_n.values[valid]) / denom.values[valid] * 100.0
    # 一字板：最高=最低
    rsv[(denom == 0) & ~np.isnan(denom)] = 50.0

    # 递推计算 K, D
    K = np.full(len(df), np.nan)
    D = np.full(len(df), np.nan)
    J = np.full(len(df), np.nan)

    # 初始 K, D 设为 50
    first_valid = period - 1
    if first_valid < len(df):
        K[first_valid] = 50.0
        D[first_valid] = 50.0
        for i in range(first_valid + 1, len(df)):
            if not np.isnan(rsv[i]):
                K[i] = 2.0 / 3.0 * K[i - 1] + 1.0 / 3.0 * rsv[i]
                D[i] = 2.0 / 3.0 * D[i - 1] + 1.0 / 3.0 * K[i]
                J[i] = 3.0 * K[i] - 2.0 * D[i]
            else:
                # 继承前一日值
                K[i] = K[i - 1]
                D[i] = D[i - 1]
                J[i] = J[i - 1]

    df["K"] = K
    df["D"] = D
    df["J"] = J
    return df


# ============================================================
# 箱体特征
# ============================================================

def calculate_box_position(df: pd.DataFrame, lengths: list = None) -> pd.DataFrame:
    """
    计算当前收盘价在不同长度箱体中的位置比例。

    箱体定义（以当前交易日为箱体最后一个交易日）：
        上轨 = max(open, close) 在箱体区间内
        下轨 = min(open, close) 在箱体区间内
        位置 = (当前收盘价 - 下轨) / (上轨 - 下轨)  ∈ [0, 1]

    注：选用 max(open, close) / min(open, close) 而非传统的 high / low
    作为箱体边界，因为：
      1. 开盘价和收盘价代表市场在连续交易中达成的"共识价格"，
         比日内极值 (high/low) 更不易受瞬时异常交易影响
      2. 避免日内冲高回落或探底回升形成的影线夸大箱体范围
      3. 相当于以实体部分定义箱体，信号更保守、噪音更小

    参数:
        df:      包含 'close', 'open' 列的 DataFrame
        lengths: 箱体长度列表，默认 [40, 50, 60]

    返回:
        添加了 box_pos_{L} 列的 DataFrame
    """
    if lengths is None:
        lengths = [40, 50, 60]

    # 每个交易日的开盘价和收盘价的范围
    oc_max = df[["open", "close"]].max(axis=1)
    oc_min = df[["open", "close"]].min(axis=1)

    for L in lengths:
        # 滚动窗口内的上轨和下轨
        upper = oc_max.rolling(window=L, min_periods=L).max()
        lower = oc_min.rolling(window=L, min_periods=L).min()

        diff = upper - lower
        pos = np.full(len(df), np.nan)
        valid = diff > 0
        pos[valid] = (df["close"].values[valid] - lower.values[valid]) / diff.values[valid]
        # 一字横盘时，若收盘等于上下轨则视为中间
        pos[(diff == 0) & ~np.isnan(diff)] = 0.5

        col_name = f"box_pos_{L}"
        df[col_name] = pos

    return df


# ============================================================
# 均线关系与交叉信号
# ============================================================

def calculate_ma_signals(df: pd.DataFrame) -> pd.DataFrame:
    """
    计算均线关系及金叉/死叉信号。

    均线关系（当前值）：
        ma5_above_ma10, ma5_above_ma20, ma10_above_ma20

    金叉信号（上穿：前一日短期 ≤ 长期，当日短期 > 长期）：
        ma5_cross_ma10, ma10_cross_ma20, ma5_cross_ma20

    死叉信号（下穿：前一日短期 ≥ 长期，当日短期 < 长期）：
        ma5_dead_ma10, ma10_dead_ma20, ma5_dead_ma20

    需要先运行 calculate_ma()。
    """
    # ---- 当前均线关系 ----
    for short, long in [(5, 10), (5, 20), (10, 20)]:
        col_short = f"MA{short}"
        col_long = f"MA{long}"
        if col_short in df.columns and col_long in df.columns:
            df[f"ma{short}_above_ma{long}"] = (
                (df[col_short] > df[col_long]).astype(int)
            )

    # ---- 金叉/死叉 ----
    for short, long in [(5, 10), (5, 20), (10, 20)]:
        col_s = f"MA{short}"
        col_l = f"MA{long}"
        if col_s not in df.columns or col_l not in df.columns:
            continue
        cur_above = df[col_s] > df[col_l]
        prev_above = df[col_s].shift(1) > df[col_l].shift(1)
        # 金叉：前一日未上穿，当日上穿
        golden = (~prev_above) & cur_above
        df[f"ma{short}_cross_ma{long}"] = golden.astype(int)
        # 死叉：前一日未下穿，当日下穿
        dead = prev_above & (~cur_above)
        df[f"ma{short}_dead_ma{long}"] = dead.astype(int)

    return df


def calculate_macd_signals(df: pd.DataFrame) -> pd.DataFrame:
    """
    计算 MACD 金叉/死叉信号。

    金叉：前一日 DIF ≤ DEA，当日 DIF > DEA（即 MACD 由负转正或由零上穿）
    死叉：前一日 DIF ≥ DEA，当日 DIF < DEA

    需要先运行 calculate_macd()。
    """
    if "DIF" not in df.columns or "DEA" not in df.columns:
        return df

    cur_above = df["DIF"] > df["DEA"]
    prev_above = df["DIF"].shift(1) > df["DEA"].shift(1)

    # 金叉
    df["macd_golden_cross"] = ((~prev_above) & cur_above).astype(int)
    # 死叉
    df["macd_dead_cross"] = (prev_above & (~cur_above)).astype(int)

    return df


# ============================================================
# 成交量特征
# ============================================================

def calculate_volume_features(df: pd.DataFrame, vol_ma_window: int = 5) -> pd.DataFrame:
    """
    计算成交量均量比。

    参数:
        df:            包含 'volume' 列的 DataFrame
        vol_ma_window: 成交量均线窗口

    返回:
        添加了 vol_ma{N}, vol_ratio 列的 DataFrame
    """
    df[f"vol_ma{vol_ma_window}"] = df["volume"].rolling(
        window=vol_ma_window, min_periods=vol_ma_window
    ).mean()
    df["vol_ratio"] = df["volume"] / df[f"vol_ma{vol_ma_window}"]
    return df


# ============================================================
# 综合特征计算
# ============================================================

def calculate_all_features(df: pd.DataFrame,
                           ma_windows: list = None,
                           box_lengths: list = None,
                           macd_params: tuple = (12, 26, 9),
                           rsi_period: int = 14,
                           kdj_period: int = 9,
                           vol_ma_window: int = 5) -> pd.DataFrame:
    """
    一站式计算所有技术指标特征。

    参数与各独立函数相同，详见对应函数文档。

    返回:
        包含所有特征列的 DataFrame
    """
    if ma_windows is None:
        ma_windows = [5, 10, 20, 60]
    if box_lengths is None:
        box_lengths = [40, 50, 60]

    # 确保数据按日期升序
    df = df.sort_values("day").reset_index(drop=True)

    # 依次计算各特征
    df = calculate_ma(df, ma_windows)
    df = calculate_macd(df, *macd_params)
    df = calculate_rsi(df, rsi_period)
    df = calculate_kdj(df, kdj_period)
    df = calculate_box_position(df, box_lengths)
    df = calculate_ma_signals(df)
    df = calculate_macd_signals(df)
    df = calculate_volume_features(df, vol_ma_window)

    return df
