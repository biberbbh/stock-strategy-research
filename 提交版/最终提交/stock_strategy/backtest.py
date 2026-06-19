# -*- coding: utf-8 -*-
"""
回测引擎模块
对交易策略进行历史数据回测，计算收益率及统计指标。

核心逻辑：
  信号日 i → 买入日 i+1 (收盘价买入)
            → 卖出日 i+1+hold_days (收盘价卖出)
            → 毛收益率 = (卖出价 - 买入价) / 买入价 × 100%
            → 净收益率 = 毛收益率 - 交易成本

交易成本模型：
  - 佣金：买入 + 卖出双向，默认万分之三
  - 印花税：仅卖出时收取，默认千分之0.5
  - 滑点：买卖各扣除 1 bp (0.01%)
  - 最低佣金：每笔最低 5 元

风险调整指标：
  - 夏普比率 (Sharpe Ratio)
  - 最大回撤 (Maximum Drawdown)
  - 卡玛比率 (Calmar Ratio)
  - 盈亏比 (Profit Factor)

验证方法：
  - 时间序列划分 (前70%训练 + 后30%测试)
  - 滚动窗口验证 (Walk-Forward Validation)
"""

import pandas as pd
import numpy as np
from typing import Dict, List, Tuple, Optional
from collections import defaultdict


# ============================================================
# 交易成本计算
# ============================================================

def calculate_transaction_cost(buy_price: float, sell_price: float,
                               shares_per_trade: int = 100,
                               commission_rate: float = None,
                               stamp_tax_rate: float = None,
                               slippage_bps: float = None,
                               min_commission: float = None) -> float:
    """
    计算单笔交易的往返成本（以买入价的百分比表示）。

    参数:
        buy_price:        每股买入价 (元)
        sell_price:       每股卖出价 (元)
        shares_per_trade: 每笔交易股数 (默认 100 股 = 1 手，A 股最小交易单位)
        commission_rate:  佣金费率 (默认取自 config)
        stamp_tax_rate:   印花税率 (默认取自 config)
        slippage_bps:     滑点基点 (默认取自 config)
        min_commission:   最低佣金 (元/笔, 默认取自 config)

    返回:
        成本占买入价格的百分比，例如 0.15 表示 0.15%
    """
    if commission_rate is None:
        from config import COMMISSION_RATE
        commission_rate = COMMISSION_RATE
    if stamp_tax_rate is None:
        from config import STAMP_TAX_RATE
        stamp_tax_rate = STAMP_TAX_RATE
    if slippage_bps is None:
        from config import SLIPPAGE_BPS
        slippage_bps = SLIPPAGE_BPS
    if min_commission is None:
        from config import MIN_COMMISSION
        min_commission = MIN_COMMISSION

    buy_amount = buy_price * shares_per_trade  # 买入成交金额 (元)
    sell_amount = sell_price * shares_per_trade  # 卖出成交金额 (元)

    # 滑点成本 (买卖各 1bp 冲击)
    slippage_cost = (buy_amount + sell_amount) * (slippage_bps / 10000.0)

    # 佣金 = max(成交金额 × 费率, 最低佣金)，买卖双向
    buy_commission = max(buy_amount * commission_rate, min_commission)
    sell_commission = max(sell_amount * commission_rate, min_commission)

    # 印花税 (仅卖出)
    stamp_tax = sell_amount * stamp_tax_rate

    # 总成本 (元)
    total_cost_yuan = slippage_cost + buy_commission + sell_commission + stamp_tax

    # 转换为买入价的百分比
    cost_pct = (total_cost_yuan / buy_amount) * 100.0

    return round(cost_pct, 6)


# ============================================================
# 单股票回测
# ============================================================

