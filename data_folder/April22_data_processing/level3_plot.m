% level3_plot.m
% Regime-wise (transient vs circle) model validation across all trials.
% This script reuses the same n4sid preprocessing style used by
% plot_n4sid_real_vs_pred_all_rawdata.m and then summarizes:
%   1) Pearson correlation by regime and output,
%   2) Theil MSE decomposition by regime and output (bar + separate figures per U^X vs prop),
%   (Residual ACF/CCF figures and console diagnostics are commented out.)

clear; clc; close all;

scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, 'rawdata_all_data');
addpath(fullfile(scriptDir, '..', 'MyFunctions'));
exportCfg = makeFigureExportConfig(scriptDir);

%% Identification data options (same style as existing script)
idUseAllExperimentCsvsInFolder = false;
idCsvPath = [];
idCsvFiles = {
    'prop1625rudder2000_1.csv'
    'prop1650rudder2000_2.csv'
    'prop1675rudder2000_3.csv'
    'prop1625rudder1775_2.csv'
    'prop1650rudder1775_1.csv'
    };

%% Shared preprocessing controls
cropEndTimeSec = 2;
modelOrder = 2;

%% Regime segmentation controls
% Regime A: Rudder step transient (accelerate then decelerate window)
stepFromPwm = 1500;
stepFromTol = 70;
stepDeltaMinPwm = 120;   % catches 1500 -> 1775/2000 style steps
maxPeakSearchSec = 25;   % search for speed peak after step
decelTailSec = 6;        % include post-peak decel tail
regimeAMaxSec = 35;      % hard cap for transient window

% Regime B: sustained circle
settleAfterRegA_sec = 3;
circleRudderMinDeltaPwm = 220; % |u_rudder_pwm - 1500| >= threshold
circleYawRateMinRadPerSec = 0.08;
circleMinSamples = 40;

%% Residual correlation controls
acfMaxLagSec = 6;
ccfMaxLagSec = 6;

%% Regime visualization controls
% Per-trial real vs model figures (speed/yaw with regime shading):
% showPerTrialRegimeOverlay = true;

%% Build/estimate model
if idUseAllExperimentCsvsInFolder
    idPaths = listExperimentCsvPaths(dataDir);
    idLabel = sprintf('all experiment CSVs in rawdata_all_data (%d files)', numel(idPaths));
else
    idPaths = resolveIdentificationPaths(idCsvPath, dataDir, idCsvFiles);
    idLabel = formatIdLabel(idPaths);
end

z = buildMergedIddataFromCsvPaths(idPaths, cropEndTimeSec);
Ts = scalarTsFromIddata(z);
sys = n4sid(z, modelOrder, 'Focus', 'simulation');

disp(['Identification source: ', idLabel]);
present(sys);

%% Evaluate all trials and collect regime-wise metrics
csvPaths = listExperimentCsvPaths(dataDir);
nFiles = numel(csvPaths);
trialRows = [];

for k = 1:nFiles
    csvPath = csvPaths{k};
    [uVal, yVal, tVal] = loadIoFromCsv(csvPath);
    [uVal, yVal, tVal] = cropSignalsToTime(uVal, yVal, tVal, cropEndTimeSec);

    [uPropPctVal, uRudderDegVal] = buildProcessedInputs(uVal);
    [speedVal, yawValUnwrapped] = buildProcessedOutputs(yVal, tVal);

    yValProc = [speedVal, yawValUnwrapped];
    zVal = iddata(yValProc, [uPropPctVal, uRudderDegVal], Ts, ...
        'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
        'OutputName', {'speed', 'yaw'});
    yHat = sim(sys, zVal.u);

    masks = makeRegimeMasks(uVal(:, 2), speedVal, yawValUnwrapped, tVal, ...
        stepFromPwm, stepFromTol, stepDeltaMinPwm, ...
        maxPeakSearchSec, decelTailSec, regimeAMaxSec, ...
        settleAfterRegA_sec, circleRudderMinDeltaPwm, ...
        circleYawRateMinRadPerSec, circleMinSamples);

    [~, trialName, ext] = fileparts(csvPath);
    trialName = [trialName, ext];

    % if showPerTrialRegimeOverlay
    %     plotTrialWithRegimeBackground(tVal, speedVal, yHat(:, 1), yawValUnwrapped, yHat(:, 2), masks, trialName);
    % end

    trialRows = [trialRows; oneTrialRegimeRows(trialName, Ts, uVal, yValProc, yHat, masks, acfMaxLagSec, ccfMaxLagSec)]; %#ok<AGROW>
end

if isempty(trialRows)
    error('No valid trial/regime rows were produced.');
end

%% Plot 1: Pearson r vs propeller percent — speed and yaw on separate figures (regimes A/B; rudders 1775 and 2000 pooled)
figure('Name', 'Level3: Pearson r - speed (regime A/B)');
setFigureMaxSquareOnScreen(gcf);
makePearsonOutputRegimeScatter(trialRows, 'speed');
exportSquareFigurePng(gcf, fullfile(exportCfg.outDir, 'level3_pearson_speed.png'), exportCfg);
figure('Name', 'Level3: Pearson r - yaw (regime A/B)');
setFigureMaxSquareOnScreen(gcf);
makePearsonOutputRegimeScatter(trialRows, 'yaw');
exportSquareFigurePng(gcf, fullfile(exportCfg.outDir, 'level3_pearson_yaw.png'), exportCfg);

%% Plot 2: Theil decomposition means by output and regime
figure('Name', 'Level3: Theil decomposition by regime');
setFigureMaxSquareOnScreen(gcf);
cats = {'Speed-A', 'Speed-B', 'Yaw-A', 'Yaw-B'};
theilMeans = nan(4, 3); % [Ub Uv Uc]
theilMeans(1, :) = meanTheil(trialRows, 'speed', 'A');
theilMeans(2, :) = meanTheil(trialRows, 'speed', 'B');
theilMeans(3, :) = meanTheil(trialRows, 'yaw',   'A');
theilMeans(4, :) = meanTheil(trialRows, 'yaw',   'B');
hTheil = bar(theilMeans, 'stacked', 'LineWidth', 1.0);
grayCols = [0.25 0.25 0.25; 0.55 0.55 0.55; 0.82 0.82 0.82];
for j = 1:min(numel(hTheil), size(grayCols, 1))
    set(hTheil(j), 'FaceColor', grayCols(j, :));
end
set(gca, 'XTick', 1:4, 'XTickLabel', cats);
ylabel('Mean Theil Proportion');
legend({'U^B', 'U^V', 'U^C'}, 'Location', 'eastoutside', 'Interpreter', 'tex');
title('Theil MSE decomposition');
ylim([0 1]);
grid off;
improvePlot();
setFigureMaxSquareOnScreen(gcf);

