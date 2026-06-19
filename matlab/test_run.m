function test_run()
% TEST_RUN 快速测试：加载20只股票，计算特征，生成信号，单股回测
%
%   用法:
%       test_run()

fprintf('快速测试 (MATLAB)\n\n');

% 添加路径
addpath(fileparts(mfilename('fullpath')));

cfg = config();
data_dir = cfg.DATA_DIR;

% 1. 加载数据
[stock_data, stock_codes] = load_all_stocks(data_dir, 20);
fprintf('\n加载了 %d 只股票\n', length(stock_data));

% 2. 测试特征计算
code = stock_data(1).code;
tbl = stock_data(1).data;
tbl = calculate_all_features(tbl);
fprintf('特征计算完成: %d 列\n', width(tbl));
colnames = tbl.Properties.VariableNames;
fprintf('列名: %s\n', strjoin(colnames, ', '));

% 检查非 NaN 值数量
check_cols = {'MA5', 'RSI14', 'DIF', 'box_pos_60', 'K'};
for c = 1:length(check_cols)
    col = check_cols{c};
    if any(strcmp(colnames, col))
        n_valid = sum(~isnan(tbl.(col)));
        fprintf('有效 %s: %d\n', col, n_valid);
    end
end

% 3. 测试信号生成
[strategies, strategy_keys, strategy_names] = get_all_strategies();
tbl = generate_all_signals(tbl, strategies, strategy_keys);
for s = 1:length(strategy_keys)
    sig_col = sprintf('signal_%s', strategy_keys{s});
    n_signals = sum(tbl.(sig_col));
    fprintf('%s 信号数: %d\n', strategy_names{s}, n_signals);
end

% 4. 测试单股回测
for s = 1:length(strategy_keys)
    key = strategy_keys{s};
    name = strategy_names{s};
    sig_col = sprintf('signal_%s', key);
    trades = backtest_single_stock(tbl, sig_col, 10);
    if ~isempty(fieldnames(trades))
        returns = [trades.net_return_pct];
        win_rate = mean(returns > 0) * 100;
        avg_ret = mean(returns);
        fprintf('\n%s (hold 10d): %d trades, win_rate(>0)=%.1f%%, avg_return=%.2f%%\n', ...
            name, length(trades), win_rate, avg_ret);
    else
        fprintf('\n%s (hold 10d): 无交易\n', name);
    end
end

fprintf('\n=== 测试通过! ===\n');

end
