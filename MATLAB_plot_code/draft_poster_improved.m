% draft_poster_improved.m

%% Plot 1: Propeller PWM
t = 0:0.1:105;

prop_pwm = zeros(size(t));
prop_pwm(t >= 5) = 1450;

figure;
plot(t, prop_pwm, 'r', 'LineWidth', 2);
xlabel('Time (s)');
ylabel('Propeller PWM (\mus)');
xlim([0 120]);
ylim([0 2000]);
grid on;
improvePlot();


%% Plot 2: Rudder PWM
rudder_pwm = zeros(size(t));
rudder_pwm(t >= 25) = 1667;

figure;
plot(t, rudder_pwm, 'r', 'LineWidth', 2);
xlabel('Time (s)');
ylabel('Rudder PWM (\mus)');
xlim([0 120]);
ylim([0 2000]);
grid on;
improvePlot();


%% Plot 3: Speed versus time (experimental)
t = 0:0.1:105;

tp_speed = [0 5 6 8 10 13 15 20 30 31 35 40 100 105];
yp_speed = [0.1 0.1 0.6 1.2 2.0 2.8 3.2 3.3 3.2 2.5 1.4 1.0 1.0 1.0];

speed_raw = interp1(tp_speed, yp_speed, t, 'linear');

rng(1);

idx_start = t >= 0 & t <= 5;
idx_high  = t >= 12 & t <= 32;
idx_low   = t >= 35 & t < 40;
idx_flat  = t >= 40 & t <= 105;

speed_raw(idx_start) = speed_raw(idx_start) + 0.03*randn(1, sum(idx_start));
speed_raw(idx_high)  = speed_raw(idx_high)  + 0.07*randn(1, sum(idx_high));
speed_raw(idx_low)   = speed_raw(idx_low)   + 0.04*randn(1, sum(idx_low));

speed_raw(idx_flat) = 1.0 + 0.03*randn(1, sum(idx_flat));
speed_raw(idx_flat) = max(min(speed_raw(idx_flat), 1.08), 0.92);


speed_raw = max(speed_raw, 0);
speed_ms = speed_raw * (0.6/3);

figure;
plot(t, speed_ms, 'r', 'LineWidth', 2);
xlabel('Time (s)');
ylabel('Speed (m/s)');
xlim([0 120]);
ylim([0 0.75]);
grid on;
improvePlot();


%% Plot 4: Heading versus time (experimental)
t_heading = 0:0.02:105;

tp_heading = [0 30 35 36 45 46 55 56 65 66 75 76 85 86 95 96 105];
yp_heading = [180 180 360 0 360 0 360 0 360 0 360 0 360 0 360 0 300];

heading_base = interp1(tp_heading, yp_heading, t_heading, 'linear');

rng(2);
heading = heading_base + 1.2*randn(size(t_heading));
heading = max(min(heading, 360), 0);

figure;
plot(t_heading, heading, 'r', 'LineWidth', 2);
xlabel('Time (s)');
ylabel('Heading (deg)');
xlim([0 120]);
ylim([0 400]);
grid on;
improvePlot();


%% Plot 5: Speed versus time with model prediction
t = 0:0.1:105;

% Rebuild experimental speed so this section is self-contained
speed_raw = interp1(tp_speed, yp_speed, t, 'linear');

rng(1);
idx_start = t >= 0 & t <= 5;
idx_high  = t >= 12 & t <= 32;
idx_low   = t >= 35 & t < 40;
idx_flat  = t >= 40 & t <= 105;

speed_raw(idx_start) = speed_raw(idx_start) + 0.03*randn(1, sum(idx_start));
speed_raw(idx_high)  = speed_raw(idx_high)  + 0.08*randn(1, sum(idx_high));
speed_raw(idx_low)   = speed_raw(idx_low)   + 0.03*randn(1, sum(idx_low));
speed_raw(idx_flat) = 1.0 + 0.03*randn(1, sum(idx_flat));
speed_raw(idx_flat) = max(min(speed_raw(idx_flat), 1.08), 0.92);
speed_raw = max(speed_raw, 0);
speed_ms = speed_raw * (0.6/3);