%% Plot 3: Theil U^B, U^C, U^V vs propeller percent — one figure per output × component (regime A/B; rudders pooled)
theilIdxBcv = [1, 3, 2]; % U^B, U^C, U^V
theilTexBcv = {'U^B', 'U^C', 'U^V'};
outsTheil = {'speed', 'yaw'};
for io = 1:numel(outsTheil)
    for jc = 1:numel(theilIdxBcv)
        figTheil = makeTheilSingleFigure(trialRows, outsTheil{io}, theilIdxBcv(jc), theilTexBcv{jc});
        outName = sprintf('level3_theil_%s_%s.png', lower(outsTheil{io}), strrep(theilTexBcv{jc}, '^', ''));
        exportSquareFigurePng(figTheil, fullfile(exportCfg.outDir, outName), exportCfg);
    end
end

% %% Plot (commented): Residual autocorrelation (mean across trials)
% figure('Name', 'Level3: Residual autocorrelation by regime');
% tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
% plotAcfOutputPanel(trialRows, 'speed');
% plotAcfOutputPanel(trialRows, 'yaw');
% sgtitle('Residual autocorrelation (mean across trials)');
% improvePlot();
%
% %% Plot (commented): Residual-input cross-correlation (mean across trials)
% figure('Name', 'Level3: Residual-input cross-correlation');
% tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
% plotCcfOutputPanel(trialRows, 'speed');
% plotCcfOutputPanel(trialRows, 'yaw');
% sgtitle('Residual-input cross-correlation (mean across trials)');
% improvePlot();

%% Console summary
% Keep Theil summary available even when Plot 2 figure is commented out.
theilMeans = nan(4, 3); % [Ub Uv Uc]
theilMeans(1, :) = meanTheil(trialRows, 'speed', 'A');
theilMeans(2, :) = meanTheil(trialRows, 'speed', 'B');
theilMeans(3, :) = meanTheil(trialRows, 'yaw',   'A');
theilMeans(4, :) = meanTheil(trialRows, 'yaw',   'B');

printAllFitUncertainty(trialRows);

disp('--- Level3 summary: weighted Pearson (by regime/output) ---');
printWeightedPearson(trialRows, 'speed', 'A');
printWeightedPearson(trialRows, 'speed', 'B');
printWeightedPearson(trialRows, 'yaw',   'A');
printWeightedPearson(trialRows, 'yaw',   'B');

disp('--- Level3 summary: mean Theil [Ub Uv Uc] ---');
fprintf('speed-A: [%.3f %.3f %.3f]\n', theilMeans(1, :));
fprintf('speed-B: [%.3f %.3f %.3f]\n', theilMeans(2, :));
fprintf('yaw-A:   [%.3f %.3f %.3f]\n', theilMeans(3, :));
fprintf('yaw-B:   [%.3f %.3f %.3f]\n', theilMeans(4, :));

% disp('--- Residual ACF diagnostics (exclude lag 0) ---');
% printAcfDiagnostics(trialRows, 'speed', 'A');
% printAcfDiagnostics(trialRows, 'speed', 'B');
% printAcfDiagnostics(trialRows, 'yaw',   'A');
% printAcfDiagnostics(trialRows, 'yaw',   'B');
%
% disp('--- Residual CCF diagnostics vs rudder PWM (exclude lag 0) ---');
% printCcfDiagnostics(trialRows, 'speed', 'A');
% printCcfDiagnostics(trialRows, 'speed', 'B');
% printCcfDiagnostics(trialRows, 'yaw',   'A');
% printCcfDiagnostics(trialRows, 'yaw',   'B');

%% ---------- local helpers ----------
function rows = oneTrialRegimeRows(trialName, Ts, uRawPwm, y, yHat, masks, acfMaxLagSec, ccfMaxLagSec)
rows = [];
regimeNames = fieldnames(masks);
for r = 1:numel(regimeNames)
    reg = regimeNames{r}; % 'A' or 'B'
    m = masks.(reg);
    if nnz(m) < 20
        continue;
    end
    yR = y(m, :);
    yHatR = yHat(m, :);
    uR = uRawPwm(m, :); % [u_prop_pwm, u_rudder_pwm]

    rSpeed = safePearsonCorr(yR(:, 1), yHatR(:, 1));
    rYaw = safePearsonCorr(yR(:, 2), yHatR(:, 2));
    thSpeed = theilMseProportions(yR(:, 1), yHatR(:, 1), rSpeed);
    thYaw = theilMseProportions(yR(:, 2), yHatR(:, 2), rYaw);

    eSpeed = yR(:, 1) - yHatR(:, 1);
    eYaw = yR(:, 2) - yHatR(:, 2);
    maxLagAcf = max(1, round(acfMaxLagSec / Ts));
    maxLagCcf = max(1, round(ccfMaxLagSec / Ts));

    [acfSpeed, acfLags] = acfLocal(eSpeed, maxLagAcf);
    [acfYaw, ~] = acfLocal(eYaw, maxLagAcf);
    [ccfSpeedProp, ccfLags] = ccfLocal(eSpeed, uR(:, 1), maxLagCcf);
    [ccfSpeedRud, ~] = ccfLocal(eSpeed, uR(:, 2), maxLagCcf);
    [ccfYawProp, ~] = ccfLocal(eYaw, uR(:, 1), maxLagCcf);
    [ccfYawRud, ~] = ccfLocal(eYaw, uR(:, 2), maxLagCcf);

    row = struct();
    row.trial = trialName;
    row.regime = reg;
    row.N = nnz(m);
    row.r_speed = rSpeed;
    row.r_yaw = rYaw;
    row.th_speed = thSpeed;
    row.th_yaw = thYaw;
    row.acf_lags = acfLags;
    row.acf_speed = acfSpeed;
    row.acf_yaw = acfYaw;
    row.ccf_lags = ccfLags;
    row.ccf_speed_prop = ccfSpeedProp;
    row.ccf_speed_rud = ccfSpeedRud;
    row.ccf_yaw_prop = ccfYawProp;
    row.ccf_yaw_rud = ccfYawRud;
    row.confBound = 1.96 / sqrt(max(row.N, 1));

    rows = [rows; row]; %#ok<AGROW>
end
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
    return;
end

stepIdx = stepCandidates(1);
Ts = median(diff(t));
peakSearchN = max(1, round(maxPeakSearchSec / Ts));
regAMaxN = max(1, round(regimeAMaxSec / Ts));
decelTailN = max(1, round(decelTailSec / Ts));

i2 = min(n, stepIdx + peakSearchN);
[~, relPk] = max(speed(stepIdx:i2));
peakIdx = stepIdx + relPk - 1;

% Regime A is pre-turn: from t=0 until turning onset.
regAEnd = max(1, stepIdx - 1);
mA(1:regAEnd) = true;

% Regime B is continuous: immediately after A until end of trial.
startB = min(n, regAEnd + 1);
mB(startB:end) = true;

masks = struct('A', mA, 'B', mB);
end

function makePearsonOutputRegimeScatter(rows, outputName)
% Pearson r vs propeller percent for one output (speed or yaw).
% 4 series = (regime A/B) x (rudder 1775/2000). Regime A is red, Regime B is blue.
fig = gcf;
clf(fig);
ax = axes('Parent', fig);
propTicksPwm = [1625, 1650, 1675];
propTicksPct = pwmToPropPercent(propTicksPwm);
markerSz = 52;
series = struct( ...
    'reg', {'A', 'B', 'A', 'B'}, ...
    'rudPwm', {1775, 1775, 2000, 2000}, ...
    'marker', {'o', '^', 's', 'd'}, ...
    'lineStyle', {'-', '-', '--', '--'}, ...
    'color', { ...
        [1.00, 0.00, 0.00], [0.00, 0.00, 1.00], ...
        [1.00, 0.00, 0.00], [0.00, 0.00, 1.00] ...
    });

