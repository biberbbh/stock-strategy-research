function wf_summary = walk_forward_validation(stock_data, strategies, strategy_keys, ...
    strategy_names, hold_days_list, window_size, step_size, verbose)
% WALK_FORWARD_VALIDATION 滚动窗口验证

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
    all_dates = [all_dates; stock_data(i).data.day]; %#ok<AGROW>
end
all_dates = unique(sort(all_dates));
total_days = length(all_dates);
n_windows = max(1, floor((total_days - window_size) / step_size));

if verbose
    fprintf('Walk-Forward 验证: %d 个窗口\n', n_windows);
    fprintf('  训练窗口: %d 天, 步长: %d 天\n', window_size, step_size);
end

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
            w+1, n_windows, datestr(train_start_date, 'yyyy-mm-dd'), ...
            datestr(train_end_date, 'yyyy-mm-dd'), ...
            datestr(test_start_date, 'yyyy-mm-dd'), ...
            datestr(test_end_date, 'yyyy-mm-dd'));
    end

    % 划分
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
            train_data(end+1).code = stock_data(i).code; %#ok<AGROW>
            train_data(end).data = train_tbl;
        end
        if height(test_tbl) >= 30
            test_data(end+1).code = stock_data(i).code; %#ok<AGROW>
            test_data(end).data = test_tbl;
        end
    end
    if isempty(train_data) || isempty(test_data), continue; end

    % 特征和信号
    for i = 1:length(train_data)
        train_data(i).data = calculate_all_features(train_data(i).data);
        train_data(i).data = generate_all_signals(train_data(i).data, strategies, strategy_keys);
    end
    for i = 1:length(test_data)
        test_data(i).data = calculate_all_features(test_data(i).data);
        test_data(i).data = generate_all_signals(test_data(i).data, strategies, strategy_keys);
    end

    % 回测
    for s = 1:length(strategy_keys)
        sig_col = sprintf('signal_%s', strategy_keys{s});
        for h = 1:length(hold_days_list)
            trades = backtest_all_stocks(test_data, sig_col, hold_days_list(h), true);
            if ~isempty(fieldnames(trades))
                returns = [trades.net_return_pct];
                win_rate = mean(returns > 0) * 100;
                avg_ret = mean(returns);
            else
                win_rate = NaN; avg_ret = NaN;
            end
            row_idx = row_idx + 1;
            wf_rows(row_idx, :) = {w+1, strategy_names{s}, hold_days_list(h), ...
                win_rate, avg_ret, length(trades)};
        end
    end
end

wf_rows = wf_rows(1:row_idx, :);
wf_summary = cell2table(wf_rows, 'VariableNames', ...
    {'窗口', '策略名称', '持有天数', '胜率gt0pct', '平均收益率pct', '交易次数'});
end
