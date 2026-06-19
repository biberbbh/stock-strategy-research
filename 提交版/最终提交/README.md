# 股票特征建模与买入时机研究

> **课程**：大学数学实验 · 综合实验项目 | **日期**：2026-06  
> **学生**：毕博昊 (2025080901001) | **指导教师**：李佑铭

---

## 项目概述

基于 A 股市场 200 只股票日线数据（2024.11—2026.03），提取 MA/MACD/RSI/KDJ/箱体等 20+ 维技术特征，设计四个差异化买入策略，在 8 个持有周期上完成全样本回测（含佣金、印花税、滑点），并进行统计显著性检验。

**核心结论**：箱体底部反弹策略最优（60 天胜率 70.2%，净收益 9.19%，夏普 7.38），"低买"逻辑显著优于"追涨"。

---

## 目录结构

```
├── 实验报告.pdf          # 编译好的实验报告（22页）
├── 实验报告.tex          # LaTeX 源文件
├── run.py                # Python 入口脚本（全量回测）
├── requirements.txt      # Python 依赖
├── 模板2.docx            # 课程实验报告模板
│
├── charts/               # 图表（13张）
│   ├── flowchart_s1~s4.png      # 四个策略决策流程图
│   ├── win_rate_line.png        # 胜率随持有天数变化折线图
│   ├── return_line.png          # 净收益率随持有天数变化折线图
│   ├── line_comparison.png      # 四维综合对比图
│   ├── pipeline_overview.png    # 研究流水线总览
│   ├── hold_period_comparison.png       # 持有周期对比图
│   ├── heatmap_Win_Rate_gt0pct.png     # 胜率热力图
│   ├── heatmap_Avg_Return_pct.png      # 收益率热力图
│   ├── sensitivity_hold_days.png       # 参数敏感性分析图
│   └── significance_forest.png         # 显著性森林图
│
├── matlab/               # MATLAB 代码（15个函数文件）
│   ├── main.m            # 全量回测入口
│   ├── config.m          # 统一参数配置
│   ├── calculate_all_features.m  # 特征计算
│   ├── get_all_strategies.m      # 策略注册
│   ├── run_full_backtest.m       # 回测引擎
│   ├── run_all_visualizations.m  # 可视化
│   └── ...
│
├── stock_strategy/       # Python 策略引擎
│   ├── config.py         # 参数配置
│   ├── features.py       # 特征计算
│   ├── strategy.py       # 策略定义
│   ├── backtest.py       # 回测引擎
│   └── ...
│
└── results/              # 回测结果
    ├── backtest_results.xlsx    # 回测结果（多Sheet）
    └── backtest_summary.csv     # 回测汇总（32行×19列）
```

---

## 编译 LaTeX 报告

```bash
xelatex 实验报告.tex
xelatex 实验报告.tex   # 第二遍生成目录
```

---

## 运行回测

### MATLAB
```matlab
cd matlab/
test_run()    # 20只快速验证
test_200()    # 200只完整回测
main()        # 全量回测
```

### Python
```bash
pip install -r requirements.txt
python run.py
```

---

## 四种策略

| # | 策略 | 类型 | 60天胜率 | 60天净收益 | 夏普比率 |
|---|------|------|:---:|:---:|:---:|
| 1 | 均线金叉+量能确认 | 追涨型 | 56.4% | 5.60% | 4.24 |
| 2 | **箱体底部反弹** ★ | 低吸型 | **70.2%** | **9.19%** | **7.38** |
| 3 | 连跌反弹 | 超跌型 | 56.2% | 6.33% | 4.37 |
| 4 | 多指标共振 | 精选型 | 60.2% | 6.78% | 4.34 |

---

## 交易成本参数

| 成本项 | 费率 | 方向 |
|--------|------|------|
| 佣金 | 万分之三 | 双向 |
| 印花税 | 千分之0.5 | 仅卖出 |
| 滑点 | 1 bp | 双向 |
| 最低佣金 | 5 元 | 单笔 |
