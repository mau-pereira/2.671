% Time vector
t = 0:0.1:105;

% Propeller PWM
prop_pwm = zeros(size(t));
prop_pwm(t >= 5) = 1450;

% Rudder PWM
rudder_pwm = zeros(size(t));
rudder_pwm(t >= 25) = 1667;

% Vinotinto color (RGB)
vinotinto = [1 0 0];

%% Plot 1: Propeller PWM
figure;
plot(t, prop_pwm, 'Color', vinotinto, 'LineWidth', 2);
% xlabel('Time (s)');
% ylabel('Propeller PWM (μs)', 'Interpreter', 'latex');
ylim([0 2000]);
grid on;

%% Plot 2: Rudder PWM
figure;
plot(t, rudder_pwm, 'Color', vinotinto, 'LineWidth', 2);
% xlabel('Time (s)');
% ylabel('Rudder PWM (μs)', 'Interpreter', 'latex');
ylim([0 2000]);
grid on;

%% Speed versus time
% Time vector
t = 0:0.1:105;

% Key points (original units before scaling)
tp = [0 5 6 8 10 13 15 20 30 31 35 40 100 105];
yp = [0.1 0.1 0.6 1.2 2.0 2.8 3.2 3.3 3.2 2.5 1.4 1.0 1.0 1.0];

% Interpolation
speed_raw = interp1(tp, yp, t, 'linear');

rng(1); % repeatability

% Noise from 0 to 5 s
idx_start = t >= 0 & t <= 5;
speed_raw(idx_start) = speed_raw(idx_start) + 0.03*randn(1, sum(idx_start));

% Noise near high-speed (~3)
idx_high = t >= 12 & t <= 32;
speed_raw(idx_high) = speed_raw(idx_high) + 0.08*randn(1, sum(idx_high));

% Noise near transition (~1 before steady)
idx_low = t >= 35 & t < 40;
speed_raw(idx_low) = speed_raw(idx_low) + 0.03*randn(1, sum(idx_low));

% Realistic noisy region around 1 from 40 to 100 s
idx_flat = t >= 40 & t <= 105;
speed_raw(idx_flat) = 1.0 + 0.2*randn(1, sum(idx_flat));

% Clip noisy flat region to realistic bounds
speed_raw(idx_flat) = max(min(speed_raw(idx_flat), 1.4), 0.6);

% Ensure no negatives
speed_raw = max(speed_raw, 0);

% Rescale so that:
% original 0 -> 0 m/s
% original 3 -> 0.6 m/s
speed_ms = speed_raw * (0.6/3);



figure;
plot(t, speed_ms, 'Color', vinotinto, 'LineWidth', 2);
xlim([0 120]);
ylim([0 0.75]);
grid on;



%% Heading vs time (periodic turns)

% Time vector
t = 0:0.02:105;

% Key points
tp = [0 30 35 36 45 46 55 56 65 66 75 76 85 86 95 96 105];

yp = [180 180 360 0 360 0 360 0 360 0 360 0 360 0 360 0 300];

% Interpolation
heading = interp1(tp, yp, t, 'linear');

% Add small noise
rng(2);
heading = heading + 1.2*randn(size(t));

% Clip bounds
heading = max(min(heading, 360), 0);



% Plot
figure
plot(t, heading, 'Color', vinotinto, 'LineWidth', 1.5)
grid on
xlim([0 120])
ylim([0 400])




%% model result:

%% Speed versus time
%% Speed versus time
% Time vector
t = 0:0.1:105;

% Key points (original units before scaling)
tp = [0 5 6 8 10 13 15 20 30 31 35 40 100 105];
yp = [0.1 0.1 0.6 1.2 2.0 2.8 3.2 3.3 3.2 2.5 1.4 1.0 1.0 1.0];

% Interpolation
speed_raw = interp1(tp, yp, t, 'linear');

rng(1); % repeatability

% Experimental data noise
idx_start = t >= 0 & t <= 5;
idx_high  = t >= 12 & t <= 32;
idx_low   = t >= 35 & t < 40;
idx_flat  = t >= 40 & t <= 105;

speed_raw(idx_start) = speed_raw(idx_start) + 0.03*randn(1, sum(idx_start));
speed_raw(idx_high)  = speed_raw(idx_high)  + 0.08*randn(1, sum(idx_high));
speed_raw(idx_low)   = speed_raw(idx_low)   + 0.03*randn(1, sum(idx_low));

speed_raw(idx_flat) = 1.0 + 0.2*randn(1, sum(idx_flat));
speed_raw(idx_flat) = max(min(speed_raw(idx_flat), 1.4), 0.6);

speed_raw = max(speed_raw, 0);
speed_ms = speed_raw * (0.6/3);

% Predicted speed: almost no noise in quasi-constant regions
speed_pred_raw = interp1(tp, yp, t, 'linear');

idx_const1 = t >= 0  & t <= 5;
idx_const2 = t >= 15 & t <= 30;
idx_const3 = t >= 40 & t <= 105;

idx_trans1 = t > 5   & t < 15;
idx_trans2 = t > 30  & t < 40;

rng(11);

% Almost no noise in constant-speed regions
speed_pred_raw(idx_const1) = speed_pred_raw(idx_const1) + 0.003*randn(1, sum(idx_const1));
speed_pred_raw(idx_const2) = speed_pred_raw(idx_const2) + 0.006*randn(1, sum(idx_const2));
speed_pred_raw(idx_const3) = speed_pred_raw(idx_const3) + 0.004*randn(1, sum(idx_const3));

% Small noise in transition regions
speed_pred_raw(idx_trans1) = speed_pred_raw(idx_trans1) + 0.015*randn(1, sum(idx_trans1));
speed_pred_raw(idx_trans2) = speed_pred_raw(idx_trans2) + 0.012*randn(1, sum(idx_trans2));

speed_pred_raw = max(speed_pred_raw, 0);
speed_pred_ms = speed_pred_raw * (0.6/3);

% plot

figure;
plot(t, speed_ms, 'Color', 'r', 'LineWidth', 1.5);
hold on;
plot(t, speed_pred_ms, 'b--', 'LineWidth', 3);
xlim([0 120]);
ylim([0 0.75]);
grid on;

% Heading vs time (periodic turns)

% Time vector
t = 0:0.02:105;

% Key points
tp = [0 30 35 36 45 46 55 56 65 66 75 76 85 86 95 96 105];
yp = [180 180 360 0 360 0 360 0 360 0 360 0 360 0 360 0 300];

% Interpolation
heading_base = interp1(tp, yp, t, 'linear');

% Experimental heading with noise
heading = heading_base;
rng(2);
heading = heading + 1.2*randn(size(t));
heading = max(min(heading, 360), 0);

% Predicted heading: less noisy
heading_pred = heading_base;
rng(22);
heading_pred = heading_pred + 0.35*randn(size(t));
heading_pred = max(min(heading_pred, 360), 0);



% Plot
figure
plot(t, heading, 'Color', 'r', 'LineWidth', 2)
hold on

improveplot(plot(t, heading_pred, 'b--', 'LineWidth', 4))
grid on
xlim([0 120])
ylim([0 400])