% run_n4sid_from_all_rawdata_all_data_csvs.m
% Identify a state-space model using all CSV files in rawdata_all_data
% except n4sid.csv, then validate with a separate file.

clear; clc; close all;

%% File path and import
scriptDir = fileparts(mfilename('fullpath'));
dataFolder = fullfile(scriptDir, 'rawdata_all_data');
excludedCsvName = 'n4sid.csv';
valCsvPath = fullfile(scriptDir, 'rawdata_all_data', 'prop1650rudder2000_2.csv');

[uId, yId, tId] = loadIoFromFolderExcludingCsv(dataFolder, excludedCsvName);

%% Sample time estimate (median handles small timestamp jitter)
Ts = median(diff(tId));
if ~isfinite(Ts) || Ts <= 0
    error('Invalid sample time estimated from timestamp data.');
end

[uPropPctId, uRudderDegId] = buildProcessedInputs(uId);
uIdProc = [uPropPctId, uRudderDegId];
uProcMean = mean(uIdProc, 1);
uCentered = uIdProc - uProcMean;

% Build processed outputs for identification (do not modify raw CSV):
% speed from x,y derivatives and yaw directly from measured yaw.
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

%% Report
disp('Estimated state-space model (n4sid):');
present(sys);

figure('Name', 'n4sid fit on identification data (all CSVs except n4sid.csv)');
compare(z, sys);
grid on;

fitInfo = goodnessOfFit(sim(sys, z.u), z.y, 'NRMSE');
fitInfo = fitInfo(:).';
disp('Identification data NRMSE fit (centered outputs, 1 = perfect):');
disp(array2table(fitInfo, 'VariableNames', cellstr(z.OutputName)));

%% Validation on separate dataset: simulated vs real
[uVal, yVal, tVal] = loadIoFromCsv(valCsvPath);
[uPropPctVal, uRudderDegVal] = buildProcessedInputs(uVal);
uValProc = [uPropPctVal, uRudderDegVal];
uValCentered = uValProc - uProcMean;

[speedVal, yawValProc] = buildProcessedOutputs(yVal, tVal);
yValProc = [speedVal, yawValProc];
yValCentered = yValProc - yProcMean;

%% Validation signals: processed inputs, speed, yaw rate, yaw
xVal = yVal(:,1);
yValPos = yVal(:,2);
yawVal = yVal(:,3);

dxdt = gradient(xVal, tVal);
dydt = gradient(yValPos, tVal);
yawUnwrapped = unwrap(yawVal);
yawRateRaw = gradient(yawUnwrapped, tVal);

figure('Name', 'Validation file processed inputs and outputs');
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

zVal = iddata(yValCentered, uValCentered, Ts, ...
    'InputName', {'u\_prop\_percent', 'u\_rudder\_deg'}, ...
    'OutputName', {'speed', 'yaw'});

yValSimCentered = sim(sys, zVal.u);
yValSim = yValSimCentered + yProcMean;

valFitInfo = goodnessOfFit(yValSim, yValProc, 'NRMSE');
valFitInfo = valFitInfo(:).';
disp('Validation data NRMSE fit (original units, 1 = perfect):');
disp(array2table(valFitInfo, 'VariableNames', {'speed', 'yaw'}));

figure('Name', 'Validation: simulated vs real processed outputs');
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

function [u, y, t] = loadIoFromFolderExcludingCsv(folderPath, excludedCsvName)
csvFiles = dir(fullfile(folderPath, '*.csv'));
if isempty(csvFiles)
    error('No CSV files found in folder: %s', folderPath);
end

uAll = [];
yAll = [];
tAll = [];
includedCount = 0;

for k = 1:numel(csvFiles)
    if strcmpi(csvFiles(k).name, excludedCsvName)
        continue;
    end

    csvPath = fullfile(folderPath, csvFiles(k).name);
    [uPart, yPart, tPart] = loadIoFromCsv(csvPath);

    % Reset local time per file before concatenation to avoid overlaps.
    tPart = tPart - tPart(1);

    uAll = [uAll; uPart]; %#ok<AGROW>
    yAll = [yAll; yPart]; %#ok<AGROW>
    tAll = [tAll; tPart]; %#ok<AGROW>
    includedCount = includedCount + 1;
end

if includedCount == 0
    error('No CSV files were included after excluding %s.', excludedCsvName);
end

% Build a synthetic continuous timeline using median Ts across included data.
TsLocal = median(diff(tAll));
if ~isfinite(TsLocal) || TsLocal <= 0
    error('Could not determine valid sample time from concatenated data.');
end
t = (0:size(uAll, 1)-1).' * TsLocal;
u = uAll;
y = yAll;
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
