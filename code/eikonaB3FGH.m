% Μέρος ΣΤ
clear;
clc;
close all;

greekDesktop = char([933 960 959 955 959 947 953 963 964 942 962]);
% Replace with your path
projectDir = fullfile(getenv('USERPROFILE'), 'OneDrive', greekDesktop, 'project');
resultsDir = fullfile(projectDir, 'resultsB3FGH');
summaryDir = fullfile(resultsDir, 'summary');
detailsDir = fullfile(resultsDir, 'details');
metricsDir = fullfile(resultsDir, 'metrics');
pipelineDetailsDir = fullfile(detailsDir, 'pipeline_images');
edgeDetailsDir = fullfile(detailsDir, 'edge_maps');
expectedFolderName = 'resultsB3FGH';

[~, actualFolderName] = fileparts(resultsDir);
if isempty(resultsDir) || strcmp(resultsDir, projectDir) || ~strcmp(actualFolderName, expectedFolderName)
    error('Unsafe results folder: %s', resultsDir);
end

if ~exist(resultsDir, 'dir')
    mkdir(resultsDir);
end

oldFiles = [dir(fullfile(resultsDir, '*.png')); dir(fullfile(resultsDir, '*.csv')); dir(fullfile(resultsDir, '*.txt')); dir(fullfile(resultsDir, '*.mat'))];
oldDirs = {summaryDir, detailsDir, metricsDir};
oldWarningState = warning('off', 'all');
for oldIdx = 1:numel(oldFiles)
    oldPath = fullfile(resultsDir, oldFiles(oldIdx).name);
    if exist(oldPath, 'file') == 2
        try
            delete(oldPath);
        catch
        end
    end
end
for oldIdx = 1:numel(oldDirs)
    if exist(oldDirs{oldIdx}, 'dir')
        try
            rmdir(oldDirs{oldIdx}, 's');
        catch
        end
    end
end
warning(oldWarningState);

mkdir(summaryDir);
mkdir(metricsDir);
mkdir(detailsDir);
mkdir(pipelineDetailsDir);
mkdir(edgeDetailsDir);

[imageFiles, imageIds] = find_low_images(projectDir);
retinexSigmas = [15 30 60];

pipelineTemplate = struct('Image', '', 'ImageNumber', 0, 'Pipeline', '', 'Parameter', '', 'MeanBrightness', 0, 'StdContrast', 0, 'EntropyValue', 0, 'DarkPixelPercent', 0, 'SaturatedPixelPercent', 0, 'Comment', '');
pipelineRows = repmat(pipelineTemplate, numel(imageFiles) * 6, 1);
pipelineRowIdx = 0;

reportFile = fullfile(metricsDir, 'B3FGH_part_ST_comments.txt');
reportFid = fopen(reportFile, 'w', 'n', 'UTF-8');
if reportFid == -1
    error('Δεν ήταν δυνατή η δημιουργία του αρχείου: %s', reportFile);
end
reportCleanup = onCleanup(@() fclose(reportFid));

fprintf(reportFid, 'Μέρος ΣΤ: Σύγκριση πλήρων pipelines\n');
fprintf(reportFid, 'Pipeline 1: gamma correction και linear contrast stretching.\n');
fprintf(reportFid, 'Pipeline 2: median filtering, CLAHE και unsharp masking.\n');
fprintf(reportFid, 'Pipeline 3: Retinex-like προσέγγιση με sigma = 15, 30, 60.\n\n');

fprintf('Μέρος ΣΤ: βρέθηκαν %d εικόνες χαμηλού φωτισμού.\n', numel(imageFiles));
fprintf('Τα αποτελέσματα θα αποθηκευτούν εδώ:\n%s\n\n', resultsDir);

for idx = 1:numel(imageFiles)
    imagePath = fullfile(projectDir, imageFiles(idx).name);
    [lowImage, isColorImage] = read_image_as_double(imagePath);
    [~, baseName] = fileparts(imageFiles(idx).name);
    safeBaseName = make_safe_filename(baseName);
    outputPrefix = sprintf('%02d_%s', idx, safeBaseName);

    pipeline1Image = pipeline_simple_brightness(lowImage);
    pipeline2Image = pipeline_equalization_denoising(lowImage, isColorImage);
    retinexImages = cell(numel(retinexSigmas), 1);

    for sigmaIdx = 1:numel(retinexSigmas)
        retinexImages{sigmaIdx} = pipeline_retinex(lowImage, isColorImage, retinexSigmas(sigmaIdx));
    end

    pipelineImages = [{lowImage}; {pipeline1Image}; {pipeline2Image}; retinexImages(:)];
    pipelineNames = [{'Original low-light'}; {'Pipeline 1 - Gamma + stretch'}; {'Pipeline 2 - Median + CLAHE + unsharp'}; arrayfun(@(sigma) sprintf('Pipeline 3 - Retinex sigma %d', sigma), retinexSigmas(:), 'UniformOutput', false)];
    pipelineParameters = [{''}; {'gamma=0.6, full range stretch'}; {'median 3x3, CLAHE 8x8 clip 0.01, unsharp k=0.8'}; arrayfun(@(sigma) sprintf('sigma=%d', sigma), retinexSigmas(:), 'UniformOutput', false)];

    imwrite(lowImage, fullfile(pipelineDetailsDir, [outputPrefix, '_original_low.png']));
    imwrite(pipeline1Image, fullfile(pipelineDetailsDir, [outputPrefix, '_pipeline1_gamma_stretch.png']));
    imwrite(pipeline2Image, fullfile(pipelineDetailsDir, [outputPrefix, '_pipeline2_median_clahe_unsharp.png']));

    for sigmaIdx = 1:numel(retinexSigmas)
        imwrite(retinexImages{sigmaIdx}, fullfile(pipelineDetailsDir, sprintf('%s_pipeline3_retinex_sigma_%d.png', outputPrefix, retinexSigmas(sigmaIdx))));
    end

    pipelineGridTitles = {'Original', 'Pipeline 1', 'Pipeline 2', 'Retinex sigma 15', 'Retinex sigma 30', 'Retinex sigma 60'};
    save_image_grid(pipelineImages, pipelineGridTitles, sprintf('Μέρος ΣΤ - Pipelines: %s', imageFiles(idx).name), fullfile(summaryDir, [outputPrefix, '_ST_pipeline_grid.png']));

    fprintf(reportFid, 'Εικόνα %02d: %s\n', idx, imageFiles(idx).name);
    for pipelineIdx = 1:numel(pipelineImages)
        currentImage = pipelineImages{pipelineIdx};
        currentName = pipelineNames{pipelineIdx};
        currentParameter = pipelineParameters{pipelineIdx};
        currentComment = make_pipeline_comment(currentName, currentParameter, lowImage, currentImage, isColorImage);

        pipelineRowIdx = pipelineRowIdx + 1;
        pipelineRows(pipelineRowIdx) = make_pipeline_row(imageFiles(idx).name, imageIds(idx), currentName, currentParameter, currentImage, isColorImage, currentComment);

        if pipelineIdx > 1
            fprintf(reportFid, '%s: %s\n', currentName, currentComment);
        end
    end
    fprintf(reportFid, '\n');

    fprintf('%02d/%02d %s: ολοκληρώθηκαν τα τρία pipelines\n', idx, numel(imageFiles), imageFiles(idx).name);
    drawnow;
