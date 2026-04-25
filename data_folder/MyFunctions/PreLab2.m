clear
clc

d1 = readtable('Signal1.csv');
t1 = d1.time;
x1 = d1.signal1;

figure
plot(t1,x1)
xlabel('Time (s)')
ylabel('Signal1')
title('Signal1 vs Time')
grid on

dt1 = mean(diff(t1));
[a1,l1] = xcorr(x1,'normalized');
lt1 = l1*dt1;

figure
plot(lt1,a1)
xlabel('Lag Time (s)')
ylabel('Auto-correlation')
title('Auto-Correlation of Signal1')
grid on

d2 = readtable('Signal2.csv');
t2 = d2.time;
x2 = d2.signal2;

figure
plot(t2,x2)
xlabel('Time (s)')
ylabel('Signal2')
title('Signal2 vs Time')
grid on

dt2 = mean(diff(t2));
[a2,l2] = xcorr(x2,'normalized');
lt2 = l2*dt2;

figure
plot(lt2,a2)
xlabel('Lag Time (s)')
ylabel('Auto-correlation')
title('Auto-Correlation of Signal2')
grid on