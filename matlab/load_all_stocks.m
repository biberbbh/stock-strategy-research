function [stock_data, stock_codes] = load_all_stocks(data_dir, max_stocks, verbose)
% LOAD_ALL_STOCKS 批量加载 data_dir 下所有股票 CSV 文件

if nargin < 3, verbose = true; end
if nargin < 2, max_stocks = []; end

if ~isfolder(data_dir)
    error('数据目录不存在: %s', data_dir);
end

csv_files = dir(fullfile(data_dir, '*.csv'));
if isempty(csv_files)
    error('在 %s 中未找到 CSV 文件', data_dir);
end

if verbose
    fprintf('找到 %d 个 CSV 文件\n', length(csv_files));
end

if ~isempty(max_stocks)
    csv_files = csv_files(1:min(max_stocks, length(csv_files)));
    if verbose, fprintf('限制加载前 %d 只股票\n', max_stocks); end
end

n_files = length(csv_files);
stock_data = struct('code', cell(n_files, 1), 'data', cell(n_files, 1));
stock_codes = strings(n_files, 1);
valid_count = 0;
fail_count = 0;
skip_count = 0;

for i = 1:n_files
    filepath = fullfile(csv_files(i).folder, csv_files(i).name);
    try
        tbl = load_single_stock(filepath);
    catch ME
        if verbose
            fprintf('  [警告] 读取失败: %s — %s\n', csv_files(i).name, ME.message);
        end
        fail_count = fail_count + 1;
        continue;
    end
    if isempty(tbl) || height(tbl) < 30
        skip_count = skip_count + 1;
        continue;
    end
    valid_count = valid_count + 1;
    if iscell(tbl.stock_code)
        stock_data(valid_count).code = char(tbl.stock_code{1});
    else
        stock_data(valid_count).code = char(tbl.stock_code(1));
    end
    stock_data(valid_count).data = tbl;
    stock_codes(valid_count) = string(stock_data(valid_count).code);

    if verbose && mod(i, 500) == 0
        fprintf('  已处理 %d/%d 个文件...\n', i, n_files);
    end
end

stock_data = stock_data(1:valid_count);
stock_codes = stock_codes(1:valid_count);

if verbose
    fprintf('加载完成: 成功 %d 只, 数据不足/跳过 %d 只, 失败 %d 只\n', ...
        valid_count, skip_count, fail_count);
end
end


function tbl = load_single_stock(filepath)
% 读取单只股票的 CSV 文件
try
    tbl = readtable(filepath, 'VariableNamingRule', 'preserve', 'TextType', 'string');
catch
    tbl = [];
    return;
end
if isempty(tbl) || height(tbl) == 0, return; end

colnames = tbl.Properties.VariableNames;
required_cols = {'day', 'close', 'open', 'high', 'low', 'volume'};
for c = 1:length(required_cols)
    if ~any(strcmp(colnames, required_cols{c}))
        warning('缺少字段: %s', required_cols{c});
        tbl = []; return;
    end
end
if ~any(strcmp(colnames, 'hsl'))
    warning('缺少 hsl 字段');
    tbl = []; return;
end

% 日期处理
if iscell(tbl.day), tbl.day = string(tbl.day); end
try
    tbl.day = datetime(tbl.day, 'InputFormat', 'yyyy-MM-dd');
catch
    tbl.day = datetime(tbl.day);
end
tbl(isnat(tbl.day), :) = [];
tbl = sortrows(tbl, 'day');

% 数值列处理
numeric_cols = {'open', 'close', 'high', 'low', 'volume', 'amount', 'zf', 'zdf', 'zde', 'hsl'};
for c = 1:length(numeric_cols)
    col = numeric_cols{c};
    if any(strcmp(colnames, col))
        if iscell(tbl.(col)) || isstring(tbl.(col))
            tbl.(col) = str2double(string(tbl.(col)));
        end
        tbl.(col) = double(tbl.(col));
    end
end

% 缺失值处理
price_cols = {'open', 'close', 'high', 'low'};
for c = 1:length(price_cols)
    col = price_cols{c};
    if any(strcmp(colnames, col))
        tbl.(col) = fillmissing(tbl.(col), 'previous');
        tbl.(col) = fillmissing(tbl.(col), 'next');
    end
end
if any(strcmp(colnames, 'volume'))
    tbl.volume = fillmissing(tbl.volume, 'previous');
    tbl.volume = fillmissing(tbl.volume, 'next');
end
if any(strcmp(colnames, 'amount'))
    tbl.amount = fillmissing(tbl.amount, 'previous');
    tbl.amount = fillmissing(tbl.amount, 'next');
end

% 涨跌幅重算
close_vals = tbl.close;
if any(strcmp(colnames, 'zdf'))
    nan_ratio = sum(isnan(tbl.zdf)) / height(tbl);
    if nan_ratio > 0.5
        zdf_vals = [NaN; (close_vals(2:end) - close_vals(1:end-1)) ./ close_vals(1:end-1) * 100];
        tbl.zdf = round(zdf_vals, 2);
    end
else
    zdf_vals = [NaN; (close_vals(2:end) - close_vals(1:end-1)) ./ close_vals(1:end-1) * 100];
    tbl.zdf = round(zdf_vals, 2);
end

% 振幅重算
if any(strcmp(colnames, 'zf'))
    nan_ratio = sum(isnan(tbl.zf)) / height(tbl);
    if nan_ratio > 0.3
        prev_close = [tbl.close(1); tbl.close(1:end-1)];
        tbl.zf = round((tbl.high - tbl.low) ./ prev_close * 100, 2);
    end
end

% 股票代码
if any(strcmp(colnames, 'code'))
    stock_code = tbl.code(1);
else
    [~, name, ~] = fileparts(filepath);
    stock_code = name;
end
tbl.stock_code = repmat(stock_code, height(tbl), 1);
end