end

pipelineRows = pipelineRows(1:pipelineRowIdx);
pipelineTable = struct2table(pipelineRows);
pipelineSummaryTable = make_pipeline_summary_table(pipelineTable);
writetable(pipelineTable, fullfile(metricsDir, 'B3FGH_part_ST_pipeline_metrics.csv'));
writetable(pipelineSummaryTable, fullfile(metricsDir, 'B3FGH_summary_pipeline_means.csv'));
write_summary_report(reportFid, pipelineTable);

% Μέρος Ζ
zTemplate = struct('Image', '', 'ImageNumber', 0, 'HighReferenceImage', '', 'Pipeline', '', 'Parameter', '', 'MSEToHigh', NaN, 'PSNRToHigh', NaN, 'MeanBrightness', 0, 'StdContrast', 0, 'MichelsonContrast', 0, 'EntropyValue', 0, 'Comment', '');
zRows = repmat(zTemplate, height(pipelineTable), 1);
zRowIdx = 0;

zReportFile = fullfile(metricsDir, 'B3FGH_part_Z_quantitative_evaluation.txt');
zReportFid = fopen(zReportFile, 'w', 'n', 'UTF-8');
if zReportFid == -1
    error('Δεν ήταν δυνατή η δημιουργία του αρχείου: %s', zReportFile);
end
zReportCleanup = onCleanup(@() fclose(zReportFid));

fprintf(zReportFid, 'Μέρος Ζ: Ποσοτική αξιολόγηση\n');
fprintf(zReportFid, 'Υπολογίζονται MSE, PSNR, μέση φωτεινότητα, τυπική απόκλιση ως αντίθεση, Michelson contrast και entropy.\n\n');

for idx = 1:numel(imageFiles)
    highReferenceName = sprintf('%d_high.png', imageIds(idx));
    highReferencePath = fullfile(projectDir, highReferenceName);
    if exist(highReferencePath, 'file') == 2
        [highImage, ~] = read_image_as_double(highReferencePath);
    else
        highReferenceName = '';
        highImage = [];
    end

    [~, baseName] = fileparts(imageFiles(idx).name);
    safeBaseName = make_safe_filename(baseName);
    outputPrefix = sprintf('%02d_%s', idx, safeBaseName);

    zImageFiles = [{[outputPrefix, '_original_low.png']}; {[outputPrefix, '_pipeline1_gamma_stretch.png']}; {[outputPrefix, '_pipeline2_median_clahe_unsharp.png']}; arrayfun(@(sigma) sprintf('%s_pipeline3_retinex_sigma_%d.png', outputPrefix, sigma), retinexSigmas(:), 'UniformOutput', false)];
    zPipelineNames = [{'Original low-light'}; {'Pipeline 1 - Gamma + stretch'}; {'Pipeline 2 - Median + CLAHE + unsharp'}; arrayfun(@(sigma) sprintf('Pipeline 3 - Retinex sigma %d', sigma), retinexSigmas(:), 'UniformOutput', false)];
    zPipelineParameters = [{''}; {'gamma=0.6, full range stretch'}; {'median 3x3, CLAHE 8x8 clip 0.01, unsharp k=0.8'}; arrayfun(@(sigma) sprintf('sigma=%d', sigma), retinexSigmas(:), 'UniformOutput', false)];

    fprintf(zReportFid, 'Εικόνα %02d: %s\n', idx, imageFiles(idx).name);
    fprintf(zReportFid, 'Φωτεινή εικόνα αναφοράς: %s\n', value_or_none(highReferenceName));

    for pipelineIdx = 1:numel(zImageFiles)
        resultPath = fullfile(pipelineDetailsDir, zImageFiles{pipelineIdx});
        if exist(resultPath, 'file') ~= 2
            continue;
        end

        [resultImage, resultIsColorImage] = read_image_as_double(resultPath);
        currentName = zPipelineNames{pipelineIdx};
        currentParameter = zPipelineParameters{pipelineIdx};
        currentComment = make_z_comment(currentName, resultImage, highImage, resultIsColorImage);

        zRowIdx = zRowIdx + 1;
        zRows(zRowIdx) = make_z_row(imageFiles(idx).name, imageIds(idx), highReferenceName, currentName, currentParameter, resultImage, highImage, resultIsColorImage, currentComment);

        if pipelineIdx > 1
            fprintf(zReportFid, '%s: %s\n', currentName, currentComment);
        end
    end
    fprintf(zReportFid, '\n');
end

zRows = zRows(1:zRowIdx);
zTable = struct2table(zRows);
bestPipelineTable = make_best_pipeline_summary(zTable);
writetable(zTable, fullfile(metricsDir, 'B3FGH_part_Z_quantitative_metrics.csv'));
writetable(bestPipelineTable, fullfile(metricsDir, 'B3FGH_summary_best_pipeline.csv'));
write_z_summary_report(zReportFid, zTable);

% Μέρος Η
edgeMethods = {'Sobel', 'Canny'};
hTemplate = struct('Image', '', 'ImageNumber', 0, 'HighReferenceImage', '', 'Pipeline', '', 'Parameter', '', 'EdgeDetector', '', 'EdgeCount', 0, 'EdgeDensity', 0, 'ComponentCount', 0, 'SmallComponentPercent', 0, 'SignificantComponentPercent', 0, 'JaccardToHigh', NaN, 'EdgeCountRatioToOriginal', 0, 'Comment', '');
hRows = repmat(hTemplate, height(pipelineTable) * numel(edgeMethods), 1);
hRowIdx = 0;

