% may_level3.m
% Level 3: RMSE vs propeller command (%) — four figures, each with two series:
%   Thrust axis at 25, 30, 35 (percent; PWM 1625 / 1650 / 1675). Trials snap to nearest grid.
%   At each level: mean RMSE with 95% CI if n>=2 (trials as solid circles).
%   All per-trial points plotted (filled markers). OLS uses unsnapped x.
%   Rudder PWM 1800 (~24 deg) vs 2000 (~40 deg).
%   (1) Acceleration | speed    (2) Acceleration | yaw
%   (3) Turning      | speed    (4) Turning      | yaw
% Yaw RMSE (deg): measured and predicted unwrapped yaw are zeroed at trial t=0 (like plot_n4sid).
% Same identification logic as plot_n4sid_real_vs_pred_all_rawdata.m Option B.
%
% Workflow (recommended):
%   1) In plot_n4sid_real_vs_pred_all_rawdata.m set exportMayLevel3N4sidBundle = true; run once.
%   2) In this script set useN4sidBundleFromFile = true; run may_level3.m
% If the bundle MAT is missing, set useN4sidBundleFromFile = false to identify here.

close all; clc;

scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, 'rawdata_all_data');
addpath(fullfile(scriptDir, '..', 'MyFunctions'));
exportCfg = makeFigureExportConfig(scriptDir);
exportMayLevel3Png = false;

%% Load n4sid model from bundle (written by plot_n4sid_real_vs_pred_all_rawdata.m) or identify here
% Set true after running plot_n4sid_real_vs_pred_all_rawdata.m once with exportMayLevel3N4sidBundle = true.
useN4sidBundleFromFile = false;
n4sidBundleMatFile = fullfile(scriptDir, 'may_level3_n4sid_bundle.mat');

%% Identification (Option B) — same defaults as plot_n4sid_real_vs_pred_all_rawdata.m
idUseAllExperimentCsvsInFolder = false;
idCsvPath = [];
idCsvFiles = {
    'prop1625rudder1800_2.csv'
    'prop1650rudder1800_4.csv'
    'prop1675rudder1800_5.csv'

    'prop1675rudder2000_1.csv'
    };

cropEndTimeSec = 2.1;
modelOrder = 2;

%% Regime segmentation (same parameters as plot_n4sid_real_vs_pred_all_rawdata.m)
stepFromPwm = 1500;
stepFromTol = 70;
stepDeltaMinPwm = 120;
maxPeakSearchSec = 25;
decelTailSec = 6;
regimeAMaxSec = 35;
settleAfterRegA_sec = 3;
circleRudderMinDeltaPwm = 220;
circleYawRateMinRadPerSec = 0.08;
circleMinSamples = 40;

minRegimeSamplesForRmse = 20;

% Three prop thrust levels (percent) — CI/marker x-positions for every RMSE vs thrust figure
mayLevel3PropPctTargets = [25, 30, 35];
% Assign each trial's prop percent to nearest target if within this half-width; else drop from CI plot
mayLevel3PropPctSnapHalfWidth = 0.6;

%% --- Model: bundle or local n4sid ---
if useN4sidBundleFromFile
    if ~isfile(n4sidBundleMatFile)
        error(['Bundle not found: %s\nSet exportMayLevel3N4sidBundle = true in ', ...
            'plot_n4sid_real_vs_pred_all_rawdata.m, run it once, or set useN4sidBundleFromFile false.'], ...
            n4sidBundleMatFile);
    end
    S = load(n4sidBundleMatFile, 'sys', 'Ts', 'idLabel', 'cropEndTimeSec', 'modelOrder');
    sys = S.sys;
    Ts = double(S.Ts);
    if isfield(S, 'idLabel')
        idLabel = S.idLabel;
    else
        idLabel = '(bundle)';
    end
    if isfield(S, 'cropEndTimeSec') && ~isempty(S.cropEndTimeSec)
        cropEndTimeSec = double(S.cropEndTimeSec(1));
    end
    if isfield(S, 'modelOrder') && ~isempty(S.modelOrder)
        modelOrder = double(S.modelOrder(1));
    end
    disp(['may_level3: loaded n4sid bundle. ID: ', idLabel]);
    present(sys);
