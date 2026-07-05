clear;
clc;

greekDesktop = char([933 960 959 955 959 947 953 963 964 942 962]);
projectDir = fullfile(getenv('USERPROFILE'), 'OneDrive', greekDesktop, 'project');
packageDir = fullfile(projectDir, 'Thema3_GitHub_ready');

if exist(packageDir, 'dir')
    rmdir(packageDir, 's');
end

mkdir(packageDir);
mkdir(fullfile(packageDir, 'code'));
mkdir(fullfile(packageDir, 'input_images'));
mkdir(fullfile(packageDir, 'results', 'by_image'));
mkdir(fullfile(packageDir, 'results', 'by_part'));

copy_code_files(projectDir, packageDir);
[imageFiles, imageIds] = copy_input_images(projectDir, packageDir);
copy_results(projectDir, packageDir, imageIds);
write_essential_metric_files(projectDir, packageDir, imageFiles, imageIds);
write_readme(packageDir);

fprintf('Ο οργανωμένος φάκελος για GitHub δημιουργήθηκε εδώ:\n%s\n', packageDir);

function copy_code_files(projectDir, packageDir)
    codeFiles = {'eikonaB3A.m', 'eikonaB3B.m', 'eikonaB3C.m', 'eikonaB3D.m', 'eikonaB3E.m', 'eikonaB3FGH.m', 'organizeB3Results.m'};
    codeDir = fullfile(packageDir, 'code');
    for idx = 1:numel(codeFiles)
        sourcePath = fullfile(projectDir, codeFiles{idx});
        if exist(sourcePath, 'file') == 2
            copyfile(sourcePath, fullfile(codeDir, codeFiles{idx}));
        end
    end
end

function [imageFiles, imageIds] = copy_input_images(projectDir, packageDir)
    lowFiles = dir(fullfile(projectDir, '*_low.png'));
    imageIds = nan(numel(lowFiles), 1);
    keepFile = false(numel(lowFiles), 1);

    for idx = 1:numel(lowFiles)
        tokens = regexp(lowFiles(idx).name, '^(\d+)_low\.png$', 'tokens', 'once');
        if ~isempty(tokens)
            keepFile(idx) = true;
            imageIds(idx) = str2double(tokens{1});
        end
    end

    imageFiles = lowFiles(keepFile);
    imageIds = imageIds(keepFile);
    [imageIds, sortOrder] = sort(imageIds);
    imageFiles = imageFiles(sortOrder);

    inputDir = fullfile(packageDir, 'input_images');
    for idx = 1:numel(imageIds)
        lowName = sprintf('%d_low.png', imageIds(idx));
        highName = sprintf('%d_high.png', imageIds(idx));
        copy_if_exists(fullfile(projectDir, lowName), fullfile(inputDir, lowName));
        copy_if_exists(fullfile(projectDir, highName), fullfile(inputDir, highName));
    end
end

function copy_results(projectDir, packageDir, imageIds)
    partNames = {'A', 'B', 'C', 'D', 'E', 'FGH'};
    resultDirs = {'resultsB3A', 'resultsB3B', 'resultsB3C', 'resultsB3D', 'resultsB3E', 'resultsB3FGH'};

    for partIdx = 1:numel(partNames)
        partName = partNames{partIdx};
        sourceDir = fullfile(projectDir, resultDirs{partIdx});
        if exist(sourceDir, 'dir') ~= 7
            continue;
        end

        files = list_files(sourceDir);
        for fileIdx = 1:numel(files)
            sourcePath = files{fileIdx};
            [~, fileName, ext] = fileparts(sourcePath);
            ext = lower(ext);
            if ~ismember(ext, {'.png', '.csv', '.txt'})
                continue;
            end

            fileWithExt = [fileName, ext];
            category = category_from_extension(ext);
            imageId = image_id_from_filename(fileWithExt);

            if ~isnan(imageId)
                destinationDir = fullfile(packageDir, 'results', 'by_image', sprintf('%03d', imageId), ['part_', partName], category);
            else
                destinationDir = fullfile(packageDir, 'results', 'by_part', ['part_', partName], category);
            end

            ensure_dir(destinationDir);
            copyfile(sourcePath, fullfile(destinationDir, fileWithExt));

            if strcmp(ext, '.csv')
                split_csv_by_image(sourcePath, packageDir, partName, imageIds);
            end
        end
    end
