% plot_n4sid_real_vs_pred_all_rawdata.m
% Fit one n4sid model from a chosen identification CSV, a hand-picked list of
% CSVs, or all files in rawdata_all_data; then for each experiment CSV plot
% real vs simulated speed and yaw, metrics in the legend (Pearson r, RMSE/σ,
% compare %), and percent error vs time. Reported NRMSE is RMSE divided by the
% sample std of measured y (good for dynamical data). Range-based RMSE/(ymax-ymin)
% is optional — see legendNrmseMode.

clear; clc; close all;

scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, 'rawdata_all_data');

%% --- User: how to choose identification data for the model ---
% Option C — use every experiment CSV in rawdata_all_data at once (same as
% run_n4sid_from_all_rawdata_all_data_csvs.m: merged iddata, then n4sid).
% When true, Option A and Option B below are ignored.
idUseAllExperimentCsvsInFolder = false;

% Option A — exactly one identification file (full path, same style as
% run_n4sid_from_april22_csv.m). When non-empty, Option B is ignored.
% Use [] or '' when you want Option B instead (and Option C is false).
idCsvPath = [];

% Option B — hand-pick any number of CSVs (same columns as the trial files).
% Used when Option C is false and Option A is not used (idCsvPath is empty). Each string is either:
%   • a file name in rawdata_all_data (e.g. 'prop1625rudder2000_3.csv'), or
%   • a full path to a CSV anywhere (if that file exists).
% Order is kept; all listed files are merged into one iddata for n4sid.
idCsvFiles = {
    'prop1625rudder2000_1.csv'
    'prop1650rudder2000_2.csv'
    'prop1675rudder2000_3.csv'
    'prop1625rudder1775_2.csv'
    'prop1650rudder1775_1.csv'
    };

%% Optional time crop on all loaded segments (same as run_n4sid_from_april22_csv.m)
cropEndTimeSec = [];

%% Paper-style estimation error (%): 100*abs(pred-real)/abs(real)
% For numerical stability when real ~ 0, denominator is max(abs(real), floor).
pctErrSpeedFloor_mps = 0.05;

% Legend NRMSE: 'std' => RMSE/sample std(measured y). 'range' => RMSE/(max(y)-min(y)).
legendNrmseMode = 'std';

modelOrder = 2;

%% Resolve identification CSV path(s)
if idUseAllExperimentCsvsInFolder
    idPaths = listExperimentCsvPaths(dataDir);
    idLabel = sprintf('all experiment CSVs in rawdata_all_data (%d files)', numel(idPaths));
else
    idPaths = resolveIdentificationPaths(idCsvPath, dataDir, idCsvFiles);
    idLabel = formatIdLabel(idPaths);
end

%% Build merged iddata z from identification file(s)
z = buildMergedIddataFromCsvPaths(idPaths, cropEndTimeSec);

Ts = scalarTsFromIddata(z);

%% Estimate model (same signal construction as run_n4sid_from_april22_csv.m)
nx = modelOrder;
sys = n4sid(z, nx, 'Focus', 'simulation');

disp(['Identification source: ', idLabel]);
present(sys);

%% Every experiment CSV: one figure, speed + yaw real vs prediction
csvPaths = listExperimentCsvPaths(dataDir);
nFiles = numel(csvPaths);

