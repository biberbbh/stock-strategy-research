function [strategies, strategy_keys, strategy_names] = get_all_strategies()
% GET_ALL_STRATEGIES 获取所有策略函数及其显示名称

strategy_keys = {'strategy1_ma_cross', 'strategy2_box_reversal', ...
    'strategy3_decline_rebound', 'strategy4_multi_resonance'};
strategy_names = {'均线金叉+量能确认', '箱体底部反弹', ...
    '连跌反弹', '多指标共振'};
strategies = {@strategy_ma_cross, @strategy_box_reversal, ...
    @strategy_decline_rebound, @strategy_multi_resonance};
end


function signal = strategy_ma_cross(tbl, params)
% 策略 1：均线金叉 + 量能确认
if nargin < 2 || isempty(params)
    cfg = config();
    params = cfg.STRATEGY_PARAMS.strategy1_ma_cross;
end
n = height(tbl);
signal = zeros(n, 1);
cond1 = tbl.ma5_cross_ma10 == 1;
cond2 = (tbl.RSI14 >= params.rsi_min) & (tbl.RSI14 <= params.rsi_max);
cond3 = tbl.vol_ratio > params.vol_ratio_min;
mask = cond1 & cond2 & cond3;
signal(mask) = 1;
end


function signal = strategy_box_reversal(tbl, params)
% 策略 2：箱体底部反弹
if nargin < 2 || isempty(params)
    cfg = config();
    params = cfg.STRATEGY_PARAMS.strategy2_box_reversal;
end
n = height(tbl);
signal = zeros(n, 1);
cond1 = tbl.box_pos_60 < params.box_position_max;
prev_zdf = [NaN; tbl.zdf(1:end-1)];
cond2a = tbl.macd_golden_cross == 1;
cond2b = prev_zdf < params.zdf_trigger;
cond2 = cond2a | cond2b;
mask = cond1 & cond2;
signal(mask) = 1;
end


function signal = strategy_decline_rebound(tbl, params)
% 策略 3：连跌反弹
if nargin < 2 || isempty(params)
    cfg = config();
    params = cfg.STRATEGY_PARAMS.strategy3_decline_rebound;
end
n = height(tbl);
n_days = params.consecutive_days;
signal = zeros(n, 1);
zdf_series = tbl.zdf;

% 近 N 日累计涨跌幅
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

last_decline = [NaN; zdf_series(1:end-1)] < -1.0;
cond = all_decline & (cum_zdf < params.cumulative_zdf_max) & last_decline & (tbl.hsl > params.hsl_min);
signal(cond) = 1;
end


function signal = strategy_multi_resonance(tbl, params)
% 策略 4：多指标共振
if nargin < 2 || isempty(params)
    cfg = config();
    params = cfg.STRATEGY_PARAMS.strategy4_multi_resonance;
end
n = height(tbl);
signal = zeros(n, 1);
cond1 = tbl.ma5_cross_ma10 == 1;
cond2 = tbl.RSI14 > params.rsi_min;
cond3 = tbl.box_pos_60 < params.box_position_max;
cond4 = tbl.hsl > params.hsl_min;
mask = cond1 & cond2 & cond3 & cond4;
signal(mask) = 1;
end
