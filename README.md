# 股票特征建模与买入时机研究 - 量化策略回测系统

> **课程**：大学数学实验 · 综合实验项目  
> **学生**：毕博昊 (2025080901001) | **指导教师**：李佑铭  
> **引擎**：MATLAB R2025b + Python 3.11

---

## 快速开始

```bash
# Python 回测
pip install -r requirements.txt
python run.py

# MATLAB 回测
cd matlab/
test_200()    # 200 只股票完整回测
```

## 项目结构

```
├── matlab/              # MATLAB 策略引擎（15个函数文件）
│   ├── config.m                   # 统一参数
│   ├── calculate_all_features.m   # 特征工程（20+维技术指标）
│   ├── get_all_strategies.m       # 4种买入策略
│   ├── run_full_backtest.m        # 回测引擎
│   └── run_all_visualizations.m   # 可视化
├── stock_strategy/      # Python 策略引擎
│   ├── config.py        ├── features.py
│   ├── strategy.py      └── backtest.py
├── 提交版/              # 实验报告 + 图表 + 数据
│   ├── 实验报告.pdf     # 编译好的报告（22页）
│   ├── 实验报告.tex     # LaTeX 源文件
│   ├── charts/          # 报告插图（8张）
│   ├── results/         # 回测结果
│   └── 最终提交/        # ⭐ 干净提交包（6.5MB）
└── results/             # Python 回测输出
```

---

## 四种策略

| # | 策略 | 类型 | 60天胜率 | 夏普 |
|---|------|------|:---:|:---:|
| 1 | 均线金叉+量能确认 | 追涨 | 56.4% | 4.24 |
| 2 | **箱体底部反弹** ★ | 低吸 | **70.2%** | **7.38** |
| 3 | 连跌反弹 | 超跌 | 56.2% | 4.37 |
| 4 | 多指标共振 | 精选 | 60.2% | 4.34 |

---

## 编译报告

```bash
cd 提交版/最终提交/
xelatex 实验报告.tex
xelatex 实验报告.tex   # 第二遍生成目录
```