hold(ax, 'on');
hLeg = nan(1, numel(series));
rShown = [];
for k = 1:numel(series)
    [xProp, rVals] = pearsonPointsForOutputRegime(rows, outputName, series(k).reg, series(k).rudPwm);
    if isempty(rVals)
        continue;
    end
    rShown = [rShown; rVals(:)]; %#ok<AGROW>
    col = series(k).color;
    ec = 0.35 * col + 0.65 * [0, 0, 0];
    rudDeg = pwmToRudderDeg(series(k).rudPwm);
    legName = sprintf('Regime %s, Rudder %.0f^\\circ', series(k).reg, rudDeg);
    h = scatter(ax, xProp, rVals, markerSz, 'filled', ...
        'Marker', series(k).marker, 'MarkerFaceColor', col, 'MarkerEdgeColor', ec, ...
        'LineWidth', 0.75, 'DisplayName', legName);
    hLeg(k) = h;
end

hFitLines = [];
allBandLo = [];
allBandHi = [];
for k = 1:numel(series)
    [xv, yv] = pearsonPointsForOutputRegime(rows, outputName, series(k).reg, series(k).rudPwm);
    if isempty(yv)
        continue;
    end
    col = series(k).color;
    rudDeg = pwmToRudderDeg(series(k).rudPwm);
    fitPrefix = sprintf('Regime %s, Rudder %.0f^\\circ', series(k).reg, rudDeg);
    [xpF, yhat, lo, hi, fitLeg] = pearsonLinearMeanCi(xv, yv, fitPrefix, 'r', 'journal_line');
    if isempty(xpF)
        continue;
    end
    allBandLo = [allBandLo; lo(:)]; %#ok<AGROW>
    allBandHi = [allBandHi; hi(:)]; %#ok<AGROW>
    hBand = shade_confidence_interval(ax, xpF(:), lo(:), hi(:), col, 0.22);
    set(hBand, 'HandleVisibility', 'off');
    hFitLines(end + 1) = plot(ax, xpF, yhat, series(k).lineStyle, 'Color', col * 0.45, 'LineWidth', 2.0, ...
        'DisplayName', fitLeg); %#ok<AGROW>
end

xlabel(ax, 'Propeller command (%)');
ylabel(ax, 'Pearson r');
grid(ax, 'off');

yTop = 1.1;
yTickMax = 1.0;
if isempty(rShown)
    if strcmpi(outputName, 'speed')
        ylim(ax, [-1.05, yTop]);
        set(ax, 'YTick', -1:0.2:yTickMax);
    else
        ylim(ax, [0.82, yTop]);
        set(ax, 'YTick', 0.85:0.05:yTickMax);
    end
else
    rMin = min(rShown);
    rMax = max(rShown);
    if ~isempty(allBandLo)
        rMin = min(rMin, min(allBandLo));
        rMax = max(rMax, max(allBandHi));
    end
    if strcmpi(outputName, 'speed')
        padLo = max(0.04, 0.1 * (rMax - rMin + 1e-6));
        yLo = rMin - padLo;
        ylim(ax, [yLo, yTop]);
        yt = pearsonScatterYTicks(yLo, yTickMax);
        set(ax, 'YTick', yt);
    else
        yLo = max(0.85, rMin - 0.03);
        yHiLim = min(1.0, rMax + 0.03);
        if yHiLim - yLo < 0.04
            mid = 0.5 * (yLo + yHiLim);
            yLo = max(0.85, mid - 0.02);
            yHiLim = min(1.0, mid + 0.02);
        end
        if ~isempty(allBandLo)
            yLo = min(yLo, min(allBandLo) - 0.02);
        end
        if ~isempty(allBandHi)
            yHiLim = max(yHiLim, min(yTop, max(allBandHi) + 0.02));
        end
        ylim(ax, [yLo, yTop]);
        yt = pearsonScatterYTicks(yLo, yTickMax);
        set(ax, 'YTick', yt);
    end
end

set(ax, 'XTick', propTicksPct, 'XTickLabel', compose('%.0f', propTicksPct));
xPadPct = 0.5;
xlim(ax, [propTicksPct(1) - xPadPct, propTicksPct(end) + xPadPct]);

% Table-style legend (5 columns):
%  (1) marker symbol, (2) line symbol, (3) regime text, (4) rudder text, (5) fit equation text.
hLeg = hLeg(isgraphics(hLeg));
hFitLines = hFitLines(isgraphics(hFitLines));
nRows = min(numel(hLeg), numel(hFitLines));
if nRows > 0
    col1 = gobjects(1, nRows);
    col2 = gobjects(1, nRows);
    col3 = gobjects(1, nRows);
    col4 = gobjects(1, nRows);
    col5 = gobjects(1, nRows);
    for i = 1:nRows
        s = series(i);
        rudDeg = pwmToRudderDeg(s.rudPwm);
        regTxt = sprintf('Regime %s', s.reg);
        rudTxt = sprintf('Rudder %.0f^\\circ', rudDeg);
        [xEq, yEq] = pearsonPointsForOutputRegime(rows, outputName, s.reg, s.rudPwm);
        eqTxt = olsJournalEquationFromXY(xEq, yEq);

        % marker symbol only
        col1(i) = plot(ax, nan, nan, 'LineStyle', 'none', 'Marker', s.marker, ...
            'Color', s.color, 'MarkerFaceColor', s.color, 'MarkerEdgeColor', s.color, ...
            'LineWidth', 0.75, 'DisplayName', '');
        % line symbol only
        col2(i) = plot(ax, nan, nan, s.lineStyle, 'Color', s.color, 'LineWidth', 2.0, 'DisplayName', '');
        % text-only entries (blank icon)
        col3(i) = plot(ax, nan, nan, 'LineStyle', 'none', 'Marker', 'none', 'DisplayName', regTxt);
        col4(i) = plot(ax, nan, nan, 'LineStyle', 'none', 'Marker', 'none', 'DisplayName', rudTxt);
        col5(i) = plot(ax, nan, nan, 'LineStyle', 'none', 'Marker', 'none', 'DisplayName', eqTxt);
        set([col1(i), col2(i), col3(i), col4(i), col5(i)], 'HandleVisibility', 'on');
    end
    % Legend fills column-major: provide [col1 rows..., col2 rows..., ...]
    hTab = [col1(:); col2(:); col3(:); col4(:); col5(:)];
    lg = legend(ax, hTab, 'Location', 'southoutside', 'Interpreter', 'tex');
    set(lg, 'NumColumns', 5);
    set(lg, 'ItemTokenSize', [28, 10]);
end
sc = findobj(ax, 'Type', 'scatter');
if ~isempty(sc)
    uistack(sc, 'top');
end
improvePlot();
hold(ax, 'off');
end

