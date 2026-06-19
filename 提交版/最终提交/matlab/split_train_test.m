function [train_data, test_data] = split_train_test(stock_data, train_ratio)
% SPLIT_TRAIN_TEST 按时间顺序将数据划分为训练集和测试集

if nargin < 2 || isempty(train_ratio)
    cfg = config();
    train_ratio = cfg.TRAIN_RATIO;
end

n = length(stock_data);
train_data = struct('code', cell(n, 1), 'data', cell(n, 1));
test_data = struct('code', cell(n, 1), 'data', cell(n, 1));
train_count = 0;
test_count = 0;

for i = 1:n
    tbl = stock_data(i).data;
    tbl = sortrows(tbl, 'day');
    split_idx = round(height(tbl) * train_ratio);

    train_count = train_count + 1;
    train_data(train_count).code = stock_data(i).code;
    if split_idx < 60
        train_data(train_count).data = tbl;
    else
        train_data(train_count).data = tbl(1:split_idx, :);
        test_count = test_count + 1;
        test_data(test_count).code = stock_data(i).code;
        test_data(test_count).data = tbl(split_idx+1:end, :);
    end
end

train_data = train_data(1:train_count);
test_data = test_data(1:test_count);
end
