% ReadTable_Workshop1;
k=1; %Which test do I want to look at?
figure;
AX1 = plotyy(Test(k).data.Time_min_,Test(k).data.Potential1_V_,...
 Test(k).data.Time_min_,Test(k).data.Current_A_);
xlabel('Time (min)');
ylabel('Potential (V)');
ylabel(AX1(2),'Current (A)');



%create a placeholder for boolean mask of data
Test(k).mask = Test(k).data.Current_A_;

% Create a boolean mask describing condition of interest
Test(k).mask = Test(k).data.Current_A_ > 5.5;


%Apply the boolean mask to each of the 6 variables of interest.
Test(k).maskeddata.Current_A_ = Test(k).data.Current_A_(Test(k).mask);
Test(k).maskeddata.Time_min_ = Test(k).data.Time_min_(Test(k).mask);
Test(k).maskeddata.Potential1_V_ = Test(k).data.Potential1_V_(Test(k).mask);
Test(k).maskeddata.Potential2_V_ = Test(k).data.Potential2_V_(Test(k).mask);
Test(k).maskeddata.Potential3_V_ = Test(k).data.Potential3_V_(Test(k).mask);
Test(k).maskeddata.Temperature_C_ = Test(k).data.Temperature_C_(Test(k).mask);


% ReadTable_Workshop1;
k=1; %Which test do I want to look at?
figure;
AX1 = plotyy(Test(k).maskeddata.Time_min_,Test(k).maskeddata.Potential1_V_,...
 Test(k).maskeddata.Time_min_,Test(k).maskeddata.Current_A_);
xlabel('Time (min)');
ylabel('Potential (V)');
ylabel(AX1(2),'Current (A)');



kmax = numel(Test);

for k = 1:1:kmax
    
    % Create Boolean mask: only current > 5.5 A
    Test(k).mask = Test(k).data.Current_A_ > 5.5;
    
    % Apply mask to each variable
    Test(k).maskeddata.Current_A_     = Test(k).data.Current_A_(Test(k).mask);
    Test(k).maskeddata.Time_min_      = Test(k).data.Time_min_(Test(k).mask);
    Test(k).maskeddata.Potential1_V_  = Test(k).data.Potential1_V_(Test(k).mask);
    Test(k).maskeddata.Potential2_V_  = Test(k).data.Potential2_V_(Test(k).mask);
    Test(k).maskeddata.Potential3_V_  = Test(k).data.Potential3_V_(Test(k).mask);
    Test(k).maskeddata.Temperature_C_ = Test(k).data.Temperature_C_(Test(k).mask);

end



figure;
for k = 1:1:kmax

 AX3 = subplot(5,3,k*3-2);
 plot(Test(k).maskeddata.Time_min_, Test(k).maskeddata.Potential1_V_, 'r-');
 ylabel({'Potential (V)',['Trial ',num2str(k)]});
 yticks(2:0.5:4);
 ylim([2 4]);
 xlim([0 35]);
 grid on;
 if k==1
 title('Battery 1'); %put titles only for the top row
 end
 if k<kmax
 xticklabels([]); % Turn x tick labels off except for the bottom row
 end
 if k==kmax
 xlabel('Time (min)'); %put xlabels only on the bottom row
 end
 AX4 = subplot(5,3,k*3-1);
 plot(Test(k).maskeddata.Time_min_, Test(k).maskeddata.Potential2_V_, 'b-');
 yticks(2:0.5:4);
 ylim([2 4]);
 xlim([0 35]);
 grid on;
 yticklabels([]);
 if k==1
 title('Battery 2'); %put titles on only for the top row
 end
 if k<kmax
 xticklabels([]); % Turn x tick labels off except for the bottom row
 end
 if k==kmax
 xlabel('Time (min)'); %put xlabels only on the bottom row
 end
 AX3 = subplot(5,3,k*3);
 plot(Test(k).maskeddata.Time_min_, Test(k).maskeddata.Potential3_V_, 'k-');
 yticks(2:0.5:4);
 ylim([2 4]);
 xlim([0 35]);
 grid on;
 yticklabels([]);
 if k==1
 title('Battery 3'); %put titles on only for the top row
 end
 if k<kmax
 xticklabels([]); % Turn x tick labels off except for the bottom row
 end
 if k==kmax
 xlabel('Time (min)'); %put xlabels only on the bottom row
 end
end



kmax = numel(Test); 
Energy   = zeros(kmax,3); 
MeanTemp = zeros(kmax,1); 

for k = 1:1:kmax %
    t_sec = Test(k).maskeddata.Time_min_ * 60; 
    I     = Test(k).maskeddata.Current_A_; 
    V1    = Test(k).maskeddata.Potential1_V_; 
    V2    = Test(k).maskeddata.Potential2_V_; 
    V3    = Test(k).maskeddata.Potential3_V_; 
    T     = Test(k).maskeddata.Temperature_C_; 

    Energy(k,1) = trapz(t_sec, I .* V1 ./ 1000); 
    Energy(k,2) = trapz(t_sec, I .* V2 ./ 1000); 
    Energy(k,3) = trapz(t_sec, I .* V3 ./ 1000); 
    MeanTemp(k) = mean(T); 
end 

figure;
plot(MeanTemp,Energy,'o');
xlabel(['Temperature (' char(176) 'C)']); %char(176) is the degree symbol in MATLAB
ylabel('Energy (kJ)');
title('My First Level 2 Plot');
legend(['Battery 1';'Battery 2';'Battery 3']);
improvePlot;