hReportFile = fullfile(metricsDir, 'B3FGH_part_H_edge_evaluation.txt');
hReportFid = fopen(hReportFile, 'w', 'n', 'UTF-8');
if hReportFid == -1
    error('Δεν ήταν δυνατή η δημιουργία του αρχείου: %s', hReportFile);
end
hReportCleanup = onCleanup(@() fclose(hReportFid));

fprintf(hReportFid, 'Μέρος Η: Επίδραση των μεθόδων σε ακμές και χαρακτηριστικά\n');
fprintf(hReportFid, 'Εφαρμόζονται Sobel και Canny στην αρχική low-light εικόνα και στις βελτιωμένες εικόνες.\n');
fprintf(hReportFid, 'Συγκρίνονται πλήθος ακμών, πυκνότητα, μικρά components ως ένδειξη θορύβου και μεγαλύτερα components ως ένδειξη ορατών αντικειμένων.\n\n');

for idx = 1:numel(imageFiles)
    highReferenceName = sprintf('%d_high.png', imageIds(idx));
    highReferencePath = fullfile(projectDir, highReferenceName);
    if exist(highReferencePath, 'file') == 2
        [highImage, ~] = read_image_as_double(highReferencePath);
    else
        highReferenceName = '';
        highImage = [];
    end

    [~, baseName] = fileparts(imageFiles(idx).name);
    safeBaseName = make_safe_filename(baseName);
    outputPrefix = sprintf('%02d_%s', idx, safeBaseName);

    hImageFiles = [{[outputPrefix, '_original_low.png']}; {[outputPrefix, '_pipeline1_gamma_stretch.png']}; {[outputPrefix, '_pipeline2_median_clahe_unsharp.png']}; arrayfun(@(sigma) sprintf('%s_pipeline3_retinex_sigma_%d.png', outputPrefix, sigma), retinexSigmas(:), 'UniformOutput', false)];
    hPipelineNames = [{'Original low-light'}; {'Pipeline 1 - Gamma + stretch'}; {'Pipeline 2 - Median + CLAHE + unsharp'}; arrayfun(@(sigma) sprintf('Pipeline 3 - Retinex sigma %d', sigma), retinexSigmas(:), 'UniformOutput', false)];
    hPipelineParameters = [{''}; {'gamma=0.6, full range stretch'}; {'median 3x3, CLAHE 8x8 clip 0.01, unsharp k=0.8'}; arrayfun(@(sigma) sprintf('sigma=%d', sigma), retinexSigmas(:), 'UniformOutput', false)];

    originalPath = fullfile(pipelineDetailsDir, hImageFiles{1});
    [originalImage, originalIsColorImage] = read_image_as_double(originalPath);
    originalGray = to_gray(originalImage, originalIsColorImage);
    if isempty(highImage)
        highGray = [];
    else
        highForEdges = resize_to_match(highImage, originalImage);
        highForEdgesIsColor = ndims(highForEdges) == 3 && size(highForEdges, 3) == 3;
        highGray = to_gray(highForEdges, highForEdgesIsColor);
    end

    fprintf(hReportFid, 'Εικόνα %02d: %s\n', idx, imageFiles(idx).name);
    fprintf(hReportFid, 'Φωτεινή εικόνα αναφοράς: %s\n', value_or_none(highReferenceName));

    for edgeIdx = 1:numel(edgeMethods)
        edgeMethod = edgeMethods{edgeIdx};
        originalEdge = edge(originalGray, lower(edgeMethod));
        if isempty(highGray)
            highEdge = [];
        else
            highEdge = edge(highGray, lower(edgeMethod));
        end

        edgeGridImages = cell(numel(hImageFiles), 1);
        edgeGridTitles = {'Original', 'Pipeline 1', 'Pipeline 2', 'Retinex sigma 15', 'Retinex sigma 30', 'Retinex sigma 60'};
        edgeGridImages{1} = originalEdge;

        edgeOutputName = sprintf('%s_original_low_edges_%s.png', outputPrefix, lower(edgeMethod));
        imwrite(originalEdge, fullfile(edgeDetailsDir, edgeOutputName));

        hRowIdx = hRowIdx + 1;
        edgeComment = make_h_comment('Original low-light', originalEdge, originalEdge, highEdge);
        hRows(hRowIdx) = make_h_row(imageFiles(idx).name, imageIds(idx), highReferenceName, 'Original low-light', '', edgeMethod, originalEdge, originalEdge, highEdge, edgeComment);

        for pipelineIdx = 2:numel(hImageFiles)
            resultPath = fullfile(pipelineDetailsDir, hImageFiles{pipelineIdx});
            if exist(resultPath, 'file') ~= 2
                continue;
            end

            [resultImage, resultIsColorImage] = read_image_as_double(resultPath);
            resultGray = to_gray(resultImage, resultIsColorImage);
            resultEdge = edge(resultGray, lower(edgeMethod));
            currentName = hPipelineNames{pipelineIdx};
            currentParameter = hPipelineParameters{pipelineIdx};
            edgeOutputName = sprintf('%s_%s_edges_%s.png', outputPrefix, make_safe_filename(currentName), lower(edgeMethod));
            imwrite(resultEdge, fullfile(edgeDetailsDir, edgeOutputName));
            edgeGridImages{pipelineIdx} = resultEdge;

            hRowIdx = hRowIdx + 1;
            edgeComment = make_h_comment(currentName, resultEdge, originalEdge, highEdge);
            hRows(hRowIdx) = make_h_row(imageFiles(idx).name, imageIds(idx), highReferenceName, currentName, currentParameter, edgeMethod, resultEdge, originalEdge, highEdge, edgeComment);
        end

        save_image_grid(edgeGridImages, edgeGridTitles, sprintf('Μέρος Η - %s edges: %s', edgeMethod, imageFiles(idx).name), fullfile(summaryDir, sprintf('%s_H_edges_%s_grid.png', outputPrefix, lower(edgeMethod))));
    end

    fprintf(hReportFid, 'Σχόλιο: %s\n\n', make_h_image_summary(hRows(1:hRowIdx), imageFiles(idx).name));
end

