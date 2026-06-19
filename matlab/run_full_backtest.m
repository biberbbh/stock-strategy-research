function summary_table = run_full_backtest(stock_data, strategies, strategy_keys, ...
    strategy_names, hold_days_list, include_costs, verbose)
% RUN_FULL_BACKTEST 完整回测流程

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
            has_signals = false; break;
        end
    end
    if ~has_signals
        stock_data(i).data = generate_all_signals(tbl, strategies, strategy_keys);
    end
end

n_combos = length(strategy_keys) * length(hold_days_list);
summary_cell = cell(n_combos, 19);
row_idx = 0;

for s = 1:length(strategy_keys)
    key = strategy_keys{s};
    name = strategy_names{s};
    sig_col = sprintf('signal_%s', key);

    for h = 1:length(hold_days_list)
        hold_days = hold_days_list(h);
        if verbose, fprintf('回测: %s | 持有 %d 天\n', name, hold_days); end

        trades = backtest_all_stocks(stock_data, sig_col, hold_days, include_costs);
        if include_costs, return_col = 'net_return_pct';
        else, return_col = 'gross_return_pct'; end

        metrics = calculate_metrics(trades, return_col);
        risk = calculate_risk_metrics(trades, return_col);
        sig_test = test_win_rate_significance(trades, return_col);

        row_idx = row_idx + 1;
        summary_cell(row_idx, :) = {
            name, hold_days, metrics.trade_count, ...
            metrics.win_rate_gt0, metrics.win_rate_gt1, ...
            metrics.avg_return, metrics.max_return, metrics.max_loss, ...
            metrics.median_return, metrics.std_return, ...
            risk.sharpe_ratio, risk.max_drawdown, risk.calmar_ratio, ...
            risk.profit_factor, risk.avg_win, risk.avg_loss, ...
            sig_test.p_value_binomial, sig_test.ci_95_lower, sig_test.ci_95_upper};
    end
end

summary_cell = summary_cell(1:row_idx, :);
summary_table = cell2table(summary_cell, 'VariableNames', {
    '策略名称', '持有天数', '交易次数', '胜率gt0pct', '胜率gt1pct', ...
    '平均收益率pct', '最大收益率pct', '最大亏损率pct', '中位数收益率pct', ...
    '标准差pct', '夏普比率', '最大回撤pct', '卡玛比率', '盈亏比', ...
    '平均盈利pct', '平均亏损pct', '胜率p值', '收益CI下界', '收益CI上界'});
end


function metrics = calculate_metrics(trades, return_col)
% 基本统计指标
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


function risk = calculate_risk_metrics(trades, return_col, risk_free_rate)
% 风险调整指标
if nargin < 3 || isempty(risk_free_rate)
    cfg = config(); risk_free_rate = cfg.RISK_FREE_RATE;
end
if nargin < 2, return_col = 'net_return_pct'; end
if isempty(trades) || isempty(fieldnames(trades))
    risk = struct('sharpe_ratio', NaN, 'max_drawdown', NaN, 'calmar_ratio', NaN, ...
        'profit_factor', NaN, 'avg_win', NaN, 'avg_loss', NaN, 'win_loss_ratio', NaN);
    return;
end
returns = [trades.(return_col)];
daily_returns = returns / 100;
mean_ret = mean(daily_returns);
std_ret = std(daily_returns);
if std_ret > 0
    risk.sharpe_ratio = round((mean_ret * 250 - risk_free_rate) / (std_ret * sqrt(250)), 4);
else
    risk.sharpe_ratio = NaN;
end
cum_returns = cumprod(1 + daily_returns);
running_max = cum_returns;
for i = 2:length(running_max)
    if running_max(i-1) > running_max(i), running_max(i) = running_max(i-1); end
end
drawdowns = (cum_returns - running_max) ./ running_max * 100;
risk.max_drawdown = round(min(drawdowns), 2);
if risk.max_drawdown < 0
    annual_return = mean_ret * 250;
    risk.calmar_ratio = round(annual_return / abs(risk.max_drawdown / 100), 4);
else
    risk.calmar_ratio = NaN;
end
wins = returns(returns > 0);
losses = returns(returns < 0);
total_profit = sum(wins);
total_loss = abs(sum(losses));
risk.profit_factor = round(conditional(total_loss > 0, total_profit / total_loss, Inf), 4);
risk.avg_win = round(conditional(~isempty(wins), mean(wins), NaN), 4);
risk.avg_loss = round(conditional(~isempty(losses), mean(losses), NaN), 4);
risk.win_loss_ratio = round(conditional(~isempty(losses) && length(losses) > 0, length(wins) / length(losses), Inf), 4);
end


function sig_test = test_win_rate_significance(trades, return_col, alpha)
% 统计显著性检验
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
if n > 0
    p_binomial = 1 - binocdf(n_wins - 1, n, 0.5);
    p_binomial = min(p_binomial, 1);
else
    p_binomial = NaN;
end
rng(42, 'twister');
n_bootstrap = 10000;
boot_means = zeros(n_bootstrap, 1);
for b = 1:n_bootstrap
    sample = returns(randi(n, [n, 1]));
    boot_means(b) = mean(sample);
end
boot_means = sort(boot_means);
sig_test.p_value_binomial = round(p_binomial, 6);
sig_test.ci_95_lower = round(prctile(boot_means, 2.5), 4);
sig_test.ci_95_upper = round(prctile(boot_means, 97.5), 4);
sig_test.significant = p_binomial < alpha;
end


function result = conditional(cond, true_val, false_val)
% 简化版条件表达式
if cond, result = true_val; else, result = false_val; end
end
