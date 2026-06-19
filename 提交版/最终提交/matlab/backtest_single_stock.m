function trades_struct = backtest_single_stock(tbl, signal_col, hold_days, include_costs)
% BACKTEST_SINGLE_STOCK 对单只股票按信号列进行回测

if nargin < 4, include_costs = true; end

if ~any(strcmp(tbl.Properties.VariableNames, signal_col))
    trades_struct = struct([]);
    return;
end

tbl = sortrows(tbl, 'day');
n = height(tbl);
signal_indices = find(tbl.(signal_col) == 1);

trades_struct = struct('stock_code', {}, 'signal_idx', {}, 'buy_idx', {}, ...
    'sell_idx', {}, 'buy_date', {}, 'sell_date', {}, ...
    'buy_price', {}, 'sell_price', {}, ...
    'gross_return_pct', {}, 'cost_pct', {}, 'net_return_pct', {});

if iscell(tbl.stock_code)
    stock_code = char(tbl.stock_code{1});
else
    stock_code = char(tbl.stock_code(1));
end

trade_count = 0;
for s = 1:length(signal_indices)
    sig_idx = signal_indices(s);
    buy_idx = sig_idx + 1;
    sell_idx = buy_idx + hold_days;
    if buy_idx > n || sell_idx > n, continue; end
    buy_price = tbl.close(buy_idx);
    sell_price = tbl.close(sell_idx);
    if isnan(buy_price) || isnan(sell_price), continue; end
    if buy_price <= 0 || sell_price <= 0, continue; end

    gross_ret_pct = (sell_price - buy_price) / buy_price * 100;
    if include_costs
        cost_pct = calculate_transaction_cost(buy_price, sell_price);
        net_ret_pct = gross_ret_pct - cost_pct;
    else
        cost_pct = 0;
        net_ret_pct = gross_ret_pct;
    end

    trade_count = trade_count + 1;
    trades_struct(trade_count).stock_code = stock_code;
    trades_struct(trade_count).signal_idx = sig_idx;
    trades_struct(trade_count).buy_idx = buy_idx;
    trades_struct(trade_count).sell_idx = sell_idx;
    trades_struct(trade_count).buy_date = tbl.day(buy_idx);
    trades_struct(trade_count).sell_date = tbl.day(sell_idx);
    trades_struct(trade_count).buy_price = buy_price;
    trades_struct(trade_count).sell_price = sell_price;
    trades_struct(trade_count).gross_return_pct = round(gross_ret_pct, 4);
    trades_struct(trade_count).cost_pct = round(cost_pct, 4);
    trades_struct(trade_count).net_return_pct = round(net_ret_pct, 4);
end
end


function total_cost_pct = calculate_transaction_cost(buy_price, sell_price, ...
    commission_rate, stamp_tax_rate, slippage_bps, min_commission)
% 计算单笔交易成本（百分比）
if nargin < 3 || isempty(commission_rate)
    cfg = config(); commission_rate = cfg.COMMISSION_RATE;
end
if nargin < 4 || isempty(stamp_tax_rate)
    cfg = config(); stamp_tax_rate = cfg.STAMP_TAX_RATE;
end
if nargin < 5 || isempty(slippage_bps)
    cfg = config(); slippage_bps = cfg.SLIPPAGE_BPS;
end
if nargin < 6 || isempty(min_commission)
    cfg = config(); min_commission = cfg.MIN_COMMISSION;
end

slippage_pct = slippage_bps / 10000 * 2;
commission_pct = commission_rate * 2;
stamp_pct = stamp_tax_rate;
total_cost_pct = (slippage_pct + commission_pct + stamp_pct) * 100;

est_commission = max(buy_price * commission_rate, min_commission / 10000);
actual_commission_pct = (est_commission / buy_price) * 2 * 100;
if actual_commission_pct > (commission_rate * 2 * 100)
    total_cost_pct = (slippage_pct + actual_commission_pct / 100 + stamp_pct) * 100;
end
end