hRows = hRows(1:hRowIdx);
hTable = struct2table(hRows);
edgeSummaryTable = make_edge_summary_table(hTable);
writetable(hTable, fullfile(metricsDir, 'B3FGH_part_H_edge_metrics.csv'));
writetable(edgeSummaryTable, fullfile(metricsDir, 'B3FGH_summary_edge_canny.csv'));
write_h_summary_report(hReportFid, hTable);

fprintf('\nΤα Μέρη ΣΤ, Ζ και Η ολοκληρώθηκαν.\n');
fprintf('Αποθηκεύτηκαν εικόνες pipelines, edge maps, συγκριτικά πλαίσια, στατιστικά και σχόλια εδώ:\n%s\n', resultsDir);

function [imageFiles, imageIds] = find_low_images(projectDir)
    lowFiles = dir(fullfile(projectDir, '*_low.png'));
    keepFile = false(numel(lowFiles), 1);
    imageIds = nan(numel(lowFiles), 1);
    for fileIdx = 1:numel(lowFiles)
        tokens = regexp(lowFiles(fileIdx).name, '^(\d+)_low\.png$', 'tokens', 'once');
        if ~isempty(tokens)
            keepFile(fileIdx) = true;
            imageIds(fileIdx) = str2double(tokens{1});
        end
    end
    imageFiles = lowFiles(keepFile);
    imageIds = imageIds(keepFile);
    if isempty(imageFiles)
        error('Δεν βρέθηκαν εικόνες με μορφή ονόματος number_low.png στον φάκελο: %s', projectDir);
    end
    [imageIds, sortOrder] = sort(imageIds);
    imageFiles = imageFiles(sortOrder);
end

function [imageDouble, isColorImage] = read_image_as_double(imagePath)
    [rawImage, colorMap] = imread(imagePath);
    if ~isempty(colorMap)
        imageDouble = ind2rgb(rawImage, colorMap);
    else
        imageDouble = im2double(rawImage);
    end
    if ndims(imageDouble) == 3 && size(imageDouble, 3) > 3
        imageDouble = imageDouble(:, :, 1:3);
    end
    isColorImage = ndims(imageDouble) == 3 && size(imageDouble, 3) == 3;
end

function outputImage = pipeline_simple_brightness(inputImage)
    gammaImage = min(max(inputImage, 0), 1) .^ 0.6;
    outputImage = linear_contrast_stretch(gammaImage);
end

function outputImage = pipeline_equalization_denoising(inputImage, isColorImage)
    denoisedImage = apply_median_filter(inputImage);
    brightness = extract_brightness(denoisedImage, isColorImage);
    enhancedBrightness = adapthisteq(brightness, 'NumTiles', [8 8], 'ClipLimit', 0.01, 'Distribution', 'uniform');
    claheImage = replace_brightness(denoisedImage, enhancedBrightness, isColorImage);
    outputImage = unsharp_mask(claheImage, 0.8);
end

function outputImage = pipeline_retinex(inputImage, isColorImage, sigmaValue)
    brightness = extract_brightness(inputImage, isColorImage);
    epsilonValue = 1e-3;
    illumination = imgaussfilt(brightness, sigmaValue);
    retinexImage = log(brightness + epsilonValue) - log(illumination + epsilonValue);
    retinexImage = robust_rescale(retinexImage, 1, 99);
    retinexImage = retinexImage .^ 0.85;
    outputImage = replace_brightness(inputImage, retinexImage, isColorImage);
end

function outputImage = apply_median_filter(inputImage)
    if ndims(inputImage) == 3
        outputImage = zeros(size(inputImage));
        for channelIdx = 1:size(inputImage, 3)
            outputImage(:, :, channelIdx) = medfilt2(inputImage(:, :, channelIdx), [3 3], 'symmetric');
        end
    else
        outputImage = medfilt2(inputImage, [3 3], 'symmetric');
    end
end

function outputImage = unsharp_mask(inputImage, kValue)
    blurredImage = imgaussfilt(inputImage, 1.0, 'FilterSize', 5);
    detailImage = inputImage - blurredImage;
    outputImage = min(max(inputImage + kValue * detailImage, 0), 1);
end

function outputImage = linear_contrast_stretch(inputImage)
    inputMin = min(inputImage(:));
    inputMax = max(inputImage(:));
    if inputMax <= inputMin
        outputImage = zeros(size(inputImage));
    else
        outputImage = (inputImage - inputMin) / (inputMax - inputMin);
    end
end

function brightness = extract_brightness(inputImage, isColorImage)
    if isColorImage
        hsvImage = rgb2hsv(inputImage);
        brightness = hsvImage(:, :, 3);
    else
        brightness = inputImage;
    end
end

function outputImage = replace_brightness(inputImage, brightness, isColorImage)
    brightness = min(max(brightness, 0), 1);
    if isColorImage
        hsvImage = rgb2hsv(inputImage);
        hsvImage(:, :, 3) = brightness;
        outputImage = hsv2rgb(hsvImage);
    else
        outputImage = brightness;
    end
end

function outputImage = robust_rescale(inputImage, lowPercentile, highPercentile)
    lowValue = percentile_value(inputImage(:), lowPercentile);
    highValue = percentile_value(inputImage(:), highPercentile);
    if highValue <= lowValue
        outputImage = linear_contrast_stretch(inputImage);
    else
        outputImage = (inputImage - lowValue) / (highValue - lowValue);
        outputImage = min(max(outputImage, 0), 1);
    end
end

function value = percentile_value(values, percentile)
    values = sort(values(:));
    if isempty(values)
        value = 0;
        return;
    end
    position = 1 + (numel(values) - 1) * percentile / 100;
    lowerIndex = floor(position);
    upperIndex = ceil(position);
    if lowerIndex == upperIndex
        value = values(lowerIndex);
    else
        value = values(lowerIndex) + (position - lowerIndex) * (values(upperIndex) - values(lowerIndex));
    end
end

function row = make_pipeline_row(imageName, imageNumber, pipelineName, parameterText, resultImage, isColorImage, commentText)
    stats = compute_image_stats(resultImage, isColorImage);
    row = struct('Image', imageName, 'ImageNumber', imageNumber, 'Pipeline', pipelineName, 'Parameter', parameterText, 'MeanBrightness', stats.Mean, 'StdContrast', stats.Std, 'EntropyValue', stats.Entropy, 'DarkPixelPercent', stats.DarkPercent, 'SaturatedPixelPercent', stats.SaturatedPercent, 'Comment', commentText);
