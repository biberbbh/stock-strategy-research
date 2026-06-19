function run_all_visualizations(summary_table, stock_data, strategies, ...
    strategy_keys, strategy_names, hold_days_list)
% RUN_ALL_VISUALIZATIONS 运行所有可视化分析
%
%   参数:
%       summary_table:  回测汇总表 (table)
%       stock_data:     股票数据 struct 数组
%       strategies:     策略函数句柄 cell 数组
%       strategy_keys:  策略键名 cell 数组
%       strategy_names: 策略名称 cell 数组
%       hold_days_list: 持有天数列表

cfg = config();
result_dir = cfg.RESULT_DIR;
if ~isfolder(result_dir), mkdir(result_dir); end

fprintf('\n============================================================\n');
fprintf('生成可视化图表...\n');
fprintf('============================================================\n');

% 1. 持有周期对比折线图
fprintf('\n[1/4] 持有周期对比图\n');
plot_hold_period_comparison(summary_table, result_dir);

% 2. 热力图 - 胜率
fprintf('\n[2/4] 热力图 (胜率)\n');
plot_heatmap(summary_table, '胜率gt0pct', '胜率(>0%)', result_dir);

% 3. 热力图 - 平均收益率
fprintf('\n[3/4] 热力图 (平均收益率)\n');
plot_heatmap(summary_table, '平均收益率pct', '平均收益率(%)', result_dir);

% 4. 统计显著性可视化
if any(strcmp(summary_table.Properties.VariableNames, '收益CI下界'))
    fprintf('\n[4/4] 统计显著性分析\n');
    plot_significance_forest(summary_table, result_dir);
end

% 额外：参数敏感性分析
fprintf('\n[额外] 参数敏感性分析\n');
plot_parameter_sensitivity(summary_table, result_dir);

fprintf('\n可视化完成。图表保存于: %s\n', result_dir);
end


% ============================================================
% 图表 1：持有周期对比折线图
% ============================================================

function plot_hold_period_comparison(summary_table, result_dir)
% 绘制不同持有天数下的表现趋势折线图

strategy_names = unique(summary_table.策略名称, 'stable');
n_strategies = length(strategy_names);

figure('Position', [100, 100, 1600, 1200], 'Visible', 'off');

% 子图 1：平均收益率
subplot(2, 2, 1);
hold on;
colors = lines(n_strategies);
for s = 1:n_strategies
    name = strategy_names{s};
    rows = strcmp(summary_table.策略名称, name);
    sub = summary_table(rows, :);
    [hold_days, sort_idx] = sort(sub.持有天数);
    avg_ret = sub.平均收益率pct(sort_idx);
    plot(hold_days, avg_ret, '-o', 'LineWidth', 2, 'Color', colors(s,:), ...
        'DisplayName', name);
end
yline(0, '--', 'Color', [0.5, 0.5, 0.5], 'LineWidth', 0.8);
xlabel('持有天数', 'FontSize', 12);
ylabel('平均收益率 (%)', 'FontSize', 12);
title('平均收益率 vs 持有天数', 'FontSize', 14);
legend('Location', 'best', 'FontSize', 9);
grid on;

% 子图 2：胜率 (>0)
subplot(2, 2, 2);
hold on;
for s = 1:n_strategies
    name = strategy_names{s};
    rows = strcmp(summary_table.策略名称, name);
    sub = summary_table(rows, :);
    [hold_days, sort_idx] = sort(sub.持有天数);
    win_rate = sub.胜率gt0pct(sort_idx);
    plot(hold_days, win_rate, '-s', 'LineWidth', 2, 'Color', colors(s,:), ...
        'DisplayName', name);
end
yline(50, '--', 'Color', [0.5, 0.5, 0.5], 'LineWidth', 0.8, 'DisplayName', '50% 基准');
xlabel('持有天数', 'FontSize', 12);
ylabel('胜率 (>0%)', 'FontSize', 12);
title('胜率 vs 持有天数', 'FontSize', 14);
legend('Location', 'best', 'FontSize', 9);
grid on;

% 子图 3：夏普比率
if any(strcmp(summary_table.Properties.VariableNames, '夏普比率'))
    subplot(2, 2, 3);
    hold on;
    for s = 1:n_strategies
        name = strategy_names{s};
        rows = strcmp(summary_table.策略名称, name);
        sub = summary_table(rows, :);
        [hold_days, sort_idx] = sort(sub.持有天数);
        sharpe = sub.夏普比率(sort_idx);
        plot(hold_days, sharpe, '-^', 'LineWidth', 2, 'Color', colors(s,:), ...
            'DisplayName', name);
    end
    yline(0, '--', 'Color', [0.5, 0.5, 0.5], 'LineWidth', 0.8);
    xlabel('持有天数', 'FontSize', 12);
    ylabel('夏普比率', 'FontSize', 12);
    title('夏普比率 vs 持有天数', 'FontSize', 14);
    legend('Location', 'best', 'FontSize', 9);
    grid on;
end

