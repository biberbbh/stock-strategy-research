function summary_table = run_full_backtest(stock_data, strategies, strategy_keys, ...
    strategy_names, hold_days_list, include_costs, verbose)
% RUN_FULL_BACKTEST 对全部股票 × 全部策略 × 全部持有周期运行回测，生成汇总表
%
%   参数:
%       stock_data:     struct 数组 (.code, .data)
%       strategies:     策略函数句柄 cell 数组
%       strategy_keys:  策略键名 cell 数组
%       strategy_names: 策略名称 cell 数组
%       hold_days_list: 持有天数列表
%       include_costs:  是否扣除交易成本（默认 true）
%       verbose:        是否打印进度（默认 true）
%
%   返回:
%       table 汇总表

if nargin < 7, verbose = true; end
if nargin < 6, include_costs = true; end

cfg = config();
if nargin < 5 || isempty(hold_days_list), hold_days_list = cfg.HOLD_DAYS; end
if nargin < 2 || isempty(strategies)
    [strategies, strategy_keys, strategy_names] = get_all_strategies();
end

% 确保每只股票已有信号列
if verbose, fprintf('检查策略信号...\n'); end
for i = 1:length(stock_data)
    tbl = stock_data(i).data;
    has_signals = true;
    for s = 1:length(strategy_keys)
        sig_col = sprintf('signal_%s', strategy_keys{s});
        if ~any(strcmp(tbl.Properties.VariableNames, sig_col))
            has_signals = false;
            break;
        end
    end
    if ~has_signals
        stock_data(i).data = generate_all_signals(tbl, strategies, strategy_keys);
    end
end

% 初始化汇总表
n_combos = length(strategy_keys) * length(hold_days_list);
summary_cell = cell(n_combos, 19);
row_idx = 0;

for s = 1:length(strategy_keys)
    key = strategy_keys{s};
    name = strategy_names{s};
    sig_col = sprintf('signal_%s', key);

    for h = 1:length(hold_days_list)
        hold_days = hold_days_list(h);

        if verbose
            fprintf('回测: %s | 持有 %d 天\n', name, hold_days);
        end

        trades = backtest_all_stocks(stock_data, sig_col, hold_days, include_costs);

        if include_costs
            return_col = 'net_return_pct';
        else
            return_col = 'gross_return_pct';
        end

        metrics = calculate_metrics(trades, return_col);
        risk = calculate_risk_metrics(trades, return_col);
        sig_test = test_win_rate_significance(trades, return_col);

        row_idx = row_idx + 1;
        summary_cell(row_idx, :) = {
            name,                                    % 策略名称
            hold_days,                               % 持有天数
            metrics.trade_count,                     % 交易次数
            metrics.win_rate_gt0,                    % 胜率(>0%)
            metrics.win_rate_gt1,                    % 胜率(>1%)
            metrics.avg_return,                      % 平均收益率(%)
            metrics.max_return,                      % 最大收益率(%)
            metrics.max_loss,                        % 最大亏损率(%)
            metrics.median_return,                   % 中位数收益率(%)
            metrics.std_return,                      % 标准差(%)
            risk.sharpe_ratio,                       % 夏普比率
            risk.max_drawdown,                       % 最大回撤(%)
            risk.calmar_ratio,                       % 卡玛比率
            risk.profit_factor,                      % 盈亏比
            risk.avg_win,                            % 平均盈利(%)
            risk.avg_loss,                           % 平均亏损(%)
            sig_test.p_value_binomial,               % 胜率p值
            sig_test.ci_95_lower,                    % 收益CI下界
            sig_test.ci_95_upper,                    % 收益CI上界
            };
    end
end

summary_cell = summary_cell(1:row_idx, :);
summary_table = cell2table(summary_cell, 'VariableNames', {
    '策略名称', '持有天数', '交易次数', '胜率gt0pct', '胜率gt1pct', ...
    '平均收益率pct', '最大收益率pct', '最大亏损率pct', '中位数收益率pct', ...
    '标准差pct', '夏普比率', '最大回撤pct', '卡玛比率', '盈亏比', ...
    '平均盈利pct', '平均亏损pct', '胜率p值', '收益CI下界', '收益CI上界'
    });

end


% ============================================================
% 交易成本计算
% ============================================================

