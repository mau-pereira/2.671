% Code to load .csv files into tables with top-level file attributes, controlled by 'LoadTable'
clear all; close all; clc;  % Clear the workspace

%% Choose options to set file path for your data loading

% Parameter to decide loading mechanism
% LoadTable = 0 for popup window file selection
% LoadTable = 1 for loading all .csv files from a specified folder
LoadTable = 0; % Adjust this as needed

% If LoadTable =1, Specify the folder path where .csv files are located
Path = 'data/'; % Adjust to your specific folder path

Instron = 0;  %if you used the instron or texture analyzer, set 'Instron = 1' to invoke formatting options for those csv's.

%% Load files
%Data will be stored in a Table called 'Test'.  Variables for the i_th test
%are called as Test(i).data.VariableName, per the printout in the command
%window

% Initialize fileInfo as an empty struct array
fileInfo = struct('name', {}, 'folder', {}, 'date', {}, 'bytes', {}, 'isdir', {}, 'datenum', {});

if LoadTable == 0
    % Open a dialog to select one or more .csv files
    [filenames, Path] = uigetfile('*.csv', 'Select one or more data files', 'MultiSelect', 'on');
    if isequal(filenames,0) || isequal(Path,0)
        disp('User pressed cancel');
        return;
    else
        disp(['User selected files from ', Path]);
    end
    
    % Ensure 'filenames' is a cell array if only one file is selected
    if ischar(filenames)
        filenames = {filenames};
    end
    
    % Manually construct fileInfo for each selected file, using dir to fill in attributes
    for i = 1:length(filenames)
        % Use dir on the full path to get all attributes
        fullFilePath = fullfile(Path, filenames{i});
        fileAttributes = dir(fullFilePath);
        
        % There should only be one match, since we're specifying a full path
        if ~isempty(fileAttributes) && length(fileAttributes) == 1
            fileInfo(i) = fileAttributes; % Assign attributes directly
        else
            error(['Could not retrieve file attributes for ', fullFilePath]);
        end
    end
else

    tmpInfo = dir(fullfile(Path, '*.csv'));
    if isempty(tmpInfo)
        disp('No .csv files found in the specified folder.');
        return;
    end
    fileInfo = tmpInfo; % Assign the result of dir directly if files are from a folder
end

% Initialize the Test structure
Test = repmat(struct(), numel(fileInfo), 1);

% Assuming the first file is representative for import options
opts = detectImportOptions(fullfile(Path, fileInfo(1).name));

if Instron
    opts.VariableNamesLine = 2;  %Texture analyzer variable names 'Force'; 'Distance';'Time'
    opts.VariableUnitsLine = 3;  %Texture analyzer units are in row 3, and default to 'N', 'mm', 's' respectively
    opts.DataLines = [5,inf]; %Texture analyzer data starts on row 5 and goes to the completion of the file.
end

% Loop through each file, read the data, and store file attributes
for k = 1:numel(fileInfo)
    F = fullfile(Path, fileInfo(k).name);
    Test(k).data = readtable(F,opts); % Load data into 'data' subfield
    % Directly assign file attributes to the top level of Test(k)
    Test(k).name = fileInfo(k).name;
    Test(k).folder = fileInfo(k).folder;
    Test(k).date = fileInfo(k).date;
    Test(k).bytes = fileInfo(k).bytes;
    Test(k).isdir = fileInfo(k).isdir;
    Test(k).datenum = fileInfo(k).datenum;
end

disp(['Data loaded for ',num2str(numel(fileInfo)),' file(s).'])
disp('For the first test, variables loaded are:');

% Display the variables loaded for the first test
for k = 1:numel(Test(1).data.Properties.VariableNames)
    if isempty(Test(1).data.Properties.VariableUnits)
        disp(['Test(1).data.',Test(1).data.Properties.VariableNames{k}])
    else
        disp(['Test(1).data.',Test(1).data.Properties.VariableNames{k},' in units of (',Test(1).data.Properties.VariableUnits{k},')']);
    end
end

%clean up the workspace
clear F; clear fileInfo; clear k; clear opts; clear tmpInfo;
clear fileAttributes; clear filenames; clear fullFilePath; clear i; 
