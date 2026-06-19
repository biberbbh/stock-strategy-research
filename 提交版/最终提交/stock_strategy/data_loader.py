# -*- coding: utf-8 -*-
"""
数据读取与预处理模块
- 遍历 data_dir 下所有 CSV 文件
- 读取单只股票数据，统一字段格式
- 缺失值处理、日期排序
"""

import os
import glob
import pandas as pd
import numpy as np
from typing import Dict, Tuple, Optional


def load_single_stock(filepath: str) -> Optional[pd.DataFrame]:
    """
    读取单只股票的 CSV 文件，返回清洗后的 DataFrame。

    参数:
        filepath: CSV 文件路径

    返回:
        DataFrame，包含标准化后的日线数据；若读取失败返回 None

    数据字段:
        day, code, open, close, high, low, volume, amount, zf, zdf, zde, hsl, market
    """
    try:
        df = pd.read_csv(filepath, encoding="utf-8")
    except (UnicodeDecodeError, FileNotFoundError) as e:
        print(f"  [警告] 读取失败: {filepath} — {e}")
        return None

    # 空文件检查
    if df.empty or len(df) == 0:
        return None

    # ---- 字段标准化 ----
    # 确保关键字段存在
    required_cols = ["day", "close", "open", "high", "low", "volume"]
    missing = [c for c in required_cols if c not in df.columns]
    if missing:
        print(f"  [警告] {filepath} 缺少字段: {missing}")
        return None

    # 检查 hsl（换手率）字段
    if "hsl" not in df.columns:
        print(f"  [警告] 缺少 hsl 字段: {filepath}")
        return None

    # ---- 日期处理 ----
    df["day"] = pd.to_datetime(df["day"], errors="coerce")
    df.dropna(subset=["day"], inplace=True)
    df.sort_values("day", inplace=True)
    df.reset_index(drop=True, inplace=True)

    # ---- 数值列处理 ----
    numeric_cols = ["open", "close", "high", "low", "volume", "amount",
                    "zf", "zdf", "zde", "hsl"]
    for col in numeric_cols:
        if col in df.columns:
            # 强制转换为数值类型，非数值设为 NaN
            df[col] = pd.to_numeric(df[col], errors="coerce")

    # ---- 缺失值处理 ----
    # 涨跌幅类字段：首个交易日 NaN 正常（无前一日比较），保留 NaN
    # 价格类字段：如果缺失则前向填充
    price_cols = ["open", "close", "high", "low"]
    for col in price_cols:
        if col in df.columns:
            # 仅填充内部的 NaN，首行 NaN 若存在则用下一有效值回填
            df[col] = df[col].ffill().bfill()

    # 成交量/成交额：前向填充
    df["volume"] = df["volume"].ffill().bfill()
    if "amount" in df.columns:
        df["amount"] = df["amount"].ffill().bfill()

    # ---- 涨跌幅重算验证 ----
    # 若原始 zdf 缺失过多，则根据收盘价重新计算
    if "zdf" in df.columns:
        nan_ratio = df["zdf"].isna().mean()
        if nan_ratio > 0.5:
            df["zdf"] = (df["close"].pct_change() * 100).round(2)
    else:
        df["zdf"] = (df["close"].pct_change() * 100).round(2)

    # ---- 振幅重算 ----
    if "zf" in df.columns:
        nan_ratio = df["zf"].isna().mean()
        if nan_ratio > 0.3:
            prev_close = df["close"].shift(1)
            df["zf"] = ((df["high"] - df["low"]) / prev_close * 100).round(2)
    else:
        prev_close = df["close"].shift(1)
        df["zf"] = ((df["high"] - df["low"]) / prev_close * 100).round(2)

    # ---- 提取股票代码 ----
    if "code" in df.columns:
        # 统一格式：取原始字符串，去除可能的空白
        stock_code = str(df["code"].iloc[0]).strip()
    else:
        # 从文件名推断
        basename = os.path.splitext(os.path.basename(filepath))[0]
        stock_code = basename

    df["stock_code"] = stock_code

    # ---- 检查最低数据量 ----
    if len(df) < 30:
        print(f"  [跳过] {stock_code}: 数据量不足 ({len(df)} 行)")
        return None

    return df


def load_all_stocks(data_dir: str, max_stocks: int = None) -> Dict[str, pd.DataFrame]:
    """
    批量加载 data_dir 下所有股票 CSV 文件。

    参数:
        data_dir: CSV 文件所在目录
        max_stocks: 最大加载数量，None 表示全部

    返回:
        dict: {股票代码: DataFrame}
    """
    if not os.path.isdir(data_dir):
        raise FileNotFoundError(f"数据目录不存在: {data_dir}")

    csv_files = sorted(glob.glob(os.path.join(data_dir, "*.csv")))
    if not csv_files:
        raise FileNotFoundError(f"在 {data_dir} 中未找到 CSV 文件")

    print(f"找到 {len(csv_files)} 个 CSV 文件")

    if max_stocks:
        csv_files = csv_files[:max_stocks]
        print(f"限制加载前 {max_stocks} 只股票")

    stock_data: Dict[str, pd.DataFrame] = {}
    skip_count = 0
    fail_count = 0

    for i, filepath in enumerate(csv_files):
        df = load_single_stock(filepath)
        if df is None or df.empty:
            fail_count += 1
            continue

        code = df["stock_code"].iloc[0]
        if len(df) < 30:
            skip_count += 1
            continue

        stock_data[code] = df

        # 进度显示
        if (i + 1) % 500 == 0:
            print(f"  已处理 {i + 1}/{len(csv_files)} 个文件...")

    print(f"加载完成: 成功 {len(stock_data)} 只, 数据不足/跳过 {skip_count} 只, "
          f"失败 {fail_count} 只")
    return stock_data


def get_data_summary(stock_data: Dict[str, pd.DataFrame]) -> pd.DataFrame:
    """
    生成数据概览，包含每只股票的基本信息。

    返回:
        DataFrame: 列包含 stock_code, rows, start_date, end_date, has_hsl, ...
    """
    records = []
    for code, df in stock_data.items():
        records.append({
            "stock_code": code,
            "rows": len(df),
            "start_date": df["day"].min(),
            "end_date": df["day"].max(),
            "has_hsl": "hsl" in df.columns,
            "avg_volume": df["volume"].mean(),
            "avg_zdf": df["zdf"].mean() if "zdf" in df.columns else np.nan,
        })
    return pd.DataFrame(records)