function total_cost_pct = calculate_transaction_cost(buy_price, sell_price, ...
    commission_rate, stamp_tax_rate, slippage_bps, min_commission)
% 计算单笔交易的往返成本（以价格百分比表示）

if nargin < 3 || isempty(commission_rate)
    cfg = config();
    commission_rate = cfg.COMMISSION_RATE;
end
if nargin < 4 || isempty(stamp_tax_rate)
    cfg = config();
    stamp_tax_rate = cfg.STAMP_TAX_RATE;
end
if nargin < 5 || isempty(slippage_bps)
    cfg = config();
    slippage_bps = cfg.SLIPPAGE_BPS;
end
if nargin < 6 || isempty(min_commission)
    cfg = config();
    min_commission = cfg.MIN_COMMISSION;
end

% 滑点成本 (买卖各 1bp 冲击)
slippage_pct = slippage_bps / 10000 * 2;  % 买卖双向

% 佣金成本 (买卖各万分之三)
commission_pct = commission_rate * 2;  % 双向

% 印花税 (仅卖出)
stamp_pct = stamp_tax_rate;

% 合计成本占买入价百分比
total_cost_pct = (slippage_pct + commission_pct + stamp_pct) * 100;

% 最低佣金调整
est_commission = max(buy_price * commission_rate, min_commission / 10000);
actual_commission_pct = (est_commission / buy_price) * 2 * 100;
if actual_commission_pct > (commission_rate * 2 * 100)
    total_cost_pct = (slippage_pct + actual_commission_pct / 100 + stamp_pct) * 100;
end

end


% ============================================================
% 单股票回测
% ============================================================

function trades_struct = backtest_single_stock(tbl, signal_col, hold_days, include_costs)
% 对单只股票按信号列进行回测
%
%   返回:
%       struct 数组，字段: stock_code, signal_idx, buy_idx, sell_idx,
%           buy_date, sell_date, buy_price, sell_price,
%           gross_return_pct, cost_pct, net_return_pct

if nargin < 4, include_costs = true; end

if ~any(strcmp(tbl.Properties.VariableNames, signal_col))
    trades_struct = struct([]);
    return;
end

% 确保按日期排序
tbl = sortrows(tbl, 'day');

n = height(tbl);

% 找出所有信号日索引
signal_indices = find(tbl.(signal_col) == 1);

% 预分配
max_trades = length(signal_indices);
trades_struct = struct('stock_code', {}, 'signal_idx', {}, 'buy_idx', {}, ...
    'sell_idx', {}, 'buy_date', {}, 'sell_date', {}, ...
    'buy_price', {}, 'sell_price', {}, ...
    'gross_return_pct', {}, 'cost_pct', {}, 'net_return_pct', {});

stock_code = tbl.stock_code{1};

trade_count = 0;
for s = 1:length(signal_indices)
    sig_idx = signal_indices(s);
    buy_idx = sig_idx + 1;
    sell_idx = buy_idx + hold_days;

    % 边界检查
    if buy_idx > n || sell_idx > n
        continue;
    end

    buy_price = tbl.close(buy_idx);
    sell_price = tbl.close(sell_idx);

    % 价格有效性检查
    if isnan(buy_price) || isnan(sell_price)
        continue;
    end
    if buy_price <= 0 || sell_price <= 0
        continue;
    end

    % 毛收益率
    gross_ret_pct = (sell_price - buy_price) / buy_price * 100;

    % 交易成本
    if include_costs
        cost_pct = calculate_transaction_cost(buy_price, sell_price);
        net_ret_pct = gross_ret_pct - cost_pct;
    else
        cost_pct = 0;
        net_ret_pct = gross_ret_pct;
    end

    trade_count = trade_count + 1;
    trades_struct(trade_count).stock_code = stock_code;
    trades_struct(trade_count).signal_idx = sig_idx;
    trades_struct(trade_count).buy_idx = buy_idx;
    trades_struct(trade_count).sell_idx = sell_idx;
    trades_struct(trade_count).buy_date = tbl.day(buy_idx);
    trades_struct(trade_count).sell_date = tbl.day(sell_idx);
    trades_struct(trade_count).buy_price = buy_price;
    trades_struct(trade_count).sell_price = sell_price;
    trades_struct(trade_count).gross_return_pct = round(gross_ret_pct, 4);
    trades_struct(trade_count).cost_pct = round(cost_pct, 4);
    trades_struct(trade_count).net_return_pct = round(net_ret_pct, 4);