def backtest_single_stock(df: pd.DataFrame, signal_col: str,
                          hold_days: int,
                          include_costs: bool = True) -> pd.DataFrame:
    """
    对单只股票按信号列进行回测。

    参数:
        df:            包含 'close' 列和信号列的 DataFrame（按日期升序）
        signal_col:    信号列名，值为 1 表示买入信号
        hold_days:     持有交易日数
        include_costs: 是否扣除交易成本

    返回:
        DataFrame，记录每次交易的详情：
            stock_code, signal_idx, buy_idx, sell_idx,
            buy_date, sell_date, buy_price, sell_price,
            gross_return_pct, cost_pct, net_return_pct
    """
    if signal_col not in df.columns:
        return pd.DataFrame()

    # 确保按日期排序
    df = df.sort_values("day").reset_index(drop=True)

    n = len(df)
    trades = []

    # 找出所有信号日索引
    signal_indices = df.index[df[signal_col] == 1].tolist()

    for sig_idx in signal_indices:
        buy_idx = sig_idx + 1               # 下一个交易日买入
        sell_idx = buy_idx + hold_days       # 持有期满卖出

        # 检查边界
        if buy_idx >= n or sell_idx >= n:
            continue

        buy_price = df.loc[buy_idx, "close"]
        sell_price = df.loc[sell_idx, "close"]

        # 价格有效性检查
        if pd.isna(buy_price) or pd.isna(sell_price):
            continue
        if buy_price <= 0 or sell_price <= 0:
            continue

        # 毛收益率
        gross_ret_pct = (sell_price - buy_price) / buy_price * 100.0

        # 交易成本
        if include_costs:
            cost_pct = calculate_transaction_cost(buy_price, sell_price)
            net_ret_pct = gross_ret_pct - cost_pct
        else:
            cost_pct = 0.0
            net_ret_pct = gross_ret_pct

        trades.append({
            "stock_code": df["stock_code"].iloc[0] if "stock_code" in df.columns else "unknown",
            "signal_idx": sig_idx,
            "buy_idx": buy_idx,
            "sell_idx": sell_idx,
            "buy_date": df.loc[buy_idx, "day"],
            "sell_date": df.loc[sell_idx, "day"],
            "buy_price": buy_price,
            "sell_price": sell_price,
            "gross_return_pct": round(gross_ret_pct, 4),
            "cost_pct": round(cost_pct, 4),
            "net_return_pct": round(net_ret_pct, 4),
        })

    return pd.DataFrame(trades)


# ============================================================
# 多股票批量回测
# ============================================================

def backtest_all_stocks(stock_data: Dict[str, pd.DataFrame],
                        signal_col: str,
                        hold_days: int,
                        include_costs: bool = True,
                        verbose: bool = False) -> pd.DataFrame:
    """
    对所有股票进行批量回测，汇总所有交易记录。

    参数:
        stock_data:    {股票代码: DataFrame}
        signal_col:    信号列名
        hold_days:     持有交易日数
        include_costs: 是否扣除交易成本
        verbose:       是否打印进度

    返回:
        DataFrame，包含所有股票的所有交易记录
    """
    all_trades = []
    total = len(stock_data)

    for i, (code, df) in enumerate(stock_data.items()):
        trades = backtest_single_stock(df, signal_col, hold_days,
                                       include_costs=include_costs)
        if not trades.empty:
            all_trades.append(trades)

        if verbose and (i + 1) % 500 == 0:
            print(f"  回测进度: {i + 1}/{total}")

    if not all_trades:
        print(f"  [警告] {signal_col} 持有 {hold_days} 天: 无任何交易信号")
        return pd.DataFrame()

    result = pd.concat(all_trades, ignore_index=True)
    if verbose:
        print(f"  {signal_col} 持有 {hold_days} 天: 共 {len(result)} 笔交易")

    return result


# ============================================================
# 基本统计指标计算
# ============================================================

def calculate_metrics(trades_df: pd.DataFrame,
                      return_col: str = "gross_return_pct") -> dict:
    """
    根据交易记录 DataFrame 计算回测指标。

    参数:
        trades_df:  回测返回的 DataFrame
        return_col: 收益率列名 (默认 "gross_return_pct", 也可用 "net_return_pct")

    返回:
        dict: 基本回测指标
    """
    if trades_df.empty:
        return {
            "trade_count": 0,
            "win_rate_gt0": np.nan,
            "win_rate_gt1": np.nan,
            "avg_return": np.nan,
            "max_return": np.nan,
            "max_loss": np.nan,
            "median_return": np.nan,
            "std_return": np.nan,
        }

    returns = trades_df[return_col].values
    n = len(returns)

    return {
        "trade_count": n,
        "win_rate_gt0": round(np.mean(returns > 0) * 100, 2),
        "win_rate_gt1": round(np.mean(returns > 1.0) * 100, 2),
        "avg_return": round(np.mean(returns), 4),
        "max_return": round(np.max(returns), 4),
        "max_loss": round(np.min(returns), 4),
        "median_return": round(np.median(returns), 4),
        "std_return": round(np.std(returns), 4),
    }


