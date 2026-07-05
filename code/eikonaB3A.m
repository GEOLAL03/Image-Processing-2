clear;
clc;
close all;

% Για να αναλυθεί μια εικόνα από το script, το όνομά της πρέπει να τελειώνει σε _low.png.

greekDesktop = char([933 960 959 955 959 947 953 963 964 942 962]);
projectDir = fullfile(getenv('USERPROFILE'), 'OneDrive', greekDesktop, 'project');
resultsDir = fullfile(projectDir, 'resultsB3A');

if ~exist(resultsDir, 'dir')
    mkdir(resultsDir);
end

oldFiles = [dir(fullfile(resultsDir, '*.png')); dir(fullfile(resultsDir, '*.csv')); dir(fullfile(resultsDir, '*.txt')); dir(fullfile(resultsDir, '*.mat'))];
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
warning(oldWarningState);

[imageFiles, imageIds] = find_low_images(projectDir);
showFigures = should_show_figures();

reportFile = fullfile(resultsDir, 'B3A_histogram_comments.txt');
reportFid = fopen(reportFile, 'w', 'n', 'UTF-8');
if reportFid == -1
    error('Δεν ήταν δυνατή η δημιουργία του αρχείου: %s', reportFile);
end
reportCleanup = onCleanup(@() fclose(reportFid));

fprintf(reportFid, 'Μέρος Α: Ανάλυση εικόνων χαμηλού φωτισμού\n');
fprintf(reportFid, 'Φάκελος εικόνων: %s\n', projectDir);
fprintf(reportFid, 'Φάκελος αποτελεσμάτων: %s\n\n', resultsDir);
fprintf(reportFid, 'Κανόνας ονομάτων: *_low.png είναι η σκοτεινή εικόνα και *_high.png η φωτεινή αναφορά.\n');
fprintf(reportFid, 'Στο Μέρος Α αναλύονται μόνο οι εικόνες *_low.png.\n\n');

imageNames = cell(numel(imageFiles), 1);
imageNumbers = zeros(numel(imageFiles), 1);
highReferenceNames = cell(numel(imageFiles), 1);
highReferenceFound = false(numel(imageFiles), 1);
meanBrightness = zeros(numel(imageFiles), 1);
intensityVariance = zeros(numel(imageFiles), 1);
stdContrast = zeros(numel(imageFiles), 1);
minIntensity = zeros(numel(imageFiles), 1);
maxIntensity = zeros(numel(imageFiles), 1);
darkPixelPercent = zeros(numel(imageFiles), 1);
brightPixelPercent = zeros(numel(imageFiles), 1);
michelsonContrast = zeros(numel(imageFiles), 1);
histogramComments = cell(numel(imageFiles), 1);

fprintf('Μέρος Α: βρέθηκαν %d εικόνες χαμηλού φωτισμού.\n', numel(imageFiles));
fprintf('Τα αποτελέσματα θα αποθηκευτούν εδώ:\n%s\n\n', resultsDir);

