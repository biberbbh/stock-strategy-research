function main(max_stocks, no_costs, walk_forward, train_test_split)
% MAIN 股票特征建模与买入时机研究 — 主程序入口
%
%   用法:
%       main()                        % 使用默认配置运行全量
%       main(200)                     % 限制股票数量（快速测试）
%       main(200, false, true, false) % Walk-Forward 验证
%       main([], true, false, false)  % 不计交易成本（调试用）
%
%   参数:
%       max_stocks:       限制股票数量，[] 表示全部 (默认 [])
%       no_costs:         不计交易成本 (默认 false)
%       walk_forward:     启用 Walk-Forward 验证 (默认 false)
%       train_test_split: 启用训练/测试集划分 (默认 false)

if nargin < 4, train_test_split = false; end
if nargin < 3, walk_forward = false; end
if nargin < 2, no_costs = false; end
if nargin < 1, max_stocks = []; end

% 添加路径
addpath(fileparts(mfilename('fullpath')));

% 加载配置
cfg = config();
include_costs = ~no_costs;

tic;
start_time = tic;

fprintf('============================================================\n');
fprintf('  股票特征建模与买入时机研究 — 回测系统 (MATLAB)\n');
fprintf('============================================================\n');
fprintf('  数据目录: %s\n', cfg.DATA_DIR);
fprintf('  输出目录: %s\n', cfg.RESULT_DIR);
if ~isempty(max_stocks)
    fprintf('  股票数量: 最多 %d 只\n', max_stocks);
end
fprintf('  交易成本: %s\n', ternary(include_costs, '计入', '不计'));
if walk_forward
    fprintf('  验证模式: Walk-Forward 滚动窗口\n');
end
if train_test_split
    fprintf('  验证模式: 训练集/测试集划分\n');
end
fprintf('============================================================\n');

% ==========================================
% 阶段 1：数据加载
% ==========================================
fprintf('\n============================================================\n');
fprintf('阶段 1/5: 数据加载\n');
fprintf('============================================================\n');

[stock_data, stock_codes] = load_all_stocks(cfg.DATA_DIR, max_stocks);
if isempty(stock_data)
    fprintf('未加载到任何股票数据，退出\n');
    return;
end

summary = get_data_summary(stock_data);
fprintf('\n数据概览:\n');
fprintf('  股票数量: %d\n', length(stock_data));
fprintf('  日期范围: %s ~ %s\n', ...
    datestr(min(summary.start_date), 'yyyy-mm-dd'), ...
    datestr(max(summary.end_date), 'yyyy-mm-dd'));
fprintf('  平均每只股票 %.0f 个交易日\n', mean(summary.rows));

% ==========================================
% 阶段 2：特征计算
% ==========================================
fprintf('\n============================================================\n');
fprintf('阶段 2/5: 特征计算\n');
fprintf('============================================================\n');

feat_start = tic;
n_stocks = length(stock_data);
for i = 1:n_stocks
    stock_data(i).data = calculate_all_features(stock_data(i).data, ...
        cfg.MA_WINDOWS, cfg.BOX_LENGTHS, ...
        [cfg.MACD_FAST, cfg.MACD_SLOW, cfg.MACD_SIGNAL], ...
        cfg.RSI_PERIOD, cfg.KDJ_PERIOD, cfg.VOL_MA_WINDOW);

    if mod(i, 1000) == 0
        fprintf('  特征计算进度: %d/%d\n', i, n_stocks);
    end
end
fprintf('特征计算完成，耗时 %.1f 秒\n', toc(feat_start));

% ==========================================
% 阶段 3：策略信号生成
% ==========================================
fprintf('\n============================================================\n');
fprintf('阶段 3/5: 策略信号生成\n');
fprintf('============================================================\n');

[strategies, strategy_keys, strategy_names] = get_all_strategies();
for s = 1:length(strategy_keys)
    fprintf('  - %s (%s)\n', strategy_names{s}, strategy_keys{s});
end

for i = 1:n_stocks
    stock_data(i).data = generate_all_signals(stock_data(i).data, ...
        strategies, strategy_keys);
end