% 子图 4：最大回撤
if any(strcmp(summary_table.Properties.VariableNames, '最大回撤pct'))
    subplot(2, 2, 4);
    hold on;
    for s = 1:n_strategies
        name = strategy_names{s};
        rows = strcmp(summary_table.策略名称, name);
        sub = summary_table(rows, :);
        [hold_days, sort_idx] = sort(sub.持有天数);
        dd = sub.最大回撤pct(sort_idx);
        plot(hold_days, dd, '-D', 'LineWidth', 2, 'Color', colors(s,:), ...
            'DisplayName', name);
    end
    xlabel('持有天数', 'FontSize', 12);
    ylabel('最大回撤 (%)', 'FontSize', 12);
    title('最大回撤 vs 持有天数', 'FontSize', 14);
    legend('Location', 'best', 'FontSize', 9);
    grid on;
end

filepath = fullfile(result_dir, 'hold_period_comparison.png');
exportgraphics(gcf, filepath, 'Resolution', 150);
close(gcf);
fprintf('  已保存: %s\n', filepath);
end


% ============================================================
% 图表 2：热力图（策略 × 持有天数）
% ============================================================

function plot_heatmap(summary_table, col_name, title_str, result_dir)
% 绘制策略 × 持有天数的热力图

strategy_names = unique(summary_table.策略名称, 'stable');
hold_days = unique(summary_table.持有天数);

% 构建透视矩阵
n_strat = length(strategy_names);
n_hold = length(hold_days);
pivot = NaN(n_strat, n_hold);

for s = 1:n_strat
    for h = 1:n_hold
        rows = strcmp(summary_table.策略名称, strategy_names{s}) & ...
               (summary_table.持有天数 == hold_days(h));
        if any(rows)
            pivot(s, h) = summary_table.(col_name)(rows);
        end
    end
end

figure('Position', [100, 100, 800, 400], 'Visible', 'off');
imagesc(pivot);
colormap(jet);
colorbar;

% 标注数值
for s = 1:n_strat
    for h = 1:n_hold
        val = pivot(s, h);
        if ~isnan(val)
            text(h, s, sprintf('%.1f', val), 'HorizontalAlignment', 'center', ...
                'FontSize', 9, 'Color', 'k');
        end
    end
end

xticks(1:n_hold);
xticklabels(cellstr(num2str(hold_days(:))));
yticks(1:n_strat);
yticklabels(strategy_names);
xlabel('持有天数', 'FontSize', 12);
title(sprintf('策略 × 持有天数 — %s 热力图', title_str), 'FontSize', 14);

% 保存
safe_name = strrep(strrep(strrep(title_str, '>', 'gt'), '(', ''), ')', '');
safe_name = strrep(safe_name, '%', 'pct');
filepath = fullfile(result_dir, sprintf('heatmap_%s.png', safe_name));
exportgraphics(gcf, filepath, 'Resolution', 150);
close(gcf);
fprintf('  已保存: %s\n', filepath);
end


% ============================================================
% 图表 3：参数敏感性分析
% ============================================================

function plot_parameter_sensitivity(summary_table, result_dir)
% 绘制参数敏感性分析图

param_name = '持有天数';
metrics = {'胜率gt0pct', '平均收益率pct'};
metric_labels = {'胜率 (>0%)', '平均收益率 (%)'};
% 检查是否有额外列
if any(strcmp(summary_table.Properties.VariableNames, '夏普比率'))
    metrics{end+1} = '夏普比率';
    metric_labels{end+1} = '夏普比率';
end
if any(strcmp(summary_table.Properties.VariableNames, '盈亏比'))
    metrics{end+1} = '盈亏比';
    metric_labels{end+1} = '盈亏比';
end

strategy_names = unique(summary_table.策略名称, 'stable');
n_metrics = length(metrics);
colors = lines(length(strategy_names));

figure('Position', [100, 100, 600 * n_metrics, 500], 'Visible', 'off');

for m = 1:n_metrics
    subplot(1, n_metrics, m);
    hold on;
    for s = 1:length(strategy_names)
        name = strategy_names{s};
        rows = strcmp(summary_table.策略名称, name);
        sub = summary_table(rows, :);
        [x_vals, sort_idx] = sort(sub.(param_name));
        y_vals = sub.(metrics{m})(sort_idx);
        plot(x_vals, y_vals, '-o', 'LineWidth', 2, 'Color', colors(s,:), ...
            'DisplayName', name);
    end
    xlabel(param_name, 'FontSize', 11);
    ylabel(metric_labels{m}, 'FontSize', 11);
    title(sprintf('%s 随 %s 变化', metric_labels{m}, param_name), 'FontSize', 12);
    legend('Location', 'best', 'FontSize', 8);
    grid on;
end

filepath = fullfile(result_dir, 'sensitivity_持有天数.png');
exportgraphics(gcf, filepath, 'Resolution', 150);
close(gcf);
fprintf('  已保存: %s\n', filepath);
end


% ============================================================
% 图表 4：统计显著性可视化 (森林图)
% ============================================================

function plot_significance_forest(summary_table, result_dir)
% 绘制各策略的置信区间森林图

if ~any(strcmp(summary_table.Properties.VariableNames, '收益CI下界'))
    fprintf('  [跳过] 无置信区间数据\n');
    return;
