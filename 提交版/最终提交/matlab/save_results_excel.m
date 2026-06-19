function filepath = save_results_excel(summary_table, result_dir)
% SAVE_RESULTS_EXCEL Save results to Excel format

if nargin < 2
    cfg = config();
    result_dir = cfg.RESULT_DIR;
end
if ~isfolder(result_dir), mkdir(result_dir); end

filepath = fullfile(result_dir, 'backtest_results.xlsx');

% Use variable names that are stored in the table
colnames = summary_table.Properties.VariableNames;
strat_col = colnames{1};  % Strategy name column
hold_col = colnames{2};   % Hold days column

% Full summary sheet
writetable(summary_table, filepath, 'Sheet', 'Summary');

% By strategy
strategy_names = unique(summary_table.(strat_col), 'stable');
for s = 1:length(strategy_names)
    name = strategy_names{s};
    rows = strcmp(summary_table.(strat_col), name);
    sub = summary_table(rows, :);
    % Use safe sheet name (max 31 chars, ASCII only)
    safe_name = matlab.lang.makeValidName(name);
    if length(safe_name) > 31, safe_name = safe_name(1:31); end
    writetable(sub, filepath, 'Sheet', safe_name);
end

% By hold days
hold_days_list = unique(summary_table.(hold_col));
for h = 1:length(hold_days_list)
    hold_days = hold_days_list(h);
    rows = summary_table.(hold_col) == hold_days;
    sub = summary_table(rows, :);
    sheet_name = sprintf('Hold%d', hold_days);
    writetable(sub, filepath, 'Sheet', sheet_name);
end

fprintf('Excel results saved: %s\n', filepath);
end
