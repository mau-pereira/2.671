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
addpath(fullfile(scriptDir, '..', 'MyFunctions'));
exportCfg = makeFigureExportConfig(scriptDir);

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

%% Optional tail trim on all loaded segments
% Set to a positive value (seconds) to remove that much time from the end
% of every trial. Example: 5 removes the last 5 seconds.
cropEndTimeSec = [2.1];

%% Paper-style estimation error (%): 100*abs(pred-real)/abs(real)
% For numerical stability when real ~ 0, denominator is max(abs(real), floor).
pctErrSpeedFloor_mps = 0.05;

% Legend NRMSE: 'std' => RMSE/sample std(measured y). 'range' => RMSE/(max(y)-min(y)).
legendNrmseMode = 'std';

modelOrder = 2;

%% Single validation trial (only this CSV is plotted)
validationCsvFile = 'prop1650rudder2000_3.csv';
plotRawOnly = true; % true: show only raw-data point plots (no lines), then stop.
plotAllRawXyInFolder = false; % true: plot X vs Y for every CSV in rawdata_all_data, then stop.
rawXyFolder = fullfile(scriptDir, 'deprecated_processing_scripts', 'rawdata_april22');

%% Regime segmentation controls (same style used in level3_plot.m)
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

%% Raw-data-only mode: plot X vs Y for all CSVs in rawXyFolder, then exit
if plotAllRawXyInFolder
    allCsvPaths = listExperimentCsvPaths(rawXyFolder);
    for iCsv = 1:numel(allCsvPaths)
        oneCsvPath = allCsvPaths{iCsv};
        [uRaw, yRawAll, tRawAll] = loadIoFromCsv(oneCsvPath, false);
        [~, yRawAll, ~] = cropSignalsToTime(uRaw, yRawAll, tRawAll, cropEndTimeSec);
        xRawAll = yRawAll(:, 1);
        yRawAllPos = yRawAll(:, 2);

        [~, oneName, oneExt] = fileparts(oneCsvPath);
        oneLabel = [oneName, oneExt];
        figXY = figure('Name', sprintf('Raw Y vs X: %s', oneLabel), 'Color', 'w');
        setFigureFullScreen(figXY);
        axXY = axes('Parent', figXY);
        scatter(axXY, xRawAll, yRawAllPos, 8, 'o', ...
            'MarkerEdgeColor', 'k', 'MarkerFaceColor', 'none', 'LineWidth', 0.6);
        xlabel(axXY, 'X');
        ylabel(axXY, 'Y');
        axis(axXY, 'equal');
        grid(axXY, 'on');
        improvePlot();
        applyPaddedAxes(axXY, xRawAll, yRawAllPos);
        setEqualDivisionTicks(axXY);
    end
    return;
end

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

%% Single validation CSV: one figure, speed + yaw real vs prediction
csvPath = fullfile(dataDir, validationCsvFile);
[uVal, yVal, tVal] = loadIoFromCsv(csvPath);
[uVal, yVal, tVal] = cropSignalsToTime(uVal, yVal, tVal, cropEndTimeSec);

%% Raw data plots (points only): y vs x and yaw vs time
tRaw = tVal - tVal(1);
xRaw = yVal(:, 1);
yRaw = yVal(:, 2);
yawRawDeg = rad2deg(yVal(:, 3));
[speedRaw, yawRawUnwrapped] = buildProcessedOutputs(yVal, tVal);
masksRaw = makeRegimeMasks(uVal(:, 2), speedRaw, yawRawUnwrapped, tVal, ...
    stepFromPwm, stepFromTol, stepDeltaMinPwm, ...
    maxPeakSearchSec, decelTailSec, regimeAMaxSec, ...
    settleAfterRegA_sec, circleRudderMinDeltaPwm, ...
    circleYawRateMinRadPerSec, circleMinSamples);

