# 股票特征建模与买入时机研究

> 课程实验项目 — 量化交易策略研究与回测系统 v2.0

## 项目简介

本项目对 A 股市场 5,000+ 只股票的日线交易数据进行技术指标特征建模，设计 4 个量化买入策略，并通过历史回测验证策略有效性。v2.0 新增交易成本建模、风险调整指标（夏普比率/最大回撤/盈亏比）、统计显著性检验和 Walk-Forward 样本外验证。

## 文件结构

```
├── stock_strategy/           # 代码模块
│   ├── config.py             # 统一参数配置（含交易成本、验证参数）
│   ├── data_loader.py        # 数据读取与预处理
│   ├── features.py           # 特征计算（MA/MACD/RSI/KDJ/箱体/交叉信号）
│   ├── strategy.py           # 4 个买入策略信号生成
│   ├── backtest.py           # 回测引擎 + 风险指标 + Walk-Forward 验证
│   ├── analysis.py           # 结果分析与可视化（7 种图表 + 统计检验）
│   └── main.py               # 主程序入口
│
├── results/                  # 实验结果
│   ├── backtest_summary.csv          # 回测汇总表（含风险指标和统计检验）
│   ├── backtest_results.xlsx         # 回测结果（Excel，含多 Sheet）
│   ├── hold_period_comparison.png    # 持有周期对比图（4 子图）
│   ├── heatmap_*.png                 # 热力图（胜率/收益/夏普比率）
│   ├── significance_forest.png       # 显著性森林图（CI + p 值）
│   ├── sensitivity_持有天数.png       # 参数敏感性分析
│   ├── cumret_*.png                  # 累积收益曲线（修正版）
│   └── 实验报告.md                    # 完整实验报告（含数学公式）
│
├── run.py                    # 顶层启动脚本（支持 CLI 参数）
└── requirements.txt          # Python 依赖清单
```

## 环境要求

- Python 3.8 及以上
- 依赖库：pandas, numpy, matplotlib, openpyxl, scipy

## 快速开始

### 1. 准备数据

将股票日线 CSV 数据放在程序可访问的目录中（如 `day/`），每个 CSV 文件对应一只股票。

CSV 文件需包含以下字段：
`day, code, open, close, high, low, volume, amount, zf, zdf, zde, hsl`

### 2. 安装依赖

```bash
pip install -r requirements.txt
```

### 3. 运行

**方式 A：使用顶层脚本**
```bash
# 全部股票回测（含交易成本 + 风险指标 + 统计检验）
python run.py --data ./day

# 只测 100 只（快速验证）
python run.py --data ./day --max-stocks 100

# Walk-Forward 样本外验证
python run.py --data ./day --max-stocks 500 --walk-forward

# 训练/测试集划分验证
python run.py --data ./day --train-test-split

# 不计交易成本（调试用）
python run.py --data ./day --no-costs
```

**方式 B：直接运行主模块**
```bash
cd stock_strategy
python main.py
```

**方式 C：通过环境变量指定数据路径**
```bash
# Windows PowerShell
$env:STOCK_DATA_DIR = "D:\stock_data\day"
python run.py
```

### 4. 查看结果

结果输出在 `results/` 目录：
- `backtest_summary.csv` — 回测数据表（含夏普比率、最大回撤、盈亏比、p 值）
- `backtest_results.xlsx` — Excel 报告
- `*.png` — 可视化图表（含新增的显著性森林图、参数敏感性图）
- `实验报告.md` — 完整实验报告（v2.0 含数学公式）

## 自定义策略

1. 在 `stock_strategy/strategy.py` 中添加新策略函数
2. 在 `get_all_strategies()` 中注册
3. 在 `stock_strategy/config.py` 中调整参数和交易成本
4. 重新运行

## 主要实验结果

对 5,476 只 A 股（2024.11.11 ~ 2026.03.19）回测结论（含交易成本）：

| 策略 | 60天胜率 | 60天净收益 | 夏普比率 | 盈亏比 | 最大回撤 | 特点 |
|------|---------|-----------|---------|--------|---------|------|
| **箱体底部反弹** | **66.0%** | **11.25%** | **0.873** | **4.96** | -37.1% | 全部指标最优 ⭐ |
| 多指标共振 | 58.1% | 8.62% | 0.640 | 3.21 | -35.2% | 信号最少但质量高 |
| 连跌反弹 | 56.4% | 8.29% | 0.599 | 2.95 | -34.6% | 信号最多（73,915次） |
| 均线金叉+量能 | 55.3% | 7.48% | 0.528 | 2.76 | -36.9% | 经典趋势策略 |

**统计显著性**：所有策略在 60 天持有期均显著优于随机（二项检验 $p < 0.001$）。

## 许可证

本代码仅用于教学实验目的。