end

% 选择 60 天持有期数据
if any(strcmp(summary_table.Properties.VariableNames, '持有天数'))
    plot_rows = summary_table.持有天数 == 60;
    plot_df = summary_table(plot_rows, :);
else
    plot_df = summary_table;
end

if isempty(plot_df), return; end

figure('Position', [100, 100, 1400, 500], 'Visible', 'off');

strategies = plot_df.策略名称;
means = plot_df.平均收益率pct;
ci_lower = plot_df.收益CI下界;
ci_upper = plot_df.收益CI上界;
n_strat = length(strategies);

% 子图 1: 置信区间森林图
subplot(1, 2, 1);
hold on;
y_pos = 1:n_strat;
for s = 1:n_strat
    plot([ci_lower(s), ci_upper(s)], [y_pos(s), y_pos(s)], ...
        'Color', [0.2, 0.4, 0.7], 'LineWidth', 2);
    plot(means(s), y_pos(s), 'o', 'Color', [0.2, 0.4, 0.7], ...
        'MarkerFaceColor', [0.2, 0.4, 0.7], 'MarkerSize', 8);
end
xline(0, '--', 'Color', 'red', 'LineWidth', 1, 'Alpha', 0.7);
yticks(y_pos);
yticklabels(strategies);
xlabel('平均收益率 (%)', 'FontSize', 12);
title('60天持有 — 平均收益率 95% Bootstrap CI', 'FontSize', 13);
grid on;

% 子图 2: 胜率 vs 随机基准
subplot(1, 2, 2);
hold on;
win_rates = plot_df.胜率gt0pct;
p_values = plot_df.胜率p值;

colors_bar = cell(n_strat, 1);
for s = 1:n_strat
    if p_values(s) < 0.05
        colors_bar{s} = [0.2, 0.7, 0.2];  % green
    else
        colors_bar{s} = [0.6, 0.6, 0.6];  % gray
    end
end

bh = barh(y_pos, win_rates, 0.8);
for s = 1:n_strat
    bh.FaceColor = 'flat';
    bh.CData(s, :) = colors_bar{s};
end
xline(50, '--', 'Color', [0.5, 0.5, 0.5], 'LineWidth', 1.5, ...
    'DisplayName', '随机基准 50%');
yticks(y_pos);
yticklabels(strategies);
xlabel('胜率 (>0%)', 'FontSize', 12);
title('60天持有 — 胜率 vs 随机基准\n(绿色 = 显著优于随机, p<0.05)', 'FontSize', 13);
legend('Location', 'best', 'FontSize', 9);
grid on;

% 显著性标注
for s = 1:n_strat
    p = p_values(s);
    if p < 0.001
        sig_mark = '***';
    elseif p < 0.01
        sig_mark = '**';
    elseif p < 0.05
        sig_mark = '*';
    else
        sig_mark = '';
    end
    if ~isempty(sig_mark)
        text(win_rates(s) + 1, y_pos(s), sig_mark, 'VerticalAlignment', 'middle', ...
            'FontSize', 12, 'Color', [0, 0.4, 0]);
    end
end

filepath = fullfile(result_dir, 'significance_forest.png');
exportgraphics(gcf, filepath, 'Resolution', 150);
close(gcf);
fprintf('  已保存: %s\n', filepath);
end


% ============================================================
% 结果保存
% ============================================================

function filepath = save_results(summary_table, result_dir)
% 将回测汇总表保存为 CSV

if nargin < 2
    cfg = config();
    result_dir = cfg.RESULT_DIR;
end
if ~isfolder(result_dir), mkdir(result_dir); end

filepath = fullfile(result_dir, 'backtest_summary.csv');
writetable(summary_table, filepath, 'Encoding', 'UTF-8');
fprintf('结果表已保存: %s\n', filepath);
end


function filepath = save_results_excel(summary_table, result_dir)
% 保存为 Excel 格式（包含多个工作表）

if nargin < 2
    cfg = config();
    result_dir = cfg.RESULT_DIR;
end
if ~isfolder(result_dir), mkdir(result_dir); end

filepath = fullfile(result_dir, 'backtest_results.xlsx');

% 完整汇总表
writetable(summary_table, filepath, 'Sheet', '汇总表');

% 按策略分表
strategy_names = unique(summary_table.策略名称, 'stable');
for s = 1:length(strategy_names)
    name = strategy_names{s};
    rows = strcmp(summary_table.策略名称, name);
    sub = summary_table(rows, :);
    % Sheet 名称截断到 31 字符
    sheet_name = name;
    if length(sheet_name) > 31, sheet_name = sheet_name(1:31); end
    writetable(sub, filepath, 'Sheet', sheet_name);
end

% 按持有天数分表
hold_days_list = unique(summary_table.持有天数);
for h = 1:length(hold_days_list)
    hold_days = hold_days_list(h);
    rows = summary_table.持有天数 == hold_days;
    sub = summary_table(rows, :);
    sheet_name = sprintf('持有%d天', hold_days);
    writetable(sub, filepath, 'Sheet', sheet_name);
end

fprintf('Excel 结果已保存: %s\n', filepath);
end
