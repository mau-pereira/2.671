% 
% % This code takes data, fits to a model, and then computes the 95%
% % confidence interval and shades that region on the plot.
% 
% % Actual coefficients of y = a*x^2 + b*x + c (without noise)
% a = -0.9;
% b = +30;
% c = -65;
% 
% % Seed for random number generator 
% % This provides repeatable simulated noise for the data.
% rng(314);  
% 
% % Create data parabolic data with 5 repeated "measurements" at each x value.
% x = [];
% for i = 1:5
%     x = [x; (6:3:27)'];
% end
% y = a*x.^2 + b*x + c;
% 
% % Add noise to the measurements.
% y = y + 15*randn(size(x));
% 
% % Make x and y inputs into columns
% x=reshape(x, [], 1); 
% y=reshape(y, [], 1);

% Here starts the "guts" of the program, which you should run on your own
% data

% Define the functional form of the fit
fit_type = fittype('a*x + b');

% Execute the fit
% You might need to change the start point or add advanced fit options
[fit_object, GoF, output] = fit(x, y, fit_type, 'StartPoint', [0.1264,0.0640]); 
% [fit_object, GoF, output] = fit(x, y, fit_type, 'StartPoint', [p1,p2]);
% Unpack curve fit parameters
params = coeffvalues(fit_object);

% Compute the confidence interval for the fit parameters
param_CI = confint(fit_object, 0.95);

significance_check = (param_CI(1,:)<0 & param_CI(2,:)<0) | (param_CI(1,:)>0 & param_CI(2,:)>0);

% For a symmetric confidence interval, the uncertainty of the parameter 
% is half of the width of the confidence interval
param_uncertainty = 0.5*diff(param_CI);

conf_level = 0.95;  % 2.671 convention is 95% confidence

% New x variable over the domain
x_ = linspace(min(x), max(x), 100);

% Construct prediction interval of the function
y_predint = predint(fit_object, x_, conf_level, 'functional', 'off');


% Plot results
figure(1);
hold off;

% Do shading first so it appears on the bottom
  
% Define the upper bound of the shaded area
y_upper = y_predint(:, 2);

% Define the lower bound of the shaded area 
y_lower = y_predint(:, 1);

% Setup the arrays for shading a closed region
x2 = [x_, fliplr(x_)];
in_between = [y_upper; flipud(y_lower)];

% Shade the region
hf = fill(x2, in_between, 'm', 'DisplayName', '95% confidence bounds');
hold on;

% Adjust some of the parameters of the shading
hf.FaceAlpha = 0.3; % Make shading semi-transparent
hf.FaceColor = 'b'; % Set color of shaded region
hf.EdgeColor = 'none'; % Set color of edge of shaded region

% Plot the least squares fit of the data
if min(significance_check>0)
    plot(x_, feval(fit_object, x_), 'b-', 'DisplayName', 'LSQ fit'); 

else
    plot(x_, feval(fit_object, x_), 'r--', 'DisplayName', 'Fit is Not Statistically Significant');

end

plot(x, y, 'o', 'MarkerFaceColor', [0 0 0.35], 'MarkerEdgeColor', [0 0 0.35], 'DisplayName', 'Data');  % Plot data last so it appears on top
xlabel(['Temperature (' char(176) 'C)']);
ylabel('Energy (kJ)');
xlim([-30 30]); ylim([30 40])
legend;
improvePlot;
