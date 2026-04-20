tracker = ArucoTracker();
tracker.CameraIndex = 2;       % Adesso CyberTrack K4
tracker.Resolution  = '1280x720';
tracker.TargetTagID = 0;       % whichever tag ID you're using

sampleRate = 50;               % Hz
duration   = 15;               % seconds
numSamples = sampleRate * duration;
dt         = 1 / sampleRate;

xData = NaN(1, numSamples);
yData = NaN(1, numSamples);

fprintf('Capturing for %d seconds at %d Hz...\n', duration, sampleRate);

for k = 1:numSamples
    tStart = tic;
    [xData(k), yData(k)] = tracker();
    elapsed = toc(tStart);
    pause(max(0, dt - elapsed));
end

release(tracker);
fprintf('Done. Plotting...\n');

valid = ~isnan(xData);
figure; hold on; grid on;
plot(xData(valid), yData(valid), 'b.', 'MarkerSize', 10);
xlabel('x (m)'); ylabel('y (m)');
title('ArUco Marker Trajectory');
axis equal;
