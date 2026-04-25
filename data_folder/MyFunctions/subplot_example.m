t = 0:0.01:4.0;

y1 = 3*sin(2*pi*0.25*t);
y2 = 5*cos(2*pi*0.25*t);
y3 = tan(2*pi*0.25*t-0.01);

figure;
ax1 = subplot(3,1,1);
plot(t, y1, 'r-');
ylabel('First row');
grid on;
xticklabels([]); % Turn x ticks off for first row plot

ax2 = subplot(3,1,2);
plot(t, y2, 'b-');
ylabel('Second row');
grid on;
xticklabels([]); % Turn x ticks off for second row plot

ax3 = subplot(3,1,3);
plot(t, y3, 'g-');
ylabel('Third row');
xlabel('Time (s)');
grid on;
improvePlot;

linkaxes([ax1, ax2, ax3], 'x'); % Magic so all axes zoom together
