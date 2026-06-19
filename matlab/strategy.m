function [strategies, strategy_keys, strategy_names] = get_all_strategies()
% GET_ALL_STRATEGIES 获取所有策略函数及其显示名称
%
%   返回:
%       strategies:     cell 数组，每个元素是函数句柄
%       strategy_keys:  策略键名 cell 数组
%       strategy_names: 策略显示名称 cell 数组

strategy_keys = {'strategy1_ma_cross', 'strategy2_box_reversal', ...
    'strategy3_decline_rebound', 'strategy4_multi_resonance'};
strategy_names = {'均线金叉+量能确认', '箱体底部反弹', ...
    '连跌反弹', '多指标共振'};
strategies = {@strategy_ma_cross, @strategy_box_reversal, ...
    @strategy_decline_rebound, @strategy_multi_resonance};

end


function tbl = generate_all_signals(tbl, strategies, strategy_keys)
% GENERATE_ALL_SIGNALS 生成所有策略的买入信号
%
%   参数:
%       tbl:           包含全部特征列的 table
%       strategies:    策略函数句柄 cell 数组
%       strategy_keys: 策略键名 cell 数组
%
%   返回:
%       table: 原始数据 + 各策略的信号列 (signal_{key})

if nargin < 2 || isempty(strategies)
    [strategies, strategy_keys, ~] = get_all_strategies();
end

for s = 1:length(strategies)
    key = strategy_keys{s};
    func = strategies{s};
    sig_col = sprintf('signal_%s', key);
    try
        tbl.(sig_col) = double(func(tbl));
    catch ME
        warning('策略 %s 生成失败: %s', key, ME.message);
        tbl.(sig_col) = zeros(height(tbl), 1);
    end
end
end


% ============================================================
% 策略 1：均线金叉 + 量能确认
% 条件：
%   1) MA5 上穿 MA10 (金叉)
%   2) RSI14 ∈ [30, 70]
%   3) 当日成交量 > 5日均量 × vol_ratio_min
% ============================================================

function signal = strategy_ma_cross(tbl, params)
% 均线金叉 + 量能确认策略

if nargin < 2 || isempty(params)
    cfg = config();
    params = cfg.STRATEGY_PARAMS.strategy1_ma_cross;
end

rsi_min = params.rsi_min;
rsi_max = params.rsi_max;
vol_ratio_min = params.vol_ratio_min;

n = height(tbl);
signal = zeros(n, 1);

% 检查必要列
required = {'ma5_cross_ma10', 'RSI14', 'vol_ratio'};
for c = 1:length(required)
    if ~any(strcmp(tbl.Properties.VariableNames, required{c}))
        error('缺少必要列: %s，请先运行 calculate_all_features()', required{c});
    end
end

cond1 = tbl.ma5_cross_ma10 == 1;
cond2 = (tbl.RSI14 >= rsi_min) & (tbl.RSI14 <= rsi_max);
cond3 = tbl.vol_ratio > vol_ratio_min;

mask = cond1 & cond2 & cond3;
signal(mask) = 1;
end


% ============================================================
% 策略 2：箱体底部反弹
% 条件：
%   1) 箱体位置 < box_position_max (默认 0.2)
%   2) 满足以下任一：
%      - MACD 金叉
%      - 前一日 zdf < zdf_trigger (急跌反弹，默认 -2%)
% ============================================================

function signal = strategy_box_reversal(tbl, params)
% 箱体底部反弹策略

if nargin < 2 || isempty(params)
    cfg = config();
    params = cfg.STRATEGY_PARAMS.strategy2_box_reversal;
end

box_pos_max = params.box_position_max;
zdf_trigger = params.zdf_trigger;
box_col = 'box_pos_60';

n = height(tbl);
signal = zeros(n, 1);

required = {box_col, 'macd_golden_cross', 'zdf'};
for c = 1:length(required)
    if ~any(strcmp(tbl.Properties.VariableNames, required{c}))
        error('缺少必要列: %s，请先运行 calculate_all_features()', required{c});
    end
end

cond1 = tbl.(box_col) < box_pos_max;

% 前一日 zdf
prev_zdf = [NaN; tbl.zdf(1:end-1)];

cond2a = tbl.macd_golden_cross == 1;
cond2b = prev_zdf < zdf_trigger;
cond2 = cond2a | cond2b;

mask = cond1 & cond2;
signal(mask) = 1;
end


% ============================================================
% 策略 3：连跌反弹
% 条件：
%   1) 连续 N 日下跌 (zdf < 0)
%   2) 近 N 日累计跌幅 < cumulative_zdf_max (默认 -3.0)
%   3) 当日换手率 > hsl_min (默认 1.0%)
% ============================================================

function signal = strategy_decline_rebound(tbl, params)
% 连跌反弹策略

if nargin < 2 || isempty(params)
    cfg = config();
    params = cfg.STRATEGY_PARAMS.strategy3_decline_rebound;
end

n_days = params.consecutive_days;
cum_zdf_max = params.cumulative_zdf_max;
hsl_min = params.hsl_min;

n = height(tbl);
signal = zeros(n, 1);
zdf_series = tbl.zdf;

% 近 N 日累计涨跌幅 (rolling sum)
cum_zdf = NaN(n, 1);
for i = n_days:n
    cum_zdf(i) = sum(zdf_series(i-n_days+1:i));
end

% 近 N 日均下跌
all_decline = true(n, 1);
for k = 0:(n_days-1)
    shifted = [NaN(k, 1); zdf_series(1:end-k)];
    all_decline = all_decline & (shifted < 0);
end

% 前一交易日跌幅满足条件
last_decline = [NaN; zdf_series(1:end-1)] < -1.0;

cond = all_decline & (cum_zdf < cum_zdf_max) & last_decline & (tbl.hsl > hsl_min);
signal(cond) = 1;
end


% ============================================================
% 策略 4：多指标共振
% 条件：
%   1) MA5 上穿 MA10 (金叉)
%   2) RSI14 > rsi_min (默认 40)
%   3) 60日箱体位置 < box_position_max (默认 0.5)
%   4) 换手率 > hsl_min (默认 2.0%)
% ============================================================

function signal = strategy_multi_resonance(tbl, params)
% 多指标共振策略

if nargin < 2 || isempty(params)
    cfg = config();
    params = cfg.STRATEGY_PARAMS.strategy4_multi_resonance;
end

rsi_min = params.rsi_min;
box_pos_max = params.box_position_max;
hsl_min = params.hsl_min;

n = height(tbl);
signal = zeros(n, 1);

required = {'ma5_cross_ma10', 'RSI14', 'box_pos_60', 'hsl'};
for c = 1:length(required)
    if ~any(strcmp(tbl.Properties.VariableNames, required{c}))
        error('缺少必要列: %s，请先运行 calculate_all_features()', required{c});
    end
end

cond1 = tbl.ma5_cross_ma10 == 1;
cond2 = tbl.RSI14 > rsi_min;
cond3 = tbl.box_pos_60 < box_pos_max;
cond4 = tbl.hsl > hsl_min;

mask = cond1 & cond2 & cond3 & cond4;
signal(mask) = 1;
end