end

function stats = compute_image_stats(inputImage, isColorImage)
    grayImage = to_gray(inputImage, isColorImage);
    pixels = grayImage(:);
    stats.Mean = mean(pixels);
    stats.Std = std(pixels);
    stats.DarkPercent = 100 * mean(pixels <= 0.25);
    stats.SaturatedPercent = 100 * mean(pixels >= 0.98);
    stats.Michelson = (max(pixels) - min(pixels)) / (max(pixels) + min(pixels) + eps);
    stats.Entropy = compute_entropy(grayImage);
end

function entropyValue = compute_entropy(grayImage)
    uintValues = uint8(round(255 * min(max(grayImage, 0), 1)));
    counts = histcounts(double(uintValues(:)), -0.5:1:255.5);
    probabilities = counts / sum(counts);
    probabilities = probabilities(probabilities > 0);
    entropyValue = -sum(probabilities .* log2(probabilities));
end

function grayImage = to_gray(inputImage, isColorImage)
    if isColorImage
        grayImage = rgb2gray(inputImage);
    else
        grayImage = inputImage;
    end
end

function save_image_grid(imageList, titleList, mainTitle, outputPath)
    validIdx = find(~cellfun(@isempty, imageList));
    if isempty(validIdx)
        return;
    end
    tileHeight = 260;
    tileWidth = 390;
    topMargin = 70;
    labelHeight = 34;
    gap = 18;
    rows = 2;
    cols = 3;
    canvasHeight = topMargin + rows * (labelHeight + tileHeight) + (rows + 1) * gap;
    canvasWidth = cols * tileWidth + (cols + 1) * gap;
    canvas = ones(canvasHeight, canvasWidth, 3);
    if exist('insertText', 'file') == 2
        canvas = insertText(canvas, [round(canvasWidth / 2) - 330, 18], mainTitle, 'FontSize', 24, 'BoxOpacity', 0, 'TextColor', 'black');
    end
    for tileIdx = 1:numel(validIdx)
        imageIdx = validIdx(tileIdx);
        rowIdx = floor((tileIdx - 1) / cols);
        colIdx = mod(tileIdx - 1, cols);
        xStart = gap + colIdx * (tileWidth + gap) + 1;
        yLabel = topMargin + gap + rowIdx * (labelHeight + tileHeight + gap) + 1;
        yStart = yLabel + labelHeight;
        tileImage = prepare_grid_image(imageList{imageIdx}, tileHeight, tileWidth);
        if exist('insertText', 'file') == 2
            canvas = insertText(canvas, [xStart + 8, yLabel + 4], titleList{imageIdx}, 'FontSize', 18, 'BoxOpacity', 0, 'TextColor', 'black');
        end
        canvas(yStart:yStart + tileHeight - 1, xStart:xStart + tileWidth - 1, :) = tileImage;
    end
    imwrite(canvas, outputPath);
end

function outputImage = prepare_grid_image(inputImage, targetHeight, targetWidth)
    inputImage = min(max(inputImage, 0), 1);
    if islogical(inputImage)
        inputImage = double(inputImage);
    end
    if ismatrix(inputImage)
        inputImage = repmat(inputImage, [1 1 3]);
    else
        inputImage = inputImage(:, :, 1:3);
    end
    outputImage = imresize(inputImage, [targetHeight targetWidth]);
end

function commentText = make_pipeline_comment(pipelineName, parameterText, lowImage, resultImage, isColorImage)
    lowStats = compute_image_stats(lowImage, isColorImage);
    resultStats = compute_image_stats(resultImage, isColorImage);
    brightnessGain = resultStats.Mean - lowStats.Mean;
    contrastGain = resultStats.Std - lowStats.Std;

    if contains(pipelineName, 'Pipeline 1')
        methodPart = 'Απλή και γρήγορη βελτίωση φωτεινότητας με gamma correction και άνοιγμα του δυναμικού εύρους.';
    elseif contains(pipelineName, 'Pipeline 2')
        methodPart = 'Πιο ισορροπημένη προσέγγιση, επειδή μειώνει θόρυβο, αυξάνει την τοπική αντίθεση και επαναφέρει λεπτομέρειες με unsharp masking.';
    elseif contains(pipelineName, 'Retinex')
        methodPart = sprintf('Η Retinex-like μέθοδος με %s εκτιμά τον φωτισμό με Gaussian smoothing και ενισχύει την τοπική αντίθεση.', parameterText);
    else
        methodPart = 'Η αρχική εικόνα χρησιμοποιείται ως βάση σύγκρισης.';
    end

    if resultStats.SaturatedPercent > lowStats.SaturatedPercent + 5
        riskPart = 'Υπάρχει αυξημένος κορεσμός, άρα μπορεί να εμφανίζεται υπερενίσχυση.';
    elseif resultStats.Entropy > lowStats.Entropy + 0.5
        riskPart = 'Η μεγαλύτερη entropy δείχνει περισσότερη ορατή πληροφορία, αλλά μπορεί να περιλαμβάνει και θόρυβο.';
    else
        riskPart = 'Η ενίσχυση παραμένει σχετικά ελεγχόμενη.';
    end

    commentText = sprintf('%s Η μέση φωτεινότητα αλλάζει κατά %.4f και η αντίθεση κατά %.4f. %s', methodPart, brightnessGain, contrastGain, riskPart);
end

function row = make_z_row(imageName, imageNumber, highReferenceName, pipelineName, parameterText, resultImage, highImage, isColorImage, commentText)
    stats = compute_image_stats(resultImage, isColorImage);
    [mseValue, psnrValue] = reference_metrics(highImage, resultImage);
    row = struct('Image', imageName, 'ImageNumber', imageNumber, 'HighReferenceImage', highReferenceName, 'Pipeline', pipelineName, 'Parameter', parameterText, 'MSEToHigh', mseValue, 'PSNRToHigh', psnrValue, 'MeanBrightness', stats.Mean, 'StdContrast', stats.Std, 'MichelsonContrast', stats.Michelson, 'EntropyValue', stats.Entropy, 'Comment', commentText);
end

