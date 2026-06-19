function [stock_data, stock_codes] = load_all_stocks(data_dir, max_stocks, verbose)
% LOAD_ALL_STOCKS 批量加载 data_dir 下所有股票 CSV 文件
%
%   参数:
%       data_dir:   CSV 文件所在目录路径
%       max_stocks: 最大加载数量，[] 或省略表示全部
%       verbose:    true/false，是否打印进度（默认 true）
%
%   返回:
%       stock_data:  struct 数组，每个元素包含 .code 和 .data (table)
%       stock_codes: 字符串数组，股票代码列表

if nargin < 3, verbose = true; end
if nargin < 2, max_stocks = []; end

if ~isfolder(data_dir)
    error('数据目录不存在: %s', data_dir);
end

% 查找所有 CSV 文件
csv_files = dir(fullfile(data_dir, '*.csv'));
if isempty(csv_files)
    error('在 %s 中未找到 CSV 文件', data_dir);
end

if verbose
    fprintf('找到 %d 个 CSV 文件\n', length(csv_files));
end

% 限制数量
if ~isempty(max_stocks)
    csv_files = csv_files(1:min(max_stocks, length(csv_files)));
    if verbose
        fprintf('限制加载前 %d 只股票\n', max_stocks);
    end
end

% 初始化
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
    stock_data(valid_count).code = char(tbl.stock_code(1));
    stock_data(valid_count).data = tbl;
    stock_codes(valid_count) = string(tbl.stock_code(1));

    % 进度显示
    if verbose && mod(i, 500) == 0
        fprintf('  已处理 %d/%d 个文件...\n', i, n_files);
    end
end

% 截取有效部分
stock_data = stock_data(1:valid_count);
stock_codes = stock_codes(1:valid_count);

if verbose
    fprintf('加载完成: 成功 %d 只, 数据不足/跳过 %d 只, 失败 %d 只\n', ...
        valid_count, skip_count, fail_count);
end

end


function tbl = load_single_stock(filepath)
% LOAD_SINGLE_STOCK 读取单只股票的 CSV 文件，返回清洗后的 table
%
%   参数:
%       filepath: CSV 文件路径
%
%   返回:
%       table，包含标准化后的日线数据；若读取失败返回空

% 尝试读取 CSV
try
    tbl = readtable(filepath, 'VariableNamingRule', 'preserve', ...
        'TextType', 'string');
catch
    tbl = [];
    return;
end

% 空文件检查
if isempty(tbl) || height(tbl) == 0
    return;
end

% ---- 字段标准化 ----
% 获取列名
colnames = tbl.Properties.VariableNames;

% 检查必要字段
required_cols = {'day', 'close', 'open', 'high', 'low', 'volume'};
for c = 1:length(required_cols)
    if ~any(strcmp(colnames, required_cols{c}))
        warning('  [警告] %s 缺少字段: %s', filepath, required_cols{c});
        tbl = [];
        return;
    end
end

% 检查 hsl（换手率）字段
if ~any(strcmp(colnames, 'hsl'))
    warning('  [警告] 缺少 hsl 字段: %s', filepath);
    tbl = [];
    return;
end

% ---- 日期处理 ----
if iscell(tbl.day), tbl.day = string(tbl.day); end
tbl.day = datetime(tbl.day, 'InputFormat', 'yyyy-MM-dd', 'Locale', 'en_US');
% 移除无效日期
tbl(isnat(tbl.day), :) = [];
% 按日期排序
tbl = sortrows(tbl, 'day');

% ---- 数值列处理 ----
numeric_cols = {'open', 'close', 'high', 'low', 'volume', 'amount', ...
                'zf', 'zdf', 'zde', 'hsl'};
for c = 1:length(numeric_cols)
    col = numeric_cols{c};
    if any(strcmp(colnames, col))
        % 转换为数值
        if iscell(tbl.(col)) || isstring(tbl.(col))
            tbl.(col) = str2double(string(tbl.(col)));
        end
        % 确保为 double
        tbl.(col) = double(tbl.(col));
    end
