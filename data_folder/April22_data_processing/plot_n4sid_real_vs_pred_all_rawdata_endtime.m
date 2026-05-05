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
idCsvPath = [];%['C:\Users\M\OneDrive - Massachusetts Institute of Technology\00 - Spring 2026\2.671\2.671 Project\code\camera\data_folder\April22_data_processing\rawdata_all_data\prop1675rudder2000_3.csv'];

% Option B — hand-pick any number of CSVs (same columns as the trial files).
% Used when Option C is false and Option A is not used (idCsvPath is empty). Each string is either:
%   • a file name in rawdata_all_data (e.g. 'prop1625rudder2000_3.csv'), or
%   • a full path to a CSV anywhere (if that file exists).
% Order is kept; all listed files are merged into one iddata for n4sid.
idCsvFiles = {
    'prop1625rudder1800_2.csv'
    'prop1650rudder1800_4.csv'
    'prop1675rudder1800_5.csv'

    'prop1625rudder2000_2.csv'
    'prop1650rudder2000_3.csv'
    'prop1675rudder2000_1.csv'

    };

%% Optional tail trim on all loaded segments
% Set to a positive value (seconds) to remove that much time from the end
% of every trial. Example: 5 removes the last 5 seconds.
cropEndTimeSec = [2];

%% Paper-style estimation error (%): 100*abs(pred-real)/abs(real)
% For numerical stability when real ~ 0, denominator is max(abs(real), floor).
pctErrSpeedFloor_mps = 0.05;

% Legend NRMSE: 'std' => RMSE/sample std(measured y). 'range' => RMSE/(max(y)-min(y)).
legendNrmseMode = 'std';

modelOrder = 2;

% When true, writes may_level3_n4sid_bundle.mat next to this script so may_level3.m
% can load the same sys/Ts without re-running n4sid.
exportMayLevel3N4sidBundle = true;

%% Single validation trial (only this CSV is plotted)
validationCsvFile = 'prop1675rudder1800_3.csv'; % must exist under rawdata_all_data (invalid_* lives under deprecated_processing_scripts)
plotRawOnly = false; % true: show only raw-data point plots (no lines), then stop.
plotAllRawXyInFolder = false; % true: plot X vs Y for every CSV in rawdata_all_data, then stop.
plotAllTrials = true; % true: model-vs-real comparison for every CSV in dataDir; false: only validationCsvFile.
rawXyFolder = fullfile(scriptDir, 'deprecated_processing_scripts', 'rawdata_april22');

%% Regime segmentation (Acceleration Test / Turning Test; same style as level3_plot.m)
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

%% Plot styling (fonts 3× MyFunctions/improvePlot.m tick/label; thick model/input time traces)
plotLineWidthTimeSeries = 6.8;
plotLineWidthRealPred = 0.5 * plotLineWidthTimeSeries; % 25% thinner for real-vs-predicted speed/yaw traces
plotLineWidthRealOnly = 0.5 * plotLineWidthRealPred; % real line is half the current real-vs-predicted width
plotLineWidthInputOnly = 0.5 * plotLineWidthTimeSeries; % input traces are half the current width
plotLineWidthLegendSwatches = 2.0; % Real/Predicted line icons in standalone legend only (thinner than plots)
trajectoryAxisDisplaySpanM = 2; % X: x''=x_right−x; tick labels read 0..this (m) at left edge
trajectoryYTickDisplayMinM = 0.5; % Y axis numbers only (world y stays data-snapped; else trajectory clips)
trajectoryYTickDisplayMaxM = 2;
rawPlotYPadFrac = 0.04; % Y-axis only: fraction of data span (raw trajectories + raw yaw)
propThrustYAxisMaxPct = 30; % prop thrust Y ticks/limit include this percent (full scale)
timeSeriesYTickTarget = 7; % speed & yaw (was 5 + 2)
regimeShadeColorA = [1.0, 0.70, 0.70]; % regime A (Acceleration)
regimeShadeColorB = [0.70, 0.80, 1.0]; % regime B (Turning)
regimeShadeAlpha = 0.60;

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
        xlim(axXY, [min(xRawAll), max(xRawAll)]);
        ylim(axXY, [min(yRawAllPos), max(yRawAllPos)]);
        set(axXY, 'XDir', 'normal', 'YDir', 'normal');
        axis(axXY, 'equal');
        setEqualDivisionTicks(axXY);
        setTrajectoryXYDisplayTicks(axXY, xRawAll, yRawAllPos, trajectoryAxisDisplaySpanM, ...
            [], [], trajectoryYTickDisplayMinM, trajectoryYTickDisplayMaxM, rawPlotYPadFrac);
        applyPosterAxisFonts(axXY);
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