function [mseValue, psnrValue] = reference_metrics(referenceImage, testImage)
    if isempty(referenceImage)
        mseValue = NaN;
        psnrValue = NaN;
        return;
    end
    referenceImage = resize_to_match(referenceImage, testImage);
    referenceImage = min(max(referenceImage, 0), 1);
    testImage = min(max(testImage, 0), 1);
    if ndims(referenceImage) ~= ndims(testImage) || size(referenceImage, 3) ~= size(testImage, 3)
        referenceImage = to_gray(referenceImage, ndims(referenceImage) == 3 && size(referenceImage, 3) == 3);
        testImage = to_gray(testImage, ndims(testImage) == 3 && size(testImage, 3) == 3);
    end
    difference = testImage - referenceImage;
    mseValue = mean(difference(:) .^ 2);
    if mseValue == 0
        psnrValue = Inf;
    else
        psnrValue = 10 * log10(1 / mseValue);
    end
end

function resizedImage = resize_to_match(referenceImage, targetImage)
    if size(referenceImage, 1) ~= size(targetImage, 1) || size(referenceImage, 2) ~= size(targetImage, 2)
        resizedImage = imresize(referenceImage, [size(targetImage, 1), size(targetImage, 2)]);
    else
        resizedImage = referenceImage;
    end
    if ismatrix(targetImage) && ndims(resizedImage) == 3 && size(resizedImage, 3) == 3
        resizedImage = rgb2gray(resizedImage);
    elseif ndims(targetImage) == 3 && size(targetImage, 3) == 3 && ismatrix(resizedImage)
        resizedImage = repmat(resizedImage, [1 1 3]);
    end
end

function commentText = make_z_comment(pipelineName, resultImage, highImage, isColorImage)
    stats = compute_image_stats(resultImage, isColorImage);
    [~, psnrValue] = reference_metrics(highImage, resultImage);
    if isempty(highImage)
        referencePart = 'Δεν υπάρχει φωτεινή εικόνα αναφοράς, οπότε η αξιολόγηση βασίζεται σε no-reference μεγέθη και οπτική σύγκριση.';
    elseif psnrValue >= 20
        referencePart = sprintf('Το PSNR είναι σχετικά καλό (%.2f dB), άρα το αποτέλεσμα βρίσκεται κοντά στη φωτεινή εικόνα αναφοράς.', psnrValue);
    elseif psnrValue >= 15
        referencePart = sprintf('Το PSNR είναι μέτριο (%.2f dB), άρα υπάρχει βελτίωση αλλά και διαφορά από τη φωτεινή αναφορά.', psnrValue);
    else
        referencePart = sprintf('Το PSNR είναι χαμηλό (%.2f dB), άρα το αποτέλεσμα απέχει αρκετά από τη φωτεινή αναφορά.', psnrValue);
    end
    if stats.Michelson > 0.85
        contrastPart = 'Η αντίθεση είναι υψηλή και μπορεί να κάνει ορατές περισσότερες λεπτομέρειες.';
    elseif stats.Michelson > 0.55
        contrastPart = 'Η αντίθεση είναι μέτρια και το αποτέλεσμα παραμένει σχετικά ισορροπημένο.';
    else
        contrastPart = 'Η αντίθεση παραμένει χαμηλή, επομένως αρκετές περιοχές μπορεί να φαίνονται επίπεδες.';
    end
    commentText = sprintf('%s Μέση φωτεινότητα %.4f, τυπική απόκλιση %.4f, Michelson %.4f, entropy %.4f. %s', referencePart, stats.Mean, stats.Std, stats.Michelson, stats.Entropy, contrastPart);
    if strcmp(pipelineName, 'Original low-light')
        commentText = ['Αρχική low-light εικόνα για βάση σύγκρισης. ', commentText];
    end
end

function row = make_h_row(imageName, imageNumber, highReferenceName, pipelineName, parameterText, edgeMethod, edgeMap, originalEdgeMap, highEdgeMap, commentText)
    edgeCount = nnz(edgeMap);
    edgeDensity = 100 * edgeCount / numel(edgeMap);
    componentInfo = edge_component_info(edgeMap);
    if isempty(highEdgeMap)
        jaccardValue = NaN;
    else
        jaccardValue = edge_jaccard(edgeMap, highEdgeMap);
    end
    originalEdgeCount = nnz(originalEdgeMap);
    edgeCountRatio = edgeCount / (originalEdgeCount + eps);
    row = struct('Image', imageName, 'ImageNumber', imageNumber, 'HighReferenceImage', highReferenceName, 'Pipeline', pipelineName, 'Parameter', parameterText, 'EdgeDetector', edgeMethod, 'EdgeCount', edgeCount, 'EdgeDensity', edgeDensity, 'ComponentCount', componentInfo.ComponentCount, 'SmallComponentPercent', componentInfo.SmallComponentPercent, 'SignificantComponentPercent', componentInfo.SignificantComponentPercent, 'JaccardToHigh', jaccardValue, 'EdgeCountRatioToOriginal', edgeCountRatio, 'Comment', commentText);
end

function info = edge_component_info(edgeMap)
    components = bwconncomp(edgeMap);
    info.ComponentCount = components.NumObjects;
    if components.NumObjects == 0
        info.SmallComponentPercent = 0;
        info.SignificantComponentPercent = 0;
    else
        componentSizes = cellfun(@numel, components.PixelIdxList);
        info.SmallComponentPercent = 100 * mean(componentSizes <= 5);
        info.SignificantComponentPercent = 100 * mean(componentSizes >= 25);
    end
end

function value = edge_jaccard(edgeMapA, edgeMapB)
    edgeMapA = logical(edgeMapA);
    edgeMapB = logical(edgeMapB);
    intersectionCount = nnz(edgeMapA & edgeMapB);
    unionCount = nnz(edgeMapA | edgeMapB);
    value = intersectionCount / (unionCount + eps);
end