function fig = makeTheilSingleFigure(rows, outputName, theilIdx, compTex)
% One axes: Theil component vs propeller percent for one output (figure name carries U^X and SPEED/YAW).
cap = upper(outputName);
fig = figure('Name', sprintf('Level3: Theil %s — %s', compTex, cap));
setFigureMaxSquareOnScreen(fig);
clf(gcf);
ax = axes('Parent', gcf);
theilOutputRegimeScatterOnAxes(ax, rows, outputName, theilIdx, compTex);
improvePlot();
setFigureMaxSquareOnScreen(fig);
end

function theilOutputRegimeScatterOnAxes(ax, rows, outputName, theilIdx, compTex)
% Scatter + linear fit on mean with CI; 4 series = (regime A/B) x (rudder 1775/2000).
% Regime A is red, Regime B is blue; rudder is differentiated by marker/line style.
cla(ax);
propTicksPwm = [1625, 1650, 1675];
propTicksPct = pwmToPropPercent(propTicksPwm);
markerSz = 52;
series = struct( ...
    'reg', {'A', 'B', 'A', 'B'}, ...
    'rudPwm', {1775, 1775, 2000, 2000}, ...
    'marker', {'o', '^', 's', 'd'}, ...
    'lineStyle', {'-', '-', '--', '--'}, ...
    'color', { ...
        [1.00, 0.00, 0.00], [0.00, 0.00, 1.00], ...
        [1.00, 0.00, 0.00], [0.00, 0.00, 1.00] ...
    });

hold(ax, 'on');
hLeg = nan(1, numel(series));
uShown = [];
for k = 1:numel(series)
    [xProp, uVals] = theilPointsForOutputRegime(rows, outputName, series(k).reg, theilIdx, series(k).rudPwm);
    if isempty(uVals)
        continue;
    end
    uShown = [uShown; uVals(:)]; %#ok<AGROW>
    col = series(k).color;
    ec = 0.35 * col + 0.65 * [0, 0, 0];
    rudDeg = pwmToRudderDeg(series(k).rudPwm);
    legName = sprintf('Regime %s, Rudder %.0f^\\circ', series(k).reg, rudDeg);
    h = scatter(ax, xProp, uVals, markerSz, 'filled', ...
        'Marker', series(k).marker, 'MarkerFaceColor', col, 'MarkerEdgeColor', ec, ...
        'LineWidth', 0.75, 'DisplayName', legName);
    hLeg(k) = h;
end

hFitLines = [];
allBandLo = [];
allBandHi = [];
for k = 1:numel(series)
    [xv, yv] = theilPointsForOutputRegime(rows, outputName, series(k).reg, theilIdx, series(k).rudPwm);
    if isempty(yv)
        continue;
    end
    col = series(k).color;
    rudDeg = pwmToRudderDeg(series(k).rudPwm);
    fitPrefix = sprintf('Regime %s, Rudder %.0f^\\circ', series(k).reg, rudDeg);
    [xpF, yhat, lo, hi, fitLeg] = pearsonLinearMeanCi(xv, yv, fitPrefix, 'share', 'journal_line');
    if isempty(xpF)
        continue;
    end
    allBandLo = [allBandLo; lo(:)]; %#ok<AGROW>
    allBandHi = [allBandHi; hi(:)]; %#ok<AGROW>
    hBand = shade_confidence_interval(ax, xpF(:), lo(:), hi(:), col, 0.22);
    set(hBand, 'HandleVisibility', 'off');
    hFitLines(end + 1) = plot(ax, xpF, yhat, series(k).lineStyle, 'Color', col * 0.45, 'LineWidth', 2.0, ...
        'DisplayName', fitLeg); %#ok<AGROW>
end

xlabel(ax, 'Propeller command (%)');
ylabel(ax, sprintf('%s Proportion', compTex), 'Interpreter', 'tex');
grid(ax, 'off');

yTop = 1.08;
yTickMax = 1.0;
if isempty(uShown)
    ylim(ax, [0, yTop]);
    set(ax, 'YTick', 0:0.2:yTickMax);
else
    uMin = min(uShown);
    uMax = max(uShown);
    if ~isempty(allBandLo)
        uMin = min(uMin, min(allBandLo));
        uMax = max(uMax, max(allBandHi));
    end
    pad = max(0.02, 0.12 * (uMax - uMin + 1e-9));
    yLo = max(-0.02, uMin - pad);
    yHi = min(yTop, uMax + pad);
    if yHi - yLo < 0.06
        mid = 0.5 * (yLo + yHi);
        yLo = max(0, mid - 0.04);
        yHi = min(yTop, mid + 0.04);
    end
    ylim(ax, [yLo, yHi]);
    yt = pearsonScatterYTicks(yLo, min(yTickMax, yHi));
    set(ax, 'YTick', yt);
end

set(ax, 'XTick', propTicksPct, 'XTickLabel', compose('%.0f', propTicksPct));
xPadPct = 0.5;
xlim(ax, [propTicksPct(1) - xPadPct, propTicksPct(end) + xPadPct]);

% Compact paired legend: 2 columns.
% Column 1: marker symbol with text (Regime/Rudder).
% Column 2: line symbol (fit) with no repeated text.
% Table-style legend (5 columns): marker | line | regime | rudder | fit equation.
hLeg = hLeg(isgraphics(hLeg));
hFitLines = hFitLines(isgraphics(hFitLines));
nRows = min(numel(hLeg), numel(hFitLines));
if nRows > 0
    col1 = gobjects(1, nRows);
    col2 = gobjects(1, nRows);
    col3 = gobjects(1, nRows);
    col4 = gobjects(1, nRows);
    col5 = gobjects(1, nRows);
    for i = 1:nRows
        s = series(i);
        rudDeg = pwmToRudderDeg(s.rudPwm);
        regTxt = sprintf('Regime %s', s.reg);
        rudTxt = sprintf('Rudder %.0f^\\circ', rudDeg);
        [xEq, yEq] = theilPointsForOutputRegime(rows, outputName, s.reg, theilIdx, s.rudPwm);
        eqTxt = olsJournalEquationFromXY(xEq, yEq);

        col1(i) = plot(ax, nan, nan, 'LineStyle', 'none', 'Marker', s.marker, ...
            'Color', s.color, 'MarkerFaceColor', s.color, 'MarkerEdgeColor', s.color, ...
            'LineWidth', 0.75, 'DisplayName', '');
        col2(i) = plot(ax, nan, nan, s.lineStyle, 'Color', s.color, 'LineWidth', 2.0, 'DisplayName', '');
        col3(i) = plot(ax, nan, nan, 'LineStyle', 'none', 'Marker', 'none', 'DisplayName', regTxt);
        col4(i) = plot(ax, nan, nan, 'LineStyle', 'none', 'Marker', 'none', 'DisplayName', rudTxt);
        col5(i) = plot(ax, nan, nan, 'LineStyle', 'none', 'Marker', 'none', 'DisplayName', eqTxt);
        set([col1(i), col2(i), col3(i), col4(i), col5(i)], 'HandleVisibility', 'on');
    end
    hTab = [col1(:); col2(:); col3(:); col4(:); col5(:)];
    lg = legend(ax, hTab, 'Location', 'southoutside', 'Interpreter', 'tex');
    set(lg, 'NumColumns', 5);
    set(lg, 'ItemTokenSize', [28, 10]);
