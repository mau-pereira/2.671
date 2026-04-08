data = readtable('rawdata/rot1_trial1.csv');

valid = ~isnan(data.x) & ~isnan(data.y);
xData = data.x(valid);
yData = data.y(valid);

% Algebraic circle fit: (x-a)^2 + (y-b)^2 = r^2
A = [xData, yData, ones(numel(xData),1)];
b = -(xData.^2 + yData.^2);
coeff = A \ b;
a_c = -coeff(1)/2;
b_c = -coeff(2)/2;
R   = sqrt(a_c^2 + b_c^2 - coeff(3));

fprintf('Center: (%.4f, %.4f) m\n', a_c, b_c);
fprintf('Radius: %.4f m\n', R);

theta = linspace(0, 2*pi, 500);
xCirc = a_c + R*cos(theta);
yCirc = b_c + R*sin(theta);

figure; hold on; grid on;
plot(xData, yData, 'b.', 'MarkerSize', 10);
plot(xCirc, yCirc, 'r-', 'LineWidth', 0.8);
plot(a_c, b_c, 'r+', 'MarkerSize', 12, 'LineWidth', 1.5);
xlabel('x (m)'); ylabel('y (m)');
title(sprintf('rot2\\_trial2 — Fitted Circle  R = %.4f m', R));
legend('Data', 'Fitted circle', 'Center', 'Location', 'best');
axis equal;