end

function split_csv_by_image(csvPath, packageDir, partName, imageIds)
    try
        tableData = readtable(csvPath, 'TextType', 'string');
    catch
        return;
    end

    if isempty(tableData) || width(tableData) == 0
        return;
    end

    variableNames = tableData.Properties.VariableNames;
    if ismember('ImageNumber', variableNames)
        imageNumbers = tableData.ImageNumber;
    elseif ismember('Image', variableNames)
        imageNumbers = image_numbers_from_image_column(tableData.Image);
    else
        return;
    end

    imageNumbers = double(imageNumbers);
    [~, fileName, ext] = fileparts(csvPath);

    for idx = 1:numel(imageIds)
        imageId = imageIds(idx);
        rows = imageNumbers == imageId;
        if any(rows)
            destinationDir = fullfile(packageDir, 'results', 'by_image', sprintf('%03d', imageId), ['part_', partName], 'csv');
            ensure_dir(destinationDir);
            writetable(tableData(rows, :), fullfile(destinationDir, [fileName, ext]));
        end
    end
end

function write_essential_metric_files(projectDir, packageDir, imageFiles, imageIds)
    tables.B3A = read_table_if_exists(fullfile(projectDir, 'resultsB3A', 'B3A_statistics.csv'));
    tables.B3B = read_table_if_exists(fullfile(projectDir, 'resultsB3B', 'B3B_statistics.csv'));
    tables.B3C = read_table_if_exists(fullfile(projectDir, 'resultsB3C', 'B3C_statistics.csv'));
    tables.B3D = read_table_if_exists(fullfile(projectDir, 'resultsB3D', 'B3D_statistics.csv'));
    tables.B3E = read_table_if_exists(fullfile(projectDir, 'resultsB3E', 'B3E_statistics.csv'));
    tables.FGHBest = read_table_if_exists(fullfile(projectDir, 'resultsB3FGH', 'metrics', 'B3FGH_summary_best_pipeline.csv'));
    tables.FGHEdges = read_table_if_exists(fullfile(projectDir, 'resultsB3FGH', 'metrics', 'B3FGH_part_H_edge_metrics.csv'));

    for idx = 1:numel(imageIds)
        imageId = imageIds(idx);
        imageDir = fullfile(packageDir, 'results', 'by_image', sprintf('%03d', imageId));
        ensure_dir(imageDir);

        txtPath = fullfile(imageDir, 'essential_metrics.txt');
        fid = fopen(txtPath, 'w', 'n', 'UTF-8');
        if fid == -1
            continue;
        end
        cleanupObj = onCleanup(@() fclose(fid));

        fprintf(fid, 'Εικόνα: %s\n', imageFiles(idx).name);
        fprintf(fid, 'Low-light: %d_low.png\n', imageId);
        fprintf(fid, 'Reference: %d_high.png\n\n', imageId);

        write_a_metrics(fid, tables.B3A, imageId);
        write_b_metrics(fid, tables.B3B, imageId);
        write_c_metrics(fid, tables.B3C, imageId);
        write_d_metrics(fid, tables.B3D, imageId);
        write_e_metrics(fid, tables.B3E, imageId);
        write_fgh_metrics(fid, tables.FGHBest, tables.FGHEdges, imageId);

        clear cleanupObj;
    end
end

function write_a_metrics(fid, tableData, imageId)
    if isempty(tableData)
        return;
    end
    rows = tableData.ImageNumber == imageId;
    if any(rows)
        row = tableData(find(rows, 1), :);
        fprintf(fid, 'Μέρος Α\n');
        fprintf(fid, 'Mean brightness: %.6f\n', row.MeanBrightness);
        fprintf(fid, 'Variance: %.6f\n', row.IntensityVariance);
        fprintf(fid, 'Std contrast: %.6f\n', row.StdContrast);
        fprintf(fid, 'Dark pixels: %.2f%%\n\n', row.DarkPixelPercent);
    end