end
sc = findobj(ax, 'Type', 'scatter');
if ~isempty(sc)
    uistack(sc, 'top');
end
hold(ax, 'off');
end

function yt = pearsonScatterYTicks(yLo, yTickMax)
% Ticks from near yLo up to yTickMax (inclusive). YLim can extend above yTickMax for headroom.
span = yTickMax - yLo;
if ~isfinite(span) || span <= 0
    yt = sort(unique([yLo, yTickMax]));
    return;
end
candidates = [0.02, 0.05, 0.1, 0.2, 0.25, 0.5, 1];
rawStep = max(span / 9, 0.02);
ix = find(candidates <= rawStep, 1, 'last');
if isempty(ix)
    step = 1;
else
    step = candidates(ix);
end
t0 = floor((yLo - 10 * eps) / step) * step;
yt = (t0:step:yTickMax);
if isempty(yt)
    yt = yTickMax;
else
    if yt(end) < yTickMax - 1e-8
        yt = [yt, yTickMax];
    end
end
yt = yt(yt <= yTickMax + 1e-9);
if numel(yt) > 18
    step = step * 2;
    t0 = floor((yLo - 10 * eps) / step) * step;
    yt = (t0:step:yTickMax);
    if isempty(yt) || yt(end) < yTickMax - 1e-8
        yt = unique([yt(:); yTickMax].');
    end
    yt = yt(yt <= yTickMax + 1e-9);
end
end

function [xProp, rVals] = pearsonPointsForOutputRegime(rows, outputName, regimeName, rudderTargetPwm)
% Propeller percent vs Pearson r for one output and regime; filtered by rudder command.
xProp = [];
rVals = [];
if nargin < 4 || isempty(rudderTargetPwm)
    rudderTargetPwm = [1775, 2000];
end
rudderTargetPwm = rudderTargetPwm(:).';
rudAllowedDeg = pwmToRudderDeg(rudderTargetPwm);
for i = 1:numel(rows)
    if ~strcmp(rows(i).regime, regimeName)
        continue;
    end
    [p, rRud] = parsePropRudderFromTrialName(rows(i).trial);
    rRudDeg = pwmToRudderDeg(rRud);
    if ~isfinite(p) || ~isfinite(rRud) || ~any(abs(rRudDeg - rudAllowedDeg) < 1e-9)
        continue;
    end
    if strcmpi(outputName, 'speed')
        rv = rows(i).r_speed;
    else
        rv = rows(i).r_yaw;
    end
    if ~isfinite(rv)
        continue;
    end
    xProp(end + 1, 1) = pwmToPropPercent(p); %#ok<AGROW>
    rVals(end + 1, 1) = rv; %#ok<AGROW>
end
end

function [xProp, uVals] = theilPointsForOutputRegime(rows, outputName, regimeName, theilIdx, rudderTargetPwm)
% Propeller percent vs one Theil component (1=U^B, 2=U^V, 3=U^C), filtered by regime and rudder command.
xProp = [];
uVals = [];
if theilIdx < 1 || theilIdx > 3 || ~isscalar(theilIdx)
    return;
end
if nargin < 5 || isempty(rudderTargetPwm)
    rudderTargetPwm = [1775, 2000];
end
rudderTargetPwm = rudderTargetPwm(:).';
rudAllowedDeg = pwmToRudderDeg(rudderTargetPwm);
for i = 1:numel(rows)
    if ~strcmp(rows(i).regime, regimeName)
        continue;
    end
    [p, rRud] = parsePropRudderFromTrialName(rows(i).trial);
    rRudDeg = pwmToRudderDeg(rRud);
    if ~isfinite(p) || ~isfinite(rRud) || ~any(abs(rRudDeg - rudAllowedDeg) < 1e-9)
        continue;
    end
    if strcmpi(outputName, 'speed')
        th = rows(i).th_speed;
    else
        th = rows(i).th_yaw;
    end
    if isempty(th) || numel(th) < theilIdx
        continue;
    end
    uv = th(theilIdx);
    if ~isfinite(uv)
        continue;
    end
    xProp(end + 1, 1) = pwmToPropPercent(p); %#ok<AGROW>
    uVals(end + 1, 1) = uv; %#ok<AGROW>
end
end

function printAllFitUncertainty(rows)
% Detailed fit uncertainty report (95% confidence) for all Pearson and Theil fit lines.
disp('--- Detailed fit uncertainty summary (95% CI) ---');
disp('Columns: n, m, um, m_CI_low, m_CI_high, b, ub, b_CI_low, b_CI_high, R2, RMSE');

series = struct( ...
    'reg', {'A', 'B', 'A', 'B'}, ...
    'rudPwm', {1775, 1775, 2000, 2000});

% Pearson fits
disp('--- Pearson r fits by output/regime/rudder ---');
outs = {'speed', 'yaw'};
for io = 1:numel(outs)
    outName = outs{io};
    for k = 1:numel(series)
        s = series(k);
        rudDeg = pwmToRudderDeg(s.rudPwm);
        [xv, yv] = pearsonPointsForOutputRegime(rows, outName, s.reg, s.rudPwm);
        fitS = olsFitSummary(xv, yv, 0.95);
        printOneFitSummary(sprintf('Pearson %-5s | Regime %s | Rudder %.0f^\\circ', ...
            outName, s.reg, rudDeg), fitS);
    end
end

% Theil fits
disp('--- Theil fits by output/component/regime/rudder ---');
theilIdx = [1, 3, 2];
theilTxt = {'U^B', 'U^C', 'U^V'};
for io = 1:numel(outs)
    outName = outs{io};
    for jt = 1:numel(theilIdx)
        idx = theilIdx(jt);
        comp = theilTxt{jt};
        for k = 1:numel(series)
            s = series(k);
            rudDeg = pwmToRudderDeg(s.rudPwm);
            [xv, yv] = theilPointsForOutputRegime(rows, outName, s.reg, idx, s.rudPwm);
            fitS = olsFitSummary(xv, yv, 0.95);
            printOneFitSummary(sprintf('Theil %-5s %-3s | Regime %s | Rudder %.0f^\\circ', ...
                outName, comp, s.reg, rudDeg), fitS);
        end
    end
end
end

function fitS = olsFitSummary(x, y, confLevel)
% OLS summary with parameter uncertainty and confidence interval.
if nargin < 3 || isempty(confLevel)
    confLevel = 0.95;
end
fitS = struct('n', 0, 'm', NaN, 'b', NaN, 'um', NaN, 'ub', NaN, ...
    'mCI', [NaN NaN], 'bCI', [NaN NaN], 'R2', NaN, 'RMSE', NaN, 'ok', false);

x = double(x(:));
y = double(y(:));
ok = isfinite(x) & isfinite(y);
x = x(ok);
y = y(ok);
n = numel(x);
fitS.n = n;
if n < 2
    return;
end

if (max(x) - min(x)) < 1e-9
    b = mean(y);
    ub = std(y, 0, 1) / sqrt(n);
    if ~isfinite(ub)
        ub = 0;
    end
    dof = max(1, n - 1);
    tc = tCriticalFromConfidence(confLevel, dof);
    fitS.m = 0;
    fitS.b = b;
    fitS.um = 0;
    fitS.ub = tc * ub;
    fitS.mCI = [0 0];
    fitS.bCI = [b - fitS.ub, b + fitS.ub];
    fitS.R2 = NaN;
    fitS.RMSE = sqrt(mean((y - b).^2, 'omitnan'));
    fitS.ok = true;
    return;
end

X = [ones(n, 1), x];
beta = X \ y; % [b; m]
res = y - X * beta;
dof = max(1, n - 2);
mse = sum(res.^2, 'omitnan') / dof;
covB = mse * inv(X' * X); %#ok<MINV>
if any(~isfinite(covB(:)))
    return;
end
se = sqrt(max(diag(covB), 0)); % [se_b; se_m]
tc = tCriticalFromConfidence(confLevel, dof);

b = beta(1);
m = beta(2);
ub = tc * se(1);
um = tc * se(2);

sst = sum((y - mean(y, 'omitnan')).^2, 'omitnan');
sse = sum(res.^2, 'omitnan');
if sst > eps
    R2 = 1 - sse / sst;
else
    R2 = NaN;
end
rmse = sqrt(mean(res.^2, 'omitnan'));

fitS.m = m;
fitS.b = b;
fitS.um = um;
fitS.ub = ub;
fitS.mCI = [m - um, m + um];
fitS.bCI = [b - ub, b + ub];
fitS.R2 = R2;
fitS.RMSE = rmse;
fitS.ok = true;
end

function tc = tCriticalFromConfidence(confLevel, dof)
% Two-sided t critical value for desired confidence level.
alpha = max(0, min(1, 1 - confLevel));
p = 1 - alpha / 2;
try
    tc = tinv(p, max(1, round(dof)));
catch
    tc = 1.96;
end
end

function printOneFitSummary(labelStr, fitS)
if ~fitS.ok
    fprintf('%s: no fit (insufficient or invalid data)\n', labelStr);
    return;
end
fprintf(['%s:\n', ...
    '  n=%d, m=%.6g, um=%.2g, m_CI=[%.6g, %.6g], ', ...
    'b=%.6g, ub=%.2g, b_CI=[%.6g, %.6g], R2=%.5g, RMSE=%.5g\n'], ...
    labelStr, fitS.n, fitS.m, fitS.um, fitS.mCI(1), fitS.mCI(2), ...
    fitS.b, fitS.ub, fitS.bCI(1), fitS.bCI(2), fitS.R2, fitS.RMSE);
end

function [xp, yhat, lo, hi, labelStr] = pearsonLinearMeanCi(x, y, legPrefix, depName, fitLabelStyle)
% OLS y = b0 + b1*x with 95%% CI on the mean response (shaded band).
% depName: legend tag for y in verbose mode (default 'r'; use 'share' for Theil proportion).
% fitLabelStyle: [] or 'default' | 'journal_line' (compact y = m x + b; CI shown only as band).
if nargin < 4 || isempty(depName)
    depName = 'r';
end
if nargin < 5 || isempty(fitLabelStyle)
    fitLabelStyle = 'default';
end
journalFit = strcmpi(fitLabelStyle, 'journal_line');
xp = [];
yhat = [];
lo = [];
hi = [];
labelStr = '';
x = double(x(:));
y = double(y(:));
ok = isfinite(x) & isfinite(y);
x = x(ok);
y = y(ok);
n = numel(x);
if n < 2
    return;
end

if (max(x) - min(x)) < 1e-6
    mu = mean(y);
    dofC = max(1, n - 1);
    tc = tCrit975(dofC);
    se = std(y, 0, 1) / sqrt(n);
    if ~isfinite(se)
        se = 0;
    end
    xp = linspace(min(x) - 8, max(x) + 8, 40).';
    yhat = repmat(mu, size(xp));
    d = tc * se;
    lo = yhat - d;
    hi = yhat + d;
    if journalFit
        labelStr = sprintf('%s: y = %s', legPrefix, formatJournalNumber(mu));
    else
        labelStr = sprintf('%s: mean %s=%.4g (95%% CI on mean; const PWM)', legPrefix, depName, mu);
    end
    return;
end

X = [ones(n, 1), x];
XtX = X' * X;
Rinv = XtX \ eye(2);
if any(~isfinite(Rinv(:)))
    return;
end
beta = X \ y;
res = y - X * beta;
dof = max(1, n - 2);
mse = sum(res.^2, 'omitnan') / dof;

xp = linspace(min(x), max(x), 80).';
Xn = [ones(numel(xp), 1), xp];
yhat = Xn * beta;
varMean = mse * sum((Xn * Rinv) .* Xn, 2);
se = sqrt(max(varMean, 0));
tc = tCrit975(dof);
lo = yhat - tc .* se;
hi = yhat + tc .* se;
if journalFit
    % y = m*x + b with x = propeller command (%); m = slope, b = intercept.
    m = beta(2);
    b0 = beta(1);
    if b0 >= 0
        labelStr = sprintf('%s: y = %s x + %s', legPrefix, formatJournalNumber(m), formatJournalNumber(b0));
    else
        labelStr = sprintf('%s: y = %s x - %s', legPrefix, formatJournalNumber(m), formatJournalNumber(-b0));
    end
else
    labelStr = sprintf(['%s: linear %s = b0+b1*PWM; ', ...
        'b0=%.5g, b1=%.5g (95%% CI on mean)'], legPrefix, depName, beta(1), beta(2));
end
end

function s = formatJournalNumber(v)
% 2–4 significant digits, no excessive trailing zeros; compact for figure legends.
if ~isfinite(v)
    s = 'NaN';
    return;
end
a = abs(v);
if a == 0
    s = '0';
    return;
end
if a >= 0.01 && a < 100
    s = sprintf('%.3g', v);
else
    s = sprintf('%.2g', v);
end
end

function eqTxt = olsJournalEquationFromXY(x, y)
% Return compact journal-style OLS equation with 95% uncertainty:
% y=(m±um)x+(b±ub), or y=mu±u for constant x.
eqTxt = '';
x = double(x(:));
y = double(y(:));
ok = isfinite(x) & isfinite(y);
x = x(ok);
y = y(ok);
n = numel(x);
if n < 2
    return;
end
if (max(x) - min(x)) < 1e-9
    mu = mean(y);
    dof = max(1, n - 1);
    tc = tCriticalFromConfidence(0.95, dof);
    seMu = std(y, 0, 1) / sqrt(n);
    if ~isfinite(seMu)
        seMu = 0;
    end
    uMu = tc * seMu;
    eqTxt = sprintf('y=%s\\pm%s', formatJournalNumber(mu), formatJournalNumber(uMu));
    return;
end
X = [ones(n, 1), x];
beta = X \ y;
m = beta(2);
b0 = beta(1);
res = y - X * beta;
dof = max(1, n - 2);
mse = sum(res.^2, 'omitnan') / dof;
covB = mse * inv(X' * X); %#ok<MINV>
if any(~isfinite(covB(:)))
    return;
end
seB = sqrt(max(diag(covB), 0)); % [se_b; se_m]
tc = tCriticalFromConfidence(0.95, dof);
um = tc * seB(2);
ub = tc * seB(1);
eqTxt = sprintf('y=(%s\\pm%s)x+(%s\\pm%s)', ...
    formatJournalNumber(m), formatJournalNumber(um), ...
    formatJournalNumber(b0), formatJournalNumber(ub));
end

function tc = tCrit975(dof)
dof = max(1, round(dof));
try
    tc = tinv(0.975, dof);
catch
    tc = 1.96;
end
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

function rW = weightedPearson(rows, outputName, regimeName)
mask = strcmp({rows.regime}, regimeName);
if ~any(mask)
    rW = NaN;
    return;
end
sub = rows(mask);
if strcmpi(outputName, 'speed')
    vals = [sub.r_speed];
else
    vals = [sub.r_yaw];
end
w = [sub.N];
ok = isfinite(vals) & isfinite(w) & (w > 0);
if ~any(ok)
    rW = NaN;
else
    rW = sum(vals(ok) .* w(ok)) / sum(w(ok));
end
end

function p = meanTheil(rows, outputName, regimeName)
mask = strcmp({rows.regime}, regimeName);
if ~any(mask)
    p = [NaN NaN NaN];
    return;
end
sub = rows(mask);
if strcmpi(outputName, 'speed')
    M = vertcat(sub.th_speed);
else
    M = vertcat(sub.th_yaw);
end
if isempty(M)
    p = [NaN NaN NaN];
else
    p = mean(M, 1, 'omitnan');
end
end

function plotAcfOutputPanel(rows, outputName)
nexttile;
[lagsA, mA, cbA] = stackAcfByOutput(rows, 'A', outputName);
[lagsB, mB, cbB] = stackAcfByOutput(rows, 'B', outputName);
if isempty(mA) && isempty(mB)
    text(0.5, 0.5, 'No data', 'HorizontalAlignment', 'center');
    axis off;
    return;
end
hold on;
if ~isempty(mA)
    plot(lagsA, mA, 'r-', 'LineWidth', 1.2);
end
if ~isempty(mB)
    plot(lagsB, mB, 'b-', 'LineWidth', 1.2);
end
cb = mean([cbA, cbB], 'omitnan');
yline(cb, 'k--', 'LineWidth', 0.9);
yline(-cb, 'k--', 'LineWidth', 0.9);
yline(0, 'k:');
xlabel('Lag (samples)');
ylabel('ACF');
title(sprintf('%s residual ACF', upper(outputName)));
legend({'Regime A', 'Regime B'}, 'Location', 'best');
grid off;
end

function [lags, mOut, cb] = stackAcfByOutput(rows, regimeName, outputName)
mask = strcmp({rows.regime}, regimeName);
sub = rows(mask);
outMat = [];
lags = [];
if isempty(sub)
    mOut = [];
    cb = NaN;
    return;
end
for i = 1:numel(sub)
    if strcmpi(outputName, 'speed')
        v = sub(i).acf_speed;
    else
        v = sub(i).acf_yaw;
    end
    if isempty(lags)
        lags = sub(i).acf_lags;
    end
    if numel(v) == numel(lags)
        outMat = [outMat; v(:).']; %#ok<AGROW>
    end
end
mOut = mean(outMat, 1, 'omitnan');
cb = mean([sub.confBound], 'omitnan');
end

function plotCcfOutputPanel(rows, outputName)
nexttile;
[lagsA, mA, cbA] = stackCcfByOutput(rows, 'A', outputName);
[lagsB, mB, cbB] = stackCcfByOutput(rows, 'B', outputName);
if isempty(mA) && isempty(mB)
    text(0.5, 0.5, 'No data', 'HorizontalAlignment', 'center');
    axis off;
    return;
end
hold on;
if ~isempty(mA)
    plot(lagsA, mA, 'r-', 'LineWidth', 1.2);
end
if ~isempty(mB)
    plot(lagsB, mB, 'b-', 'LineWidth', 1.2);
end
cb = mean([cbA, cbB], 'omitnan');
yline(cb, 'k--', 'LineWidth', 0.9);
yline(-cb, 'k--', 'LineWidth', 0.9);
yline(0, 'k:');
xlabel('Lag (samples)');
ylabel('CCF');
title(sprintf('%s residual-input CCF (vs rudder PWM)', upper(outputName)));
legend({'Regime A', 'Regime B'}, 'Location', 'best');
grid off;
end

function [lags, mOut, cb] = stackCcfByOutput(rows, regimeName, outputName)
mask = strcmp({rows.regime}, regimeName);
sub = rows(mask);
outMat = [];
lags = [];
if isempty(sub)
    mOut = [];
    cb = NaN;
    return;
end
for i = 1:numel(sub)
    if strcmpi(outputName, 'speed')
        v = sub(i).ccf_speed_rud;
    else
        v = sub(i).ccf_yaw_rud;
    end
    if isempty(lags)
        lags = sub(i).ccf_lags;
    end
    if numel(v) == numel(lags)
        outMat = [outMat; v(:).']; %#ok<AGROW>
    end
end
mOut = mean(outMat, 1, 'omitnan');
cb = mean([sub.confBound], 'omitnan');
end

function [acfVals, lags] = acfLocal(x, maxLag)
x = x(:);
if numel(x) < 3
    acfVals = NaN(2 * maxLag + 1, 1);
    lags = (-maxLag:maxLag).';
    return;
end
x = x - mean(x, 'omitnan');
[acfVals, lags] = xcorr(x, maxLag, 'coeff');
end

function [ccfVals, lags] = ccfLocal(a, b, maxLag)
a = a(:);
b = b(:);
n = min(numel(a), numel(b));
a = a(1:n);
b = b(1:n);
if n < 3
    ccfVals = NaN(2 * maxLag + 1, 1);
    lags = (-maxLag:maxLag).';
    return;
end
a = a - mean(a, 'omitnan');
b = b - mean(b, 'omitnan');
[ccfVals, lags] = xcorr(a, b, maxLag, 'coeff');
end

function printWeightedPearson(rows, outputName, regimeName)
rW = weightedPearson(rows, outputName, regimeName);
fprintf('%s-%s: %.3f\n', outputName, regimeName, rW);
end

function printAcfDiagnostics(rows, outputName, regimeName)
[lags, mOut, cb] = stackAcfByOutput(rows, regimeName, outputName);
if isempty(mOut) || isempty(lags) || ~isfinite(cb)
    fprintf('%s-%s: no data\n', outputName, regimeName);
    return;
end
nz = (lags ~= 0) & isfinite(mOut);
if ~any(nz)
    fprintf('%s-%s: no nonzero-lag data\n', outputName, regimeName);
    return;
end
v = abs(mOut(nz));
lz = lags(nz);
[peakAbs, idx] = max(v);
peakLag = lz(idx);
fracOut = mean(v > cb);
rmsVal = sqrt(mean(v.^2));
fprintf('%s-%s: peak|ACF|=%.3f at lag=%d, frac>|cb|=%.1f%%, rms=%.3f, cb=%.3f\n', ...
    outputName, regimeName, peakAbs, peakLag, 100 * fracOut, rmsVal, cb);
end

function printCcfDiagnostics(rows, outputName, regimeName)
[lags, mOut, cb] = stackCcfByOutput(rows, regimeName, outputName);
if isempty(mOut) || isempty(lags) || ~isfinite(cb)
    fprintf('%s-%s: no data\n', outputName, regimeName);
    return;
end
nz = (lags ~= 0) & isfinite(mOut);
if ~any(nz)
    fprintf('%s-%s: no nonzero-lag data\n', outputName, regimeName);
    return;
end
v = abs(mOut(nz));
lz = lags(nz);
[peakAbs, idx] = max(v);
peakLag = lz(idx);
fracOut = mean(v > cb);
rmsVal = sqrt(mean(v.^2));
fprintf('%s-%s: peak|CCF|=%.3f at lag=%d, frac>|cb|=%.1f%%, rms=%.3f, cb=%.3f\n', ...
    outputName, regimeName, peakAbs, peakLag, 100 * fracOut, rmsVal, cb);
end

function plotTrialWithRegimeBackground(t, speedReal, speedPred, yawReal, yawPred, masks, trialName)
tPlot = t - t(1);

figure('Name', sprintf('Regime check: %s', trialName), 'Color', 'w');
tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% Speed panel
nexttile;
hold on;
hSpdReal = plot(tPlot, speedReal, 'k-', 'LineWidth', 1.2);
hSpdPred = plot(tPlot, speedPred, 'r--', 'LineWidth', 1.2);
shadeRegimeBackground(gca, tPlot, masks.A, [1.0, 0.70, 0.70], 0.60); % Regime A red-ish
shadeRegimeBackground(gca, tPlot, masks.B, [0.70, 0.80, 1.0], 0.60); % Regime B blue-ish
uistack([hSpdReal, hSpdPred], 'top');
ylabel('Speed (m/s)');
title(sprintf('%s | speed', trialName), 'Interpreter', 'none');
legend({'Regime A', 'Regime B', 'Real', 'Predicted'}, 'Location', 'best');
grid off;
hold off;

% Yaw panel
nexttile;
hold on;
hYawReal = plot(tPlot, yawReal, 'k-', 'LineWidth', 1.2);
hYawPred = plot(tPlot, yawPred, 'r--', 'LineWidth', 1.2);
shadeRegimeBackground(gca, tPlot, masks.A, [1.0, 0.70, 0.70], 0.60);
shadeRegimeBackground(gca, tPlot, masks.B, [0.70, 0.80, 1.0], 0.60);
uistack([hYawReal, hYawPred], 'top');
xlabel('Time (s)');
ylabel('Yaw (rad, unwrapped)');
title(sprintf('%s | yaw', trialName), 'Interpreter', 'none');
legend({'Regime A', 'Regime B', 'Real', 'Predicted'}, 'Location', 'best');
grid off;
hold off;

improvePlot();
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

function p = theilMseProportions(y, yHat, r)
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
v = max([ub, uv, uc], 0);
sv = sum(v);
if sv > eps
    p = v / sv;
else
    p = [NaN, NaN, NaN];
end
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
rawTs = z.Ts;
if isnumeric(rawTs) && isscalar(rawTs)
    Ts = double(rawTs);
elseif iscell(rawTs)
    nExp = numel(rawTs);
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
    error('Set id source using idUseAllExperimentCsvsInFolder, idCsvPath, or idCsvFiles.');
end
if ~iscell(idCsvFiles)
    error('idCsvFiles must be a cell array.');
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
    f = strtrim(f);
    if isempty(f)
        continue;
    end
    if isfile(f)
        idPaths{end + 1} = f; %#ok<AGROW>
    elseif isfile(fullfile(dataDir, f))
        idPaths{end + 1} = fullfile(dataDir, f); %#ok<AGROW>
    else
        error('Identification file not found: %s', f);
    end
end
if isempty(idPaths)
    error('idCsvFiles has no usable entries.');
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
    end
    [uPropPct, uRudderDeg] = buildProcessedInputs(u);
    [speed, yawUnwrapped] = buildProcessedOutputs(y, t);
    zList{i} = iddata([speed, yawUnwrapped], [uPropPct, uRudderDeg], TsRef, ...
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
    [~, n, e] = fileparts(idPaths{1});
    s = [n, e];
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
trialDurationSec = tRel(end);
if cropEndTimeSec >= trialDurationSec
    error('cropEndTimeSec=%g is >= trial duration %g s.', cropEndTimeSec, trialDurationSec);
end
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
uPropPercent = pwmToPropPercent(uPropPwm);
uRudderDeg = pwmToRudderDeg(uRudderPwm);
end

function uPropPercent = pwmToPropPercent(uPropPwm)
uPropPercent = (uPropPwm - 1500) * (100 / 500);
uPropPercent = min(max(uPropPercent, 0), 100);
end

function uRudderDeg = pwmToRudderDeg(uRudderPwm)
uRudderDeg = (uRudderPwm - 1500) * (40 / 500);
uRudderDeg = min(max(uRudderDeg, -40), 40);
end

function cfg = makeFigureExportConfig(scriptDir)
% Export config for large square pixel exports (user can scale in manuscript tools).
cfg = struct();
cfg.outDir = fullfile(scriptDir, '..', 'processed_data');
if ~exist(cfg.outDir, 'dir')
    mkdir(cfg.outDir);
end
scr = get(0, 'ScreenSize'); % [left bottom width height] in pixels
cfg.squareSidePx = max(900, min(scr(3) - 140, scr(4) - 180));
cfg.exportResolution = 220;
end

function exportSquareFigurePng(fig, outPath, cfg)
set(fig, 'Color', 'w');
set(fig, 'Units', 'pixels');
pos = get(fig, 'Position');
pos(3) = cfg.squareSidePx;
pos(4) = cfg.squareSidePx;
set(fig, 'Position', pos);
drawnow;
exportgraphics(fig, outPath, 'Resolution', cfg.exportResolution, 'ContentType', 'image', 'BackgroundColor', 'white');
fprintf('Saved PNG: %s\n', outPath);
end

function setFigureMaxSquareOnScreen(fig)
% Make the figure a centered square as large as practical on the current screen.
if nargin < 1 || isempty(fig) || ~ishandle(fig)
    fig = gcf;
end
set(fig, 'Units', 'pixels');
scr = get(0, 'ScreenSize'); % [left bottom width height]
padLeftRight = 70;
padTopBottom = 110; % leave room for title bar/taskbar
sq = floor(max(700, min(scr(3) - 2 * padLeftRight, scr(4) - 2 * padTopBottom)));
sq = max(300, sq);
x = scr(1) + floor((scr(3) - sq) / 2);
y = scr(2) + floor((scr(4) - sq) / 2);
set(fig, 'Position', [x, y, sq, sq]);
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
Wn = speedFcHz / (fs / 2);
if ~(Wn > 0 && Wn < 1)
    error('Speed filter cutoff must be in (0, Nyquist). Got Wn=%g (fs=%g Hz).', Wn, fs);
end
[bSpd, aSpd] = butter(speedFilterOrder, Wn, 'low');
speed = filtfilt(bSpd, aSpd, speed);
yawOut = unwrap(yaw);
end