figRawXY = figure('Name', sprintf('Raw Y vs X: %s', validationCsvFile), 'Color', 'w');
setFigureFullScreen(figRawXY);
axRaw1 = axes('Parent', figRawXY);
hold(axRaw1, 'on');
if any(masksRaw.A)
    hRawA_xy = scatter(axRaw1, xRaw(masksRaw.A), yRaw(masksRaw.A), 10, 'o', ...
        'MarkerEdgeColor', [0.88, 0.22, 0.18], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
else
    hRawA_xy = scatter(axRaw1, NaN, NaN, 10, 'o', ...
        'MarkerEdgeColor', [0.88, 0.22, 0.18], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
end
if any(masksRaw.B)
    hRawB_xy = scatter(axRaw1, xRaw(masksRaw.B), yRaw(masksRaw.B), 10, 'o', ...
        'MarkerEdgeColor', [0.18, 0.42, 0.88], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
else
    hRawB_xy = scatter(axRaw1, NaN, NaN, 10, 'o', ...
        'MarkerEdgeColor', [0.18, 0.42, 0.88], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
end
xlabel(axRaw1, 'X (m)');
ylabel(axRaw1, 'Y (m)');
axis(axRaw1, 'equal');
grid(axRaw1, 'off');
axes(axRaw1); %#ok<LAXES>
improvePlot();
hold(axRaw1, 'off');

figRawYaw = figure('Name', sprintf('Raw Yaw vs Time: %s', validationCsvFile), 'Color', 'w');
setFigureFullScreen(figRawYaw);
axRaw2 = axes('Parent', figRawYaw);
hold(axRaw2, 'on');
if any(masksRaw.A)
    hRawA_yaw = scatter(axRaw2, tRaw(masksRaw.A), yawRawDeg(masksRaw.A), 10, 'o', ...
        'MarkerEdgeColor', [0.88, 0.22, 0.18], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
else
    hRawA_yaw = scatter(axRaw2, NaN, NaN, 10, 'o', ...
        'MarkerEdgeColor', [0.88, 0.22, 0.18], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
end
if any(masksRaw.B)
    hRawB_yaw = scatter(axRaw2, tRaw(masksRaw.B), yawRawDeg(masksRaw.B), 10, 'o', ...
        'MarkerEdgeColor', [0.18, 0.42, 0.88], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
else
    hRawB_yaw = scatter(axRaw2, NaN, NaN, 10, 'o', ...
        'MarkerEdgeColor', [0.18, 0.42, 0.88], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
end
xlabel(axRaw2, 'Time (s)');
ylabel(axRaw2, 'Yaw (degrees)');
grid(axRaw2, 'off');
axes(axRaw2); %#ok<LAXES>
improvePlot();
hold(axRaw2, 'off');

figRawLegend = figure('Name', sprintf('Legend: %s', validationCsvFile), 'Color', 'w');
axRawL = axes('Parent', figRawLegend);
hold(axRawL, 'on');
hLegA = scatter(axRawL, NaN, NaN, 10, 'o', ...
    'MarkerEdgeColor', [0.88, 0.22, 0.18], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
hLegB = scatter(axRawL, NaN, NaN, 10, 'o', ...
    'MarkerEdgeColor', [0.18, 0.42, 0.88], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
axis(axRawL, 'off');
legend(axRawL, [hLegA, hLegB], {'Regime A', 'Regime B'}, ...
    'Location', 'north', 'Interpreter', 'none', 'Box', 'on');
improvePlot();
hold(axRawL, 'off');

applyPaddedAxesCustom(axRaw1, xRaw, yRaw, 0.04);
setEqualDivisionTicks(axRaw1);
applyPaddedAxes(axRaw2, tRaw, yawRawDeg);

% Export raw-only figures to data_folder/processed_data
rawExportDir = fullfile(scriptDir, '..', 'processed_data');
if ~exist(rawExportDir, 'dir')
    mkdir(rawExportDir);
end
exportFigurePng(figRawXY, fullfile(rawExportDir, 'level1_trajectory.png'), exportCfg);
exportFigurePng(figRawYaw, fullfile(rawExportDir, 'level1_yaw.png'), exportCfg);
exportFigurePng(figRawLegend, fullfile(rawExportDir, 'level1_legened.png'), exportCfg);

if plotRawOnly
    return;
end

[uPropPctVal, uRudderDegVal] = buildProcessedInputs(uVal);
uValProc = [uPropPctVal, uRudderDegVal];
[speedVal, yawValProc] = buildProcessedOutputs(yVal, tVal);
yValProc = [speedVal, yawValProc];

zVal = iddata(yValProc, uValProc, Ts, ...
    'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
    'OutputName', {'speed', 'yaw'});

yValSim = sim(sys, zVal.u);
tPlot = tVal - tVal(1);
yawRealWrapped = wrapToPiLocal(yValProc(:, 2));
yawPredWrapped = wrapToPiLocal(yValSim(:, 2));
yawRealWrappedDeg = rad2deg(yawRealWrapped);
yawPredWrappedDeg = rad2deg(yawPredWrapped);

masks = makeRegimeMasks(uVal(:, 2), speedVal, yawValProc, tVal, ...
    stepFromPwm, stepFromTol, stepDeltaMinPwm, ...
    maxPeakSearchSec, decelTailSec, regimeAMaxSec, ...
    settleAfterRegA_sec, circleRudderMinDeltaPwm, ...
    circleYawRateMinRadPerSec, circleMinSamples);

figOutputs = figure('Name', sprintf('n4sid: %s (ID: %s)', validationCsvFile, idLabel), 'Color', 'w');
setFigureFullScreen(figOutputs);
tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
ax1 = gca;
hold(ax1, 'on');
hSpdReal = plot(ax1, tPlot, yValProc(:, 1), 'k-', 'LineWidth', 2.4);
hSpdPred = plot(ax1, tPlot, yValSim(:, 1), 'k--', 'LineWidth', 2.4);
shadeRegimeBackground(ax1, tPlot, masks.A, [1.0, 0.70, 0.70], 0.60);
shadeRegimeBackground(ax1, tPlot, masks.B, [0.70, 0.80, 1.0], 0.60);
uistack([hSpdReal, hSpdPred], 'top');
ylabel('Speed (m/s)');
% hRegA1 = patch(ax1, NaN, NaN, [1.0, 0.70, 0.70], 'EdgeColor', 'none', 'FaceAlpha', 0.60);
% hRegB1 = patch(ax1, NaN, NaN, [0.70, 0.80, 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.60);
% legend(ax1, [hSpdReal, hSpdPred, hRegA1, hRegB1], ...
%     {'Real', 'Predicted', 'Regime A', 'Regime B'}, 'Location', 'eastoutside');
grid(ax1, 'off');
hold(ax1, 'off');

nexttile;
ax2 = gca;
hold(ax2, 'on');
hYawReal = plot(ax2, tPlot, yawRealWrappedDeg, 'k-', 'LineWidth', 2.4);
hYawPred = plot(ax2, tPlot, yawPredWrappedDeg, 'k--', 'LineWidth', 2.4);
shadeRegimeBackground(ax2, tPlot, masks.A, [1.0, 0.70, 0.70], 0.60);
shadeRegimeBackground(ax2, tPlot, masks.B, [0.70, 0.80, 1.0], 0.60);
uistack([hYawReal, hYawPred], 'top');
xlabel('Time (s)');
ylabel('Yaw (degrees)');
% hRegA2 = patch(ax2, NaN, NaN, [1.0, 0.70, 0.70], 'EdgeColor', 'none', 'FaceAlpha', 0.60);
% hRegB2 = patch(ax2, NaN, NaN, [0.70, 0.80, 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.60);
% legend(ax2, [hYawReal, hYawPred, hRegA2, hRegB2], ...
%     {'Real', 'Predicted', 'Regime A', 'Regime B'}, 'Location', 'eastoutside');
grid(ax2, 'off');
hold(ax2, 'off');

improvePlot();

% Apply padding after improvePlot() so axis limits are not overwritten.
applyPaddedAxes(ax1, tPlot, [yValProc(:, 1); yValSim(:, 1)]);
applyPaddedAxes(ax2, tPlot, [yawRealWrappedDeg; yawPredWrappedDeg]);

%% Second figure: control inputs vs time (propeller % and rudder degrees)
figInputs = figure('Name', sprintf('Inputs: %s', validationCsvFile), 'Color', 'w');
setFigureFullScreen(figInputs);
tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
ax3 = gca;
hold(ax3, 'on');
hPropCmd = plot(ax3, tPlot, uPropPctVal, 'k-', 'LineWidth', 2.4);
shadeRegimeBackground(ax3, tPlot, masks.A, [1.0, 0.70, 0.70], 0.60);
shadeRegimeBackground(ax3, tPlot, masks.B, [0.70, 0.80, 1.0], 0.60);
uistack(hPropCmd, 'top');
ylabel('Propeller Thrust (%)');
% hRegA3 = patch(ax3, NaN, NaN, [1.0, 0.70, 0.70], 'EdgeColor', 'none', 'FaceAlpha', 0.60);
% hRegB3 = patch(ax3, NaN, NaN, [0.70, 0.80, 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.60);
% legend(ax3, [hPropCmd, hRegA3, hRegB3], ...
%     {'Command', 'Regime A', 'Regime B'}, 'Location', 'eastoutside');
grid(ax3, 'off');
hold(ax3, 'off');

nexttile;
ax4 = gca;
hold(ax4, 'on');
hRudCmd = plot(ax4, tPlot, uRudderDegVal, 'k-', 'LineWidth', 2.4);
shadeRegimeBackground(ax4, tPlot, masks.A, [1.0, 0.70, 0.70], 0.60);
shadeRegimeBackground(ax4, tPlot, masks.B, [0.70, 0.80, 1.0], 0.60);
uistack(hRudCmd, 'top');
xlabel('Time (s)');
ylabel('Propeller Angle (degrees)');
% hRegA4 = patch(ax4, NaN, NaN, [1.0, 0.70, 0.70], 'EdgeColor', 'none', 'FaceAlpha', 0.60);
% hRegB4 = patch(ax4, NaN, NaN, [0.70, 0.80, 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.60);
% legend(ax4, [hRudCmd, hRegA4, hRegB4], ...
%     {'Command', 'Regime A', 'Regime B'}, 'Location', 'eastoutside');
grid(ax4, 'off');
hold(ax4, 'off');

improvePlot();

% Apply padding after improvePlot() so axis limits are not overwritten.
applyPaddedAxes(ax3, tPlot, uPropPctVal);
applyPaddedAxes(ax4, tPlot, uRudderDegVal);

%% Standalone legend figure (Real / Predicted / Regime A / Regime B)
figLegend = figure('Name', 'Legend (real vs predicted)', 'Color', 'w');
axL = axes('Parent', figLegend);
hold(axL, 'on');
hLegReal  = plot(axL, NaN, NaN, 'k-',  'LineWidth', 2.4);
hLegPred  = plot(axL, NaN, NaN, 'k--', 'LineWidth', 2.4);
hLegRegA  = patch(axL, NaN, NaN, [1.0, 0.70, 0.70], 'EdgeColor', 'none', 'FaceAlpha', 0.60);
hLegRegB  = patch(axL, NaN, NaN, [0.70, 0.80, 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.60);
axis(axL, 'off');
lgd = legend(axL, [hLegReal, hLegPred, hLegRegA, hLegRegB], ...
    {'Real', 'Predicted', 'Regime A', 'Regime B'}, ...
    'Orientation', 'vertical', 'Location', 'north', 'Box', 'on');
set(lgd, 'FontSize', 16);
improvePlot();

%% Export figures to processed_data
% exportFigurePng(figOutputs, fullfile(exportCfg.outDir, 'level1_2_outputs_and_validation.png'), exportCfg);
% exportFigurePng(figInputs,  fullfile(exportCfg.outDir, 'level1_2_inputs.png'), exportCfg);
% exportFigurePng(figLegend,  fullfile(exportCfg.outDir, 'level1_2_legend.png'), exportCfg);

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
trialDurationSec = tRel(end);
if cropEndTimeSec >= trialDurationSec
    error('cropEndTimeSec=%g is >= trial duration %g s.', cropEndTimeSec, trialDurationSec);
end

% Keep all samples up to (end - cropEndTimeSec): trim only tail portion.
keep = tRel <= (trialDurationSec - cropEndTimeSec);
if nnz(keep) < 20
    error('Tail trim keeps too few samples (%d). Decrease cropEndTimeSec.', nnz(keep));
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

function masks = makeRegimeMasks(uRudderPwm, speed, yawUnwrapped, t, ...
    stepFromPwm, stepFromTol, stepDeltaMinPwm, maxPeakSearchSec, decelTailSec, regimeAMaxSec, ...
    settleAfterRegA_sec, circleRudderMinDeltaPwm, circleYawRateMinRadPerSec, circleMinSamples)
% Same regime style used in level3_plot.m.
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

% Keep the same A/B split behavior used in the level3 helper.
stepIdx = stepCandidates(1); %#ok<NASGU,ASGLU>
regAEnd = max(1, stepCandidates(1) - 1);
mA(1:regAEnd) = true;
startB = min(n, regAEnd + 1);
mB(startB:end) = true;

% Unused arguments intentionally kept to preserve a compatible call shape.
unusedArgs = [maxPeakSearchSec, decelTailSec, regimeAMaxSec, ...
    settleAfterRegA_sec, circleRudderMinDeltaPwm, circleYawRateMinRadPerSec, circleMinSamples, ...
    mean(speed, 'omitnan'), mean(yawUnwrapped, 'omitnan')]; %#ok<NASGU>

masks = struct('A', mA, 'B', mB);
end

function shadeRegimeBackground(ax, tPlot, mask, colorRgb, alphaVal)
if ~any(mask)
    return;
end
yl = ylim(ax);
[starts, ends] = maskToSegments(mask);
for i = 1:numel(starts)
    x1 = tPlot(starts(i));
    x2 = tPlot(ends(i));
    patch(ax, [x1 x2 x2 x1], [yl(1) yl(1) yl(2) yl(2)], colorRgb, ...
        'FaceAlpha', alphaVal, 'EdgeColor', 'none', 'HandleVisibility', 'off');
end
uistack(findobj(ax, 'Type', 'patch'), 'bottom');
end

function [starts, ends] = maskToSegments(mask)
mask = mask(:);
d = diff([false; mask; false]);
starts = find(d == 1);
ends = find(d == -1) - 1;
end

function applyPaddedAxes(ax, tVals, yVals)
xMin = min(tVals);
xMax = max(tVals);
xSpan = max(eps, xMax - xMin);
xPad = 0.02 * xSpan;
xlim(ax, [xMin - xPad, xMax + xPad]);

yMin = min(yVals);
yMax = max(yVals);
ySpan = max(eps, yMax - yMin);
yPad = 0.18 * ySpan;
ylim(ax, [yMin - yPad, yMax + yPad]);
end

function applyPaddedAxesCustom(ax, xVals, yVals, padFrac)
if nargin < 4 || ~isfinite(padFrac) || padFrac < 0
    padFrac = 0.18;
end
xMin = min(xVals);
xMax = max(xVals);
xSpan = max(eps, xMax - xMin);
xPad = padFrac * xSpan;
xlim(ax, [xMin - xPad, xMax + xPad]);

yMin = min(yVals);
yMax = max(yVals);
ySpan = max(eps, yMax - yMin);
yPad = padFrac * ySpan;
ylim(ax, [yMin - yPad, yMax + yPad]);
end

function setEqualDivisionTicks(ax)
% Force equal x/y tick spacing for XY scatter readability.
xl = xlim(ax);
yl = ylim(ax);
targetTicks = 6;
step = niceTickStep(max(diff(xl), diff(yl)) / targetTicks);
if ~isfinite(step) || step <= 0
    return;
end
xt = (ceil(xl(1) / step) * step):step:(floor(xl(2) / step) * step);
yt = (ceil(yl(1) / step) * step):step:(floor(yl(2) / step) * step);
if numel(xt) >= 2
    set(ax, 'XTick', xt);
end
if numel(yt) >= 2
    set(ax, 'YTick', yt);
end
axis(ax, 'equal');
end

function s = niceTickStep(v)
if ~isfinite(v) || v <= 0
    s = NaN;
    return;
end
e = floor(log10(v));
f = v / 10^e;
if f <= 1
    nf = 1;
elseif f <= 2
    nf = 2;
elseif f <= 5
    nf = 5;
else
    nf = 10;
end
s = nf * 10^e;
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
% Export the figure at its current on-screen aspect ratio (no forced square).
set(fig, 'Color', 'w');
drawnow;
exportgraphics(fig, outPath, 'Resolution', cfg.exportResolution, ...
    'ContentType', 'image', 'BackgroundColor', 'white');
fprintf('Saved PNG: %s\n', outPath);
end

function setFigureFullScreen(fig)
% Make the figure occupy nearly the full screen (wide rectangle, not square).
if nargin < 1 || isempty(fig) || ~ishandle(fig)
    fig = gcf;
end
set(fig, 'Units', 'pixels');
scr = get(0, 'ScreenSize'); % [left bottom width height]
padLeftRight = 30;
padTopBottom = 80; % leave room for title bar / taskbar
w = max(800, scr(3) - 2 * padLeftRight);
h = max(500, scr(4) - 2 * padTopBottom);
x = scr(1) + padLeftRight;
y = scr(2) + padTopBottom;
set(fig, 'Position', [x, y, w, h]);
end