% 统计信号
fprintf('\n各策略总信号数:\n');
for s = 1:length(strategy_keys)
    key = strategy_keys{s};
    sig_col = sprintf('signal_%s', key);
    total = 0;
    for i = 1:n_stocks
        if any(strcmp(stock_data(i).data.Properties.VariableNames, sig_col))
            total = total + sum(stock_data(i).data.(sig_col));
        end
    end
    fprintf('  %s: %d\n', strategy_names{s}, total);
end

% ==========================================
% 阶段 4：回测验证
% ==========================================
fprintf('\n============================================================\n');
fprintf('阶段 4/5: 回测验证\n');
fprintf('============================================================\n');

% --- 全样本回测 ---
fprintf('\n--- 全样本回测 ---\n');
summary_table = run_full_backtest(stock_data, strategies, strategy_keys, ...
    strategy_names, cfg.HOLD_DAYS, include_costs, true);

% --- 样本外验证 (可选) ---
if train_test_split
    fprintf('\n--- 训练/测试集划分验证 ---\n');
    [train_data, test_data] = split_train_test(stock_data);
    fprintf('  训练集: %d 只, 测试集: %d 只\n', length(train_data), length(test_data));
    if ~isempty(test_data)
        for i = 1:length(test_data)
            test_data(i).data = generate_all_signals(test_data(i).data, ...
                strategies, strategy_keys);
        end
        train_test_result = run_full_backtest(test_data, strategies, strategy_keys, ...
            strategy_names, cfg.HOLD_DAYS, include_costs, false);
    else
        fprintf('  [警告] 测试集为空，跳过\n');
    end
end

if walk_forward
    fprintf('\n--- Walk-Forward 滚动窗口验证 ---\n');
    wf_result = walk_forward_validation(stock_data, strategies, strategy_keys, ...
        strategy_names, cfg.HOLD_DAYS, cfg.WALK_FORWARD_WINDOW, ...
        cfg.WALK_FORWARD_STEP, true);
    if ~isempty(wf_result)
        wf_path = fullfile(cfg.RESULT_DIR, 'walk_forward_summary.csv');
        writetable(wf_result, wf_path, 'Encoding', 'UTF-8');
        fprintf('\nWalk-Forward 结果已保存: %s\n', wf_path);
    end
end

% 打印汇总表
fprintf('\n============================================================\n');
fprintf('回测结果汇总表 (全样本)\n');
fprintf('============================================================\n');

for s = 1:length(strategy_names)
    name = strategy_names{s};
    sub = summary_table(strcmp(summary_table.策略名称, name), :);
    fprintf('\n--- %s ---\n', name);
    fprintf('%-8s %-8s %-8s %-10s %-8s %-8s %-8s\n', ...
        '持有天', '交易次', '胜率>0', '平均收益', '夏普', '最大回撤', '盈亏比');
    for r = 1:height(sub)
        fprintf('%-8d %-8d %-7.1f%% %-9.2f%% %-7.2f %-7.1f%% %-7.2f\n', ...
            sub.持有天数(r), sub.交易次数(r), sub.胜率gt0pct(r), ...
            sub.平均收益率pct(r), sub.夏普比率(r), sub.最大回撤pct(r), sub.盈亏比(r));
    end
end

% 保存结果
fprintf('\n保存回测结果...\n');
save_results(summary_table, cfg.RESULT_DIR);
try
    save_results_excel(summary_table, cfg.RESULT_DIR);
catch ME
    fprintf('  Excel 保存失败: %s\n', ME.message);
end

% ==========================================
% 阶段 5：可视化分析
% ==========================================
fprintf('\n============================================================\n');
fprintf('阶段 5/5: 可视化分析\n');
fprintf('============================================================\n');

run_all_visualizations(summary_table, stock_data, strategies, ...
    strategy_keys, strategy_names, cfg.HOLD_DAYS);

% ==========================================
% 完成
% ==========================================
total_elapsed = toc(start_time);
fprintf('\n============================================================\n');
fprintf('全部完成！总耗时 %.1f 秒 (%.1f 分钟)\n', total_elapsed, total_elapsed / 60);
fprintf('结果保存于: %s\n', cfg.RESULT_DIR);
fprintf('============================================================\n');

end


function result = ternary(condition, true_val, false_val)
% 简化版三元运算符
if condition
    result = true_val;
else
    result = false_val;
end
end