end

end


% ============================================================
% 多股票批量回测
% ============================================================

function all_trades = backtest_all_stocks(stock_data, signal_col, hold_days, ...
    include_costs, verbose)
% 对所有股票进行批量回测，汇总所有交易记录

if nargin < 5, verbose = false; end
if nargin < 4, include_costs = true; end

all_trades = struct([]);
total = length(stock_data);

for i = 1:total
    trades = backtest_single_stock(stock_data(i).data, signal_col, hold_days, include_costs);
    if ~isempty(fieldnames(trades))
        if isempty(all_trades)
            all_trades = trades;
        else
            all_trades = [all_trades, trades];  %#ok<AGROW>
        end
    end

    if verbose && mod(i, 500) == 0
        fprintf('  回测进度: %d/%d\n', i, total);
    end
end

if isempty(all_trades)
    if verbose
        fprintf('  [警告] %s 持有 %d 天: 无任何交易信号\n', signal_col, hold_days);
    end
    return;
end

if verbose
    fprintf('  %s 持有 %d 天: 共 %d 笔交易\n', signal_col, hold_days, length(all_trades));
end

end


% ============================================================
% 基本统计指标计算
% ============================================================

function metrics = calculate_metrics(trades, return_col)
% 根据交易记录计算回测指标

if nargin < 2, return_col = 'gross_return_pct'; end

if isempty(trades) || isempty(fieldnames(trades))
    metrics = struct('trade_count', 0, 'win_rate_gt0', NaN, 'win_rate_gt1', NaN, ...
        'avg_return', NaN, 'max_return', NaN, 'max_loss', NaN, ...
        'median_return', NaN, 'std_return', NaN);
    return;
end

returns = [trades.(return_col)];
n = length(returns);

metrics.trade_count = n;
metrics.win_rate_gt0 = round(mean(returns > 0) * 100, 2);
metrics.win_rate_gt1 = round(mean(returns > 1.0) * 100, 2);
metrics.avg_return = round(mean(returns), 4);
metrics.max_return = round(max(returns), 4);
metrics.max_loss = round(min(returns), 4);
metrics.median_return = round(median(returns), 4);
metrics.std_return = round(std(returns), 4);
end


% ============================================================
% 风险调整指标
% ============================================================

function risk = calculate_risk_metrics(trades, return_col, risk_free_rate)
% 计算风险调整后的绩效指标

if nargin < 3 || isempty(risk_free_rate)
    cfg = config();
    risk_free_rate = cfg.RISK_FREE_RATE;
end
if nargin < 2, return_col = 'net_return_pct'; end

if isempty(trades) || isempty(fieldnames(trades))
    risk = struct('sharpe_ratio', NaN, 'max_drawdown', NaN, 'calmar_ratio', NaN, ...
        'profit_factor', NaN, 'avg_win', NaN, 'avg_loss', NaN, 'win_loss_ratio', NaN);
    return;
end

returns = [trades.(return_col)];
n = length(returns);

% 转换为小数
daily_returns = returns / 100;

% --- 夏普比率 ---
% 使用单笔交易作为观测单位，年化
mean_ret = mean(daily_returns);
std_ret = std(daily_returns);

if std_ret > 0
    risk.sharpe_ratio = round((mean_ret * 250 - risk_free_rate) / (std_ret * sqrt(250)), 4);
else
    risk.sharpe_ratio = NaN;
end

% --- 最大回撤 ---
% 按交易顺序计算累积收益的回撤
cum_returns = cumprod(1 + daily_returns);
running_max = cum_returns;
for i = 2:length(running_max)
    if running_max(i-1) > running_max(i)
        running_max(i) = running_max(i-1);
    end
end
drawdowns = (cum_returns - running_max) ./ running_max * 100;
risk.max_drawdown = round(min(drawdowns), 2);

% --- 卡玛比率 ---
if risk.max_drawdown < 0
    annual_return = mean_ret * 250;
    risk.calmar_ratio = round(annual_return / abs(risk.max_drawdown / 100), 4);
else
    risk.calmar_ratio = NaN;
end

