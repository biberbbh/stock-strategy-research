function summary = get_data_summary(stock_data)
% GET_DATA_SUMMARY 生成数据概览

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