if exportMayLevel3N4sidBundle
    bundleFile = fullfile(scriptDir, 'may_level3_n4sid_bundle.mat');
    save(bundleFile, 'sys', 'Ts', 'idLabel', 'cropEndTimeSec', 'modelOrder', '-v7.3');
    fprintf('Saved n4sid bundle for may_level3.m: %s\n', bundleFile);
end

%% Single validation CSV: one figure, speed + yaw real vs prediction
csvPath = fullfile(dataDir, validationCsvFile);
[uVal, yVal, tVal] = loadIoFromCsv(csvPath);
[uVal, yVal, tVal] = cropSignalsToTime(uVal, yVal, tVal, cropEndTimeSec);

%% Raw data plots (points only): y vs x and yaw vs time
tRaw = tVal - tVal(1);
xRaw = yVal(:, 1);
yRaw = yVal(:, 2);
[speedRaw, yawRawUnwrapped] = buildProcessedOutputs(yVal, tVal);
% Use unwrapped yaw (continuous, no sawtooth jumps) for the raw yaw plot.
% yawRawDeg = rad2deg(yawRawUnwrapped);
% Zero at t=0 like real-vs-predicted yaw (same vertical offset convention).
% yawRawDegZeroed = yawRawDeg - yawRawDeg(1);
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

