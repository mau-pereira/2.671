% run_n4sid_from_april22_csv_auto_order.m
% Identify a state-space model from April 22 experimental data using n4sid
% and automatically choose the best model order by validation fit.

clear; clc; close all;

%% File path and import
scriptDir = fileparts(mfilename('fullpath'));
idCsvPath = fullfile(scriptDir, 'rawdata_all_data', 'prop1625rudder2000_1.csv');
valCsvPath = fullfile(scriptDir, 'rawdata_all_data', 'prop1625rudder2000_1.csv');

[uId, yId, tId] = loadIoFromCsv(idCsvPath);

%% Sample time estimate (median handles small timestamp jitter)
Ts = median(diff(tId));
if ~isfinite(Ts) || Ts <= 0
    error('Invalid sample time estimated from timestamp data.');
end

% Mean-centering disabled per experiment request.
[uPropPctId, uRudderDegId] = buildProcessedInputs(uId);
uIdProc = [uPropPctId, uRudderDegId];
uCentered = uIdProc;

% Build processed outputs for identification (do not modify raw CSV):
% speed from x,y derivatives and yaw directly from measured yaw.
[speedId, yawId] = buildProcessedOutputs(yId, tId);
yIdProc = [speedId, yawId];
yCentered = yIdProc;

z = iddata(yCentered, uCentered, Ts, ...
    'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
    'OutputName', {'speed', 'yaw'});

%% Validation dataset prepared once for model-order selection
[uVal, yVal, tVal] = loadIoFromCsv(valCsvPath);
[uPropPctVal, uRudderDegVal] = buildProcessedInputs(uVal);
uValProc = [uPropPctVal, uRudderDegVal];
uValCentered = uValProc;

[speedVal, yawValProc] = buildProcessedOutputs(yVal, tVal);
yValProc = [speedVal, yawValProc];
yValCentered = yValProc;

zVal = iddata(yValCentered, uValCentered, Ts, ...
    'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
    'OutputName', {'speed', 'yaw'});

%% Choose model order automatically by validation fit
candidateOrders = 2:8;
bestScore = -inf;
bestOrder = candidateOrders(1);
bestSys = [];
bestValFit = [];

orderSummary = nan(numel(candidateOrders), 4); % [order, meanFit, fitSpeed, fitYaw]

for i = 1:numel(candidateOrders)
    nx = candidateOrders(i);
    try
        sysTry = n4sid(z, nx, 'Focus', 'simulation');
        yValSimTry = sim(sysTry, zVal.u);
        fitTry = goodnessOfFit(yValSimTry, yValProc, 'NRMSE');
        fitTry = fitTry(:).';
        meanFitTry = mean(fitTry);

        orderSummary(i,:) = [nx, meanFitTry, fitTry];
        if meanFitTry > bestScore
            bestScore = meanFitTry;
            bestOrder = nx;
            bestSys = sysTry;
            bestValFit = fitTry;
        end
    catch ME
        warning('Order %d failed during estimation/validation: %s', nx, ME.message);
    end
end

if isempty(bestSys)
    error('No candidate model order succeeded. Check data quality and settings.');
end

sys = bestSys;
modelOrder = bestOrder;
disp('Model-order sweep summary (NRMSE, 1 = perfect):');
disp(array2table(orderSummary, ...
    'VariableNames', {'order', 'mean_fit', 'fit_speed', 'fit_yaw'}));
fprintf('Selected model order: %d (mean validation NRMSE = %.4f)\n', modelOrder, bestScore);

%% Report
disp('Estimated state-space model (n4sid):');
present(sys);

figure('Name', sprintf('n4sid fit on identification data (selected order = %d)', modelOrder));
compare(z, sys);
grid on;

fitInfo = goodnessOfFit(sim(sys, z.u), z.y, 'NRMSE');
fitInfo = fitInfo(:).';
disp('Identification data NRMSE fit (1 = perfect):');
disp(array2table(fitInfo, 'VariableNames', cellstr(z.OutputName)));