end

function write_b_metrics(fid, tableData, imageId)
    if isempty(tableData)
        return;
    end
    rows = tableData.ImageNumber == imageId;
    if any(rows)
        fprintf(fid, 'Μέρος Β\n');
        write_method_line(fid, tableData(rows, :), 'Linear stretch');
        write_parameter_line(fid, tableData(rows, :), 'Gamma correction', 'gamma = 0.4');
        write_parameter_line(fid, tableData(rows, :), 'Gamma correction', 'gamma = 0.6');
        write_method_line(fid, tableData(rows, :), 'Log transform');
        fprintf(fid, '\n');
    end
end

function write_c_metrics(fid, tableData, imageId)
    if isempty(tableData)
        return;
    end
    rows = tableData.ImageNumber == imageId;
    if any(rows)
        fprintf(fid, 'Μέρος Γ\n');
        write_method_line(fid, tableData(rows, :), 'Global histogram equalization');
        write_parameter_line(fid, tableData(rows, :), 'Adaptive histogram equalization', 'NumTiles=[8 8], ClipLimit=0.01');
        fprintf(fid, '\n');
    end
end

function write_d_metrics(fid, tableData, imageId)
    if isempty(tableData)
        return;
    end
    rows = tableData.ImageNumber == imageId & strcmp(tableData.Stage, 'Denoising');
    if any(rows)
        selected = tableData(rows, :);
        [~, bestIdx] = max(selected.PSNR);
        best = selected(bestIdx, :);
        fprintf(fid, 'Μέρος Δ\n');
        fprintf(fid, 'Best denoising row: %s / %s, PSNR %.2f, MSE %.6f\n\n', char(best.NoiseType), char(best.Method), best.PSNR, best.MSE);
    end
end

function write_e_metrics(fid, tableData, imageId)
    if isempty(tableData)
        return;
    end
    rows = tableData.ImageNumber == imageId;
    if any(rows)
        fprintf(fid, 'Μέρος Ε\n');
        write_method_line(fid, tableData(rows, :), 'Laplacian sharpening');
        write_parameter_line(fid, tableData(rows, :), 'Unsharp masking', 'k = 1.0');
        fprintf(fid, '\n');
    end
end

function write_fgh_metrics(fid, bestTable, edgeTable, imageId)
    fprintf(fid, 'Μέρη ΣΤ-Ζ-Η\n');
    if ~isempty(bestTable)
        rows = bestTable.ImageNumber == imageId;
        if any(rows)
            row = bestTable(find(rows, 1), :);
            bestPipeline = get_text_value(row, {'BestPipelineByPSNR', 'BestPipeline', 'Pipeline'});
            bestPsnr = get_numeric_value(row, {'BestPSNRToHigh', 'PSNRToHigh'});
            bestMse = get_numeric_value(row, {'BestMSEToHigh', 'MSEToHigh'});
            fprintf(fid, 'Best pipeline by PSNR: %s\n', bestPipeline);
            fprintf(fid, 'Best PSNR: %.2f dB, MSE: %.6f\n', bestPsnr, bestMse);
        end
    end

    if ~isempty(edgeTable)
        rows = edgeTable.ImageNumber == imageId & strcmp(edgeTable.EdgeDetector, 'Canny') & ~strcmp(edgeTable.Pipeline, 'Original low-light');
        if any(rows)
            selected = edgeTable(rows, :);
            [~, bestIdx] = max(selected.JaccardToHigh);
            best = selected(bestIdx, :);
            fprintf(fid, 'Best Canny edge match: %s, Jaccard %.4f, Edge density %.4f\n', char(best.Pipeline), best.JaccardToHigh, best.EdgeDensity);
        end
    end
    fprintf(fid, '\n');
end

function textValue = get_text_value(row, variableNames)
    textValue = '';
    for idx = 1:numel(variableNames)
        if ismember(variableNames{idx}, row.Properties.VariableNames)
            textValue = char(row.(variableNames{idx}));
            return;
        end
    end