else
    if idUseAllExperimentCsvsInFolder
        idPaths = listExperimentCsvPaths(dataDir);
        idLabel = sprintf('all experiment CSVs in rawdata_all_data (%d files)', numel(idPaths));
    else
        idPaths = resolveIdentificationPaths(idCsvPath, dataDir, idCsvFiles);
        idLabel = formatIdLabel(idPaths);
    end
    z = buildMergedIddataFromCsvPaths(idPaths, cropEndTimeSec);
    Ts = scalarTsFromIddata(z);
    nx = modelOrder;
    sys = n4sid(z, nx, 'Focus', 'simulation');
    disp(['may_level3: identified n4sid. Source: ', idLabel]);
    present(sys);
end

%% Collect speed RMSE (m/s) and yaw RMSE (deg) per trial, regime A/B, for plotting vs prop %
% Yaw RMSE: same convention as plot_n4sid_real_vs_pred_all_rawdata.m — real and predicted
% unwrapped yaw are shifted to 0 at the first sample so error reflects shape, not IC offset.
csvPaths = listExperimentCsvPaths(dataDir);
rows = struct('trial', {}, 'propPwm', {}, 'rudderPwm', {}, 'propPct', {}, ...
    'rmse_speed_A', {}, 'rmse_speed_B', {}, 'rmse_yaw_A', {}, 'rmse_yaw_B', {});

for k = 1:numel(csvPaths)
    csvPath = csvPaths{k};
    [~, trialName, ext] = fileparts(csvPath);
    trialName = [trialName, ext];

    [propPwm, rudderPwm] = parsePropRudderFromTrialName(trialName);
    if ~isfinite(propPwm) || ~isfinite(rudderPwm)
        continue;
    end
    if ~any(rudderPwm == [1800, 2000])
        continue;
    end

    try
        [uVal, yVal, tVal] = loadIoFromCsv(csvPath);
        [uVal, yVal, tVal] = cropSignalsToTime(uVal, yVal, tVal, cropEndTimeSec);
    catch ME
        warning('Skipping %s: %s', trialName, ME.message);
        continue;
    end

    [uPropPctVal, uRudderDegVal] = buildProcessedInputs(uVal);
    uValProc = [uPropPctVal, uRudderDegVal];
    [speedVal, yawValProc] = buildProcessedOutputs(yVal, tVal);
    yValProc = [speedVal, yawValProc];

    zVal = iddata(yValProc, uValProc, Ts, ...
        'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
        'OutputName', {'speed', 'yaw'});
    yHat = sim(sys, zVal.u);

    yawRealRad = yValProc(:, 2);
    yawPredRad = yHat(:, 2);
    yawRealAdj = yawRealRad - yawRealRad(1);
    yawPredAdj = yawPredRad - yawPredRad(1);

    masks = makeRegimeMasks(uVal(:, 2), speedVal, yawValProc, tVal, ...
        stepFromPwm, stepFromTol, stepDeltaMinPwm, ...
        maxPeakSearchSec, decelTailSec, regimeAMaxSec, ...
        settleAfterRegA_sec, circleRudderMinDeltaPwm, ...
        circleYawRateMinRadPerSec, circleMinSamples);

    rSpA = rmseVector(speedVal(masks.A), yHat(masks.A, 1), minRegimeSamplesForRmse);
    rSpB = rmseVector(speedVal(masks.B), yHat(masks.B, 1), minRegimeSamplesForRmse);
    rYwA = rmseVector(rad2deg(yawRealAdj(masks.A)), rad2deg(yawPredAdj(masks.A)), minRegimeSamplesForRmse);
    rYwB = rmseVector(rad2deg(yawRealAdj(masks.B)), rad2deg(yawPredAdj(masks.B)), minRegimeSamplesForRmse);

    row = struct();
    row.trial = trialName;
    row.propPwm = propPwm;
    row.rudderPwm = rudderPwm;
    row.propPct = pwmToPropPercent(propPwm);
    row.rmse_speed_A = rSpA;
    row.rmse_speed_B = rSpB;
    row.rmse_yaw_A = rYwA;
    row.rmse_yaw_B = rYwB;
    rows(end + 1) = row; %#ok<AGROW>
end

if isempty(rows)
    error('may_level3: no trials produced RMSE rows. Check rawdata_all_data and filename pattern prop####rudder####.');
end

