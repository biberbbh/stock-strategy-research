function all_trades = backtest_all_stocks(stock_data, signal_col, hold_days, ...
    include_costs, verbose)
% BACKTEST_ALL_STOCKS 对所有股票进行批量回测

if nargin < 5, verbose = false; end
if nargin < 4, include_costs = true; end

all_trades = struct([]);
total = length(stock_data);

for i = 1:total
    trades = backtest_single_stock(stock_data(i).data, signal_col, hold_days, include_costs);
    if ~isempty(fieldnames(trades))
        if isempty(all_trades)
            all_trades = trades;
        else
            all_trades = [all_trades, trades]; %#ok<AGROW>
        end
    end
    if verbose && mod(i, 500) == 0
        fprintf('  回测进度: %d/%d\n', i, total);
    end
end

if verbose && ~isempty(all_trades)
    fprintf('  %s 持有 %d 天: 共 %d 笔交易\n', signal_col, hold_days, length(all_trades));
end
end
