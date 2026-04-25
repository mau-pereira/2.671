%% ── Configuration ────────────────────────────────────────────────────────────
plot_all          = true;    % true = auto-detect all rotations/trials in rawdata_dir
rotations         = [3];     % only used when plot_all = false
trials            = {1:6};   % only used when plot_all = false (one entry per rotation)

rawdata_dir       = 'rawdata_1600prop_april1';           % folder containing CSV files
show_nan_count    = true;                % print NaN / duplicate / outlier counts
filter_outliers   = true;                % remove points far from the fitted circle
outlier_threshold = 3;                   % MADs away from circle to count as outlier
marker_size       = 10;                  % data point size
circle_linewidth  = 0.8;                % fitted circle line width

%% ── Auto-detect rotations and trials ─────────────────────────────────────────
if plot_all
    files = dir(fullfile(rawdata_dir, 'rot*_trial*.csv'));
    tokens = regexp({files.name}, 'rot(\d+)_trial(\d+)\.csv', 'tokens');
    allRots   = [];
    allTrials = [];
    for i = 1:numel(tokens)
        if ~isempty(tokens{i})
            allRots(end+1)   = str2double(tokens{i}{1}{1});
            allTrials(end+1) = str2double(tokens{i}{1}{2});
        end
    end
    rotations = unique(allRots);
    trials = cell(1, numel(rotations));
    for ri = 1:numel(rotations)
        trials{ri} = sort(allTrials(allRots == rotations(ri)));
    end
end

maxTrials = max(cellfun(@numel, trials));
colors = lines(maxTrials);

%% ── Plot each rotation ──────────────────────────────────────────────────────
for r = 1:numel(rotations)
    rot = rotations(r);
    tr  = trials{r};

    figure; hold on; grid on;
    legendHandles = [];
    legendLabels  = {};
    allRadii = [];
    pwm_rud  = NaN;
    pwm_prop = NaN;

    for k = 1:numel(tr)
        fname = fullfile(rawdata_dir, sprintf('rot%d_trial%d.csv', rot, tr(k)));
        if ~isfile(fname)
            warning('File not found: %s — skipping', fname);
            continue;
        end

        data  = readtable(fname);
        if isnan(pwm_rud)
            pwm_rud  = data.pwm_rudder(1);
            pwm_prop = data.pwm_prop(1);
        end
        valid = ~isnan(data.x) & ~isnan(data.y);
        nTotal   = height(data);
        nInvalid = sum(~valid);
        xData = data.x(valid);
        yData = data.y(valid);

        if show_nan_count
            fprintf('rot%d trial%d — %d / %d points invalid (NaN)\n', ...
                    rot, tr(k), nInvalid, nTotal);
        end

        % Remove consecutive duplicate points (stale tracker readings)
        changed = [true; diff(xData) ~= 0 | diff(yData) ~= 0];
        nDupes  = sum(~changed);
        xData   = xData(changed);
        yData   = yData(changed);
        if show_nan_count && nDupes > 0
            fprintf('rot%d trial%d — %d consecutive duplicates removed\n', ...
                    rot, tr(k), nDupes);
        end

        if numel(xData) < 3
            warning('%s has fewer than 3 valid points — skipping', fname);
            continue;
        end

        % Algebraic circle fit (preliminary, used for outlier detection)
        A = [xData, yData, ones(numel(xData),1)];
        b = -(xData.^2 + yData.^2);
        coeff = A \ b;
        a_c = -coeff(1)/2;
        b_c = -coeff(2)/2;
        R   = sqrt(a_c^2 + b_c^2 - coeff(3));

        % Outlier removal based on distance from fitted circle
        if filter_outliers
            dist_from_center = sqrt((xData - a_c).^2 + (yData - b_c).^2);
            residual = abs(dist_from_center - R);
            med_res = median(residual);
            mad_res = median(abs(residual - med_res));
            inlier = residual < med_res + outlier_threshold * mad_res;
            nOutlier = sum(~inlier);
            xData = xData(inlier);
            yData = yData(inlier);
            if show_nan_count
                fprintf('rot%d trial%d — %d outliers removed\n', ...
                        rot, tr(k), nOutlier);
            end

            % Refit circle on clean data
            A = [xData, yData, ones(numel(xData),1)];
            b = -(xData.^2 + yData.^2);
            coeff = A \ b;
            a_c = -coeff(1)/2;
            b_c = -coeff(2)/2;
            R   = sqrt(a_c^2 + b_c^2 - coeff(3));
        end

        fprintf('rot%d trial%d — Center: (%.4f, %.4f) m, R = %.4f m\n', ...
                rot, tr(k), a_c, b_c, R);

        theta = linspace(0, 2*pi, 500);
        xCirc = a_c + R*cos(theta);
        yCirc = b_c + R*sin(theta);

        c = colors(k,:);
        hData = plot(xData, yData, '.', 'Color', c, 'MarkerSize', marker_size);
        plot(xCirc, yCirc, '-', 'Color', c, 'LineWidth', circle_linewidth, ...
             'HandleVisibility', 'off');
        allRadii(end+1) = R;
        legendHandles(end+1)  = hData;
        legendLabels{end+1}   = sprintf('Trial %d (R = %.1f cm)', tr(k), R*100);
    end

    % Average radius entry (bold, via invisible dummy point)
    R_avg = mean(allRadii);
    hAvg = plot(NaN, NaN, 'k', 'HandleVisibility', 'on');
    legendHandles(end+1) = hAvg;
    legendLabels{end+1}  = sprintf('\\bf Avg R = %.1f cm', R_avg*100);

    xlabel('x (m)'); ylabel('y (m)');
    title(sprintf('PWM Propeller: %d   PWM Rudder: %d', pwm_prop, pwm_rud));
    legend(legendHandles, legendLabels, 'Location', 'northeast', 'Interpreter', 'tex');
    axis equal;
end
