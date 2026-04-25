% run_n4sid_from_rawdata_all_data_rudder_cropped.m
% Identify a state-space model using n4sid, but crop each dataset to:
%   start = 3 s before first rudder departure from 1500
%   end   = 1 s before rudder returns to 1500

clear; clc; close all;

%% File path and import
scriptDir = fileparts(mfilename('fullpath'));
idCsvPath = fullfile(scriptDir, 'rawdata_all_data', 'prop1650rudder2000_3.csv');
valCsvPath = fullfile(scriptDir, 'rawdata_all_data', 'prop1650rudder2000_3.csv');

[uIdRaw, yIdRaw, tIdRaw] = loadIoFromCsv(idCsvPath);
[uValRaw, yValRaw, tValRaw] = loadIoFromCsv(valCsvPath);

%% Crop to maneuver window based on rudder transitions
rudderNeutralPwm = 1500;
startLeadSec = 1.0;
endLeadSec = 1.0;
rudderTolPwm = 0.0;

[uId, yId, tId] = cropByRudderWindow(uIdRaw, yIdRaw, tIdRaw, ...
    rudderNeutralPwm, startLeadSec, endLeadSec, rudderTolPwm, 'ID');
[uVal, yVal, tVal] = cropByRudderWindow(uValRaw, yValRaw, tValRaw, ...
    rudderNeutralPwm, startLeadSec, endLeadSec, rudderTolPwm, 'VAL');

%% Sample time estimate (median handles small timestamp jitter)
Ts = median(diff(tId));
if ~isfinite(Ts) || Ts <= 0
    error('Invalid sample time estimated from timestamp data.');
end

%% Preprocess inputs/outputs
[uPropPctId, uRudderDegId] = buildProcessedInputs(uId);
uIdProc = [uPropPctId, uRudderDegId];
uProcMean = mean(uIdProc, 1);
uCentered = uIdProc - uProcMean;

[speedId, yawId] = buildProcessedOutputs(yId, tId);
yIdProc = [speedId, yawId];
yProcMean = mean(yIdProc, 1);
yCentered = yIdProc - yProcMean;

z = iddata(yCentered, uCentered, Ts, ...
    'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
    'OutputName', {'speed', 'yaw'});

%% Choose model order and estimate model
modelOrder = 2;
nx = modelOrder;
sys = n4sid(z, nx, 'Focus', 'simulation');

%% Report on ID set
disp('Estimated state-space model (n4sid):');
present(sys);

figure(2); clf;
set(gcf, 'Name', 'n4sid fit on identification data (rudder-cropped)');
compare(z, sys);
grid on;

fitInfo = goodnessOfFit(sim(sys, z.u), z.y, 'NRMSE');
fitInfo = fitInfo(:).';
disp('Identification data NRMSE fit (centered outputs, 1 = perfect):');
disp(array2table(fitInfo, 'VariableNames', cellstr(z.OutputName)));

%% Validation preprocessing and simulation
[uPropPctVal, uRudderDegVal] = buildProcessedInputs(uVal);
uValProc = [uPropPctVal, uRudderDegVal];
uValCentered = uValProc - uProcMean;

[speedVal, yawValProc] = buildProcessedOutputs(yVal, tVal);
yValProc = [speedVal, yawValProc];
yValCentered = yValProc - yProcMean;

zVal = iddata(yValCentered, uValCentered, Ts, ...
    'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
    'OutputName', {'speed', 'yaw'});

yValSimCentered = sim(sys, zVal.u);
yValSim = yValSimCentered + yProcMean;

valFitInfo = goodnessOfFit(yValSim, yValProc, 'NRMSE');
valFitInfo = valFitInfo(:).';
disp('Validation data NRMSE fit (original units, 1 = perfect):');
disp(array2table(valFitInfo, 'VariableNames', {'speed', 'yaw'}));

%% Validation figures
xVal = yVal(:,1);
yValPos = yVal(:,2);
yawVal = yVal(:,3);

