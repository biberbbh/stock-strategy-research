function tbl = calculate_all_features(tbl, ma_windows, box_lengths, ...
    macd_params, rsi_period, kdj_period, vol_ma_window)
% CALCULATE_ALL_FEATURES 一站式计算所有技术指标特征
%
%   参数:
%       tbl:           包含股票日线数据的 table
%       ma_windows:    均线窗口列表，默认 [5, 10, 20, 60]
%       box_lengths:   箱体长度列表，默认 [40, 50, 60]
%       macd_params:   [fast, slow, signal]，默认 [12, 26, 9]
%       rsi_period:    RSI 周期，默认 14
%       kdj_period:    KDJ 周期，默认 9
%       vol_ma_window: 成交量均量窗口，默认 5
%
%   返回:
%       包含所有特征列的 table
%
%   注意：所有特征仅使用当前及历史数据，无未来信息泄露。

if nargin < 2 || isempty(ma_windows), ma_windows = [5, 10, 20, 60]; end
if nargin < 3 || isempty(box_lengths), box_lengths = [40, 50, 60]; end
if nargin < 4 || isempty(macd_params), macd_params = [12, 26, 9]; end
if nargin < 5 || isempty(rsi_period), rsi_period = 14; end
if nargin < 6 || isempty(kdj_period), kdj_period = 9; end
if nargin < 7 || isempty(vol_ma_window), vol_ma_window = 5; end

% 确保数据按日期升序
tbl = sortrows(tbl, 'day');

% 依次计算各特征
tbl = calculate_ma(tbl, ma_windows);
tbl = calculate_macd(tbl, macd_params(1), macd_params(2), macd_params(3));
tbl = calculate_rsi(tbl, rsi_period);
tbl = calculate_kdj(tbl, kdj_period);
tbl = calculate_box_position(tbl, box_lengths);
tbl = calculate_ma_signals(tbl);
tbl = calculate_macd_signals(tbl);
tbl = calculate_volume_features(tbl, vol_ma_window);

end


% ============================================================
% 移动均线
% ============================================================

function tbl = calculate_ma(tbl, windows)
% 计算收盘价的简单移动平均 (SMA)
close_vals = tbl.close;
for w = windows
    col_name = sprintf('MA%d', w);
    ma_vals = movmean(close_vals, [w-1, 0]); ma_vals(1:w-1) = NaN; tbl.(col_name) = ma_vals;
end
end


% ============================================================
% MACD
% ============================================================

function tbl = calculate_macd(tbl, fast, slow, signal)
% 计算 MACD 指标
%   fast:   快线 EMA 周期 (默认 12)
%   slow:   慢线 EMA 周期 (默认 26)
%   signal: 信号线 EMA 周期 (默认 9)

close_vals = tbl.close;
ema_fast = ema_recursive(close_vals, fast);
ema_slow = ema_recursive(close_vals, slow);

dif = ema_fast - ema_slow;
dea = ema_recursive(dif, signal);
macd_bar = 2 * (dif - dea);

tbl.DIF = dif;
tbl.DEA = dea;
tbl.MACD = macd_bar;
end


function result = ema_recursive(data, span)
% EMA_RECURSIVE 递推计算指数移动平均 (EMA)
%   等价于 pandas ewm(span=span, adjust=False).mean()
%
%   参数:
%       data: 输入序列 (列向量)
%       span: EMA 周期
%
%   返回:
%       EMA 序列 (列向量)

n = length(data);
result = NaN(n, 1);
if n == 0, return; end

alpha = 2 / (span + 1);

% 找到第一个非 NaN 值
first_valid = find(~isnan(data), 1, 'first');
if isempty(first_valid), return; end

result(first_valid) = data(first_valid);
for i = first_valid+1:n
    if isnan(data(i))
        result(i) = result(i-1);
    else
        result(i) = alpha * data(i) + (1 - alpha) * result(i-1);
    end
end
end


% ============================================================
% RSI
% ============================================================