% Print Turning Test speed RMSE per trial (sorted by trial file name).
turningSpeedRmse = [rows.rmse_speed_B].';
trialNames = {rows.trial}.';
propPwms = [rows.propPwm].';
rudderPwms = [rows.rudderPwm].';
okPrint = isfinite(turningSpeedRmse);
if any(okPrint)
    vals = turningSpeedRmse(okPrint);
    names = trialNames(okPrint);
    pvals = propPwms(okPrint);
    rvals = rudderPwms(okPrint);
    [names, ix] = sort(names);
    valsSorted = vals(ix);
    pvals = pvals(ix);
    rvals = rvals(ix);
    fprintf('\nmay_level3: Turning Test speed RMSE by trial (sorted by file name)\n');
    fprintf('  RMSE(m/s) | propPWM | rudderPWM | trial\n');
    for i = 1:numel(valsSorted)
        fprintf('  %8.4f | %7d | %9d | %s\n', valsSorted(i), pvals(i), rvals(i), names{i});
    end
else
    fprintf('\nmay_level3: no finite Turning Test speed RMSE values to print.\n');
end

%% Four figures: rudder 1800 vs 2000; thrust x = 25 / 30 / 35 (percent)
figSpeedA = plotRmseDualRudderFigure(rows, 'A', 'speed', 'Acceleration Test', mayLevel3PropPctTargets, mayLevel3PropPctSnapHalfWidth);
figYawA   = plotRmseDualRudderFigure(rows, 'A', 'yaw',   'Acceleration Test', mayLevel3PropPctTargets, mayLevel3PropPctSnapHalfWidth);
figSpeedB = plotRmseDualRudderFigure(rows, 'B', 'speed', 'Turning Test', mayLevel3PropPctTargets, mayLevel3PropPctSnapHalfWidth);
figYawB   = plotRmseDualRudderFigure(rows, 'B', 'yaw',   'Turning Test', mayLevel3PropPctTargets, mayLevel3PropPctSnapHalfWidth);
figLegend = createMayLevel3LegendFigure();

%% Export figures to data_folder/processed_data (similar style to plot_n4sid_real_vs_pred_all_rawdata.m)
if exportMayLevel3Png
    exportFigurePng(figSpeedA, fullfile(exportCfg.outDir, 'level3_rmse_speed_acceleration.png'), exportCfg);
    exportFigurePng(figYawA,   fullfile(exportCfg.outDir, 'level3_rmse_yaw_acceleration.png'), exportCfg);
    exportFigurePng(figSpeedB, fullfile(exportCfg.outDir, 'level3_rmse_speed_turning.png'), exportCfg);
    exportFigurePng(figYawB,   fullfile(exportCfg.outDir, 'level3_rmse_yaw_turning.png'), exportCfg);
    exportFigurePng(figLegend, fullfile(exportCfg.outDir, 'level3_legend.png'), exportCfg);
end

%% ---------- local helpers ----------
function fig = plotRmseDualRudderFigure(rows, regimeLetter, outputName, regimeTitle, propPctTargets, propPctSnapHalfWidth)
% One axes: RMSE vs prop (percent) for rudder PWM 1800 and 2000 (no legend).
% propPctTargets e.g. [25,30,35]; mean and CI only at these thrust levels.
if nargin < 5 || isempty(propPctTargets)
    propPctTargets = [25, 30, 35];
end
if nargin < 6 || isempty(propPctSnapHalfWidth)
    propPctSnapHalfWidth = 0.6;
end
rudList = [1800, 2000];
cols = {
    [0.00, 0.62, 0.27]  % 24 deg -> green
    [0.86, 0.00, 0.86]  % 40 deg -> magenta
    };
ciLineStyles = {'-', '--'}; % Option 2: distinguish overlapping CI bars by line style
if strcmpi(regimeLetter, 'A')
    regKey = 'A';
    fldShort = 'Accel';
else
    regKey = 'B';
    fldShort = 'Turn';
end
if strcmpi(outputName, 'speed')
    yLabelTxt = 'Speed RMSE (m/s)';
    cap = 'Speed';
else
    yLabelTxt = 'Yaw RMSE (degrees)';
    cap = 'Yaw';
end

fig = figure('Name', sprintf('may_level3: %s RMSE vs prop | %s | 1800+2000', cap, fldShort), 'Color', 'w');
setFigureFullScreen(fig);
ax = axes('Parent', fig);
hold(ax, 'on');
anyPlotted = false;
for ir = 1:numel(rudList)
    [xs, ys] = sortedRmseVsPropForRudder(rows, regKey, rudList(ir), outputName);
    if isempty(xs)
        continue;
    end
    anyPlotted = true;
    c = cols{ir};
    ciLs = ciLineStyles{ir};
    plotOlsLineOnAxes(ax, xs, ys, c, 6.8);
    plotAllTrialRmsePoints(ax, xs, ys, c);
    plotGroupedRmseWithMeanCi(ax, xs, ys, c, propPctTargets, propPctSnapHalfWidth, ciLs);