%% Validation on separate dataset: simulated vs real
% The processed signals used for n4sid are speedVal and yawValProc.
yValSim = sim(sys, zVal.u);

valFitInfo = goodnessOfFit(yValSim, yValProc, 'NRMSE');
valFitInfo = valFitInfo(:).';
disp('Validation data NRMSE fit (original units, 1 = perfect):');
disp(array2table(valFitInfo, 'VariableNames', {'speed', 'yaw'}));

%% Validation signals: processed inputs, speed, yaw rate, yaw
xVal = yVal(:,1);
yValPos = yVal(:,2);
yawVal = yVal(:,3);

dxdt = gradient(xVal, tVal);
dydt = gradient(yValPos, tVal);
yawUnwrapped = unwrap(yawVal);
yawRateRaw = gradient(yawUnwrapped, tVal);

figure('Name', 'prop1675 processed inputs and outputs');
subplot(4,1,1);
plot(tVal, uValProc(:,1), 'b', tVal, uValProc(:,2), 'm--', 'LineWidth', 1.2);
ylabel('Input');
legend('u\_prop\_percent (%)', 'u\_rudder\_deg', 'Location', 'best');
grid on;

subplot(4,1,2);
plot(tVal, speedVal, 'k', 'LineWidth', 1.2);
ylabel('Speed (m/s)');
grid on;

subplot(4,1,3);
plot(tVal, yawRateRaw, 'r', 'LineWidth', 1.2);
ylabel('Yaw Rate (rad/s)');
grid on;

subplot(4,1,4);
plot(tVal, yawVal, 'g', 'LineWidth', 1.2);
xlabel('Time (s)');
ylabel('Yaw (rad)');
grid on;

figure('Name', sprintf('Validation: simulated vs real processed outputs (selected order = %d)', modelOrder));
subplot(3,1,1);
plot(tVal, yValProc(:,1), 'k', tVal, yValSim(:,1), 'r--', 'LineWidth', 1.2);
ylabel('Speed (m/s)'); legend('Real', 'Simulated', 'Location', 'best'); grid on;

subplot(3,1,2);
plot(tVal, yValProc(:,2), 'k', tVal, yValSim(:,2), 'r--', 'LineWidth', 1.2);
ylabel('Yaw Unwrapped (rad)'); legend('Real', 'Simulated', 'Location', 'best'); grid on;

% Extra view in wrapped coordinates for easier visual comparison.
yawRealWrapped = yVal(:,3);
yawSimWrapped = atan2(sin(yValSim(:,2)), cos(yValSim(:,2)));
subplot(3,1,3);
plot(tVal, yawRealWrapped, 'k', tVal, yawSimWrapped, 'r--', 'LineWidth', 1.2);
xlabel('Time (s)'); ylabel('Yaw Wrapped (rad)'); legend('Real', 'Simulated', 'Location', 'best'); grid on;

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

function [uPropPercent, uRudderDeg] = buildProcessedInputs(uPwm)
uPropPwm = uPwm(:,1);
uRudderPwm = uPwm(:,2);

% Propeller mapping: 1500us->0%, 2000us->100%, 1000us->-100%.
% Keep only forward command range for this dataset usage.
uPropPercent = (uPropPwm - 1500) * (100 / 500);
uPropPercent = min(max(uPropPercent, 0), 100);

% Rudder mapping: 1500us->0 deg, 2000us->+40 deg, 1000us->-40 deg.
uRudderDeg = (uRudderPwm - 1500) * (40 / 500);
uRudderDeg = min(max(uRudderDeg, -40), 40);
end

function [speed, yawOut] = buildProcessedOutputs(y, t)
x = y(:,1);
yPos = y(:,2);
yaw = y(:,3);

dxdt = gradient(x, t);
dydt = gradient(yPos, t);
speed = hypot(dxdt, dydt);

% Speed only: zero-phase Butterworth low-pass.
speedFcHz = 1.5;
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