# ============================================================
# 风险调整指标
# ============================================================

def _build_daily_return_series(trades_df: pd.DataFrame,
                               return_col: str = "net_return_pct") -> pd.Series:
    """
    从交易记录构建日历日收益率序列。

    方法：将每笔交易的收益率归入其卖出日期（P&L realization date）。
    日收益率 = 当日所有平仓交易收益率的算术平均（等价于等权重分配于当日
    平仓的所有头寸）。

    不同于除以总交易数 (N) 的做法（会将日收益率稀释至零），取均值保证了
    无论总交易数多少，日收益率都在合理范围内，从而得到有意义的夏普比率和
    最大回撤。

    参数:
        trades_df: 回测交易记录 (需含 sell_date 列)
        return_col: 收益率列名

    返回:
        pd.Series: 以日历日为索引的日收益率序列 (小数)
    """
    if trades_df.empty or "sell_date" not in trades_df.columns:
        return pd.Series(dtype=float)

    # 确保 sell_date 为 datetime
    sell_dates = pd.to_datetime(trades_df["sell_date"])

    # 按卖出日聚合：日收益率 = 当日所有平仓交易收益率的均值
    # 这等价于"每笔交易等权重，当日平均赚/亏多少"
    daily_return_pct = pd.Series(
        trades_df[return_col].values, index=sell_dates
    ).groupby(level=0).mean()

    # 转换为小数
    daily_return = daily_return_pct / 100.0

    # 填充日历日范围 (仅交易日，使用 'B' 商业日频率)
    if len(daily_return) > 0:
        date_range = pd.date_range(
            daily_return.index.min(),
            daily_return.index.max(),
            freq="B"
        )
        daily_return = daily_return.reindex(date_range, fill_value=0.0)

    return daily_return


