tracker = ArucoTracker();
tracker.CameraIndex = 2;       % Adesso CyberTrack K4
tracker.TargetTagID = 0;       % whichever tag ID you're using

figure;
h = animatedline;
xlabel('Frame'); ylabel('x (m)');

for k = 1:300
    [x, y] = tracker();
    addpoints(h, k, x);
    drawnow limitrate;
    fprintf('Frame %3d:  x = %+.4f  y = %+.4f\n', k, x, y);
end

release(tracker);