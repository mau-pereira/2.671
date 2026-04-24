% create_jitter_free_datafolder.m
% Resample all CSV files in rawdata_all_data to a fixed Ts (jitter-free)
% and save them in jitter_free_datafolder.

clear; clc;

%% Paths
scriptDir = fileparts(mfilename('fullpath'));
srcDir = fullfile(scriptDir, 'rawdata_all_data');
dstDir = fullfile(scriptDir, 'jitter_free_datafolder');

if ~isfolder(srcDir)
    error('Source folder not found: %s', srcDir);
end
if ~isfolder(dstDir)
    mkdir(dstDir);
end

%% Resampling configuration
% Fixed sample time for all output files (seconds).
TsTarget = 0.017;

% Interpolation methods
interpMethodContinuous = 'pchip'; % for x,y
interpMethodCommand = 'previous'; % for PWM inputs

%% Process all CSV files
csvFiles = dir(fullfile(srcDir, '*.csv'));
if isempty(csvFiles)
    error('No CSV files found in: %s', srcDir);
end

fprintf('Creating jitter-free files in: %s\n', dstDir);
fprintf('Target Ts: %.6f s\n', TsTarget);

for k = 1:numel(csvFiles)
    srcPath = fullfile(csvFiles(k).folder, csvFiles(k).name);
    T = readtable(srcPath);

    requiredVars = {'timestamp', 'u_propeller_pwm', 'u_rudder_pwm', 'x', 'y', 'yaw'};
    missingVars = requiredVars(~ismember(requiredVars, T.Properties.VariableNames));
    if ~isempty(missingVars)
        warning('Skipping %s (missing columns: %s)', ...
            csvFiles(k).name, strjoin(missingVars, ', '));
        continue;
    end

    % Keep only finite rows in required channels.
    isValid = isfinite(T.timestamp) & isfinite(T.u_propeller_pwm) & isfinite(T.u_rudder_pwm) ...
        & isfinite(T.x) & isfinite(T.y) & isfinite(T.yaw);
    T = T(isValid, :);
    if height(T) < 3
        warning('Skipping %s (not enough valid rows).', csvFiles(k).name);
        continue;
    end

    % Ensure timestamps are strictly increasing and unique.
    [tUnique, idxUnique] = unique(T.timestamp, 'stable');
    T = T(idxUnique, :);
    t = T.timestamp;
    if numel(t) < 3
        warning('Skipping %s (not enough unique timestamps).', csvFiles(k).name);
        continue;
    end
    if any(diff(t) <= 0)
        warning('Skipping %s (timestamps not strictly increasing).', csvFiles(k).name);
        continue;
    end

    % Uniform target timeline.
    tStart = t(1);
    tEnd = t(end);
    tUniform = (tStart:TsTarget:tEnd).';
    if numel(tUniform) < 3
        warning('Skipping %s (uniform timeline too short).', csvFiles(k).name);
        continue;
    end

    % Resample commands (piecewise constant behavior).
    uPropUniform = interp1(t, T.u_propeller_pwm, tUniform, interpMethodCommand, 'extrap');
    uRudderUniform = interp1(t, T.u_rudder_pwm, tUniform, interpMethodCommand, 'extrap');

    % Resample position as continuous.
    xUniform = interp1(t, T.x, tUniform, interpMethodContinuous, 'extrap');
    yUniform = interp1(t, T.y, tUniform, interpMethodContinuous, 'extrap');

    % Unwrap yaw before interpolation, then wrap back to [-pi, pi].
    yawUnwrapped = unwrap(T.yaw);
    yawUniformUnwrapped = interp1(t, yawUnwrapped, tUniform, interpMethodContinuous, 'extrap');
    yawUniform = atan2(sin(yawUniformUnwrapped), cos(yawUniformUnwrapped));

    % Build output table.
    Tout = table(tUniform, uPropUniform, uRudderUniform, xUniform, yUniform, yawUniform, ...
        'VariableNames', {'timestamp', 'u_propeller_pwm', 'u_rudder_pwm', 'x', 'y', 'yaw'});

    dstPath = fullfile(dstDir, csvFiles(k).name);
    writetable(Tout, dstPath);

    fprintf('[%2d/%2d] %s -> %s (%d -> %d rows)\n', ...
        k, numel(csvFiles), csvFiles(k).name, dstPath, height(T), height(Tout));
end

fprintf('Done.\n');