end
hold(ax, 'off');
if ~anyPlotted
    warning('may_level3: no finite RMSE data for %s | %s — empty figure.', regimeTitle, cap);
end
xlabel(ax, 'Propeller Thrust (%)');
ylabel(ax, yLabelTxt);
grid(ax, 'off');
set(ax, 'XTick', propPctTargets, 'XTickLabel', compose('%.0f', propPctTargets));
xlim(ax, [min(propPctTargets) - 0.4, max(propPctTargets) + 0.4]);
axes(ax); %#ok<LAXES>
improvePlot();
applyPosterAxisFonts(ax);
end

function figLegend = createMayLevel3LegendFigure()
% Standalone legend figure (single legend for all may_level3 plots).
cols = {
    [0.00, 0.62, 0.27]  % 24 deg -> green
    [0.86, 0.00, 0.86]  % 40 deg -> magenta
    };
figLegend = figure('Name', 'may_level3 legend', 'Color', 'w');
axL = axes('Parent', figLegend);
hold(axL, 'on');
axis(axL, 'off');
improvePlot();
applyPosterAxisFonts(axL);
% Create legend-only dummy handles (NaN data => no visible points on axes).
hLegGreen = line(axL, 'XData', NaN, 'YData', NaN, ...
    'LineStyle', 'none', 'Marker', 'o', 'Color', cols{1}, ...
    'MarkerSize', 14, 'LineWidth', 1.1, ...
    'MarkerFaceColor', cols{1}, 'MarkerEdgeColor', cols{1});
hLegMagenta = line(axL, 'XData', NaN, 'YData', NaN, ...
    'LineStyle', 'none', 'Marker', 'o', 'Color', cols{2}, ...
    'MarkerSize', 14, 'LineWidth', 1.1, ...
    'MarkerFaceColor', cols{2}, 'MarkerEdgeColor', cols{2});
legend(axL, [hLegGreen, hLegMagenta], ...
    {'Propeller Angle 24^\circ', 'Propeller Angle 40^\circ'}, ...
    'Orientation', 'vertical', 'Location', 'north', ...
    'Interpreter', 'tex', 'Box', 'on');
hold(axL, 'off');
end

function plotAllTrialRmsePoints(ax, xs, ys, c)
% Every trial as a solid circle at (prop %, RMSE); drawn under mean/CI.
xs = double(xs(:));
ys = double(ys(:));
ok = isfinite(xs) & isfinite(ys);
xs = xs(ok);
ys = ys(ok);
if isempty(xs)
    return;
end
ec = 0.35 * c + 0.65 * [0, 0, 0];
plot(ax, xs, ys, 'o', 'MarkerSize', 21, 'LineWidth', 1.1, ...
    'MarkerFaceColor', c, 'MarkerEdgeColor', ec, 'Color', c, ...
    'HandleVisibility', 'off');
end

function plotGroupedRmseWithMeanCi(ax, xs, ys, c, propPctTargets, snapHalfWidth, ciLineStyle)
% Mean ± 95% CI at each propPctTargets when n>=2 (trials plotted separately). Snap x to nearest target.
if nargin < 5 || isempty(propPctTargets)
    propPctTargets = [25, 30, 35];
end
if nargin < 6 || isempty(snapHalfWidth)
    snapHalfWidth = 0.6;
end
if nargin < 7 || isempty(ciLineStyle)
    ciLineStyle = '-';
end
xs = double(xs(:));
ys = double(ys(:));
ok = isfinite(xs) & isfinite(ys);
xs = xs(ok);
ys = ys(ok);
if isempty(xs)
    return;