for k = 1:nFiles
    csvPath = csvPaths{k};
    [uVal, yVal, tVal] = loadIoFromCsv(csvPath);
    [uVal, yVal, tVal] = cropSignalsToTime(uVal, yVal, tVal, cropEndTimeSec);

    [uPropPctVal, uRudderDegVal] = buildProcessedInputs(uVal);
    uValProc = [uPropPctVal, uRudderDegVal];
    [speedVal, yawValProc] = buildProcessedOutputs(yVal, tVal);
    yValProc = [speedVal, yawValProc];

    zVal = iddata(yValProc, uValProc, Ts, ...
        'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
        'OutputName', {'speed', 'yaw'});

    yValSim = sim(sys, zVal.u);
    tPlot = tVal - tVal(1);

    % Validation metrics: shape (Pearson r) + normalized RMSE + Theil decomposition.
    fitM = validationFitMetrics(yValProc, yValSim, legendNrmseMode);
    disp(sprintf('%s | speed: r=%.3f, Ub/Uv/Uc=%.1f/%.1f/%.1f%% | yaw: r=%.3f, Ub/Uv/Uc=%.1f/%.1f/%.1f%%', ...
        shortLabelForLog(csvPath), ...
        fitM.r(1), 100 * fitM.theil(1,1), 100 * fitM.theil(1,2), 100 * fitM.theil(1,3), ...
        fitM.r(2), 100 * fitM.theil(2,1), 100 * fitM.theil(2,2), 100 * fitM.theil(2,3)));

    yawRealWrapped = wrapToPiLocal(yValProc(:, 2));
    yawPredWrapped = wrapToPiLocal(yValSim(:, 2));

    pctSpd = percentErrorPaperStyle(yValSim(:, 1), yValProc(:, 1), pctErrSpeedFloor_mps);
    pctYaw = percentErrorPaperStyleWrappedYaw(yawPredWrapped, yawRealWrapped);
    maxPctSpd = max(pctSpd);
    maxPctYaw = max(pctYaw);

    [~, fname, ext] = fileparts(csvPath);
    shortName = [fname, ext];

    figure('Name', sprintf('n4sid: %s (ID: %s)', shortName, idLabel));
    tiledlayout(4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    hSpdReal = plot(tPlot, yValProc(:, 1), 'k', 'LineWidth', 1.2); hold on;
    hSpdPred = plot(tPlot, yValSim(:, 1), 'r--', 'LineWidth', 1.2);
    ylabel('Speed (m/s)');
    title(sprintf('%s — speed', shortName), 'Interpreter', 'none');
    applyMetricsLegend(gca, hSpdReal, hSpdPred, fitM.r(1), fitM.theil(1, :));
    grid on;

    nexttile;
    plot(tPlot, pctSpd, 'b', 'LineWidth', 1.1);
    yline(0, 'k:', 'LineWidth', 0.8);
    ylabel('Speed err (%)');
    title('Absolute percent estimation error', 'Interpreter', 'none');
    grid on;

    nexttile;
    hYawReal = plot(tPlot, yawRealWrapped, 'k', 'LineWidth', 1.2); hold on;
    hYawPred = plot(tPlot, yawPredWrapped, 'r--', 'LineWidth', 1.2);
    ylabel('Yaw (rad, wrapped)');
    title(sprintf('%s — yaw', shortName), 'Interpreter', 'none');
    applyMetricsLegend(gca, hYawReal, hYawPred, fitM.r(2), fitM.theil(2, :));
    grid on;

    nexttile;
    plot(tPlot, pctYaw, 'b', 'LineWidth', 1.1);
    yline(0, 'k:', 'LineWidth', 0.8);
    xlabel('Time (s)');
    ylabel('Yaw err (%)');
    title('Absolute percent estimation error', 'Interpreter', 'none');
    grid on;

    sgtitle(sprintf('Model ID: %s', idLabel), 'Interpreter', 'none');
end

%% --- Local functions -------------------------------------------------

function pct = percentErrorPaperStyle(yHat, y, yFloor)
% Paper-style estimation error (%): 100 * abs(yHat - y) ./ abs(y).
% yFloor avoids numerical blow-ups when measured y is near zero.
den = max(abs(y), yFloor);
pct = 100 * abs(yHat - y) ./ den;
end

function pct = percentErrorPaperStyleWrappedYaw(yHatWrapped, yWrapped)
% Yaw percent error with fixed angular scale: 100 * |yawErrWrapped| / pi.
yawErrWrapped = atan2(sin(yHatWrapped - yWrapped), cos(yHatWrapped - yWrapped));
pct = 100 * abs(yawErrWrapped) / pi;
end

function yWrapped = wrapToPiLocal(y)
yWrapped = atan2(sin(y), cos(y));
end

function M = validationFitMetrics(y, yHat, nrmseMode)
% Per column: Pearson r (shape), NRMSE (std/range), compare%, and Theil
% proportions Ub (bias), Uv (variance), Uc (covariance/shape-timing).
identGof = goodnessOfFit(yHat, y, 'NRMSE');
identGof = identGof(:).';
comparePct = max(0, min(100, 100 * (1 - identGof)));

M.legendLines = cell(1, 2);
M.r = nan(1, 2);
M.theil = nan(2, 3); % columns: [Ub, Uv, Uc]
useRange = strcmpi(strtrim(nrmseMode), 'range');
for i = 1:2
    yi = y(:, i);
    yiHat = yHat(:, i);
    e = yi - yiHat;
    rmse = sqrt(mean(e.^2));
    rPearson = safePearsonCorr(yi, yiHat);
    M.r(i) = rPearson;
    M.theil(i, :) = theilMseProportions(yi, yiHat, rPearson);
    if useRange
        denom = max(max(yi) - min(yi), eps);
        nrmseStr = 'RMSE/rng';
    else
        denom = max(std(yi, 0, 1), eps);
        nrmseStr = 'RMSE/std';
    end
    nrmseVal = rmse / denom;
    M.legendLines{i} = sprintf('%s=%.3f (compare=%.0f%%)', nrmseStr, nrmseVal, comparePct(i));
end
end

function applyMetricsLegend(ax, hReal, hPred, rVal, theilRow)
% Legend layout:
% -- black full -- Real
% -- red dashed -- Predicted
% r value
% U^B value
% U^V value
% U^C value
hTxt1 = plot(ax, nan, nan, 'LineStyle', 'none', 'Marker', 'none', 'HandleVisibility', 'on');
hTxt2 = plot(ax, nan, nan, 'LineStyle', 'none', 'Marker', 'none', 'HandleVisibility', 'on');
hTxt3 = plot(ax, nan, nan, 'LineStyle', 'none', 'Marker', 'none', 'HandleVisibility', 'on');
hTxt4 = plot(ax, nan, nan, 'LineStyle', 'none', 'Marker', 'none', 'HandleVisibility', 'on');

lgd = legend(ax, [hReal, hPred, hTxt1, hTxt2, hTxt3, hTxt4], { ...
    'Real', ...
    'Predicted', ...
    sprintf('r      %.3f', rVal), ...
    sprintf('U^B   %.1f%%', 100 * theilRow(1)), ...
    sprintf('U^V   %.1f%%', 100 * theilRow(2)), ...
    sprintf('U^C   %.1f%%', 100 * theilRow(3))}, ...
    'Location', 'southeast', ...
    'Interpreter', 'tex', ...
    'Box', 'on');
lgd.AutoUpdate = 'off';
end

function p = theilMseProportions(y, yHat, r)
% Decompose MSE = Ub + Uv + Uc where proportions sum to ~1.
% Ub: bias, Uv: variance mismatch, Uc: covariance/shape-timing mismatch.
ok = isfinite(y) & isfinite(yHat);
if nnz(ok) < 3
    p = [NaN, NaN, NaN];
    return;
end
y = y(ok);
yHat = yHat(ok);

mse = mean((y - yHat).^2);
if mse <= eps
    p = [0, 0, 0];
    return;
end

my = mean(y);
mh = mean(yHat);
sy = std(y, 1, 1);
sh = std(yHat, 1, 1);
if ~isfinite(r)
    r = safePearsonCorr(y, yHat);
end
r = max(min(r, 1), -1);

ub = (mh - my)^2 / mse;
uv = (sh - sy)^2 / mse;
uc = 2 * sy * sh * (1 - r) / mse;

v = [ub, uv, uc];
v = max(v, 0);
sv = sum(v);
if sv > eps
    p = v / sv;
else
    p = [NaN, NaN, NaN];
end
end

function s = shortLabelForLog(csvPath)
[~, n, e] = fileparts(csvPath);
s = [n, e];
end

function r = safePearsonCorr(a, b)
ok = isfinite(a) & isfinite(b);
if nnz(ok) < 3
    r = NaN;
    return;
end
aa = a(ok);
bb = b(ok);
if std(aa, 0, 1) < eps || std(bb, 0, 1) < eps
    r = NaN;
    return;
end
r = corr(aa, bb, 'Type', 'Pearson', 'Rows', 'complete');
if ~isfinite(r)
    r = NaN;
end
end

function Ts = scalarTsFromIddata(z)
% Single-experiment iddata uses numeric scalar Ts; merged multi-experiment
% data uses a 1-by-Ne cell array (one sample time per experiment).
rawTs = z.Ts;
if isnumeric(rawTs) && isscalar(rawTs)
    Ts = double(rawTs);
elseif iscell(rawTs)
    nExp = numel(rawTs);
    if nExp < 1
        error('iddata has empty Ts cell array.');
    end
    vals = zeros(1, nExp);
    for k = 1:nExp
        tk = rawTs{k};
        if isduration(tk)
            vals(k) = seconds(tk);
        elseif isnumeric(tk) && isscalar(tk)
            vals(k) = double(tk);
        else
            error('Unsupported iddata.Ts{%d} type: %s', k, class(tk));
        end
    end
    Ts = vals(1);
    if nExp > 1 && (max(vals) - min(vals)) / max(Ts, eps) > 0.02
        warning(['Sample times differ across merged experiments ', ...
            '(min=%.6g s, max=%.6g s). Using Ts=%.6g s from the first experiment.'], ...
            min(vals), max(vals), Ts);
    end
else
    error('Unsupported iddata.Ts type: %s', class(rawTs));
end

if ~isfinite(Ts) || Ts <= 0
    error('Invalid sample time on identification iddata (Ts=%g).', Ts);
end
end

function idPaths = resolveIdentificationPaths(idCsvPath, dataDir, idCsvFiles)
if ~(isempty(idCsvPath) || (isstring(idCsvPath) && strlength(idCsvPath) == 0))
    if isstring(idCsvPath)
        idCsvPath = char(idCsvPath);
    end
    if ~isfile(idCsvPath)
        error('Identification CSV not found: %s', idCsvPath);
    end
    idPaths = {idCsvPath};
    return;
end

idPaths = resolveIdPathsFromPickList(dataDir, idCsvFiles);
end

function idPaths = resolveIdPathsFromPickList(dataDir, idCsvFiles)
if isempty(idCsvFiles) || (iscell(idCsvFiles) && numel(idCsvFiles) == 0)
    error(['Set idUseAllExperimentCsvsInFolder to true, set idCsvPath to one CSV, ', ...
        'or set idCsvFiles to a non-empty cell array of file names (see Option B comments).']);
end
if ~iscell(idCsvFiles)
    error('idCsvFiles must be a cell array, e.g. {''a.csv'',''b.csv''}.');
end

idPaths = {};
for k = 1:numel(idCsvFiles)
    f = idCsvFiles{k};
    if isstring(f)
        if strlength(f) == 0
            continue;
        end
        f = char(f);
    end
    if ~ischar(f)
        error('idCsvFiles{%d} must be a character vector or string scalar.', k);
    end
    f = strtrim(f);
    if isempty(f)
        continue;
    end

    if isfile(f)
        idPaths{end + 1} = f; %#ok<AGROW>
    elseif isfile(fullfile(dataDir, f))
        idPaths{end + 1} = fullfile(dataDir, f); %#ok<AGROW>
    else
        error('Identification file not found: %s (also tried %s).', f, fullfile(dataDir, f));
    end
end

if isempty(idPaths)
    error('idCsvFiles has no usable entries after skipping blanks.');
end

idPaths = idPaths(:);
end

function z = buildMergedIddataFromCsvPaths(csvPaths, cropEndTimeSec)
zList = cell(numel(csvPaths), 1);
TsRef = [];

for i = 1:numel(csvPaths)
    [u, y, t] = loadIoFromCsv(csvPaths{i});
    [u, y, t] = cropSignalsToTime(u, y, t, cropEndTimeSec);

    Ts_i = median(diff(t));
    if ~isfinite(Ts_i) || Ts_i <= 0
        error('Invalid sample time in %s.', csvPaths{i});
    end
    if isempty(TsRef)
        TsRef = Ts_i;
    elseif abs(Ts_i - TsRef) / TsRef > 0.02
        warning('Median Ts differs between ID files (%.6g vs %.6g). Using first file Ts.', ...
            TsRef, Ts_i);
    end

    [uPropPct, uRudderDeg] = buildProcessedInputs(u);
    uProc = [uPropPct, uRudderDeg];
    [speed, yawUnwrapped] = buildProcessedOutputs(y, t);
    yProc = [speed, yawUnwrapped];

    zList{i} = iddata(yProc, uProc, TsRef, ...
        'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
        'OutputName', {'speed', 'yaw'});
end

if numel(zList) == 1
    z = zList{1};
else
    z = merge(zList{:});
end
end

function s = formatIdLabel(idPaths)
if numel(idPaths) == 1
    [~, nameOnly, ext] = fileparts(idPaths{1});
    s = [nameOnly, ext];
    return;
end

bases = cellfun(@(p) localFileNameOnly(p), idPaths, 'UniformOutput', false);
s = strjoin(bases, ', ');
if numel(s) > 120
    s = sprintf('%d files: %s...', numel(idPaths), strjoin(bases(1:min(2, numel(bases))), ', '));
end
end

function nameOnly = localFileNameOnly(fullPath)
[~, nameOnly, ext] = fileparts(fullPath);
nameOnly = [nameOnly, ext];
end

function paths = listExperimentCsvPaths(dataDir)
d = dir(fullfile(dataDir, '*.csv'));
names = {d.name};
keep = ~strcmpi(names, 'n4sid.csv');
names = names(keep);
if isempty(names)
    error('No experiment CSV files found in %s.', dataDir);
end
[~, ix] = sort(lower(names));
names = names(ix);
paths = cellfun(@(n) fullfile(dataDir, n), names, 'UniformOutput', false);
end

function [u, y, t] = loadIoFromCsv(csvPath)
if ~isfile(csvPath)
    error('CSV file not found: %s', csvPath);
end

T = readtable(csvPath);
requiredVars = {'timestamp', 'u_propeller_pwm', 'u_rudder_pwm', 'x', 'y', 'yaw'};
missingVars = requiredVars(~ismember(requiredVars, T.Properties.VariableNames));
if ~isempty(missingVars)
    error('Missing required column(s) in %s: %s', csvPath, strjoin(missingVars, ', '));
end

u = [T.u_propeller_pwm, T.u_rudder_pwm];
y = [T.x, T.y, T.yaw];
t = T.timestamp;

validRows = all(isfinite([u, y, t]), 2);
u = u(validRows, :);
y = y(validRows, :);
t = t(validRows, :);

if size(u, 1) < 20
    error('Not enough valid samples in %s after NaN filtering (%d rows).', csvPath, size(u, 1));
end
end

function [uOut, yOut, tOut] = cropSignalsToTime(u, y, t, cropEndTimeSec)
if isempty(cropEndTimeSec)
    uOut = u;
    yOut = y;
    tOut = t;
    return;
end

if ~isfinite(cropEndTimeSec) || cropEndTimeSec <= 0
    error('cropEndTimeSec must be a positive finite scalar or empty.');
end

tRel = t - t(1);
keep = tRel <= cropEndTimeSec;
if nnz(keep) < 20
    error('Time crop keeps too few samples (%d). Increase cropEndTimeSec.', nnz(keep));
end

uOut = u(keep, :);
yOut = y(keep, :);
tOut = t(keep, :);
end

function [uPropPercent, uRudderDeg] = buildProcessedInputs(uPwm)
uPropPwm = uPwm(:, 1);
uRudderPwm = uPwm(:, 2);

uPropPercent = (uPropPwm - 1500) * (100 / 500);
uPropPercent = min(max(uPropPercent, 0), 100);

uRudderDeg = (uRudderPwm - 1500) * (40 / 500);
uRudderDeg = min(max(uRudderDeg, -40), 40);
end

function [speed, yawOut] = buildProcessedOutputs(y, t)
x = y(:, 1);
yPos = y(:, 2);
yaw = y(:, 3);

xySgOrder = 3;
xySgFrame = 11;
if numel(x) >= xySgFrame
    xSmooth = sgolayfilt(x, xySgOrder, xySgFrame);
    ySmooth = sgolayfilt(yPos, xySgOrder, xySgFrame);
else
    xSmooth = smoothdata(x, 'movmean', min(5, numel(x)));
    ySmooth = smoothdata(yPos, 'movmean', min(5, numel(yPos)));
end

dxdt = gradient(xSmooth, t);
dydt = gradient(ySmooth, t);
speed = hypot(dxdt, dydt);

speedFcHz = 1.0;
speedFilterOrder = 2;
Ts_med = median(diff(t));
fs = 1 / Ts_med;
nyq = fs / 2;
Wn = speedFcHz / nyq;
if ~(Wn > 0 && Wn < 1)
    error('Speed filter cutoff must be in (0, Nyquist). Got Wn=%g (fs=%g Hz).', Wn, fs);
end
[bSpd, aSpd] = butter(speedFilterOrder, Wn, 'low');
speed = filtfilt(bSpd, aSpd, speed);
% Use unwrapped yaw for identification; wrapped/sawtooth is handled in plotting.
yawOut = unwrap(yaw);
end