dxdt = gradient(xVal, tVal);
dydt = gradient(yValPos, tVal);
yawUnwrapped = unwrap(yawVal);
yawRateRaw = gradient(yawUnwrapped, tVal);

figure('Name', 'validation processed inputs and outputs (rudder-cropped)');
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

speedPredErr = yValProc(:,1) - yValSim(:,1);
yawPredErr = yValProc(:,2) - yValSim(:,2);

figure(1); clf;
set(gcf, 'Name', 'Validation: simulated vs real processed outputs (rudder-cropped)');
subplot(5,1,1);
plot(tVal, yValProc(:,1), 'k', tVal, yValSim(:,1), 'r--', 'LineWidth', 1.2);
ylabel('Speed (m/s)'); legend('Real', 'Simulated', 'Location', 'best'); grid on;

subplot(5,1,2);
plot(tVal, yValProc(:,2), 'k', tVal, yValSim(:,2), 'r--', 'LineWidth', 1.2);
ylabel('Yaw Unwrapped (rad)'); legend('Real', 'Simulated', 'Location', 'best'); grid on;

subplot(5,1,3);
plot(tVal, speedPredErr, 'b', 'LineWidth', 1.2);
ylabel('Speed Err'); grid on;

subplot(5,1,4);
plot(tVal, yawPredErr, 'm', 'LineWidth', 1.2);
ylabel('Yaw Err'); grid on;

yawRealWrapped = yVal(:,3);
yawSimWrapped = atan2(sin(yValSim(:,2)), cos(yValSim(:,2)));
subplot(5,1,5);
plot(tVal, yawRealWrapped, 'k', tVal, yawSimWrapped, 'r--', 'LineWidth', 1.2);
xlabel('Time (s)'); ylabel('Yaw Wrapped (rad)'); legend('Real', 'Simulated', 'Location', 'best'); grid on;

figure('Name', 'validation position vs time (rudder-cropped)');
subplot(2,1,1);
plot(tVal, xVal, 'b', 'LineWidth', 1.2);
ylabel('x');
grid on;

subplot(2,1,2);
plot(tVal, yValPos, 'm', 'LineWidth', 1.2);
xlabel('Time (s)');
ylabel('y');
grid on;

function [uCrop, yCrop, tCrop] = cropByRudderWindow(u, y, t, neutralPwm, startLeadSec, endLeadSec, tolPwm, tag)
rudder = u(:,2);
isNeutral = abs(rudder - neutralPwm) <= tolPwm;
isTurning = ~isNeutral;

idxTurnStart = find(isTurning, 1, 'first');
if isempty(idxTurnStart)
    error('[%s] Could not find first rudder departure from neutral (%g).', tag, neutralPwm);
end

idxReturn = find(isNeutral & ((1:numel(isNeutral)).' > idxTurnStart), 1, 'first');
if isempty(idxReturn)
    error('[%s] Could not find rudder return to neutral (%g) after turn start.', tag, neutralPwm);
end

startTime = t(idxTurnStart) - startLeadSec;
endTime = t(idxReturn) - endLeadSec;

idxStart = find(t >= startTime, 1, 'first');
idxEnd = find(t <= endTime, 1, 'last');
if isempty(idxStart) || isempty(idxEnd) || idxEnd <= idxStart
    error('[%s] Invalid crop window. startTime=%.3f, endTime=%.3f', tag, startTime, endTime);
end

uCrop = u(idxStart:idxEnd, :);
yCrop = y(idxStart:idxEnd, :);
tCrop = t(idxStart:idxEnd, :);
tCrop = tCrop - tCrop(1);

fprintf('[%s] Crop window: t=[%.3f, %.3f] s, samples=%d\n', ...
    tag, t(idxStart), t(idxEnd), numel(tCrop));
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

function [uPropPercent, uRudderDeg] = buildProcessedInputs(uPwm)
uPropPwm = uPwm(:,1);
uRudderPwm = uPwm(:,2);

uPropPercent = (uPropPwm - 1500) * (100 / 500);
uPropPercent = min(max(uPropPercent, 0), 100);

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
