% run_n4sid_from_april22_csv.m
% Identify a state-space model from April 22 experimental data using n4sid.

clear; clc;

%% File path and import
scriptDir = fileparts(mfilename('fullpath'));
idCsvPath = fullfile(scriptDir, 'rawdata_all_data', 'prop1625rudder2000_3.csv');
valCsvPath = fullfile(scriptDir, 'rawdata_all_data', 'prop1650rudder2000_2.csv');

[uId, yId, tId] = loadIoFromCsv(idCsvPath);

%% Optional time crop (for signals passed to models/analysis only)
% Leave empty to disable. Example: set to 20 to keep t = 0..20 s.
cropEndTimeSec = [];   % e.g., 20
%cropEndTimeSec = 20; % uncomment to enable quick crop
[uId, yId, tId] = cropSignalsToTime(uId, yId, tId, cropEndTimeSec);

%% Sample time estimate (median handles small timestamp jitter)
Ts = median(diff(tId));
if ~isfinite(Ts) || Ts <= 0
    error('Invalid sample time estimated from timestamp data.');
end

[uPropPctId, uRudderDegId] = buildProcessedInputs(uId);
uIdProc = [uPropPctId, uRudderDegId];
% uProcMean = mean(uIdProc, 1);
% uCentered = uIdProc - uProcMean;
uCentered = uIdProc;

% Build processed outputs for identification:
% speed from x,y derivatives and yaw directly from measured yaw.
[speedId, yawId] = buildProcessedOutputs(yId, tId);
yIdProc = [speedId, yawId];
% yProcMean = mean(yIdProc, 1);
% yCentered = yIdProc - yProcMean;
yCentered = yIdProc;

z = iddata(yCentered, uCentered, Ts, ...
    'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
    'OutputName', {'speed', 'yaw'});

%% Choose model order and estimate model
modelOrder = 2;
nx = modelOrder;
sys = n4sid(z, nx, 'Focus', 'simulation');

%% Report
disp('Estimated state-space model (n4sid):');
present(sys);

figure(2); clf;
set(gcf, 'Name', 'n4sid fit on identification data');
compare(z, sys);
grid on;

fitInfo = goodnessOfFit(sim(sys, z.u), z.y, 'NRMSE');
fitInfo = fitInfo(:).'; % force row vector for table display
disp('Identification data NRMSE fit (1 = perfect):');
disp(array2table(fitInfo, 'VariableNames', cellstr(z.OutputName)));

%% Validation on separate dataset (prop1675.csv): simulated vs real
[uVal, yVal, tVal] = loadIoFromCsv(valCsvPath);
[uVal, yVal, tVal] = cropSignalsToTime(uVal, yVal, tVal, cropEndTimeSec);
[uPropPctVal, uRudderDegVal] = buildProcessedInputs(uVal);
uValProc = [uPropPctVal, uRudderDegVal];
% uValCentered = uValProc - uProcMean;
uValCentered = uValProc;

[speedVal, yawValProc] = buildProcessedOutputs(yVal, tVal);
yValProc = [speedVal, yawValProc];
% yValCentered = yValProc - yProcMean;
yValCentered = yValProc;

%% Validation signals: processed inputs, speed, yaw rate, yaw
xVal = yVal(:,1);
yValPos = yVal(:,2);
yawVal = yVal(:,3);

dxdt = gradient(xVal, tVal);
dydt = gradient(yValPos, tVal);
yawUnwrapped = unwrap(yawVal);
yawRateRaw = gradient(yawUnwrapped, tVal);

% The processed signals used for n4sid are speedVal and yawValProc.

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

figure('Name', 'prop1675 position vs time');
subplot(2,1,1);
plot(tVal, xVal, 'b', 'LineWidth', 1.2);
ylabel('x');
grid on;

subplot(2,1,2);
plot(tVal, yValPos, 'm', 'LineWidth', 1.2);
xlabel('Time (s)');
ylabel('y');
grid on;

zVal = iddata(yValCentered, uValCentered, Ts, ...
    'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
    'OutputName', {'speed', 'yaw'});

% yValSimCentered = sim(sys, zVal.u);
% yValSim = yValSimCentered + yProcMean;
yValSim = sim(sys, zVal.u);

valFitInfo = goodnessOfFit(yValSim, yValProc, 'NRMSE');
valFitInfo = valFitInfo(:).'; % force row vector for table display
disp('Validation data NRMSE fit on prop1675.csv (original units, 1 = perfect):');
disp(array2table(valFitInfo, 'VariableNames', {'speed', 'yaw'}));

speedPredErr = yValProc(:,1) - yValSim(:,1);
yawPredErr = yValProc(:,2) - yValSim(:,2);

figure(1); clf;
set(gcf, 'Name', 'Validation: simulated vs real processed outputs (prop1675)');
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

% Extra view in wrapped coordinates for easier visual comparison.
yawRealWrapped = yVal(:,3);
yawSimWrapped = atan2(sin(yValSim(:,2)), cos(yValSim(:,2)));
subplot(5,1,5);
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

tRel = t - t(1); % treat first sample as t = 0
keep = tRel <= cropEndTimeSec;
if nnz(keep) < 20
    error('Time crop keeps too few samples (%d). Increase cropEndTimeSec.', nnz(keep));
end

uOut = u(keep, :);
yOut = y(keep, :);
tOut = t(keep, :);
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

% Smooth position first, then differentiate for more robust speed estimates.
% This reduces boundary artifacts compared to differentiating raw x,y.
xySgOrder = 3;
xySgFrame = 11; % odd window length
if numel(x) >= xySgFrame
    xSmooth = sgolayfilt(x, xySgOrder, xySgFrame);
    ySmooth = sgolayfilt(yPos, xySgOrder, xySgFrame);
else
    % Fallback for short segments where SG window does not fit.
    xSmooth = smoothdata(x, 'movmean', min(5, numel(x)));
    ySmooth = smoothdata(yPos, 'movmean', min(5, numel(yPos)));
end

dxdt = gradient(xSmooth, t);
dydt = gradient(ySmooth, t);
speed = hypot(dxdt, dydt);

% Speed only: zero-phase Butterworth low-pass.
% More aggressive smoothing to attenuate high-frequency speed noise.
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