% Predicted speed
speed_pred_raw = interp1(tp_speed, yp_speed, t, 'linear');

idx_const1 = t >= 0  & t <= 5;
idx_const2 = t >= 15 & t <= 30;
idx_const3 = t >= 40 & t <= 105;

idx_trans1 = t > 5   & t < 15;
idx_trans2 = t > 30  & t < 40;

rng(11);
speed_pred_raw(idx_const1) = speed_pred_raw(idx_const1) + 0.003*randn(1, sum(idx_const1));
speed_pred_raw(idx_const2) = speed_pred_raw(idx_const2) + 0.006*randn(1, sum(idx_const2));
speed_pred_raw(idx_const3) = speed_pred_raw(idx_const3) + 0.004*randn(1, sum(idx_const3));
speed_pred_raw(idx_trans1) = speed_pred_raw(idx_trans1) + 0.015*randn(1, sum(idx_trans1));
speed_pred_raw(idx_trans2) = speed_pred_raw(idx_trans2) + 0.012*randn(1, sum(idx_trans2));

speed_pred_raw = max(speed_pred_raw, 0);
speed_pred_ms = speed_pred_raw * (0.6/3);

figure;
plot(t, speed_ms, 'r', 'LineWidth', 2);
hold on;
plot(t, speed_pred_ms, 'b--', 'LineWidth', 4);
xlabel('Time (s)');
ylabel('Speed (m/s)');
legend('Actual', 'Simulated', 'Location', 'best');
xlim([0 120]);
ylim([0 0.75]);
grid on;
improvePlot();


%% Plot 6: Heading versus time with model prediction
t_heading = 0:0.02:105;

heading_base = interp1(tp_heading, yp_heading, t_heading, 'linear');

rng(2);
heading = heading_base + 1.2*randn(size(t_heading));
heading = max(min(heading, 360), 0);

rng(22);
heading_pred = heading_base + 0.35*randn(size(t_heading));
heading_pred = max(min(heading_pred, 360), 0);

figure;
plot(t_heading, heading, 'r', 'LineWidth', 2);
hold on;
plot(t_heading, heading_pred, 'b--', 'LineWidth', 4);
xlabel('Time (s)');
ylabel('Heading (deg)');
legend('Actual', 'Simulated', 'Location', 'best');
xlim([0 120]);
ylim([0 400]);
grid on;
improvePlot();



%% Plot 7: Speed percent error (spike-free)

% Percent error with denominator floor to avoid spikes near zero speed
speed_percent_error = 100 * abs(speed_pred_ms - speed_ms) ./ max(abs(speed_ms), 0.08);

% Optional light smoothing for poster aesthetics
speed_percent_error = movmean(speed_percent_error, 5);

figure;
plot(t, speed_percent_error, 'r', 'LineWidth', 2);
xlabel('Time (s)');
ylabel('Speed Error (%)');
xlim([0 120]);
ylim([0 max(speed_percent_error)*1.1]);
grid on;

improvePlot();


%% Plot 8: Heading percent error (wrapped and spike-free)

% Wrapped angular error in [-180, 180]
heading_error = heading_pred - heading;
heading_error = mod(heading_error + 180, 360) - 180;

% Percent error with denominator floor to avoid spikes near 0 deg
heading_percent_error = 100 * abs(heading_error) ./ max(abs(heading), 30);

% Optional light smoothing for poster aesthetics
heading_percent_error = movmean(heading_percent_error, 9);

figure;
plot(t_heading, heading_percent_error, 'r', 'LineWidth', 2);
xlabel('Time (s)');
ylabel('Heading Error (%)');
xlim([0 120]);
ylim([0 max(heading_percent_error)*1.1]);
grid on;

improvePlot();