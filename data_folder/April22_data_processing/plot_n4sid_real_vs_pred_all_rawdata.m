% plot_n4sid_real_vs_pred_all_rawdata.m
% Fit one n4sid model from a chosen identification CSV (or stem + trial),
% then plot real vs simulated speed and yaw for every data CSV in
% rawdata_all_data (one figure per experiment CSV, excluding n4sid.csv).

clear; clc; close all;

scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, 'rawdata_all_data');

%% --- User: how to choose identification data for the model ---
% Option C — use every experiment CSV in rawdata_all_data at once (same as
% run_n4sid_from_all_rawdata_all_data_csvs.m: merged iddata, then n4sid).
% When true, Option A and Option B below are ignored.
idUseAllExperimentCsvsInFolder = true;

% Option A — single file (same style as run_n4sid_from_april22_csv.m).
% Leave empty [] to use Option B instead (only if Option C is false).
idCsvPath = fullfile(scriptDir, 'rawdata_all_data', 'n4sid_all_data_folder.csv');

% Option B — used only when Option C is false and idCsvPath is empty:
%   idStem        = name without _1/_2/_3, e.g. 'prop1625rudder2000'
%   idTrialChoice = 1, 2, 3, or 'all' (merge _1, _2, _3 into one iddata)
idStem = 'prop1625rudder2000';
idTrialChoice = 3;

%% Optional time crop on all loaded segments (same as run_n4sid_from_april22_csv.m)
cropEndTimeSec = [];

modelOrder = 2;

%% Resolve identification CSV path(s)
if idUseAllExperimentCsvsInFolder
    idPaths = listExperimentCsvPaths(dataDir);
    idLabel = sprintf('all experiment CSVs in rawdata_all_data (%d files)', numel(idPaths));
else
    idPaths = resolveIdentificationPaths(idCsvPath, dataDir, idStem, idTrialChoice);
    idLabel = formatIdLabel(idPaths, idTrialChoice);
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

    [~, fname, ext] = fileparts(csvPath);
    shortName = [fname, ext];

    figure('Name', sprintf('n4sid: %s (ID: %s)', shortName, idLabel));
    tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    plot(tPlot, yValProc(:, 1), 'k', 'LineWidth', 1.2); hold on;
    plot(tPlot, yValSim(:, 1), 'r--', 'LineWidth', 1.2);
    ylabel('Speed (m/s)');
    title(sprintf('%s — speed', shortName), 'Interpreter', 'none');
    legend('Real', 'Predicted', 'Location', 'best');
    grid on;

    nexttile;
    plot(tPlot, yValProc(:, 2), 'k', 'LineWidth', 1.2); hold on;
    plot(tPlot, yValSim(:, 2), 'r--', 'LineWidth', 1.2);
    xlabel('Time (s)');
    ylabel('Yaw (rad, unwrapped)');
    title(sprintf('%s — yaw', shortName), 'Interpreter', 'none');
    legend('Real', 'Predicted', 'Location', 'best');
    grid on;

    sgtitle(sprintf('Model ID: %s', idLabel), 'Interpreter', 'none');
end

%% --- Local functions -------------------------------------------------

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

function idPaths = resolveIdentificationPaths(idCsvPath, dataDir, idStem, idTrialChoice)
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

if isempty(idStem) || (isstring(idStem) && strlength(idStem) == 0)
    error(['Set idUseAllExperimentCsvsInFolder to true, set idCsvPath to a full file path, ', ...
        'or leave idCsvPath empty and set idStem + idTrialChoice (1, 2, 3, or ''all'').']);
end
if isstring(idStem)
    idStem = char(idStem);
end

if strcmpi(idTrialChoice, 'all')
    trials = 1:3;
else
    if ~(isnumeric(idTrialChoice) && isscalar(idTrialChoice) && ...
            ismember(idTrialChoice, [1, 2, 3]))
        error('idTrialChoice must be 1, 2, 3, or ''all''.');
    end
    trials = idTrialChoice;
end

idPaths = cell(numel(trials), 1);
for i = 1:numel(trials)
    fn = sprintf('%s_%d.csv', idStem, trials(i));
    idPaths{i} = fullfile(dataDir, fn);
    if ~isfile(idPaths{i})
        error('Identification CSV not found: %s', idPaths{i});
    end
end
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

function s = formatIdLabel(idPaths, idTrialChoice)
if numel(idPaths) == 1
    [~, s, e] = fileparts(idPaths{1});
    s = [s, e];
else
    [~, stem0, ~] = fileparts(idPaths{1});
    stemBase = regexprep(stem0, '_\d+$', '');
    if strcmpi(idTrialChoice, 'all')
        s = sprintf('%s (_1,_2,_3)', stemBase);
    else
        shortNames = cellfun(@(p) [regexprep(p, '.*[/\\]', ''), ''], idPaths, ...
            'UniformOutput', false);
        s = strjoin(shortNames, ' + ');
    end
end
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
yawOut = unwrap(yaw);
end