def calculate_risk_metrics(trades_df: pd.DataFrame,
                           return_col: str = "net_return_pct",
                           hold_days: int = None,
                           risk_free_rate: float = None) -> dict:
    """
    计算风险调整后的绩效指标。

    夏普比率：基于单笔交易收益率统计量，按持有天数年化。
        annual_return = mean(returns) / hold_days * 252
        annual_std    = std(returns) * sqrt(252 / hold_days)
        sharpe        = (annual_return - rf) / annual_std

    最大回撤：将交易按卖出日排序，构建累积净值曲线，计算峰值到谷底
    的最大跌幅。

    参数:
        trades_df:     回测交易记录 (需含 sell_date 列)
        return_col:    收益率列名 (默认 "net_return_pct")
        hold_days:     持有天数，用于年化 (若trades_df不含该列则需传入)
        risk_free_rate: 年化无风险利率 (默认取自 config)

    返回:
        dict: {
            "sharpe_ratio", "max_drawdown", "calmar_ratio",
            "profit_factor", "avg_win", "avg_loss", "win_loss_ratio",
        }
    """
    if risk_free_rate is None:
        from config import RISK_FREE_RATE
        risk_free_rate = RISK_FREE_RATE

    if trades_df.empty:
        return {
            "sharpe_ratio": np.nan,
            "max_drawdown": np.nan,
            "calmar_ratio": np.nan,
            "profit_factor": np.nan,
            "avg_win": np.nan,
            "avg_loss": np.nan,
            "win_loss_ratio": np.nan,
        }

    returns = trades_df[return_col].values  # 百分比收益率
    n_returns = len(returns)

    TRADING_DAYS_PER_YEAR = 252

    # 确定持有天数（用于年化）
    if hold_days is None:
        if "hold_days" in trades_df.columns:
            hold_days = int(trades_df["hold_days"].iloc[0])
        else:
            # 从买入日和卖出日推算
            if "buy_idx" in trades_df.columns and "sell_idx" in trades_df.columns:
                hold_days = int((trades_df["sell_idx"] - trades_df["buy_idx"]).mean())
            else:
                hold_days = 20  # 默认

    # --- 夏普比率 (交易级别，年化) ---
    if n_returns > 1:
        # 年化收益率
        mean_return_pct = np.mean(returns)
        annual_return = mean_return_pct / hold_days * TRADING_DAYS_PER_YEAR  # % per year
        # 年化波动率: std 随 sqrt(时间) 缩放
        annual_std = np.std(returns, ddof=1) * np.sqrt(TRADING_DAYS_PER_YEAR / hold_days)
        if annual_std > 0:
            sharpe_ratio = (annual_return / 100.0 - risk_free_rate) / (annual_std / 100.0)
        else:
            sharpe_ratio = np.nan
    else:
        sharpe_ratio = np.nan

    # --- 最大回撤 (基于按日聚合的净值曲线，避免逐笔溢出) ---
    if n_returns > 1 and "sell_date" in trades_df.columns:
        # 使用 _build_daily_return_series 将交易聚合为日收益率，
        # 日数 ≈ 323 天，避免 73,915 笔逐笔累积导致的浮点溢出
        daily_ret = _build_daily_return_series(trades_df, return_col)
        if len(daily_ret) > 1:
            nav = (1.0 + daily_ret).cumprod()
            running_max = nav.cummax()
            max_drawdown = ((nav - running_max) / running_max).min() * 100.0
        else:
            max_drawdown = np.nan
    else:
        max_drawdown = np.nan

    # --- 卡玛比率 ---
    if max_drawdown is not None and not np.isnan(max_drawdown) and max_drawdown < 0:
        annual_return_pct = np.mean(returns) / hold_days * TRADING_DAYS_PER_YEAR
        calmar_ratio = (annual_return_pct / 100.0) / abs(max_drawdown / 100.0)
    else:
        calmar_ratio = np.nan

    # --- 盈亏比 (Profit Factor) ---
    wins = returns[returns > 0]
    losses = returns[returns < 0]
    total_profit = wins.sum() if len(wins) > 0 else 0
    total_loss = abs(losses.sum()) if len(losses) > 0 else 0
    profit_factor = total_profit / total_loss if total_loss > 0 else np.inf

    # --- 平均盈亏 ---
    avg_win = np.mean(wins) if len(wins) > 0 else np.nan
    avg_loss = np.mean(losses) if len(losses) > 0 else np.nan

    # --- 盈亏次数比 ---
    win_loss_ratio = len(wins) / len(losses) if len(losses) > 0 else np.inf

    return {
        "sharpe_ratio": round(sharpe_ratio, 4),
        "max_drawdown": round(max_drawdown, 2),
        "calmar_ratio": round(calmar_ratio, 4),
        "profit_factor": round(profit_factor, 4),
        "avg_win": round(avg_win, 4),
        "avg_loss": round(avg_loss, 4),
        "win_loss_ratio": round(win_loss_ratio, 4),
    }


# ============================================================
# 统计显著性检验
# ============================================================

# scipy 为可选依赖，不可用时使用正态近似
try:
    from scipy import stats as scipy_stats
    _HAS_SCIPY = True
except ImportError:
    scipy_stats = None
    _HAS_SCIPY = False


def test_win_rate_significance(trades_df: pd.DataFrame,
                               return_col: str = "net_return_pct",
                               alpha: float = 0.05) -> dict:
    """
    检验胜率是否显著高于随机（50%）。

    使用二项检验和 Bootstrap 置信区间。
    若 scipy 不可用则仅计算 Bootstrap CI。

    参数:
        trades_df: 交易记录
        return_col: 收益率列名
        alpha:     显著性水平

    返回:
        dict: {
            "p_value_binomial": 二项检验 p 值,
            "ci_95_lower": 95% CI 下界,
            "ci_95_upper": 95% CI 上界,
            "significant": 是否显著,
        }
    """
    if trades_df.empty:
        return {
            "p_value_binomial": np.nan,
            "ci_95_lower": np.nan,
            "ci_95_upper": np.nan,
            "significant": False,
        }

    returns = trades_df[return_col].values
    n = len(returns)
    n_wins = int(np.sum(returns > 0))

    # --- 二项检验：H0: 胜率 = 0.5 ---
    if n > 0 and _HAS_SCIPY:
        p_binomial = scipy_stats.binomtest(n_wins, n, p=0.5, alternative="greater").pvalue
    elif n > 0:
        # 无 scipy 时用正态近似
        import math
        p_hat = n_wins / n
        se = math.sqrt(0.5 * 0.5 / n)
        z = (p_hat - 0.5) / se if se > 0 else 0
        # 单侧标准正态 CDF 近似
        p_binomial = round(0.5 * math.erfc(z / math.sqrt(2)), 6)
    else:
        p_binomial = np.nan

    # --- Bootstrap 置信区间 ---
    rng = np.random.RandomState(42)
    n_bootstrap = 10000
    boot_means = []
    for _ in range(n_bootstrap):
        sample = rng.choice(returns, size=n, replace=True)
        boot_means.append(np.mean(sample))
    boot_means = np.sort(boot_means)
    ci_lower = np.percentile(boot_means, 2.5)
    ci_upper = np.percentile(boot_means, 97.5)

    return {
        "p_value_binomial": round(p_binomial, 6),
        "ci_95_lower": round(ci_lower, 4),
        "ci_95_upper": round(ci_upper, 4),
        "significant": p_binomial < alpha,
    }