end

function numericValue = get_numeric_value(row, variableNames)
    numericValue = NaN;
    for idx = 1:numel(variableNames)
        if ismember(variableNames{idx}, row.Properties.VariableNames)
            numericValue = row.(variableNames{idx});
            return;
        end
    end
end

function write_method_line(fid, tableData, methodName)
    rows = strcmp(tableData.Method, methodName);
    if any(rows)
        row = tableData(find(rows, 1), :);
        fprintf(fid, '%s: mean %.6f, contrast %.6f\n', methodName, row.MeanBrightness, row.StdContrast);
    end
end

function write_parameter_line(fid, tableData, methodName, parameterText)
    rows = strcmp(tableData.Method, methodName) & strcmp(tableData.Parameter, parameterText);
    if any(rows)
        row = tableData(find(rows, 1), :);
        fprintf(fid, '%s (%s): mean %.6f, contrast %.6f\n', methodName, parameterText, row.MeanBrightness, row.StdContrast);
    end
end

function tableData = read_table_if_exists(csvPath)
    if exist(csvPath, 'file') ~= 2
        tableData = table();
        return;
    end
    try
        tableData = readtable(csvPath, 'TextType', 'string');
    catch
        tableData = table();
    end
end

function write_readme(packageDir)
    readmePath = fullfile(packageDir, 'README.md');
    fid = fopen(readmePath, 'w', 'n', 'UTF-8');
    if fid == -1
        return;
    end
    cleanupObj = onCleanup(@() fclose(fid));

    fprintf(fid, '# Thema 3 - Low-light image enhancement\n\n');
    fprintf(fid, 'This folder contains the code, input images, organized results, full CSV files, and essential TXT metric summaries.\n\n');
    fprintf(fid, '## Structure\n\n');
    fprintf(fid, '- `code/`: all MATLAB scripts.\n');
    fprintf(fid, '- `input_images/`: `*_low.png` and `*_high.png` pairs.\n');
    fprintf(fid, '- `results/by_image/`: all outputs separated by image number.\n');
    fprintf(fid, '- `results/by_part/`: combined outputs and complete CSV/TXT files per assignment part.\n\n');
    fprintf(fid, 'The report contains selected results and discussion; this folder keeps the full organized run for reproducibility.\n');

    clear cleanupObj;
end

function files = list_files(rootDir)
    dirData = dir(rootDir);
    files = {};
    for idx = 1:numel(dirData)
        name = dirData(idx).name;
        if strcmp(name, '.') || strcmp(name, '..')
            continue;
        end
        path = fullfile(rootDir, name);
        if dirData(idx).isdir
            childFiles = list_files(path);
            files = [files; childFiles]; %#ok<AGROW>
        else
            files{end + 1, 1} = path; %#ok<AGROW>
        end
    end
end

function category = category_from_extension(ext)
    switch lower(ext)
        case '.png'
            category = 'figures';
        case '.csv'
            category = 'csv';
        otherwise
            category = 'txt';
    end
end

function imageId = image_id_from_filename(fileName)
    tokens = regexp(fileName, '^\d+_(\d+)_low', 'tokens', 'once');
    if isempty(tokens)
        imageId = NaN;
    else
        imageId = str2double(tokens{1});
    end
end

function imageNumbers = image_numbers_from_image_column(imageColumn)
    imageNumbers = nan(numel(imageColumn), 1);
    for idx = 1:numel(imageColumn)
        tokens = regexp(char(imageColumn(idx)), '^(\d+)_low\.png$', 'tokens', 'once');
        if ~isempty(tokens)
            imageNumbers(idx) = str2double(tokens{1});
        end
    end
end

function copy_if_exists(sourcePath, destinationPath)
    if exist(sourcePath, 'file') == 2
        copyfile(sourcePath, destinationPath);
    end
end

function ensure_dir(folderPath)
    if exist(folderPath, 'dir') ~= 7
        mkdir(folderPath);
    end
end
