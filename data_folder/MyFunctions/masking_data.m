% Make some fake data
dist = -(0:8:150);
F = 100*sin(0.1*dist);

figure;
plot(dist, F, 'k:o', 'DisplayName', 'Data'); hold on;
xlabel('Distance');
ylabel('Force');

% Create a boolean mask describing condition of interest
test_started = (dist < -60) & (dist >= -130);

% Mark points that satisfy the boolean mask with a beautiful green diamond
plot(dist(test_started), F(test_started), 'gd', 'DisplayName', 'Bool mask');

% Find the first point that satisfies the boolean mask
idx_start = find( test_started == true, 1, 'first');

% Mark the first point with a bold red x
plot(dist(idx_start), F(idx_start), 'rx', 'DisplayName', 'First point');

% Find the maximum value in the region satisfying the boolean mask
[max_val, idx_max_val] = max( F(idx_start:end) );

% Mark the max value of the boolean range... right?
plot(dist(idx_max_val), F(idx_max_val), 'bo','DisplayName', 'Max value in bool range?');

% Correct the indexing by noting that we found the max from a SUBSET of F
idx_max_val = idx_max_val + (idx_start - 1);

% Mark the max value of the boolean range
plot(dist(idx_max_val), F(idx_max_val), 'ms','DisplayName', 'Max value in bool range!');

hl = legend('show');
improvePlot;
set(hl, 'location', 'northoutside');
