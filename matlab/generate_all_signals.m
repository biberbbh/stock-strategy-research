function tbl = generate_all_signals(tbl, strategies, strategy_keys)
% GENERATE_ALL_SIGNALS 生成所有策略的买入信号

if nargin < 2 || isempty(strategies)
    [strategies, strategy_keys, ~] = get_all_strategies();
end

for s = 1:length(strategies)
    key = strategy_keys{s};
    func = strategies{s};
    sig_col = sprintf('signal_%s', key);
    try
        tbl.(sig_col) = double(func(tbl));
    catch ME
        warning('策略 %s 生成失败: %s', key, ME.message);
        tbl.(sig_col) = zeros(height(tbl), 1);
    end
end
end
