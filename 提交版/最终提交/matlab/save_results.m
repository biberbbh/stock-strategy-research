function filepath = save_results(summary_table, result_dir)
% SAVE_RESULTS 将回测汇总表保存为 CSV

if nargin < 2
    cfg = config();
    result_dir = cfg.RESULT_DIR;
end
if ~isfolder(result_dir), mkdir(result_dir); end

filepath = fullfile(result_dir, 'backtest_summary.csv');
writetable(summary_table, filepath, 'Encoding', 'UTF-8');
fprintf('结果表已保存: %s\n', filepath);
end
