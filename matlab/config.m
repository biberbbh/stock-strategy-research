function cfg = config()
% CONFIG 统一参数配置
%   所有可调参数集中在此处，便于实验调整与对比
%
%   返回:
%       cfg: 包含所有配置参数的结构体

% ============================================================
% 数据路径
% ============================================================
cfg.DATA_DIR = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'day');
cfg.RESULT_DIR = fullfile(fileparts(mfilename('fullpath')), 'results');

% ============================================================
% 持有周期列表（交易日）
% ============================================================
cfg.HOLD_DAYS = [5, 10, 15, 20, 30, 40, 50, 60];

% ============================================================
% 均线参数
% ============================================================
cfg.MA_WINDOWS = [5, 10, 20, 60];  % 简单移动平均窗口

% ============================================================
% MACD 参数
% ============================================================
cfg.MACD_FAST = 12;     % 快线周期
cfg.MACD_SLOW = 26;     % 慢线周期
cfg.MACD_SIGNAL = 9;    % 信号线周期

% ============================================================
% RSI 参数
% ============================================================
cfg.RSI_PERIOD = 14;

% ============================================================
% KDJ 参数
% ============================================================
cfg.KDJ_PERIOD = 9;     % KDJ 周期（n 日）

% ============================================================
% 箱体参数
% ============================================================
cfg.BOX_LENGTHS = [40, 50, 60];     % 箱体长度（交易日）

% ============================================================
% 成交量均量参数
% ============================================================
cfg.VOL_MA_WINDOW = 5;   % 成交量均量窗口

% ============================================================
% 涨跌幅窗口（连跌判断）
% ============================================================
cfg.CONSECUTIVE_DECLINE_DAYS = 3;

% ============================================================
% 回测参数
% ============================================================
cfg.MIN_HISTORY_DAYS = 60;   % 回测前需要的最少历史数据天数
cfg.MAX_STOCKS = [];          % 回测股票数量上限，[] 表示全部

% ============================================================
% 交易成本参数
% ============================================================
cfg.COMMISSION_RATE = 0.0003;    % 佣金费率 (双向, 默认万分之三)
cfg.STAMP_TAX_RATE = 0.0005;     % 印花税率 (卖出单向, 千分之0.5)
cfg.SLIPPAGE_BPS = 1.0;          % 滑点 (基点, 1bp = 0.01%)
cfg.MIN_COMMISSION = 5.0;        % 最低佣金 (元/笔)

% ============================================================
% 样本外验证参数
% ============================================================
cfg.TRAIN_RATIO = 0.70;          % 训练集比例
cfg.WALK_FORWARD_WINDOW = 60;    % 滚动窗口训练窗口长度 (交易日)
cfg.WALK_FORWARD_STEP = 20;      % 滚动窗口步长 (交易日)

% ============================================================
% 无风险利率 (用于夏普比率计算)
% ============================================================
cfg.RISK_FREE_RATE = 0.02;       % 年化无风险利率 (默认2%)

% ============================================================
% 策略参数（各策略的阈值）
% ============================================================
cfg.STRATEGY_PARAMS.strategy1_ma_cross.name = '均线金叉+量能确认';
cfg.STRATEGY_PARAMS.strategy1_ma_cross.rsi_min = 30;
cfg.STRATEGY_PARAMS.strategy1_ma_cross.rsi_max = 70;
cfg.STRATEGY_PARAMS.strategy1_ma_cross.vol_ratio_min = 1.0;

cfg.STRATEGY_PARAMS.strategy2_box_reversal.name = '箱体底部反弹';
cfg.STRATEGY_PARAMS.strategy2_box_reversal.box_position_max = 0.2;
cfg.STRATEGY_PARAMS.strategy2_box_reversal.zdf_trigger = -2.0;

cfg.STRATEGY_PARAMS.strategy3_decline_rebound.name = '连跌反弹';
cfg.STRATEGY_PARAMS.strategy3_decline_rebound.consecutive_days = 3;
cfg.STRATEGY_PARAMS.strategy3_decline_rebound.cumulative_zdf_max = -3.0;
cfg.STRATEGY_PARAMS.strategy3_decline_rebound.hsl_min = 1.0;

cfg.STRATEGY_PARAMS.strategy4_multi_resonance.name = '多指标共振';
cfg.STRATEGY_PARAMS.strategy4_multi_resonance.rsi_min = 40;
cfg.STRATEGY_PARAMS.strategy4_multi_resonance.box_position_max = 0.5;
cfg.STRATEGY_PARAMS.strategy4_multi_resonance.hsl_min = 2.0;

% ============================================================
% 可视化参数
% ============================================================
cfg.FIGURE_DPI = 150;
cfg.FIGURE_FIGSIZE = [12, 8];

% 检查中文字体支持
if ispc
    cfg.FONT_NAME = 'Microsoft YaHei';
else
    cfg.FONT_NAME = 'SimHei';
end

end