end

% ---- 缺失值处理 ----
% 价格类字段：前向/后向填充
price_cols = {'open', 'close', 'high', 'low'};
for c = 1:length(price_cols)
    col = price_cols{c};
    if any(strcmp(colnames, col))
        tbl.(col) = fillmissing(tbl.(col), 'previous');
        tbl.(col) = fillmissing(tbl.(col), 'next');
    end
end

% 成交量/成交额：前向/后向填充
if any(strcmp(colnames, 'volume'))
    tbl.volume = fillmissing(tbl.volume, 'previous');
    tbl.volume = fillmissing(tbl.volume, 'next');
end
if any(strcmp(colnames, 'amount'))
    tbl.amount = fillmissing(tbl.amount, 'previous');
    tbl.amount = fillmissing(tbl.amount, 'next');
end

% ---- 涨跌幅重算验证 ----
if any(strcmp(colnames, 'zdf'))
    nan_ratio = sum(isnan(tbl.zdf)) / height(tbl);
    if nan_ratio > 0.5
        close_vals = tbl.close;
        zdf_vals = [NaN; (close_vals(2:end) - close_vals(1:end-1)) ./ close_vals(1:end-1) * 100];
        tbl.zdf = round(zdf_vals, 2);
    end
else
    close_vals = tbl.close;
    zdf_vals = [NaN; (close_vals(2:end) - close_vals(1:end-1)) ./ close_vals(1:end-1) * 100];
    tbl.zdf = round(zdf_vals, 2);
end

% ---- 振幅重算 ----
if any(strcmp(colnames, 'zf'))
    nan_ratio = sum(isnan(tbl.zf)) / height(tbl);
    if nan_ratio > 0.3
        prev_close = [tbl.close(1); tbl.close(1:end-1)];
        tbl.zf = round((tbl.high - tbl.low) ./ prev_close * 100, 2);
    end
else
    prev_close = [tbl.close(1); tbl.close(1:end-1)];
    tbl.zf = round((tbl.high - tbl.low) ./ prev_close * 100, 2);
end

% ---- 提取股票代码 ----
if any(strcmp(colnames, 'code'))
    stock_code = char(tbl.code(1));
else
    [~, name, ~] = fileparts(filepath);
    stock_code = name;
end

% 添加 stock_code 列（作为 categorical 或 cellstr）
tbl.stock_code = repmat({stock_code}, height(tbl), 1);

end


function summary = get_data_summary(stock_data)
% GET_DATA_SUMMARY 生成数据概览
%
%   参数:
%       stock_data: struct 数组，load_all_stocks 的返回结果
%
%   返回:
%       table: 每只股票的基本信息

n = length(stock_data);
codes = cell(n, 1);
rows = zeros(n, 1);
start_dates = NaT(n, 1);
end_dates = NaT(n, 1);
has_hsl = false(n, 1);
avg_volumes = zeros(n, 1);
avg_zdfs = zeros(n, 1);

for i = 1:n
    codes{i} = stock_data(i).code;
    tbl = stock_data(i).data;
    rows(i) = height(tbl);
    start_dates(i) = min(tbl.day);
    end_dates(i) = max(tbl.day);
    has_hsl(i) = any(strcmp(tbl.Properties.VariableNames, 'hsl'));
    avg_volumes(i) = mean(tbl.volume, 'omitnan');
    if any(strcmp(tbl.Properties.VariableNames, 'zdf'))
        avg_zdfs(i) = mean(tbl.zdf, 'omitnan');
    else
        avg_zdfs(i) = NaN;
    end
end

summary = table(string(codes), rows, start_dates, end_dates, has_hsl, ...
    avg_volumes, avg_zdfs, ...
    'VariableNames', {'stock_code', 'rows', 'start_date', 'end_date', ...
    'has_hsl', 'avg_volume', 'avg_zdf'});

end
