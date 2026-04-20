classdef ArucoTracker < matlab.System
% ArucoTracker  Track an ArUco marker and output its x,y position in meters.
%
%   Usage in Simulink
%   -----------------
%   1. Add a "MATLAB System" block to your model.
%   2. Set the System object name to:  ArucoTracker
%   3. Make sure this file is on the MATLAB path (or in the model folder).
%   4. Set the simulation solver to "Fixed-step" with a sample time that
%      matches your desired frame rate (e.g. 0.033 s ≈ 30 fps).
%   5. The block outputs two scalar doubles: x and y (meters, camera frame).
%      When no marker is detected the outputs hold their previous value.
%
%   Standalone quick-test
%   ---------------------
%     tracker = ArucoTracker();
%     tracker.TargetTagID = 0;       % change if needed
%     for k = 1:200
%         [x, y] = tracker();
%         fprintf('x = %+.4f  y = %+.4f\n', x, y);
%     end
%     release(tracker);

    %% ------- Tunable at design-time only (block mask parameters) -------
    properties (Nontunable)
        CameraIndex  (1,1) {mustBePositive,  mustBeInteger} = 2
        Resolution   (1,:) char                              = '3840x2160'
        TagSizeMeters(1,1) double {mustBePositive}           = 0.075
        TargetTagID  (1,1) {mustBeNonnegative, mustBeInteger} = 0
    end

    %% ------- Private state -------
    properties (Access = private)
        Camera
        Intrinsics
        PrevX
        PrevY
    end

    %% ========================  SYSTEM OBJECT METHODS  ========================
    methods (Access = protected)

        % ----- one-time initialization (runs when simulation starts) -----
        function setupImpl(obj)
            obj.Camera = webcam(obj.CameraIndex);
            obj.Camera.Resolution = obj.Resolution;

            % Parse chosen resolution
            dims = sscanf(obj.Resolution, '%dx%d');
            resW = dims(1);  resH = dims(2);

            % Scale factor relative to the 4K calibration (3840x2160)
            scale = resW / 3840;

            % Calibration from calibration_chessboard_4k_tank.yaml (at 4K)
            focalLength    = scale * [2158.4005877723357, 2163.2849601522089];
            principalPoint = scale * [2044.3005328609349, 1076.2210330849771];
            imageSize      = [resH, resW];   % [rows, cols]

            % Distortion coefficients are unitless -- no scaling needed
            k1 =  0.05018169956081317;
            k2 = -0.093405263128664873;
            p1 = -0.003023698993409909;
            p2 =  0.0028858909433426036;
            k3 =  0.033734590146695498;

            obj.Intrinsics = cameraIntrinsics(focalLength, principalPoint, ...
                imageSize, ...
                'RadialDistortion',     [k1, k2, k3], ...
                'TangentialDistortion', [p1, p2]);

            obj.PrevX = 0;
            obj.PrevY = 0;
        end

        % ----- called every simulation step -----
        function [x, y] = stepImpl(obj)
            img = snapshot(obj.Camera);

            [ids, locs] = readArucoMarker(img, 'DICT_6X6_250');

            if isempty(ids)
                x = obj.PrevX;
                y = obj.PrevY;
                return;
            end

            idx = find(ids == obj.TargetTagID, 1);
            if isempty(idx)
                idx = 1;   % fall back to first detected marker
            end

            imagePoints = locs(:, :, idx);          % 4×2 corner pixels

            % 3D world points for the marker corners (z = 0 plane).
            % Corner order matches OpenCV / MATLAB ArUco convention:
            %   top-left, top-right, bottom-right, bottom-left
            s = obj.TagSizeMeters / 2;
            worldPoints = [-s  s  0;
                            s  s  0;
                            s -s  0;
                           -s -s  0];

            try
                [R_cw, t_cw] = estimateWorldCameraPose( ...
                    imagePoints, worldPoints, obj.Intrinsics);

                % t_cw  = camera location  in world (marker) frame   (1×3)
                % R_cw  = camera orientation in world frame           (3×3)
                % Convert to marker position in camera frame (≡ OpenCV tvec):
                tvec = -t_cw * R_cw';

                x = tvec(1);
                y = tvec(2);
            catch
                x = obj.PrevX;
                y = obj.PrevY;
            end

            obj.PrevX = x;
            obj.PrevY = y;
        end

        % ----- cleanup (runs when simulation stops) -----
        function releaseImpl(obj)
            clear obj.Camera;
        end

        % ----- Simulink output-port metadata -----
        function [s1, s2] = getOutputSizeImpl(~)
            s1 = [1 1];  s2 = [1 1];
        end
        function [d1, d2] = getOutputDataTypeImpl(~)
            d1 = 'double';  d2 = 'double';
        end
        function [c1, c2] = isOutputComplexImpl(~)
            c1 = false;  c2 = false;
        end
        function [f1, f2] = isOutputFixedSizeImpl(~)
            f1 = true;  f2 = true;
        end
    end
end
