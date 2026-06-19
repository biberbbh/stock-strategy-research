function test_200()
% TEST_200 中等规模测试：200只股票，全流程
%
%   用法:
%       test_200()

fprintf('============================================================\n');
fprintf('200只股票测试 (MATLAB)\n');
fprintf('============================================================\n');

t0 = tic;

% 添加路径
addpath(fileparts(mfilename('fullpath')));

% 加载配置
cfg = config();
cfg.RESULT_DIR = fullfile(fileparts(mfilename('fullpath')), 'results');

% 1. 加载数据
fprintf('\n[1] 加载数据...\n');
data_dir = cfg.DATA_DIR;
[stock_data, ~] = load_all_stocks(data_dir, 200);
fprintf('加载了 %d 只股票\n', length(stock_data));

% 2. 特征计算
fprintf('\n[2] 计算特征...\n');
for i = 1:length(stock_data)
    stock_data(i).data = calculate_all_features(stock_data(i).data, ...
        cfg.MA_WINDOWS, cfg.BOX_LENGTHS, ...
        [cfg.MACD_FAST, cfg.MACD_SLOW, cfg.MACD_SIGNAL], ...
        cfg.RSI_PERIOD, cfg.KDJ_PERIOD, cfg.VOL_MA_WINDOW);
    if mod(i, 50) == 0
        fprintf('  %d/%d\n', i, length(stock_data));
    end
end
fprintf('特征计算完成。\n');

% 3. 信号生成
fprintf('\n[3] 生成信号...\n');
[strategies, strategy_keys, strategy_names] = get_all_strategies();
for i = 1:length(stock_data)
    stock_data(i).data = generate_all_signals(stock_data(i).data, ...
        strategies, strategy_keys);
end

for s = 1:length(strategy_keys)
    key = strategy_keys{s};
    sig_col = sprintf('signal_%s', key);
    total = 0;
    for i = 1:length(stock_data)
        if any(strcmp(stock_data(i).data.Properties.VariableNames, sig_col))
            total = total + sum(stock_data(i).data.(sig_col));
        end
    end
    fprintf('  %s: %d 个信号\n', strategy_names{s}, total);
end

% 4. 回测
fprintf('\n[4] 运行回测...\n');
summary_table = run_full_backtest(stock_data, strategies, strategy_keys, ...
    strategy_names, cfg.HOLD_DAYS, true, true);

% 打印结果
disp(summary_table);

% 5. 保存结果
fprintf('\n[5] 保存结果和图表...\n');
save_results(summary_table, cfg.RESULT_DIR);
try
    save_results_excel(summary_table, cfg.RESULT_DIR);
catch ME
    fprintf('Excel 保存失败: %s\n', ME.message);
end
run_all_visualizations(summary_table, stock_data, strategies, ...
    strategy_keys, strategy_names, cfg.HOLD_DAYS);

t1 = toc(t0);
fprintf('\n总耗时: %.1f 秒\n', t1);

end