% --- 盈亏比 (Profit Factor) ---
wins = returns(returns > 0);
losses = returns(returns < 0);
total_profit = sum(wins);
total_loss = abs(sum(losses));
if total_loss > 0
    risk.profit_factor = round(total_profit / total_loss, 4);
else
    risk.profit_factor = Inf;
end

% --- 平均盈亏 ---
if ~isempty(wins)
    risk.avg_win = round(mean(wins), 4);
else
    risk.avg_win = NaN;
end
if ~isempty(losses)
    risk.avg_loss = round(mean(losses), 4);
else
    risk.avg_loss = NaN;
end

% --- 盈亏次数比 ---
if ~isempty(losses) && length(losses) > 0
    risk.win_loss_ratio = round(length(wins) / length(losses), 4);
else
    risk.win_loss_ratio = Inf;
end
end


% ============================================================
% 统计显著性检验
% ============================================================

function sig_test = test_win_rate_significance(trades, return_col, alpha)
% 检验胜率是否显著高于随机（50%）
%   使用二项检验和 Bootstrap 置信区间

if nargin < 3, alpha = 0.05; end
if nargin < 2, return_col = 'net_return_pct'; end

if isempty(trades) || isempty(fieldnames(trades))
    sig_test = struct('p_value_binomial', NaN, 'ci_95_lower', NaN, ...
        'ci_95_upper', NaN, 'significant', false);
    return;
end

returns = [trades.(return_col)];
n = length(returns);
n_wins = sum(returns > 0);

% --- 二项检验：H0: 胜率 = 0.5 ---
if n > 0
    % 使用 binocdf 计算 P(X >= n_wins | p=0.5)
    p_binomial = 1 - binocdf(n_wins - 1, n, 0.5);
    p_binomial = min(p_binomial, 1);  % 数值稳定
else
    p_binomial = NaN;
end

% --- Bootstrap 置信区间 ---
rng(42, 'twister');  % 固定随机种子
n_bootstrap = 10000;
boot_means = zeros(n_bootstrap, 1);
for b = 1:n_bootstrap
    sample = returns(randi(n, [n, 1]));
    boot_means(b) = mean(sample);
end
boot_means = sort(boot_means);
ci_lower = prctile(boot_means, 2.5);
ci_upper = prctile(boot_means, 97.5);

sig_test.p_value_binomial = round(p_binomial, 6);
sig_test.ci_95_lower = round(ci_lower, 4);
sig_test.ci_95_upper = round(ci_upper, 4);
sig_test.significant = p_binomial < alpha;
end


% ============================================================
% 样本划分
% ============================================================

function [train_data, test_data] = split_train_test(stock_data, train_ratio)
% 按时间顺序将数据划分为训练集和测试集

if nargin < 2 || isempty(train_ratio)
    cfg = config();
    train_ratio = cfg.TRAIN_RATIO;
end

n = length(stock_data);
train_data = struct('code', cell(n, 1), 'data', cell(n, 1));
test_data = struct('code', cell(n, 1), 'data', cell(n, 1));
train_count = 0;
test_count = 0;

for i = 1:n
    tbl = stock_data(i).data;
    tbl = sortrows(tbl, 'day');
    split_idx = round(height(tbl) * train_ratio);

    if split_idx < 60
        train_count = train_count + 1;
        train_data(train_count).code = stock_data(i).code;
        train_data(train_count).data = tbl;
    else
        train_count = train_count + 1;
        train_data(train_count).code = stock_data(i).code;
        train_data(train_count).data = tbl(1:split_idx, :);
        test_count = test_count + 1;
        test_data(test_count).code = stock_data(i).code;
        test_data(test_count).data = tbl(split_idx+1:end, :);
    end
end

train_data = train_data(1:train_count);
test_data = test_data(1:test_count);
end


% ============================================================
% Walk-Forward 验证
% ============================================================

function wf_summary = walk_forward_validation(stock_data, strategies, strategy_keys, ...
    strategy_names, hold_days_list, window_size, step_size, verbose)
% 滚动窗口验证 (Walk-Forward Validation)

if nargin < 8, verbose = true; end
cfg = config();
if nargin < 7 || isempty(step_size), step_size = cfg.WALK_FORWARD_STEP; end
if nargin < 6 || isempty(window_size), window_size = cfg.WALK_FORWARD_WINDOW; end
if nargin < 5 || isempty(hold_days_list), hold_days_list = cfg.HOLD_DAYS; end
if nargin < 2 || isempty(strategies)
    [strategies, strategy_keys, strategy_names] = get_all_strategies();