end
nPt = numel(xs);
xsSnap = nan(nPt, 1);
for i = 1:nPt
    [d, k] = min(abs(xs(i) - propPctTargets(:).'));
    if d <= snapHalfWidth
        xsSnap(i) = propPctTargets(k);
    end
end
okS = isfinite(xsSnap);
xsSnap = xsSnap(okS);
ys = ys(okS);
if isempty(xsSnap)
    return;
end
for ti = 1:numel(propPctTargets)
    t = propPctTargets(ti);
    yg = ys(xsSnap == t);
    n = numel(yg);
    if n < 2
        continue;
    end
    mu = mean(yg, 'omitnan');
    se = std(yg, 0, 1) / sqrt(n);
    if ~isfinite(se)
        se = 0;
    end
    dof = max(1, n - 1);
    try
        tc = tinv(0.975, dof);
    catch
        tc = 1.96;
    end
    errBar = tc * se;
    lo = mu - errBar;
    hi = mu + errBar;
    % Draw CI manually so LineStyle (solid vs dashed) is obvious — MATLAB errorbar often ignores it.
    capHalfW = 0.45;
    ciLw = 4.0;
    plot(ax, [t, t], [lo, hi], 'LineStyle', ciLineStyle, 'Color', c, 'LineWidth', ciLw, ...
        'HandleVisibility', 'off');
    plot(ax, [t - capHalfW, t + capHalfW], [hi, hi], 'LineStyle', '-', 'Color', c, ...
        'LineWidth', ciLw, 'HandleVisibility', 'off');
    plot(ax, [t - capHalfW, t + capHalfW], [lo, lo], 'LineStyle', '-', 'Color', c, ...
        'LineWidth', ciLw, 'HandleVisibility', 'off');
end
end

function plotOlsLineOnAxes(ax, xs, ys, c, lineW)
% Least-squares line y = p(1)*x + p(2) over [min(xs), max(xs)]; markers plotted separately.
if nargin < 5 || isempty(lineW)
    lineW = 2.2;
end
xs = double(xs(:));
ys = double(ys(:));
ok = isfinite(xs) & isfinite(ys);
xs = xs(ok);
ys = ys(ok);
if numel(xs) < 2
    return;
end
xSpan = max(xs) - min(xs);
if xSpan > 1e-9
    p = polyfit(xs, ys, 1);
    xf = linspace(min(xs), max(xs), max(50, 10 * numel(xs)));
    yf = polyval(p, xf);
    plot(ax, xf, yf, '-', 'Color', c, 'LineWidth', lineW, 'HandleVisibility', 'off');
else
    yBar = mean(ys, 'omitnan');
    if isfinite(yBar)
        x0 = mean(xs, 'omitnan');
        pad = 0.5;
        plot(ax, [x0 - pad, x0 + pad], [yBar, yBar], '-', 'Color', c, ...
            'LineWidth', lineW, 'HandleVisibility', 'off');
    end
end
end

function [xs, ys] = sortedRmseVsPropForRudder(rows, regimeKey, rudderPwmTarget, outputName)
maskR = abs([rows.rudderPwm] - rudderPwmTarget) < 0.5;
sub = rows(maskR);
if isempty(sub)
    xs = [];
    ys = [];
    return;
end
if strcmpi(regimeKey, 'A')
    if strcmpi(outputName, 'speed')
        rmseVals = [sub.rmse_speed_A];
    else
        rmseVals = [sub.rmse_yaw_A];
    end
else
    if strcmpi(outputName, 'speed')
        rmseVals = [sub.rmse_speed_B];
    else
        rmseVals = [sub.rmse_yaw_B];
    end
end
xProp = [sub.propPct].';
yRmse = rmseVals(:);
ok = isfinite(xProp) & isfinite(yRmse);
xProp = xProp(ok);
yRmse = yRmse(ok);
if isempty(xProp)
    xs = [];
    ys = [];
    return;
end
[xs, ix] = sort(xProp);
ys = yRmse(ix);
end

function r = rmseVector(y, yHat, nMin)
if numel(y) < nMin || numel(yHat) < nMin || numel(y) ~= numel(yHat)
    r = NaN;
    return;
end
e = y(:) - yHat(:);
ok = isfinite(e);
if nnz(ok) < nMin
    r = NaN;
    return;
end
e = e(ok);
r = sqrt(mean(e.^2, 'omitnan'));
end

function pct = pwmToPropPercent(propPwm)
pct = (propPwm - 1500) * (100 / 500);
pct = min(max(pct, 0), 100);
end

function [propPwm, rudderPwm] = parsePropRudderFromTrialName(trialName)
propPwm = NaN;
rudderPwm = NaN;
if isempty(trialName)
    return;
end
if isstring(trialName)
    trialName = char(trialName);
end
tok = regexp(lower(trialName), 'prop(\d+)rudder(\d+)', 'tokens', 'once');
if isempty(tok)
    return;
end
propPwm = str2double(tok{1});
rudderPwm = str2double(tok{2});
end

function applyPosterAxisFonts(axh)
if ismac
    tickFs = 72;
    lblFs = 72;
else
    tickFs = 54;
    lblFs = 54;
end
axh = axh(:);
for i = 1:numel(axh)
    ax = axh(i);
    if isempty(ax) || ~isgraphics(ax)
        continue;
    end
    set(ax, 'FontSize', tickFs, 'FontName', 'Arial');
    xl = get(ax, 'XLabel');
    yl = get(ax, 'YLabel');
    if isgraphics(xl)
        set(xl, 'FontSize', lblFs, 'FontWeight', 'bold');
    end
    if isgraphics(yl)
        set(yl, 'FontSize', lblFs, 'FontWeight', 'bold');
    end
end
end

function setFigureFullScreen(fig)
if nargin < 1 || isempty(fig) || ~ishandle(fig)
    fig = gcf;
end
set(fig, 'Units', 'pixels');
scr = get(0, 'ScreenSize');
padTopBottom = 80;
heightFrac = 0.86;  % keep plots tall
widthFrac = 0.62;   % narrower than full width for 3-column x-axis content
w = max(800, floor(scr(3) * widthFrac));
h = max(500, floor(scr(4) * heightFrac) - 2 * padTopBottom);
x = scr(1) + floor((scr(3) - w) / 2);
y = scr(2) + padTopBottom;
set(fig, 'Position', [x, y, w, h]);
end

function Ts = scalarTsFromIddata(z)
rawTs = z.Ts;
if isnumeric(rawTs) && isscalar(rawTs)
    Ts = double(rawTs);
elseif iscell(rawTs)
    nExp = numel(rawTs);
    if nExp < 1
        error('iddata has empty Ts cell array.');
    end
    vals = zeros(1, nExp);
    for kk = 1:nExp
        tk = rawTs{kk};
        if isduration(tk)
            vals(kk) = seconds(tk);
        elseif isnumeric(tk) && isscalar(tk)
            vals(kk) = double(tk);
        else
            error('Unsupported iddata.Ts{%d} type: %s', kk, class(tk));
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
for kk = 1:numel(idCsvFiles)
    f = idCsvFiles{kk};
    if isstring(f)
        if strlength(f) == 0
            continue;
        end
        f = char(f);
    end
    if ~ischar(f)
        error('idCsvFiles{%d} must be a character vector or string scalar.', kk);
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

function [u, y, t] = loadIoFromCsv(csvPath, requireYaw)
if nargin < 2
    requireYaw = true;
end
if ~isfile(csvPath)
    error('CSV file not found: %s', csvPath);
end
T = readtable(csvPath);
vn = T.Properties.VariableNames;
vnNorm = lower(strrep(strrep(strtrim(vn), '_', ''), ' ', ''));
idxTimestamp = find(strcmp(vnNorm, 'timestamp'), 1, 'first');
idxX = find(strcmp(vnNorm, 'x'), 1, 'first');
idxY = find(strcmp(vnNorm, 'y'), 1, 'first');
idxProp = find(strcmp(vnNorm, 'upropellerpwm'), 1, 'first');
if isempty(idxProp)
    idxProp = find(strcmp(vnNorm, 'pwmprop'), 1, 'first');
end
idxRudder = find(strcmp(vnNorm, 'urudderpwm'), 1, 'first');
if isempty(idxRudder)
    idxRudder = find(strcmp(vnNorm, 'pwmrudder'), 1, 'first');
end
idxYaw = find(strcmp(vnNorm, 'yaw'), 1, 'first');
if isempty(idxYaw)
    idxYaw = find(strcmp(vnNorm, 'heading'), 1, 'first');
end
missing = {};
if isempty(idxTimestamp), missing{end+1} = 'timestamp'; end %#ok<AGROW>
if isempty(idxX), missing{end+1} = 'x'; end %#ok<AGROW>
if isempty(idxY), missing{end+1} = 'y'; end %#ok<AGROW>
if isempty(idxProp), missing{end+1} = 'u_propeller_pwm or pwm prop'; end %#ok<AGROW>
if isempty(idxRudder), missing{end+1} = 'u_rudder_pwm or pwm rudder'; end %#ok<AGROW>
if requireYaw && isempty(idxYaw), missing{end+1} = 'yaw (or heading)'; end %#ok<AGROW>
if ~isempty(missing)
    error('Missing required column(s) in %s: %s', csvPath, strjoin(missing, ', '));
end
t = T{:, idxTimestamp};
u = [T{:, idxProp}, T{:, idxRudder}];
if isempty(idxYaw)
    yawCol = zeros(size(T{:, idxX}));
else
    yawCol = T{:, idxYaw};
end
y = [T{:, idxX}, T{:, idxY}, yawCol];
validRows = all(isfinite([u, y, t]), 2);
u = u(validRows, :);
y = y(validRows, :);
t = t(validRows, :);
if size(u, 1) < 20
    error('Not enough valid samples in %s after NaN filtering (%d rows).', csvPath, size(u, 1));
end
end

function [uOut, yOut, tOut] = cropSignalsToTime(u, y, t, cropEndTimeSec)
% End each segment when rudder command returns from turn (1800/2000 PWM) to
% neutral (1500 PWM). If that transition is not found, fall back to the
% legacy tail-trim behavior controlled by cropEndTimeSec.
rudderPwm = u(:, 2);
tolHigh = 15;
tolNeutral = 15;
isFromTurn = abs(rudderPwm(1:end-1) - 1800) <= tolHigh | abs(rudderPwm(1:end-1) - 2000) <= tolHigh;
isToNeutral = abs(rudderPwm(2:end) - 1500) <= tolNeutral;
transitionIdx = find(isFromTurn & isToNeutral, 1, 'first');

if ~isempty(transitionIdx)
    transitionTime = t(transitionIdx + 1);
    cutoffTime = transitionTime - 0.25; % crop 0.25 s before return-to-neutral
    keep = t <= cutoffTime;
elseif isempty(cropEndTimeSec)
    keep = true(size(t));
else
    if ~isfinite(cropEndTimeSec) || cropEndTimeSec <= 0
        error('cropEndTimeSec must be a positive finite scalar or empty.');
    end
    tRel = t - t(1);
    trialDurationSec = tRel(end);
    if cropEndTimeSec >= trialDurationSec
        error('cropEndTimeSec=%g is >= trial duration %g s.', cropEndTimeSec, trialDurationSec);
    end
    keep = tRel <= (trialDurationSec - cropEndTimeSec);
end

if nnz(keep) < 20
    error('Trim keeps too few samples (%d).', nnz(keep));
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

function masks = makeRegimeMasks(uRudderPwm, speed, yawUnwrapped, t, ...
    stepFromPwm, stepFromTol, stepDeltaMinPwm, maxPeakSearchSec, decelTailSec, regimeAMaxSec, ...
    settleAfterRegA_sec, circleRudderMinDeltaPwm, circleYawRateMinRadPerSec, circleMinSamples)
n = numel(t);
mA = false(n, 1);
mB = false(n, 1);
du = [0; diff(uRudderPwm)];
nearFrom = abs(uRudderPwm - stepFromPwm) <= stepFromTol;
stepCandidates = find((abs(du) >= stepDeltaMinPwm) & [false; nearFrom(1:end-1)]);
if isempty(stepCandidates)
    mA(:) = true;
    masks = struct('A', mA, 'B', mB);
    return;
end
stepIdx = stepCandidates(1); %#ok<NASGU>
regAEnd = max(1, stepCandidates(1) - 1);
mA(1:regAEnd) = true;
startB = min(n, regAEnd + 1);
mB(startB:end) = true;
unusedArgs = [maxPeakSearchSec, decelTailSec, regimeAMaxSec, ...
    settleAfterRegA_sec, circleRudderMinDeltaPwm, circleYawRateMinRadPerSec, circleMinSamples, ...
    mean(speed, 'omitnan'), mean(yawUnwrapped, 'omitnan')]; %#ok<NASGU>
masks = struct('A', mA, 'B', mB);
end

function cfg = makeFigureExportConfig(scriptDir)
cfg = struct();
cfg.outDir = fullfile(scriptDir, '..', 'processed_data');
if ~exist(cfg.outDir, 'dir')
    mkdir(cfg.outDir);
end
cfg.exportResolution = 220;
end

function exportFigurePng(fig, outPath, cfg)
set(fig, 'Color', 'w');
drawnow;
exportgraphics(fig, outPath, 'Resolution', cfg.exportResolution, ...
    'ContentType', 'image', 'BackgroundColor', 'white');
fprintf('Saved PNG: %s\n', outPath);
end