for idx = 1:numel(imageFiles)
    imagePath = fullfile(projectDir, imageFiles(idx).name);
    [inputImage, isColorImage] = read_image_as_double(imagePath);

    if isColorImage
        grayImage = rgb2gray(inputImage);
    else
        grayImage = inputImage;
    end

    stats = compute_gray_stats(grayImage);
    commentText = make_histogram_comment(stats.Mean, stats.Std, stats.DarkPercent, stats.BrightPercent);

    highReferenceName = sprintf('%d_high.png', imageIds(idx));
    highReferencePath = fullfile(projectDir, highReferenceName);

    imageNames{idx} = imageFiles(idx).name;
    imageNumbers(idx) = imageIds(idx);
    highReferenceFound(idx) = exist(highReferencePath, 'file') == 2;
    if highReferenceFound(idx)
        highReferenceNames{idx} = highReferenceName;
    else
        highReferenceNames{idx} = '';
    end

    meanBrightness(idx) = stats.Mean;
    intensityVariance(idx) = stats.Variance;
    stdContrast(idx) = stats.Std;
    minIntensity(idx) = stats.Min;
    maxIntensity(idx) = stats.Max;
    darkPixelPercent(idx) = stats.DarkPercent;
    brightPixelPercent(idx) = stats.BrightPercent;
    michelsonContrast(idx) = stats.Michelson;
    histogramComments{idx} = commentText;

    [~, baseName] = fileparts(imageFiles(idx).name);
    safeBaseName = make_safe_filename(baseName);
    outputPrefix = sprintf('%02d_%s', idx, safeBaseName);

    imwrite(inputImage, fullfile(resultsDir, [outputPrefix, '_original.png']));
    imwrite(grayImage, fullfile(resultsDir, [outputPrefix, '_grayscale.png']));

    grayCounts = intensity_histogram(grayImage);
    if isColorImage
        redCounts = intensity_histogram(inputImage(:, :, 1));
        greenCounts = intensity_histogram(inputImage(:, :, 2));
        blueCounts = intensity_histogram(inputImage(:, :, 3));
    else
        redCounts = zeros(1, 256);
        greenCounts = zeros(1, 256);
        blueCounts = zeros(1, 256);
    end

    histogramTable = table((0:255)', grayCounts(:), redCounts(:), greenCounts(:), blueCounts(:), 'VariableNames', {'IntensityLevel', 'GrayCount', 'RedCount', 'GreenCount', 'BlueCount'});
    writetable(histogramTable, fullfile(resultsDir, [outputPrefix, '_histograms.csv']));

    if showFigures
        hAnalysis = figure('Name', ['B3A - ', imageFiles(idx).name], 'Color', 'w', 'Visible', 'on', 'Position', [80 80 1250 900]);
        tiledlayout(hAnalysis, 2, 2, 'Padding', 'loose', 'TileSpacing', 'compact');

        nexttile;
        imshow(inputImage);
        title('Αρχική εικόνα', 'Interpreter', 'none');

        nexttile;
        imshow(grayImage);
        title('Grayscale');

        nexttile;
        bar(0:255, grayCounts, 1, 'FaceColor', [0.25 0.25 0.25], 'EdgeColor', 'none');
        xlim([0 255]);
        grid on;
        title('Ιστόγραμμα φωτεινότητας');
        xlabel('Intensity level');
        ylabel('Pixels');

        nexttile;
        if isColorImage
            plot(0:255, redCounts, 'r', 'LineWidth', 1.1);
            hold on;
            plot(0:255, greenCounts, 'g', 'LineWidth', 1.1);
            plot(0:255, blueCounts, 'b', 'LineWidth', 1.1);
            hold off;
            legend({'R', 'G', 'B'}, 'Location', 'northeast');
            title('RGB histograms');
        else
            plot(0:255, grayCounts, 'k', 'LineWidth', 1.1);
            title('Ιστόγραμμα');
        end
        xlim([0 255]);
        grid on;
        xlabel('Intensity level');
        ylabel('Pixels');

        sgtitle(sprintf('Μέρος Α - %s | μέση φωτεινότητα %.4f, διασπορά %.5f', imageFiles(idx).name, stats.Mean, stats.Variance), 'Interpreter', 'none', 'Color', 'k', 'FontSize', 12);
        save_figure_png(hAnalysis, fullfile(resultsDir, [outputPrefix, '_analysis.png']));
    end

    fprintf(reportFid, 'Εικόνα %02d: %s\n', idx, imageFiles(idx).name);
    fprintf(reportFid, 'Αντίστοιχη φωτεινή εικόνα: %s\n', value_or_none(highReferenceNames{idx}));
    fprintf(reportFid, 'Μέση φωτεινότητα: %.6f\n', stats.Mean);
    fprintf(reportFid, 'Διασπορά έντασης: %.6f\n', stats.Variance);
    fprintf(reportFid, 'Τυπική απόκλιση/εκτίμηση αντίθεσης: %.6f\n', stats.Std);
    fprintf(reportFid, 'Ελάχιστη ένταση: %.6f\n', stats.Min);
    fprintf(reportFid, 'Μέγιστη ένταση: %.6f\n', stats.Max);
    fprintf(reportFid, 'Σκοτεινά pixels <= 0.25: %.2f%%\n', stats.DarkPercent);
    fprintf(reportFid, 'Φωτεινά pixels >= 0.75: %.2f%%\n', stats.BrightPercent);
    fprintf(reportFid, 'Michelson contrast: %.6f\n', stats.Michelson);
    fprintf(reportFid, 'Σχόλιο: %s\n\n', commentText);

    fprintf('%02d/%02d %s: μέση φωτεινότητα=%.4f, διασπορά=%.5f, σκοτεινά pixels=%.1f%%\n', idx, numel(imageFiles), imageFiles(idx).name, stats.Mean, stats.Variance, stats.DarkPercent);
    drawnow;
end

statsTable = table(imageNames, imageNumbers, highReferenceNames, highReferenceFound, meanBrightness, intensityVariance, stdContrast, minIntensity, maxIntensity, darkPixelPercent, brightPixelPercent, michelsonContrast, histogramComments, 'VariableNames', {'Image', 'ImageNumber', 'HighReferenceImage', 'HighReferenceFound', 'MeanBrightness', 'IntensityVariance', 'StdContrast', 'MinIntensity', 'MaxIntensity', 'DarkPixelPercent', 'BrightPixelPercent', 'MichelsonContrast', 'HistogramComment'});
writetable(statsTable, fullfile(resultsDir, 'B3A_statistics.csv'));

if showFigures
    hSummary = figure('Name', 'B3A - Summary statistics', 'Color', 'w', 'Visible', 'on', 'Position', [120 120 1300 900]);
    tiledlayout(hSummary, 3, 1, 'Padding', 'loose', 'TileSpacing', 'compact');

    nexttile;
    bar(meanBrightness, 'FaceColor', [0.20 0.45 0.75]);
    ylim([0 1]);
    grid on;
    title('Mean brightness');
    ylabel('Mean');
    set_image_axis_labels(imageNames);

    nexttile;
    bar(intensityVariance, 'FaceColor', [0.65 0.35 0.15]);
    grid on;
    title('Intensity variance');
    ylabel('Variance');
    set_image_axis_labels(imageNames);

    nexttile;
    bar(darkPixelPercent, 'FaceColor', [0.25 0.25 0.25]);
    ylim([0 100]);
    grid on;
    title('Dark pixels [0, 0.25]');
    ylabel('Dark pixels (%)');
    set_image_axis_labels(imageNames);

    sgtitle('Μέρος Α - Συνοπτικά στατιστικά', 'Color', 'k', 'FontSize', 12);
    save_figure_png(hSummary, fullfile(resultsDir, 'B3A_summary_statistics.png'));
end

fprintf('\nΤο Μέρος Α ολοκληρώθηκε.\n');
if showFigures
    fprintf('Αποθηκεύτηκαν εικόνες, figures, ιστογράμματα, στατιστικά και σχόλια εδώ:\n%s\n', resultsDir);
else
    fprintf('Αποθηκεύτηκαν εικόνες, ιστογράμματα, στατιστικά και σχόλια εδώ:\n%s\n', resultsDir);
end

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

function showFigures = should_show_figures()
    try
        showFigures = usejava('desktop') && desktop('-inuse');
    catch
        showFigures = usejava('desktop');
    end
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

function stats = compute_gray_stats(grayImage)
    pixels = grayImage(:);
    stats.Mean = mean(pixels);
    stats.Variance = mean((pixels - stats.Mean) .^ 2);
    stats.Std = sqrt(stats.Variance);
    stats.Min = min(pixels);
    stats.Max = max(pixels);
    stats.DarkPercent = 100 * mean(pixels <= 0.25);
    stats.BrightPercent = 100 * mean(pixels >= 0.75);
    stats.Michelson = (stats.Max - stats.Min) / (stats.Max + stats.Min + eps);
end

function counts = intensity_histogram(channelImage)
    channelImage = min(max(channelImage, 0), 1);
    uintValues = uint8(round(255 * channelImage));
    counts = histcounts(double(uintValues(:)), -0.5:1:255.5);
end

function commentText = make_histogram_comment(mu, sigmaValue, darkPercent, brightPercent)
    if darkPercent >= 65 || mu < 0.30
        brightnessComment = 'Το ιστόγραμμα είναι συγκεντρωμένο στις χαμηλές στάθμες, άρα η εικόνα είναι έντονα υποφωτισμένη.';
    elseif darkPercent >= 40 || mu < 0.45
        brightnessComment = 'Το ιστόγραμμα μετατοπίζεται προς χαμηλές και μεσαίες στάθμες, άρα η φωτεινότητα είναι μειωμένη.';
    else
        brightnessComment = 'Το ιστόγραμμα δεν είναι συγκεντρωμένο αποκλειστικά στις σκοτεινές στάθμες.';
    end

    if sigmaValue < 0.12
        contrastComment = 'Η μικρή διασπορά δείχνει χαμηλή αντίθεση.';
    elseif sigmaValue < 0.22
        contrastComment = 'Η διασπορά δείχνει μέτρια αντίθεση.';
    else
        contrastComment = 'Η διασπορά είναι σχετικά υψηλή, πιθανώς λόγω τοπικών φωτεινών πηγών.';
    end

    if brightPercent > 8
        highlightComment = 'Υπάρχει και φωτεινή ουρά στο ιστόγραμμα, πιθανώς από έντονες πηγές φωτός.';
    else
        highlightComment = 'Λίγα pixels βρίσκονται στις υψηλές στάθμες φωτεινότητας.';
    end

    commentText = [brightnessComment, ' ', contrastComment, ' ', highlightComment];
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

function set_image_axis_labels(imageNames)
    ax = gca;
    ax.XTick = 1:numel(imageNames);
    ax.XTickLabel = imageNames;
    ax.TickLabelInterpreter = 'none';
    xtickangle(45);
end

function save_figure_png(figureHandle, outputPath)
    set(figureHandle, 'Color', 'w', 'InvertHardcopy', 'off');
    axesHandles = findall(figureHandle, 'Type', 'axes');
    for idx = 1:numel(axesHandles)
        set(axesHandles(idx), 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'ZColor', 'k');
        set(get(axesHandles(idx), 'Title'), 'Color', 'k');
        set(get(axesHandles(idx), 'XLabel'), 'Color', 'k');
        set(get(axesHandles(idx), 'YLabel'), 'Color', 'k');
        set(get(axesHandles(idx), 'ZLabel'), 'Color', 'k');
    end
    textHandles = findall(figureHandle, 'Type', 'text');
    if ~isempty(textHandles)
        set(textHandles, 'Color', 'k');
    end
    legendHandles = findall(figureHandle, 'Type', 'legend');
    if ~isempty(legendHandles)
        set(legendHandles, 'TextColor', 'k', 'Color', 'w', 'EdgeColor', 'k');
    end
    drawnow;
    print(figureHandle, outputPath, '-dpng', '-r200');
end
