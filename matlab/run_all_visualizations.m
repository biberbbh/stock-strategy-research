function run_all_visualizations(summary_table, stock_data, strategies, ...
    strategy_keys, strategy_names, hold_days_list)
% RUN_ALL_VISUALIZATIONS Generate all visualization charts

cfg = config();
result_dir = cfg.RESULT_DIR;
if ~isfolder(result_dir), mkdir(result_dir); end

% Get column names from table
colnames = summary_table.Properties.VariableNames;
strat_col = colnames{1};
hold_col = colnames{2};

fprintf('\nGenerating visualizations...\n');

% 1. Hold period comparison
fprintf('[1/4] Hold period comparison\n');
plot_hold_period_comparison(summary_table, strat_col, hold_col, result_dir);

% 2. Heatmap - win rate
fprintf('[2/4] Heatmap (win rate)\n');
% Column 4 is always win rate >0 pct
wr_col = colnames{4};
plot_heatmap(summary_table, strat_col, hold_col, wr_col, 'Win Rate (>0%)', result_dir);

% 3. Heatmap - avg return
fprintf('[3/4] Heatmap (avg return)\n');
% Find avg return column (column 5 is always avg return pct)
ret_col = colnames{5};
plot_heatmap(summary_table, strat_col, hold_col, ret_col, 'Avg Return (%)', result_dir);

% 4. Significance forest
fprintf('[4/4] Significance forest plot\n');
% Check if CI columns exist (columns 18 and 19)
if length(colnames) >= 19
    plot_significance_forest(summary_table, strat_col, hold_col, result_dir);
end

% Extra: Sensitivity analysis
fprintf('[Extra] Sensitivity analysis\n');
plot_parameter_sensitivity(summary_table, strat_col, hold_col, result_dir);

fprintf('Visualizations saved to: %s\n', result_dir);
end


function plot_hold_period_comparison(summary_table, strat_col, hold_col, result_dir)
strategy_names = unique(summary_table.(strat_col), 'stable');
n_strategies = length(strategy_names);
colors = lines(n_strategies);

% Find metric columns by position/name
colnames = summary_table.Properties.VariableNames;
avg_ret_col = colnames{5};  % avg return pct
win_rate_col = colnames{4}; % win rate >0 pct
sharpe_col = colnames{11};  % sharpe ratio
dd_col = colnames{12};      % max drawdown pct

fig = figure('Position', [100, 100, 1600, 1200], 'Visible', 'off');

subplot(2, 2, 1); hold on;
for s = 1:n_strategies
    rows = strcmp(summary_table.(strat_col), strategy_names{s});
    sub = summary_table(rows, :);
    [hd, idx] = sort(sub.(hold_col));
    plot(hd, sub.(avg_ret_col)(idx), '-o', 'LineWidth', 2, 'Color', colors(s,:), ...
        'DisplayName', strategy_names{s});
end
yline(0, '--', 'Color', [0.5 0.5 0.5]); xlabel('Hold Days'); ylabel('Avg Return (%)');
title('Avg Return vs Hold Period'); legend('Location', 'best'); grid on;

subplot(2, 2, 2); hold on;
for s = 1:n_strategies
    rows = strcmp(summary_table.(strat_col), strategy_names{s});
    sub = summary_table(rows, :);
    [hd, idx] = sort(sub.(hold_col));
    plot(hd, sub.(win_rate_col)(idx), '-s', 'LineWidth', 2, 'Color', colors(s,:), ...
        'DisplayName', strategy_names{s});
end
yline(50, '--', 'Color', [0.5 0.5 0.5], 'DisplayName', '50% Baseline');
xlabel('Hold Days'); ylabel('Win Rate (%)'); title('Win Rate vs Hold Period');
legend('Location', 'best'); grid on;

subplot(2, 2, 3); hold on;
for s = 1:n_strategies
    rows = strcmp(summary_table.(strat_col), strategy_names{s});
    sub = summary_table(rows, :);
    [hd, idx] = sort(sub.(hold_col));
    plot(hd, sub.(sharpe_col)(idx), '-^', 'LineWidth', 2, 'Color', colors(s,:), ...
        'DisplayName', strategy_names{s});
end
yline(0, '--', 'Color', [0.5 0.5 0.5]); xlabel('Hold Days'); ylabel('Sharpe Ratio');
title('Sharpe Ratio vs Hold Period'); legend('Location', 'best'); grid on;

subplot(2, 2, 4); hold on;
for s = 1:n_strategies
    rows = strcmp(summary_table.(strat_col), strategy_names{s});
    sub = summary_table(rows, :);
    [hd, idx] = sort(sub.(hold_col));
    plot(hd, sub.(dd_col)(idx), '-D', 'LineWidth', 2, 'Color', colors(s,:), ...
        'DisplayName', strategy_names{s});
end
xlabel('Hold Days'); ylabel('Max Drawdown (%)'); title('Max Drawdown vs Hold Period');
legend('Location', 'best'); grid on;

exportgraphics(fig, fullfile(result_dir, 'hold_period_comparison.png'), 'Resolution', 150);
close(fig);
fprintf('  Saved: hold_period_comparison.png\n');
end


function plot_heatmap(summary_table, strat_col, hold_col, metric_col, title_str, result_dir)
strategy_names = unique(summary_table.(strat_col), 'stable');
hold_days = unique(summary_table.(hold_col));
n_strat = length(strategy_names);
n_hold = length(hold_days);
pivot = NaN(n_strat, n_hold);
for s = 1:n_strat
    for h = 1:n_hold
        rows = strcmp(summary_table.(strat_col), strategy_names{s}) & ...
               (summary_table.(hold_col) == hold_days(h));
        if any(rows), pivot(s, h) = summary_table.(metric_col)(rows); end
    end