% figRawYaw = figure('Name', sprintf('Raw Yaw vs Time: %s', validationCsvFile), 'Color', 'w');
% setFigureFullScreen(figRawYaw);
% axRaw2 = axes('Parent', figRawYaw);
% hold(axRaw2, 'on');
% if any(masksRaw.A)
%     hRawA_yaw = scatter(axRaw2, tRaw(masksRaw.A), yawRawDegZeroed(masksRaw.A), 10, 'o', ...
%         'MarkerEdgeColor', [0.88, 0.22, 0.18], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
% else
%     hRawA_yaw = scatter(axRaw2, NaN, NaN, 10, 'o', ...
%         'MarkerEdgeColor', [0.88, 0.22, 0.18], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
% end
% if any(masksRaw.B)
%     hRawB_yaw = scatter(axRaw2, tRaw(masksRaw.B), yawRawDegZeroed(masksRaw.B), 10, 'o', ...
%         'MarkerEdgeColor', [0.18, 0.42, 0.88], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
% else
%     hRawB_yaw = scatter(axRaw2, NaN, NaN, 10, 'o', ...
%         'MarkerEdgeColor', [0.18, 0.42, 0.88], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
% end
% xlabel(axRaw2, 'Time (s)');
% ylabel(axRaw2, 'Yaw (degrees)');
% grid(axRaw2, 'off');
% axes(axRaw2); %#ok<LAXES>
% improvePlot();
% hold(axRaw2, 'off');

% figRawLegend = figure('Name', sprintf('Legend: %s', validationCsvFile), 'Color', 'w');
% axRawL = axes('Parent', figRawLegend);
% hold(axRawL, 'on');
% hLegA = scatter(axRawL, NaN, NaN, 10, 'o', ...
%     'MarkerEdgeColor', [0.88, 0.22, 0.18], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
% hLegB = scatter(axRawL, NaN, NaN, 10, 'o', ...
%     'MarkerEdgeColor', [0.18, 0.42, 0.88], 'MarkerFaceColor', 'none', 'LineWidth', 0.7);
% axis(axRawL, 'off');
% legend(axRawL, [hLegA, hLegB], {'Acceleration Test', 'Turning Test'}, ...
%     'Location', 'north', 'Interpreter', 'none', 'Box', 'on');
% improvePlot();
% setPosterLegendFontSize(figRawLegend);
% applyPosterAxisFonts(axRawL);
% hold(axRawL, 'off');

xlim(axRaw1, [min(xRaw), max(xRaw)]);
ylim(axRaw1, [min(yRaw), max(yRaw)]);
set(axRaw1, 'XDir', 'normal', 'YDir', 'normal');
axis(axRaw1, 'equal');
setEqualDivisionTicks(axRaw1);
setTrajectoryXYDisplayTicks(axRaw1, xRaw, yRaw, trajectoryAxisDisplaySpanM, ...
    [], [], trajectoryYTickDisplayMinM, trajectoryYTickDisplayMaxM, rawPlotYPadFrac);
% applyPaddedAxes(axRaw2, tRaw, yawRawDegZeroed);
applyPosterAxisFonts(axRaw1);
% sparseYTicks(axRaw2, timeSeriesYTickTarget);

% Export raw-only figures to data_folder/processed_data
rawExportDir = fullfile(scriptDir, '..', 'processed_data');
if ~exist(rawExportDir, 'dir')
    mkdir(rawExportDir);
end
% exportFigurePng(figRawXY, fullfile(rawExportDir, 'level1_trajectory.png'), exportCfg);
% exportFigurePng(figRawYaw, fullfile(rawExportDir, 'level1_yaw.png'), exportCfg);
% exportFigurePng(figRawLegend, fullfile(rawExportDir, 'level1_legened.png'), exportCfg);

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

%% Build list of validation CSVs to compare against the model
if plotAllTrials
    valPathsLoop = listExperimentCsvPaths(dataDir);
else
    valPathsLoop = {fullfile(dataDir, validationCsvFile)};
end

%% One real-vs-predicted figure per validation trial
for iVal = 1:numel(valPathsLoop)
    csvPathLoop = valPathsLoop{iVal};
    [~, valNameLoop, valExtLoop] = fileparts(csvPathLoop);
    valLabelLoop = [valNameLoop, valExtLoop];

    [uValL, yValL, tValL] = loadIoFromCsv(csvPathLoop);
    [uValL, yValL, tValL] = cropSignalsToTime(uValL, yValL, tValL, cropEndTimeSec);

    [uPropPctL, uRudderDegL] = buildProcessedInputs(uValL);
    uValProcL = [uPropPctL, uRudderDegL];
    [speedValL, yawValProcL] = buildProcessedOutputs(yValL, tValL);
    yValProcL = [speedValL, yawValProcL];

    zValL = iddata(yValProcL, uValProcL, Ts, ...
        'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
        'OutputName', {'speed', 'yaw'});

    % Simulate from the default zero initial state. Speed is left as-is
    % (the model was characterized around small/zero states, so x0 = 0
    % gives the most reliable speed prediction). Yaw, on the other hand,
    % behaves like a pure integrator state: any constant additive offset
    % is dynamically harmless. We zero both the real and predicted yaw at
    % t = 0 so the plot starts cleanly at 0 deg, while preserving the
    % shape of each curve.
    yValSimL = sim(sys, zValL.u);
    tPlotL = tValL - tValL(1);
    yawRealRad = yValProcL(:, 2);
    yawPredRad = yValSimL(:, 2);
    yawRealRadZeroed = yawRealRad - yawRealRad(1);
    yawPredRadZeroed = yawPredRad - yawPredRad(1);
    yawRealDegL = rad2deg(yawRealRadZeroed);
    yawPredDegL = rad2deg(yawPredRadZeroed);

    masksL = makeRegimeMasks(uValL(:, 2), speedValL, yawValProcL, tValL, ...
        stepFromPwm, stepFromTol, stepDeltaMinPwm, ...
        maxPeakSearchSec, decelTailSec, regimeAMaxSec, ...
        settleAfterRegA_sec, circleRudderMinDeltaPwm, ...
        circleYawRateMinRadPerSec, circleMinSamples);

    figSpeed = figure('Name', sprintf('Speed: %s (ID: %s)', valLabelLoop, idLabel), 'Color', 'w');
    setFigureFullScreen(figSpeed);
    ax1 = axes('Parent', figSpeed);
    hold(ax1, 'on');
    hSpdReal = plot(ax1, tPlotL, yValProcL(:, 1), 'k-', 'LineWidth', plotLineWidthRealOnly);
    hSpdPred = plot(ax1, tPlotL, yValSimL(:, 1), 'k--', 'LineWidth', plotLineWidthRealPred);
    uistack(hSpdReal, 'top');
    uistack(hSpdPred, 'top');
    xlabel(ax1, 'Time (s)');
    ylabel(ax1, 'Speed (m/s)');
    grid(ax1, 'off');
    hold(ax1, 'off');

    figYaw = figure('Name', sprintf('Yaw: %s (ID: %s)', valLabelLoop, idLabel), 'Color', 'w');
    setFigureFullScreen(figYaw);
    ax2 = axes('Parent', figYaw);
    hold(ax2, 'on');
    hYawReal = plot(ax2, tPlotL, yawRealDegL, 'k-', 'LineWidth', plotLineWidthRealOnly);
    hYawPred = plot(ax2, tPlotL, yawPredDegL, 'k--', 'LineWidth', plotLineWidthRealPred);
    uistack(hYawReal, 'top');
    uistack(hYawPred, 'top');
    xlabel(ax2, 'Time (s)');
    ylabel(ax2, 'Yaw (degrees)');
    grid(ax2, 'off');
    hold(ax2, 'off');

    figure(figSpeed);
    improvePlot();
    figure(figYaw);
    improvePlot();

    % Apply padding after improvePlot(), then regime shading so patches span full ylim.
    applyPaddedAxes(ax1, tPlotL, [yValProcL(:, 1); yValSimL(:, 1)]);
    shadeRegimeBackground(ax1, tPlotL, masksL.A, regimeShadeColorA, regimeShadeAlpha);
    shadeRegimeBackground(ax1, tPlotL, masksL.B, regimeShadeColorB, regimeShadeAlpha);
    uistack(hSpdReal, 'top');
    uistack(hSpdPred, 'top');
    applyPosterAxisFonts(ax1);
    sparseYTicks(ax1, timeSeriesYTickTarget);

    applyPaddedAxes(ax2, tPlotL, [yawRealDegL; yawPredDegL]);
    shadeRegimeBackground(ax2, tPlotL, masksL.A, regimeShadeColorA, regimeShadeAlpha);
    shadeRegimeBackground(ax2, tPlotL, masksL.B, regimeShadeColorB, regimeShadeAlpha);
    uistack(hYawReal, 'top');
    uistack(hYawPred, 'top');
    applyPosterAxisFonts(ax2);
    sparseYTicks(ax2, timeSeriesYTickTarget);

    % Trajectory XY stats only (path plot is raw section level1_trajectory, not a separate figure).
    xRawL = yValL(:, 1);
    yRawL = yValL(:, 2);
    xMinL = min(xRawL); xMaxL = max(xRawL);
    yMinL = min(yRawL); yMaxL = max(yRawL);
    xSpanL = xMaxL - xMinL;
    ySpanL = yMaxL - yMinL;
    fprintf(['Trajectory %s | X range = [%.3f, %.3f] m (span %.3f m), ', ...
        'Y range = [%.3f, %.3f] m (span %.3f m), span ratio Y/X = %.3f\n'], ...
        valLabelLoop, xMinL, xMaxL, xSpanL, yMinL, yMaxL, ySpanL, ...
        ySpanL / max(xSpanL, eps));
end

%% Inputs vs time (separate figures: prop thrust %, prop angle)
figPropThrust = figure('Name', sprintf('Prop thrust %%: %s', validationCsvFile), 'Color', 'w');
setFigureFullScreen(figPropThrust);
ax3 = axes('Parent', figPropThrust);
hold(ax3, 'on');
hPropCmd = plot(ax3, tPlot, uPropPctVal, 'k-', 'LineWidth', plotLineWidthInputOnly);
uistack(hPropCmd, 'top');
xlabel(ax3, 'Time (s)');
ylabel(ax3, 'Propeller Thrust (%)');
grid(ax3, 'off');
hold(ax3, 'off');

figPropAngle = figure('Name', sprintf('Prop angle: %s', validationCsvFile), 'Color', 'w');
setFigureFullScreen(figPropAngle);
ax4 = axes('Parent', figPropAngle);
hold(ax4, 'on');
hRudCmd = plot(ax4, tPlot, uRudderDegVal, 'k-', 'LineWidth', plotLineWidthInputOnly);
uistack(hRudCmd, 'top');
xlabel(ax4, 'Time (s)');
ylabel(ax4, 'Propeller Angle (degrees)');
grid(ax4, 'off');
hold(ax4, 'off');

figure(figPropThrust);
improvePlot();
figure(figPropAngle);
improvePlot();

% Apply padding after improvePlot() so axis limits are not overwritten.
% Prop thrust: Y padding like applyPaddedAxes (18% of data span); yTop at least 30 percent; YTick 0, 15, 30.
xMinT = min(tPlot(:)); xMaxT = max(tPlot(:));
xSpanT = max(eps, xMaxT - xMinT);
xPadT = 0.02 * xSpanT;
xlim(ax3, [xMinT - xPadT, xMaxT + xPadT]);
yMinP = min(uPropPctVal(:));
yMaxP = max(uPropPctVal(:));
ySpanP = max(eps, yMaxP - yMinP);
yPadP = 0.18 * ySpanP;
yBotP = min(yMinP - yPadP, 0);
yTopP = max(propThrustYAxisMaxPct, yMaxP + yPadP);
ylim(ax3, [yBotP, yTopP]);
set(ax3, 'YTick', [0, 15, propThrustYAxisMaxPct]);
shadeRegimeBackground(ax3, tPlot, masks.A, regimeShadeColorA, regimeShadeAlpha);
shadeRegimeBackground(ax3, tPlot, masks.B, regimeShadeColorB, regimeShadeAlpha);
uistack(hPropCmd, 'top');
applyPosterAxisFonts(ax3);

applyPaddedAxes(ax4, tPlot, uRudderDegVal);
shadeRegimeBackground(ax4, tPlot, masks.A, regimeShadeColorA, regimeShadeAlpha);
shadeRegimeBackground(ax4, tPlot, masks.B, regimeShadeColorB, regimeShadeAlpha);
uistack(hRudCmd, 'top');
applyPosterAxisFonts(ax4);
sparseYTicks(ax4, 5);

% %% Standalone legend figure (Real / Predicted / Acceleration Test / Turning Test)
% figLegend = figure('Name', 'Legend (real vs predicted)', 'Color', 'w');
% axL = axes('Parent', figLegend);
% hold(axL, 'on');
% hLegReal  = plot(axL, NaN, NaN, 'k-',  'LineWidth', plotLineWidthLegendSwatches);
% hLegPred  = plot(axL, NaN, NaN, 'k--', 'LineWidth', plotLineWidthLegendSwatches);
% hLegRegA  = patch(axL, NaN, NaN, regimeShadeColorA, 'EdgeColor', 'none', 'FaceAlpha', regimeShadeAlpha);
% hLegRegB  = patch(axL, NaN, NaN, regimeShadeColorB, 'EdgeColor', 'none', 'FaceAlpha', regimeShadeAlpha);
% axis(axL, 'off');
% lgd = legend(axL, [hLegReal, hLegPred, hLegRegA, hLegRegB], ...
%     {'Real', 'Predicted', 'Acceleration Test', 'Turning Test'}, ...
%     'Orientation', 'vertical', 'Location', 'north', 'Box', 'on');
% improvePlot();
% setPosterLegendFontSize(figLegend);
% applyPosterAxisFonts(axL);

%% Export figures to processed_data
% exportFigurePng(figSpeed, fullfile(exportCfg.outDir, 'level1_2_speed_vs_time.png'), exportCfg);
% exportFigurePng(figYaw, fullfile(exportCfg.outDir, 'level1_2_yaw_vs_time.png'), exportCfg);
% exportFigurePng(figPropThrust, fullfile(exportCfg.outDir, 'level1_2_prop_thrust_vs_time.png'), exportCfg);
% exportFigurePng(figPropAngle, fullfile(exportCfg.outDir, 'level1_2_prop_angle_vs_time.png'), exportCfg);
% exportFigurePng(figLegend, fullfile(exportCfg.outDir, 'level1_2_legend.png'), exportCfg);

%% --- Local functions -------------------------------------------------

function applyPosterAxisFonts(axh)
% Tick and axis-label fonts: 3× improvePlot defaults (2× then 1.5×): PC 54/54, Mac 72/72.
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

function setPosterLegendFontSize(fig)
% Legend text only: same as data_folder/MyFunctions/improvePlot.m (axis fonts stay larger).
if nargin < 1 || isempty(fig) || ~isgraphics(fig)
    fig = gcf;
end
hLeg = findall(fig, 'Type', 'legend');
if isempty(hLeg)
    return;
end
if ismac
    fs = 20;
else
    fs = 16;
end
set(hLeg, 'FontSize', fs);
end

function sparseYTicks(ax, nTarget)
% Reduce Y tick count after ylim is final; uses niceTickStep in this file.
if isempty(ax) || ~isgraphics(ax)
    return;
end
nTarget = max(3, min(10, double(nTarget)));
yl = ylim(ax);
span = max(eps, yl(2) - yl(1));
step = niceTickStep(span / max(nTarget - 1, 1));
if ~isfinite(step) || step <= 0
    return;
end
v1 = ceil(yl(1) / step - 1e-9) * step;
v2 = floor(yl(2) / step + 1e-9) * step;
yt = v1:step:v2;
if isempty(yt)
    return;
end
if numel(yt) > nTarget
    ix = unique(round(linspace(1, numel(yt), nTarget)));
    yt = yt(ix);
end
if numel(yt) >= 2
    yticks(ax, yt);
end
end

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

% lgd = legend(ax, [hReal, hPred, hTxt1, hTxt2, hTxt3, hTxt4], { ...
%     'Real', ...
%     'Predicted', ...
%     sprintf('r      %.3f', rVal), ...
%     sprintf('U^B   %.1f%%', 100 * theilRow(1)), ...
%     sprintf('U^V   %.1f%%', 100 * theilRow(2)), ...
%     sprintf('U^C   %.1f%%', 100 * theilRow(3))}, ...
%     'Location', 'southeast', ...
%     'Interpreter', 'tex', ...
%     'Box', 'on');
% lgd.AutoUpdate = 'off';
% setPosterLegendFontSize(ancestor(ax, 'figure'));
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
% End each segment when rudder command returns from turn (1800/2000 PWM) to
% neutral (1500 PWM). If that transition is not found, optionally fall back
% to the previous tail-trim behavior controlled by cropEndTimeSec.
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

    % Keep all samples up to (end - cropEndTimeSec): trim only tail portion.
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
% Vertical extent follows current ylim(ax) — call after applyPaddedAxes / ylim are final.
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

function setTrajectoryXYDisplayTicks(ax, xVals, yVals, labelSpanM, yLimMinM, yLimMaxM, yTickDispMinM, yTickDispMaxM, yPadFrac)
% World X,Y data unchanged. Snap X limits to centimeters; 5 ticks per axis.
% X labels: x'' = x_right - x (0 at right).
% Y: world ylim = data min/max plus yPadFrac * span (0 = tight to data).
% Y tick labels: optional affine map (yTickDispMinM,yTickDispMaxM) bottom→min top→max.
% Optional yLimMinM, yLimMaxM: fixed world ylim ONLY when [min(y),max(y)] lies inside; else [].
if isempty(ax) || ~isgraphics(ax) || isempty(xVals) || isempty(yVals)
    return;
end
if nargin < 4 || isempty(labelSpanM)
    labelSpanM = 2;
end
if nargin < 9 || isempty(yPadFrac) || ~isfinite(yPadFrac) || yPadFrac < 0
    yPadFrac = 0;
end
hasYLimArgs = nargin >= 6 && ~isempty(yLimMinM) && ~isempty(yLimMaxM) && ...
    isscalar(yLimMinM) && isscalar(yLimMaxM) && isfinite(yLimMinM) && isfinite(yLimMaxM) && yLimMaxM > yLimMinM;
hasAffineYTicks = nargin >= 8 && ~isempty(yTickDispMinM) && ~isempty(yTickDispMaxM) && ...
    isscalar(yTickDispMinM) && isscalar(yTickDispMaxM) && isfinite(yTickDispMinM) && ...
    isfinite(yTickDispMaxM) && yTickDispMaxM > yTickDispMinM;
xl = xlim(ax);
xMinD = min(xVals(:));
xMaxD = max(xVals(:));
yMinD = min(yVals(:));
yMaxD = max(yVals(:));
b = ceil(max(xl(2), xMaxD) * 100) / 100;
a = b - labelSpanM;
if a > min(xl(1), xMinD) - 1e-9
    a = floor(min(xl(1), xMinD) * 100) / 100;
    b = a + labelSpanM;
    if b < max(xl(2), xMaxD) - 1e-9
        b = ceil(max(xl(2), xMaxD) * 100) / 100;
        a = b - labelSpanM;
    end
end
useFixedY = hasYLimArgs && yMinD >= yLimMinM - 1e-9 && yMaxD <= yLimMaxM + 1e-9;
if hasYLimArgs && ~useFixedY
    fprintf(['[trajectory XY] fixed ylim [%.4f, %.4f] m skipped; data Y in [%.4f, %.4f] m ', ...
        '(using snapped limits).\n'], yLimMinM, yLimMaxM, yMinD, yMaxD);
end
if useFixedY
    c = yLimMinM;
    d = yLimMaxM;
else
    ySpanD = max(eps, yMaxD - yMinD);
    padY = yPadFrac * ySpanD;
    c = floor((yMinD - padY) * 100) / 100;
    d = ceil((yMaxD + padY) * 100) / 100;
    if d <= c + 1e-12
        d = c + 0.05;
    end
end
xlim(ax, [a, b]);
ylim(ax, [c, d]);
nTick = 5;
xt = linspace(a, b, nTick);
xlabs = arrayfun(@(v) sprintf('%g', b - v), xt, 'UniformOutput', false);
if hasAffineYTicks
    % Four ticks so displayed labels are exactly 0.5, 1, 1.5, 2 (not five uneven decimals).
    nYTick = 4;
    yt = linspace(c, d, nYTick);
    yDispVals = linspace(yTickDispMinM, yTickDispMaxM, nYTick);
    ylabs = arrayfun(@(t) sprintf('%g', t), yDispVals, 'UniformOutput', false);
else
    yt = linspace(c, d, nTick);
    ylabs = arrayfun(@(v) sprintf('%g', v - c), yt, 'UniformOutput', false);
end
set(ax, 'XTick', xt, 'XTickLabel', xlabs, ...
    'YTick', yt, 'YTickLabel', ylabs, ...
    'XDir', 'normal', 'YDir', 'normal');
daspect(ax, [1, 1, 1]);
pbaspect(ax, 'auto');
axis(ax, 'equal');
ySpanDisp = d - c;
if hasAffineYTicks
    fprintf(['[trajectory XY] world xlim=[%.4f, %.4f] m ylim=[%.4f, %.4f] m | ', ...
        'x'''' labels (m): %s | Y tick numbers (m): %s | X: right=%.4f→0 left=%.4f→%.4f | ', ...
        'Y affine: bottom=%.4f→%.4f top=%.4f→%.4f\n'], ...
        a, b, c, d, sprintf('%s, ', xlabs{:}), sprintf('%s, ', ylabs{:}), ...
        b, a, labelSpanM, c, yTickDispMinM, d, yTickDispMaxM);
else
    fprintf(['[trajectory XY] world xlim=[%.4f, %.4f] m ylim=[%.4f, %.4f] m | ', ...
        'x'''' labels (m): %s | y'''' labels (m): %s | X: right=%.4f→0 left=%.4f→%.4f | ', ...
        'Y: bottom=%.4f→0 top=%.4f→%.4f\n'], ...
        a, b, c, d, sprintf('%s, ', xlabs{:}), sprintf('%s, ', ylabs{:}), ...
        b, a, labelSpanM, c, d, ySpanDisp);
end
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
% exportgraphics(fig, outPath, 'Resolution', cfg.exportResolution, ...
%     'ContentType', 'image', 'BackgroundColor', 'white');
% fprintf('Saved PNG: %s\n', outPath);
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