function commentText = make_h_comment(pipelineName, edgeMap, originalEdgeMap, highEdgeMap)
    edgeRatio = nnz(edgeMap) / (nnz(originalEdgeMap) + eps);
    componentInfo = edge_component_info(edgeMap);
    if edgeRatio > 1.6
        countPart = 'Το πλήθος ακμών αυξάνεται πολύ, οπότε αποκαλύπτονται λεπτομέρειες αλλά πιθανόν ενισχύεται και θόρυβος.';
    elseif edgeRatio > 1.1
        countPart = 'Το πλήθος ακμών αυξάνεται ήπια και δείχνει καλύτερη ανάδειξη δομών.';
    elseif edgeRatio < 0.75
        countPart = 'Το πλήθος ακμών μειώνεται, πιθανώς επειδή η επεξεργασία εξομαλύνει λεπτομέρειες.';
    else
        countPart = 'Το πλήθος ακμών μένει κοντά στην αρχική low-light εικόνα.';
    end
    if componentInfo.SmallComponentPercent > 60
        noisePart = 'Τα πολλά μικρά components δείχνουν θορυβώδες edge map.';
    elseif componentInfo.SmallComponentPercent > 35
        noisePart = 'Υπάρχουν αρκετά μικρά components, άρα χρειάζεται προσοχή στην ερμηνεία.';
    else
        noisePart = 'Το edge map έχει λιγότερα μικρά θραύσματα και φαίνεται πιο καθαρό.';
    end
    if componentInfo.SignificantComponentPercent > 25
        objectPart = 'Οι μεγαλύτερες συνδεδεμένες ακμές βοηθούν στην ορατότητα σημαντικών αντικειμένων.';
    else
        objectPart = 'Οι σημαντικές συνεχόμενες ακμές παραμένουν περιορισμένες.';
    end
    if isempty(highEdgeMap)
        referencePart = 'Δεν υπάρχει φωτεινή αναφορά για σύγκριση ακμών.';
    else
        jaccardValue = edge_jaccard(edgeMap, highEdgeMap);
        if jaccardValue > 0.35
            referencePart = sprintf('Η συμφωνία με τις ακμές της φωτεινής αναφοράς είναι σχετικά καλή (Jaccard %.3f).', jaccardValue);
        elseif jaccardValue > 0.20
            referencePart = sprintf('Η συμφωνία με τις ακμές της φωτεινής αναφοράς είναι μέτρια (Jaccard %.3f).', jaccardValue);
        else
            referencePart = sprintf('Η συμφωνία με τις ακμές της φωτεινής αναφοράς είναι χαμηλή (Jaccard %.3f).', jaccardValue);
        end
    end
    commentText = [pipelineName, ': ', countPart, ' ', noisePart, ' ', objectPart, ' ', referencePart];
end

