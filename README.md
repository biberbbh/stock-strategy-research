# 股票特征建模与买入时机研究

量化交易策略研究与回测系统 v2.0 — 课程实验项目

## 快速运行

```bash
# 安装依赖
pip install pandas numpy matplotlib openpyxl scipy

# 运行回测（限制 200 只股票快速验证）
python main.py --max-stocks 200

# 全量回测
python main.py

# Walk-Forward 样本外验证
python main.py --walk-forward
```

## 项目结构

- `stock_strategy/` — 核心代码模块
- `day/` — 股票日线 CSV 数据
- `results/` — 实验输出
- `提交版/` — 课程提交版本