# ============================================================
# 样本划分
# ============================================================

def split_train_test(stock_data: Dict[str, pd.DataFrame],
                     train_ratio: float = 0.70) -> Tuple[Dict[str, pd.DataFrame],
                                                          Dict[str, pd.DataFrame]]:
    """
    按时间顺序将数据划分为训练集和测试集。

    每只股票按日期排序后，前 train_ratio 比例的数据作为训练集，
    后 (1 - train_ratio) 作为测试集。

    参数:
        stock_data:  原始股票数据字典
        train_ratio: 训练集比例 (默认 0.70)

    返回:
        (train_data, test_data): 两个分割后的数据字典
    """
    if train_ratio is None:
        from config import TRAIN_RATIO
        train_ratio = TRAIN_RATIO

    train_data = {}
    test_data = {}

    for code, df in stock_data.items():
        df = df.sort_values("day").reset_index(drop=True)
        split_idx = int(len(df) * train_ratio)
        if split_idx < 60:  # 确保训练集至少有足够数据计算特征
            train_data[code] = df.copy()
            test_data[code] = pd.DataFrame()
        else:
            train_data[code] = df.iloc[:split_idx].copy()
            test_data[code] = df.iloc[split_idx:].copy()

    return train_data, test_data


# ============================================================
# Walk-Forward 验证
# ============================================================