function summaryText = make_h_image_summary(hRows, imageName)
    rows = strcmp({hRows.Image}', imageName) & strcmp({hRows.EdgeDetector}', 'Canny') & ~strcmp({hRows.Pipeline}', 'Original low-light');
    selectedRows = hRows(rows);
    if isempty(selectedRows)
        summaryText = 'Δεν υπολογίστηκαν Canny ακμές στις βελτιωμένες εικόνες.';
        return;
    end
    jaccardValues = [selectedRows.JaccardToHigh]';
    if all(isnan(jaccardValues))
        scoreValues = [selectedRows.SignificantComponentPercent]' - [selectedRows.SmallComponentPercent]';
        [~, bestIdx] = max(scoreValues);
        summaryText = sprintf('Χωρίς φωτεινή αναφορά, πιο χρήσιμο για επόμενο vision στάδιο φαίνεται το %s, επειδή κρατά περισσότερες σημαντικές ακμές με λιγότερο μικρό θόρυβο.', selectedRows(bestIdx).Pipeline);
    else
        [~, bestIdx] = max(jaccardValues);
        summaryText = sprintf('Με βάση το Canny και τη φωτεινή αναφορά, καλύτερη συμφωνία ακμών δίνει το %s.', selectedRows(bestIdx).Pipeline);
    end
end

function summaryTable = make_pipeline_summary_table(pipelineTable)
    enhancedRows = ~strcmp(pipelineTable.Pipeline, 'Original low-light');
    pipelines = unique(pipelineTable.Pipeline(enhancedRows), 'stable');
    rowTemplate = struct('Pipeline', '', 'MeanBrightness', 0, 'MeanStdContrast', 0, 'MeanEntropyValue', 0, 'MeanDarkPixelPercent', 0, 'MeanSaturatedPixelPercent', 0);
    summaryRows = repmat(rowTemplate, numel(pipelines), 1);
    for pipelineIdx = 1:numel(pipelines)
        currentPipeline = pipelines{pipelineIdx};
        rows = enhancedRows & strcmp(pipelineTable.Pipeline, currentPipeline);
        summaryRows(pipelineIdx) = struct('Pipeline', currentPipeline, 'MeanBrightness', mean(pipelineTable.MeanBrightness(rows), 'omitnan'), 'MeanStdContrast', mean(pipelineTable.StdContrast(rows), 'omitnan'), 'MeanEntropyValue', mean(pipelineTable.EntropyValue(rows), 'omitnan'), 'MeanDarkPixelPercent', mean(pipelineTable.DarkPixelPercent(rows), 'omitnan'), 'MeanSaturatedPixelPercent', mean(pipelineTable.SaturatedPixelPercent(rows), 'omitnan'));
    end
    summaryTable = struct2table(summaryRows);
end

function summaryTable = make_best_pipeline_summary(zTable)
    imageNames = unique(zTable.Image, 'stable');
    rowTemplate = struct('Image', '', 'ImageNumber', 0, 'HighReferenceImage', '', 'BestPipeline', '', 'PSNRToHigh', NaN, 'MSEToHigh', NaN, 'MeanBrightness', 0, 'StdContrast', 0, 'EntropyValue', 0);
    summaryRows = repmat(rowTemplate, numel(imageNames), 1);
    for imageIdx = 1:numel(imageNames)
        currentImage = imageNames{imageIdx};
        rows = strcmp(zTable.Image, currentImage) & ~strcmp(zTable.Pipeline, 'Original low-light');
        selectedRows = zTable(rows, :);
        if any(~isnan(selectedRows.PSNRToHigh))
            [~, bestIdx] = max(selectedRows.PSNRToHigh);
        else
            [~, bestIdx] = max(selectedRows.EntropyValue);
        end
        bestRow = selectedRows(bestIdx, :);
        summaryRows(imageIdx) = struct('Image', currentImage, 'ImageNumber', bestRow.ImageNumber, 'HighReferenceImage', bestRow.HighReferenceImage{1}, 'BestPipeline', bestRow.Pipeline{1}, 'PSNRToHigh', bestRow.PSNRToHigh, 'MSEToHigh', bestRow.MSEToHigh, 'MeanBrightness', bestRow.MeanBrightness, 'StdContrast', bestRow.StdContrast, 'EntropyValue', bestRow.EntropyValue);
    end
    summaryTable = struct2table(summaryRows);
end

function summaryTable = make_edge_summary_table(hTable)
    cannyRows = strcmp(hTable.EdgeDetector, 'Canny') & ~strcmp(hTable.Pipeline, 'Original low-light');
    pipelines = unique(hTable.Pipeline(cannyRows), 'stable');
    rowTemplate = struct('Pipeline', '', 'MeanEdgeDensity', 0, 'MeanSmallComponentPercent', 0, 'MeanSignificantComponentPercent', 0, 'MeanJaccardToHigh', NaN);
    summaryRows = repmat(rowTemplate, numel(pipelines), 1);
    for pipelineIdx = 1:numel(pipelines)
        currentPipeline = pipelines{pipelineIdx};
        rows = cannyRows & strcmp(hTable.Pipeline, currentPipeline);
        summaryRows(pipelineIdx) = struct('Pipeline', currentPipeline, 'MeanEdgeDensity', mean(hTable.EdgeDensity(rows), 'omitnan'), 'MeanSmallComponentPercent', mean(hTable.SmallComponentPercent(rows), 'omitnan'), 'MeanSignificantComponentPercent', mean(hTable.SignificantComponentPercent(rows), 'omitnan'), 'MeanJaccardToHigh', mean(hTable.JaccardToHigh(rows), 'omitnan'));
    end
    summaryTable = struct2table(summaryRows);
end

function write_summary_report(reportFid, pipelineTable)
    fprintf(reportFid, 'Συνοπτική παρατήρηση:\n');
    enhancedRows = ~strcmp(pipelineTable.Pipeline, 'Original low-light');
    pipelines = unique(pipelineTable.Pipeline(enhancedRows), 'stable');
    for pipelineIdx = 1:numel(pipelines)
        rows = enhancedRows & strcmp(pipelineTable.Pipeline, pipelines{pipelineIdx});
        meanBrightness = mean(pipelineTable.MeanBrightness(rows), 'omitnan');
        meanContrast = mean(pipelineTable.StdContrast(rows), 'omitnan');
        meanEntropy = mean(pipelineTable.EntropyValue(rows), 'omitnan');
        fprintf(reportFid, '%s: μέση φωτεινότητα %.4f, μέση αντίθεση %.4f, μέση entropy %.4f.\n', pipelines{pipelineIdx}, meanBrightness, meanContrast, meanEntropy);
    end
    fprintf(reportFid, 'Συνήθως μικρό sigma στο Retinex δίνει πιο έντονη τοπική αντίθεση αλλά μπορεί να τονίσει θόρυβο, ενώ μεγαλύτερο sigma δίνει πιο ομαλό αποτέλεσμα.\n');
end

function write_z_summary_report(zReportFid, zTable)
    fprintf(zReportFid, 'Συνοπτική ποσοτική αξιολόγηση:\n');
    enhancedRows = ~strcmp(zTable.Pipeline, 'Original low-light');
    pipelines = unique(zTable.Pipeline(enhancedRows), 'stable');
    for pipelineIdx = 1:numel(pipelines)
        rows = enhancedRows & strcmp(zTable.Pipeline, pipelines{pipelineIdx});
        meanMse = mean(zTable.MSEToHigh(rows), 'omitnan');
        meanPsnr = mean(zTable.PSNRToHigh(rows), 'omitnan');
        meanBrightness = mean(zTable.MeanBrightness(rows), 'omitnan');
        meanContrast = mean(zTable.StdContrast(rows), 'omitnan');
        meanEntropy = mean(zTable.EntropyValue(rows), 'omitnan');
        fprintf(zReportFid, '%s: μέσο MSE %.5f, μέσο PSNR %.2f dB, μέση φωτεινότητα %.4f, αντίθεση %.4f, entropy %.4f.\n', pipelines{pipelineIdx}, meanMse, meanPsnr, meanBrightness, meanContrast, meanEntropy);
    end
    fprintf(zReportFid, 'Με εικόνα αναφοράς προτιμάται υψηλότερο PSNR και χαμηλότερο MSE. Χωρίς αναφορά, κοιτάμε αν η φωτεινότητα, η αντίθεση και η entropy αυξάνονται χωρίς υπερβολικό κορεσμό ή θόρυβο.\n');
end

function write_h_summary_report(hReportFid, hTable)
    fprintf(hReportFid, 'Συνοπτική αξιολόγηση ακμών:\n');
    cannyRows = strcmp(hTable.EdgeDetector, 'Canny') & ~strcmp(hTable.Pipeline, 'Original low-light');
    if any(cannyRows)
        pipelines = unique(hTable.Pipeline(cannyRows), 'stable');
        for pipelineIdx = 1:numel(pipelines)
            rows = cannyRows & strcmp(hTable.Pipeline, pipelines{pipelineIdx});
            meanDensity = mean(hTable.EdgeDensity(rows), 'omitnan');
            meanSmall = mean(hTable.SmallComponentPercent(rows), 'omitnan');
            meanSignificant = mean(hTable.SignificantComponentPercent(rows), 'omitnan');
            meanJaccard = mean(hTable.JaccardToHigh(rows), 'omitnan');
            fprintf(hReportFid, '%s: μέση πυκνότητα ακμών %.3f%%, μικρά components %.2f%%, σημαντικά components %.2f%%, Jaccard προς high %.3f.\n', pipelines{pipelineIdx}, meanDensity, meanSmall, meanSignificant, meanJaccard);
        end
    end
    fprintf(hReportFid, 'Γενικά, μια βελτίωση εικόνας βοηθά ως προεπεξεργασία όταν αυξάνει τις συνεχόμενες και σημαντικές ακμές χωρίς να γεμίζει το edge map με πολλά μικρά θορυβώδη components.\n');
end

function safeName = make_safe_filename(fileName)
    safeName = regexprep(fileName, '[^A-Za-z0-9]+', '_');
    safeName = regexprep(safeName, '^_+|_+$', '');
    if isempty(safeName)
        safeName = 'image';
    end
end

function textValue = value_or_none(inputText)
    if isempty(inputText)
        textValue = 'δεν βρέθηκε';
    else
        textValue = inputText;
    end
end
