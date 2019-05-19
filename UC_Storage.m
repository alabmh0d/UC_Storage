% Part of this code is taken from work done by  Szilard Nement, szilard.nemeth@gamax.hu

%EE622 Term Paper Project
%Mohammed Alabdullah & Ahmed Alrashed
%This code implements UC with energy storage devices
%Need to have load profile, and conventional generator data before running
%code

clear all
clc


%function [sol,TotalCost,exitflag,output]=UC_Storage(month)
%% Initial input data
month = 1;
duration = 24;
load KSA_GEN %plants information
%disp(UC2)
load_data = xlsread('net_load_2.xlsx');
starting= 730*(month-1)+1;
ending = starting+duration-1;
load_data=load_data(starting:ending)*1000;
nHrs = numel(load_data);
Time = (1:nHrs)';
%%
% target generation
GenerationTarget = load_data * 1;
% Check if load > capacity
InstalledCapacity   = sum(UC2{5,:});
% if not, get error
if InstalledCapacity < max(GenerationTarget)
    error('Error', max(GenerationTarget),InstalledCapacity)  
end

%% Setup the data for the problem
% pull apart plant properties
FuelCost            = UC2{1,:};
StartupCost         = UC2{3,:};
OperatingCost       = UC2{2,:};
MinGenerationLevel  = UC2{4,:};
MaxGenerationLevel  = UC2{5,:};
RampUp              = UC2{6,:};
RampDown            = UC2{7,:};
%MinimumUpTime       = UC2{8,:};
%MinimumDownTime     = UC2{9,:};

%% define battery data
MaxGenerationLevelBattery = [500,500];
BatteryCapacity = [1000,1000];
battery_storage_cost =[0.5;0.5];
battery_production_cost =[0.1;0.1];
storage_units = [{'one'},{'two'}];
maxBatConst = repmat(MaxGenerationLevelBattery,nHrs,1);
bat_capacity_max = repmat(BatteryCapacity,nHrs,1);

%% define generator data
nPlants = size(UC2,1);
plants = UC2.Properties.VariableNames;
nSlots = nHrs*nPlants;

idxHr2ToEnd=2:nHrs;
maxGenConst = repmat(MaxGenerationLevel,nHrs,1);
minGenConst = repmat(MinGenerationLevel,nHrs,1);
%% Define the optimization problem and the optimization variables
%%
powerprob = optimproblem;
%%
% amount of power generated in an hour by a plant
power_var = optimvar('power',nHrs,plants,'LowerBound',0,'UpperBound',maxGenConst);
% indicator if plant is operating during an hour 
status_var = optimvar('isOn',nHrs,plants,'Type','integer','LowerBound',0,'UpperBound',1);
% indicator if plant is starting up during an hour
startup_var = optimvar('startup',nHrs,plants,'Type','integer','LowerBound',0,'UpperBound',1);
%% Storage variables
% stored power in energy stroage unit
stor_var = optimvar('stored',nHrs,storage_units,'LowerBound',0,'UpperBound',maxBatConst);
produc_var = optimvar('produced',nHrs,storage_units,'LowerBound',0,'UpperBound',maxBatConst);
batCap_Var = optimvar('batCapacity',nHrs,storage_units,'LowerBound',0,'UpperBound',bat_capacity_max);


%% Define the objective function
%%
% costs
powerCost = sum(power_var*FuelCost',1);
isOnCost = sum(status_var*OperatingCost',1);
startupCost = sum(startup_var*StartupCost',1);
production_cost =  sum(produc_var*battery_production_cost,1);
storage_cost =   sum(produc_var*battery_storage_cost,1);
% set objective
powerprob.Objective = powerCost + isOnCost + startupCost+production_cost+storage_cost;
%% Demand constraints
powerprob.Constraints.isDemandMet = sum(power_var,2)+sum(produc_var,2)-sum(stor_var,2) >= GenerationTarget;
%%  plant operating status to power generation
powerprob.Constraints.powerOnlyWhenOn = power_var <= maxGenConst.*status_var; 
powerprob.Constraints.meetMinGenLevel = power_var >= minGenConst.*status_var; 

%% Constraints linking operating status change to startup
powerprob.Constraints.startupConst = -status_var(idxHr2ToEnd-1,:) + status_var(idxHr2ToEnd,:) - startup_var(idxHr2ToEnd,:) <= 0;
%% Ramp rate limits
% rampup limit
RampUpConst = repmat(RampUp,nHrs-1,1);
powerprob.Constraints.rampupConst = -power_var(idxHr2ToEnd-1,:) + power_var(idxHr2ToEnd,:) <= RampUpConst(idxHr2ToEnd-1,:) + ...
     max(minGenConst(idxHr2ToEnd,:)-RampUpConst(idxHr2ToEnd-1,:),0).*startup_var(idxHr2ToEnd,:);

% rampdown limit
RampDownConst = repmat(RampDown,nHrs-1,1);
powerprob.Constraints.rampdownConst = power_var(idxHr2ToEnd-1,:) - power_var(idxHr2ToEnd,:) <= max(minGenConst(idxHr2ToEnd,:),RampDownConst(idxHr2ToEnd-1,:)) - ...
    max(minGenConst(idxHr2ToEnd,:)-RampDownConst(idxHr2ToEnd-1,:),0).*status_var(idxHr2ToEnd,:);
%showconstr(powerprob.Constraints.rampdownConst(1:3))


%% battery capacity constraint
powerprob.Constraints.battery_capacity_const = batCap_Var(idxHr2ToEnd,:) == batCap_Var(idxHr2ToEnd-1,:) + 0.9*stor_var(idxHr2ToEnd,:)-1/0.9*produc_var(idxHr2ToEnd,:);

%%
% options for the optimization algorithm, here we set the max time it can run for
options = optimoptions('intlinprog','MaxTime',100);%'RelativeGapTolerance',1e-2,'CutMaxIterations',25,'CutGeneration','intermediate','RootLPAlgorithm','primal-simplex','Heuristics','advanced');%,'CutGeneration','intermediate','ObjectiveImprovementThreshold',1e-4,'CutMaxIterations',25,'CutGeneration','advanced');
% call the optimization solver to find the best solution
[sol,TotalCost,exitflag,output] = solve(powerprob,options);

%%
Scheduled_LoadProfile = sol.power;
loadPercentage = Scheduled_LoadProfile./repmat(UC2{5,:},nHrs,1);

