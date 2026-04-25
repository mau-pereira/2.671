%% Bode Plot Prelab
% First-order RC filter
% Gain = 1/sqrt(1 + (f/fc)^2)
% Phase = -atan(f/fc)   [converted to degrees]

%% Parameters
fc = 234; % cutoff frequency [Hz]

% Frequency vector: 10 Hz to 10 kHz. Use many points so curves look smooth
freq = logspace(log10(10), log10(1e4), 400);

%% Computing gain and phase
Gain  = 1 ./ sqrt(1 + (freq./fc).^2);     % V/V
Phase = -atan(freq./fc) * 180/pi;         % degrees

%% Creating plots
figure;

% a) Gain plot
subplot(1,2,1)
loglog(freq, Gain, 'b-', 'LineWidth', 1.5);
grid on;
grid minor;
xlabel('Frequency (Hz)');
ylabel('Gain (V/V)');
title('Gain vs. Frequency');

% axis limits
xlim([10 1e4]);
ylim([1e-2 1.2]);

% label "a)"
text(0.05, 0.92, 'a)', 'Units', 'normalized', 'FontWeight', 'bold');

% b) Phase plot 
subplot(1,2,2)
semilogx(freq, Phase, 'r-', 'LineWidth', 1.5);
grid on;
grid minor;
xlabel('Frequency (Hz)');
ylabel('Phase (deg)');
title('Phase vs. Frequency');

% axis limits
xlim([10 1e4]);
ylim([-90 0]);

% label "b)"
text(0.05, 0.92, 'b)', 'Units', 'normalized', 'FontWeight', 'bold');


improvePlot;