end
fig = figure('Position', [100, 100, 800, 400], 'Visible', 'off');
imagesc(pivot); colormap(jet); colorbar;
for s = 1:n_strat
    for h = 1:n_hold
        if ~isnan(pivot(s, h))
            text(h, s, sprintf('%.1f', pivot(s, h)), ...
                'HorizontalAlignment', 'center', 'FontSize', 9);
        end
    end
end
xticks(1:n_hold); xticklabels(cellstr(num2str(hold_days(:))));
yticks(1:n_strat); yticklabels(strategy_names);
xlabel('Hold Days'); title(sprintf('Strategy x Hold Period - %s', title_str));
safe_name = strrep(strrep(strrep(strrep(title_str, '>', 'gt'), '(', ''), ')', ''), '%', 'pct');
safe_name = strrep(safe_name, ' ', '_');
exportgraphics(fig, fullfile(result_dir, sprintf('heatmap_%s.png', safe_name)), 'Resolution', 150);
close(fig);
fprintf('  Saved: heatmap_%s.png\n', safe_name);
end


function plot_parameter_sensitivity(summary_table, strat_col, hold_col, result_dir)
strategy_names = unique(summary_table.(strat_col), 'stable');
colnames = summary_table.Properties.VariableNames;

% Use known column positions
metric_cols = {colnames{4}, colnames{5}, colnames{11}};  % win rate, avg ret, sharpe
metric_labels = {'Win Rate (>0%)', 'Avg Return (%)', 'Sharpe Ratio'};

n_metrics = length(metric_cols);
colors = lines(length(strategy_names));
fig = figure('Position', [100, 100, 600*n_metrics, 500], 'Visible', 'off');
for m = 1:n_metrics
    subplot(1, n_metrics, m); hold on;
    for s = 1:length(strategy_names)
        rows = strcmp(summary_table.(strat_col), strategy_names{s});
        tbl_sub = summary_table(rows, :);
        [xv, idx] = sort(tbl_sub.(hold_col));
        plot(xv, tbl_sub.(metric_cols{m})(idx), '-o', 'LineWidth', 2, ...
            'Color', colors(s,:), 'DisplayName', strategy_names{s});
    end
    xlabel('Hold Days'); ylabel(metric_labels{m});
    title(sprintf('%s vs Hold Days', metric_labels{m}));
    legend('Location', 'best'); grid on;
end
exportgraphics(fig, fullfile(result_dir, 'sensitivity_hold_days.png'), 'Resolution', 150);
close(fig);
fprintf('  Saved: sensitivity_hold_days.png\n');
end


function plot_significance_forest(summary_table, strat_col, hold_col, result_dir)
colnames = summary_table.Properties.VariableNames;

% Find needed columns by known positions
ci_lower_col = colnames{18};  % CI lower
ci_upper_col = colnames{19};  % CI upper
pval_col = colnames{17};       % p-value
avg_ret_col = colnames{5};     % avg return
win_rate_col = colnames{4};    % win rate

% Select 60-day hold data
hold_vals = unique(summary_table.(hold_col));
target_hold = max(hold_vals);  % use max hold days
plot_rows = summary_table.(hold_col) == target_hold;
plot_df = summary_table(plot_rows, :);
strategies = plot_df.(strat_col);
means = plot_df.(avg_ret_col);
ci_lower = plot_df.(ci_lower_col);
ci_upper = plot_df.(ci_upper_col);
win_rates = plot_df.(win_rate_col);
p_values = plot_df.(pval_col);
n_strat = length(strategies);

fig = figure('Position', [100, 100, 1400, 500], 'Visible', 'off');

subplot(1, 2, 1); hold on;
for s = 1:n_strat
    plot([ci_lower(s) ci_upper(s)], [s s], 'Color', [0.2 0.4 0.7], 'LineWidth', 2);
    plot(means(s), s, 'o', 'Color', [0.2 0.4 0.7], ...
        'MarkerFaceColor', [0.2 0.4 0.7], 'MarkerSize', 8);
end
xline(0, '--', 'Color', 'red', 'LineWidth', 1);
yticks(1:n_strat); yticklabels(strategies); xlabel('Avg Return (%)');
title(sprintf('%d-day Hold - Bootstrap 95%% CI', target_hold)); grid on;

subplot(1, 2, 2); hold on;
for s = 1:n_strat
    if p_values(s) < 0.05, clr = [0.2 0.7 0.2]; else, clr = [0.6 0.6 0.6]; end
    barh(s, win_rates(s), 0.8, 'FaceColor', clr);
end
xline(50, '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 1.5, ...
    'DisplayName', 'Random Baseline 50%');
yticks(1:n_strat); yticklabels(strategies); xlabel('Win Rate (>0%)');
title(sprintf('%d-day Hold - Win Rate vs Random\n(Green = significant, p<0.05)', target_hold));
legend('Location', 'best'); grid on;

for s = 1:n_strat
    p = p_values(s);
    if p < 0.001, sig_mark = '***';
    elseif p < 0.01, sig_mark = '**';
    elseif p < 0.05, sig_mark = '*';
    else, sig_mark = '';
    end
    if ~isempty(sig_mark)
        text(win_rates(s) + 1, s, sig_mark, 'VerticalAlignment', 'middle', ...
            'FontSize', 12, 'Color', [0 0.4 0]);
    end
end

exportgraphics(fig, fullfile(result_dir, 'significance_forest.png'), 'Resolution', 150);
close(fig);
fprintf('  Saved: significance_forest.png\n');
end
