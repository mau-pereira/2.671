function hFill = shade_confidence_interval(ax, x, yLower, yUpper, faceColor, faceAlpha)
%SHADE_CONFIDENCE_INTERVAL  Fill a closed band between yLower and yUpper along x.
%
%   h = shade_confidence_interval(ax, x, yLower, yUpper, faceColor, faceAlpha)
%
%   x, yLower, yUpper — same length (column vectors after internal (:)).
%   faceColor — RGB triplet (e.g. [0.2 0.45 0.85]).
%   faceAlpha — scalar in (0, 1], default 0.22 if omitted or empty.
%
% Typical use: mean response plus/minus confidence bounds on a grid x.
% (Polynomial + Curve Fitting Toolbox predint demo previously lived in this filename.)

if nargin < 6 || isempty(faceAlpha)
    faceAlpha = 0.22;
end
if nargin < 5 || isempty(faceColor)
    faceColor = [0.2 0.45 0.85];
end

x = double(x(:));
yLower = double(yLower(:));
yUpper = double(yUpper(:));
n = numel(x);
if numel(yLower) ~= n || numel(yUpper) ~= n
    error('shade_confidence_interval:SizeMismatch', ...
        'x, yLower, and yUpper must have the same number of elements.');
end

xf = [x; flipud(x)];
yf = [yUpper; flipud(yLower)];

if nargin < 1 || isempty(ax) || ~isgraphics(ax) || ~strcmpi(get(ax, 'Type'), 'axes')
    error('shade_confidence_interval:InvalidAxes', 'ax must be a valid axes handle.');
end

hFill = fill(ax, xf, yf, faceColor, ...
    'FaceAlpha', faceAlpha, ...
    'EdgeColor', 'none');
end