end

% 确定全局日期范围
all_dates = [];
for i = 1:length(stock_data)
    all_dates = [all_dates; stock_data(i).data.day];  %#ok<AGROW>
end
all_dates = unique(sort(all_dates));
total_days = length(all_dates);
n_windows = max(1, floor((total_days - window_size) / step_size));

if verbose
    fprintf('Walk-Forward 验证: %d 个窗口\n', n_windows);
    fprintf('  训练窗口: %d 天, 步长: %d 天\n', window_size, step_size);
end

% 预分配汇总
max_rows = n_windows * length(strategy_keys) * length(hold_days_list);
wf_rows = cell(max_rows, 6);
row_idx = 0;

for w = 0:(n_windows-1)
    train_start_idx = w * step_size + 1;
    train_end_idx = train_start_idx + window_size - 1;
    test_start_idx = train_end_idx + 1;
    test_end_idx = min(test_start_idx + step_size - 1, total_days);

    if test_start_idx > total_days, break; end

    train_start_date = all_dates(train_start_idx);
    train_end_date = all_dates(min(train_end_idx, total_days));
    test_start_date = all_dates(test_start_idx);
    test_end_date = all_dates(test_end_idx);

    if verbose
        fprintf('\n[窗口 %d/%d] 训练: %s ~ %s, 测试: %s ~ %s\n', ...
            w+1, n_windows, ...
            datestr(train_start_date, 'yyyy-mm-dd'), ...
            datestr(train_end_date, 'yyyy-mm-dd'), ...
            datestr(test_start_date, 'yyyy-mm-dd'), ...
            datestr(test_end_date, 'yyyy-mm-dd'));
    end

    % 划分训练集和测试集
    train_data = struct('code', {}, 'data', {});
    test_data = struct('code', {}, 'data', {});
    for i = 1:length(stock_data)
        tbl = stock_data(i).data;
        tbl = sortrows(tbl, 'day');
        train_mask = (tbl.day >= train_start_date) & (tbl.day <= train_end_date);
        test_mask = (tbl.day >= test_start_date) & (tbl.day <= test_end_date);
        train_tbl = tbl(train_mask, :);
        test_tbl = tbl(test_mask, :);
        if height(train_tbl) >= 60
            train_data(end+1).code = stock_data(i).code;  %#ok<AGROW>
            train_data(end).data = train_tbl;
        end
        if height(test_tbl) >= 30
            test_data(end+1).code = stock_data(i).code;  %#ok<AGROW>
            test_data(end).data = test_tbl;
        end
    end

    if isempty(train_data) || isempty(test_data), continue; end

    % 计算特征和信号
    for i = 1:length(train_data)
        train_data(i).data = calculate_all_features(train_data(i).data);
        train_data(i).data = generate_all_signals(train_data(i).data, ...
            strategies, strategy_keys);
    end
    for i = 1:length(test_data)
        test_data(i).data = calculate_all_features(test_data(i).data);
        test_data(i).data = generate_all_signals(test_data(i).data, ...
            strategies, strategy_keys);
    end

    % 在测试集上回测
    for s = 1:length(strategy_keys)
        key = strategy_keys{s};
        name = strategy_names{s};
        sig_col = sprintf('signal_%s', key);
        for h = 1:length(hold_days_list)
            hold_days = hold_days_list(h);
            trades = backtest_all_stocks(test_data, sig_col, hold_days, true);
            if ~isempty(fieldnames(trades))
                returns = [trades.net_return_pct];
                win_rate = mean(returns > 0) * 100;
                avg_ret = mean(returns);
            else
                win_rate = NaN;
                avg_ret = NaN;
            end

            row_idx = row_idx + 1;
            wf_rows(row_idx, :) = {w+1, name, hold_days, win_rate, avg_ret, length(trades)};
        end
    end
end

wf_rows = wf_rows(1:row_idx, :);
wf_summary = cell2table(wf_rows, 'VariableNames', ...
    {'窗口', '策略名称', '持有天数', '胜率gt0pct', '平均收益率pct', '交易次数'});

end