def walk_forward_validation(stock_data: Dict[str, pd.DataFrame],
                            strategies: Dict[str, tuple] = None,
                            hold_days_list: List[int] = None,
                            window_size: int = None,
                            step_size: int = None,
                            verbose: bool = True) -> pd.DataFrame:
    """
    滚动窗口样本外验证 (Rolling Window Out-of-Sample Testing)。

    将数据按时间划分为多个窗口：
      - 训练窗口: 前 window_size 个交易日
      - 测试窗口: 紧接训练窗口后的 step_size 个交易日，用于样本外验证
    滚动推进，汇总所有样本外结果。

    注意：当前版本使用固定策略参数（来自 config.py），在每个窗口
    不做参数优化。这属于"滚动窗口样本外测试"而非标准 Walk-Forward
    优化（后者需在训练窗内网格搜索最优参数后再应用于测试窗）。

    TODO: 添加 param_grid 参数支持训练窗内参数网格搜索。

    参数:
        stock_data:     股票数据字典
        strategies:     策略字典
        hold_days_list: 持有天数列表
        window_size:    训练窗口长度（交易日）
        step_size:      窗口步长（交易日）
        verbose:        是否打印进度

    返回:
        DataFrame: 所有窗口样本外结果的汇总
    """
    if strategies is None:
        from strategy import get_all_strategies
        strategies = get_all_strategies()
    if hold_days_list is None:
        from config import HOLD_DAYS
        hold_days_list = HOLD_DAYS
    if window_size is None:
        from config import WALK_FORWARD_WINDOW
        window_size = WALK_FORWARD_WINDOW
    if step_size is None:
        from config import WALK_FORWARD_STEP
        step_size = WALK_FORWARD_STEP

    # 确定全局日期范围
    all_dates = set()
    for df in stock_data.values():
        all_dates.update(df["day"].values)
    all_dates = sorted(all_dates)
    global_start = pd.to_datetime(all_dates[0])
    global_end = pd.to_datetime(all_dates[-1])

    total_days = len(all_dates)
    n_windows = max(1, (total_days - window_size) // step_size)

    if verbose:
        print(f"Walk-Forward 验证: {n_windows} 个窗口")
        print(f"  训练窗口: {window_size} 天, 步长: {step_size} 天")

    all_summaries = []

    for w in range(n_windows):
        train_start_idx = w * step_size
        train_end_idx = train_start_idx + window_size
        test_start_idx = train_end_idx
        test_end_idx = min(test_start_idx + step_size, total_days)

        if test_start_idx >= total_days:
            break

        train_start_date = pd.to_datetime(all_dates[train_start_idx])
        train_end_date = pd.to_datetime(all_dates[min(train_end_idx - 1, total_days - 1)])
        test_start_date = pd.to_datetime(all_dates[test_start_idx])
        test_end_date = pd.to_datetime(all_dates[test_end_idx - 1])

        if verbose:
            print(f"\n[窗口 {w + 1}/{n_windows}] "
                  f"训练: {train_start_date.date()} ~ {train_end_date.date()}, "
                  f"测试: {test_start_date.date()} ~ {test_end_date.date()}")

        # 划分训练集和测试集
        train_data = {}
        test_data = {}
        for code, df in stock_data.items():
            df = df.sort_values("day")
            train_mask = (df["day"] >= train_start_date) & (df["day"] <= train_end_date)
            test_mask = (df["day"] >= test_start_date) & (df["day"] <= test_end_date)
            train_df = df[train_mask].copy()
            test_df = df[test_mask].copy()
            if len(train_df) >= 60:  # 需要足够训练数据
                train_data[code] = train_df
            if len(test_df) >= 30:
                test_data[code] = test_df

        if not train_data or not test_data:
            continue

        # 在训练集上计算特征和信号
        from features import calculate_all_features
        from strategy import generate_all_signals
        from config import MA_WINDOWS, BOX_LENGTHS

        for code in train_data:
            train_data[code] = calculate_all_features(train_data[code],
                ma_windows=MA_WINDOWS, box_lengths=BOX_LENGTHS)
            train_data[code] = generate_all_signals(train_data[code], strategies)
        for code in test_data:
            test_data[code] = calculate_all_features(test_data[code],
                ma_windows=MA_WINDOWS, box_lengths=BOX_LENGTHS)
            test_data[code] = generate_all_signals(test_data[code], strategies)

        # 在测试集上回测
        for strategy_key, (_, strategy_name) in strategies.items():
            signal_col = f"signal_{strategy_key}"
            for hold_days in hold_days_list:
                trades = backtest_all_stocks(test_data, signal_col, hold_days,
                                             include_costs=True)
                metrics = calculate_metrics(trades, return_col="net_return_pct")
                risk = calculate_risk_metrics(trades, return_col="net_return_pct", hold_days=hold_days)

                all_summaries.append({
                    "窗口": w + 1,
                    "策略名称": strategy_name,
                    "持有天数": hold_days,
                    "交易次数": metrics["trade_count"],
                    "胜率(>0%)": metrics["win_rate_gt0"],
                    "胜率(>1%)": metrics["win_rate_gt1"],
                    "平均收益率(%)": metrics["avg_return"],
                    "最大收益率(%)": metrics["max_return"],
                    "最大亏损率(%)": metrics["max_loss"],
                    "中位数收益率(%)": metrics["median_return"],
                    "标准差(%)": metrics["std_return"],
                    "夏普比率": risk["sharpe_ratio"],
                    "最大回撤(%)": risk["max_drawdown"],
                    "卡玛比率": risk["calmar_ratio"],
                    "盈亏比": risk["profit_factor"],
                    "平均盈利(%)": risk["avg_win"],
                    "平均亏损(%)": risk["avg_loss"],
                })

    if not all_summaries:
        print("[警告] Walk-Forward 验证未产生任何结果")
        return pd.DataFrame()

    result_df = pd.DataFrame(all_summaries)

    # 按策略+持有天数聚合各窗口结果
    if verbose and not result_df.empty:
        print("\n" + "=" * 60)
        print("Walk-Forward 样本外汇总 (各窗口均值)")
        print("=" * 60)
        grouped = result_df.groupby(["策略名称", "持有天数"]).agg({
            "胜率(>0%)": "mean",
            "平均收益率(%)": "mean",
            "夏普比率": "mean",
            "最大回撤(%)": "mean",
            "交易次数": "sum",
        }).reset_index()
        for _, row in grouped.iterrows():
            print(f"  {row['策略名称']:<14s} hold={int(row['持有天数']):>2d}  "
                  f"胜率={row['胜率(>0%)']:.1f}%  "
                  f"均收益={row['平均收益率(%)']:.2f}%  "
                  f"夏普={row['夏普比率']:.2f}  "
                  f"交易={int(row['交易次数'])}次")

    return result_df


# ============================================================
# 完整回测流程
# ============================================================

def run_full_backtest(stock_data: Dict[str, pd.DataFrame],
                      strategies: Dict[str, tuple] = None,
                      hold_days_list: List[int] = None,
                      include_costs: bool = True,
                      verbose: bool = True) -> pd.DataFrame:
    """
    对全部股票 × 全部策略 × 全部持有周期运行回测，生成汇总表。

    参数:
        stock_data:     {股票代码: DataFrame (含特征和信号列)}
        strategies:     策略字典，默认使用 get_all_strategies()
        hold_days_list: 持有天数列表，默认使用 config.HOLD_DAYS
        include_costs:  是否扣除交易成本（默认 True）
        verbose:        是否打印进度

    返回:
        DataFrame 汇总表，列为:
            策略名称, 持有天数, 交易次数, 胜率(>0), 胜率(>1%),
            平均收益率, 最大收益率, 最大亏损率, 中位数收益率, 标准差,
            夏普比率, 最大回撤(%), 卡玛比率, 盈亏比,
            平均盈利(%), 平均亏损(%)
    """
    from strategy import get_all_strategies
    if strategies is None:
        strategies = get_all_strategies()
    if hold_days_list is None:
        from config import HOLD_DAYS
        hold_days_list = HOLD_DAYS

    summary_rows = []

    # 确保每只股票已有信号列
    if verbose:
        print("检查策略信号...")
    for code, df in stock_data.items():
        from strategy import generate_all_signals
        # 检查是否已有信号列
        has_signals = all(f"signal_{key}" in df.columns for key in strategies)
        if not has_signals:
            generate_all_signals(df, strategies)

    for strategy_key, (_, strategy_name) in strategies.items():
        signal_col = f"signal_{strategy_key}"

        for hold_days in hold_days_list:
            if verbose:
                print(f"回测: {strategy_name} | 持有 {hold_days} 天")

            trades = backtest_all_stocks(stock_data, signal_col, hold_days,
                                         include_costs=include_costs)
            return_col = "net_return_pct" if include_costs else "gross_return_pct"
            metrics = calculate_metrics(trades, return_col=return_col)
            risk = calculate_risk_metrics(trades, return_col=return_col, hold_days=hold_days)
            sig_test = test_win_rate_significance(trades, return_col=return_col)

            summary_rows.append({
                "策略名称": strategy_name,
                "持有天数": hold_days,
                "交易次数": metrics["trade_count"],
                "胜率(>0%)": metrics["win_rate_gt0"],
                "胜率(>1%)": metrics["win_rate_gt1"],
                "平均收益率(%)": metrics["avg_return"],
                "最大收益率(%)": metrics["max_return"],
                "最大亏损率(%)": metrics["max_loss"],
                "中位数收益率(%)": metrics["median_return"],
                "标准差(%)": metrics["std_return"],
                "夏普比率": risk["sharpe_ratio"],
                "最大回撤(%)": risk["max_drawdown"],
                "卡玛比率": risk["calmar_ratio"],
                "盈亏比": risk["profit_factor"],
                "平均盈利(%)": risk["avg_win"],
                "平均亏损(%)": risk["avg_loss"],
                "胜率p值": sig_test["p_value_binomial"],
                "收益CI下界": sig_test["ci_95_lower"],
                "收益CI上界": sig_test["ci_95_upper"],
            })

    summary_df = pd.DataFrame(summary_rows)
    return summary_df