function tbl = calculate_rsi(tbl, period)
% 计算相对强弱指数 RSI (Wilder's smoothing)

close_vals = tbl.close;
n = length(close_vals);

% 计算涨跌
delta = [0; diff(close_vals)];
gain = max(delta, 0);
loss = max(-delta, 0);

% Wilder's smoothing (等效于 EMA，alpha = 1/period)
avg_gain = NaN(n, 1);
avg_loss = NaN(n, 1);

if n > period
    avg_gain(period+1) = mean(gain(2:period+1));
    avg_loss(period+1) = mean(loss(2:period+1));
    for i = period+2:n
        avg_gain(i) = (avg_gain(i-1) * (period-1) + gain(i)) / period;
        avg_loss(i) = (avg_loss(i-1) * (period-1) + loss(i)) / period;
    end
end

rsi = NaN(n, 1);
for i = 1:n
    if ~isnan(avg_gain(i))
        if avg_loss(i) > 0
            rs_val = avg_gain(i) / avg_loss(i);
            rsi(i) = 100 - 100 / (1 + rs_val);
        elseif avg_loss(i) == 0
            rsi(i) = 100;  % 无亏损日
        end
    end
end

col_name = sprintf('RSI%d', period);
tbl.(col_name) = rsi;
end


% ============================================================
% KDJ
% ============================================================

function tbl = calculate_kdj(tbl, period)
% 计算随机指标 KDJ

close_vals = tbl.close;
high_vals = tbl.high;
low_vals = tbl.low;
n = length(close_vals);

% 计算 N 日最低价和最高价
low_n = NaN(n, 1);
high_n = NaN(n, 1);
for i = period:n
    low_n(i) = min(low_vals(i-period+1:i));
    high_n(i) = max(high_vals(i-period+1:i));
end

% RSV
rsv = NaN(n, 1);
for i = period:n
    denom = high_n(i) - low_n(i);
    if denom > 0
        rsv(i) = (close_vals(i) - low_n(i)) / denom * 100;
    elseif denom == 0
        rsv(i) = 50;  % 一字板
    end
end

% 递推计算 K, D, J
K = NaN(n, 1);
D = NaN(n, 1);
J = NaN(n, 1);

first_valid = period;
if first_valid <= n
    K(first_valid) = 50;
    D(first_valid) = 50;
    for i = first_valid+1:n
        if ~isnan(rsv(i))
            K(i) = 2/3 * K(i-1) + 1/3 * rsv(i);
            D(i) = 2/3 * D(i-1) + 1/3 * K(i);
            J(i) = 3 * K(i) - 2 * D(i);
        elseif ~isnan(K(i-1))
            K(i) = K(i-1);
            D(i) = D(i-1);
            J(i) = J(i-1);
        end
    end
end

tbl.K = K;
tbl.D = D;
tbl.J = J;
end


% ============================================================
% 箱体特征
% ============================================================

function tbl = calculate_box_position(tbl, lengths)
% 计算当前收盘价在不同长度箱体中的位置比例
%
% 箱体定义（以当前交易日为箱体最后一个交易日）：
%   上轨 = max(open, close) 在箱体区间内滚动最大值
%   下轨 = min(open, close) 在箱体区间内滚动最小值
%   位置 = (当前收盘价 - 下轨) / (上轨 - 下轨) ∈ [0, 1]
%
% 注：选用 max(open, close) / min(open, close) 而非 high / low，
%   避免日内瞬时异常波动（影线）夸大箱体范围。

close_vals = tbl.close;
open_vals = tbl.open;
n = length(close_vals);

% 每个交易日的开盘价和收盘价的范围
oc_max = max(open_vals, close_vals);
oc_min = min(open_vals, close_vals);

for L = lengths
    % 滚动窗口内的上轨和下轨
    upper = NaN(n, 1);
    lower = NaN(n, 1);
    for i = L:n
        upper(i) = max(oc_max(i-L+1:i));
        lower(i) = min(oc_min(i-L+1:i));
    end

    diff_val = upper - lower;
    pos = NaN(n, 1);
    for i = 1:n
        if diff_val(i) > 0
            pos(i) = (close_vals(i) - lower(i)) / diff_val(i);
        elseif ~isnan(diff_val(i)) && diff_val(i) == 0
            pos(i) = 0.5;  % 一字横盘
        end
    end

    col_name = sprintf('box_pos_%d', L);
    tbl.(col_name) = pos;
end
end


% ============================================================
% 均线关系与交叉信号
% ============================================================

function tbl = calculate_ma_signals(tbl)
% 计算均线关系及金叉/死叉信号
% 需要先运行 calculate_ma()

pairs = {5, 10; 5, 20; 10, 20};

for p = 1:size(pairs, 1)
    short = pairs{p, 1};
    long = pairs{p, 2};
    col_s = sprintf('MA%d', short);
    col_l = sprintf('MA%d', long);

    if ~any(strcmp(tbl.Properties.VariableNames, col_s)) || ...
       ~any(strcmp(tbl.Properties.VariableNames, col_l))
        continue;
    end

    ma_s = tbl.(col_s);
    ma_l = tbl.(col_l);

    % 当前均线关系
    col_above = sprintf('ma%d_above_ma%d', short, long);
    tbl.(col_above) = double(ma_s > ma_l);

    % 金叉/死叉
    cur_above = ma_s > ma_l;
    prev_above = [false; cur_above(1:end-1)];

    % 金叉：前一日未上穿，当日上穿
    golden = (~prev_above) & cur_above;
    col_golden = sprintf('ma%d_cross_ma%d', short, long);
    tbl.(col_golden) = double(golden);

    % 死叉：前一日未下穿，当日下穿
    dead = prev_above & (~cur_above);
    col_dead = sprintf('ma%d_dead_ma%d', short, long);
    tbl.(col_dead) = double(dead);
end
end


% ============================================================
% MACD 信号
% ============================================================

function tbl = calculate_macd_signals(tbl)
% 计算 MACD 金叉/死叉信号
% 需要先运行 calculate_macd()

if ~any(strcmp(tbl.Properties.VariableNames, 'DIF')) || ...
   ~any(strcmp(tbl.Properties.VariableNames, 'DEA'))
    return;
end

dif = tbl.DIF;
dea = tbl.DEA;

cur_above = dif > dea;
prev_above = [false; cur_above(1:end-1)];

% 金叉
tbl.macd_golden_cross = double((~prev_above) & cur_above);
% 死叉
tbl.macd_dead_cross = double(prev_above & (~cur_above));
end


% ============================================================
% 成交量特征
% ============================================================

function tbl = calculate_volume_features(tbl, vol_ma_window)
% 计算成交量均量比

volume = tbl.volume;
n = length(volume);

% 成交量均线
vol_ma = NaN(n, 1);
for i = vol_ma_window:n
    vol_ma(i) = mean(volume(i-vol_ma_window+1:i));
end

col_ma = sprintf('vol_ma%d', vol_ma_window);
tbl.(col_ma) = vol_ma;
tbl.vol_ratio = volume ./ vol_ma;
end
