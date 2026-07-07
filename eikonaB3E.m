clear;
clc;
close all;

% Για να επεξεργαστεί μια εικόνα, το όνομά της πρέπει να τελειώνει σε _low.png.

greekDesktop = char([933 960 959 955 959 947 953 963 964 942 962]);
% Replace with your path
projectDir = fullfile(getenv('USERPROFILE'), 'OneDrive', greekDesktop, 'project');
resultsDir = fullfile(projectDir, 'resultsB3E');
expectedFolderName = 'resultsB3E';

[~, actualFolderName] = fileparts(resultsDir);
if isempty(resultsDir) || strcmp(resultsDir, projectDir) || ~strcmp(actualFolderName, expectedFolderName)
    error('Unsafe results folder: %s', resultsDir);
end

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
saveComparisonFigures = should_save_comparison_figures();
figureVisibility = 'off';
unsharpKValues = [0.5 1.0 1.5];

reportFile = fullfile(resultsDir, 'B3E_sharpening_comments.txt');
reportFid = fopen(reportFile, 'w', 'n', 'UTF-8');
if reportFid == -1
    error('Δεν ήταν δυνατή η δημιουργία του αρχείου: %s', reportFile);
end
reportCleanup = onCleanup(@() fclose(reportFid));

fprintf(reportFid, 'Μέρος Ε: Όξυνση και ανάδειξη λεπτομερειών\n');
fprintf(reportFid, 'Φάκελος εικόνων: %s\n', projectDir);
fprintf(reportFid, 'Φάκελος αποτελεσμάτων: %s\n\n', resultsDir);
fprintf(reportFid, 'Κανόνας ονομάτων: *_low.png είναι η σκοτεινή εικόνα και *_high.png η φωτεινή αναφορά.\n');
fprintf(reportFid, 'Πριν την όξυνση εφαρμόζεται βασική βελτίωση φωτεινότητας και ήπια αποθορυβοποίηση, ώστε να μελετηθεί η ανάδειξη λεπτομερειών σε πιθανώς θολή εικόνα.\n');
fprintf(reportFid, 'Εξετάζονται Laplacian sharpening και unsharp masking με k = 0.5, 1.0, 1.5.\n\n');

rowTemplate = struct('Image', '', 'ImageNumber', 0, 'HighReferenceImage', '', 'Method', '', 'Parameter', '', 'MeanBrightness', 0, 'StdContrast', 0, 'GradientMean', 0, 'GradientRatioToBase', 0, 'LaplacianEnergy', 0, 'DarkPixelPercent', 0, 'SaturatedPixelPercent', 0, 'MSEToHigh', NaN, 'PSNRToHigh', NaN, 'Comment', '');
resultRows = repmat(rowTemplate, numel(imageFiles) * 6, 1);
rowIdx = 0;

fprintf('Μέρος Ε: βρέθηκαν %d εικόνες χαμηλού φωτισμού.\n', numel(imageFiles));
fprintf('Τα αποτελέσματα θα αποθηκευτούν εδώ:\n%s\n\n', resultsDir);

for idx = 1:numel(imageFiles)
    imagePath = fullfile(projectDir, imageFiles(idx).name);
    [inputImage, isColorImage] = read_image_as_double(imagePath);

    highReferenceName = sprintf('%d_high.png', imageIds(idx));
    highReferencePath = fullfile(projectDir, highReferenceName);
    if exist(highReferencePath, 'file') == 2
        [highReferenceImage, ~] = read_image_as_double(highReferencePath);
    else
        highReferenceName = '';
        highReferenceImage = [];
    end

    [~, baseName] = fileparts(imageFiles(idx).name);
    safeBaseName = make_safe_filename(baseName);
    outputPrefix = sprintf('%02d_%s', idx, safeBaseName);

    baseImage = create_base_enhanced_denoised_image(inputImage);
    laplacianImage = laplacian_sharpen(baseImage);
    unsharpImages = cell(numel(unsharpKValues), 1);

    for kIdx = 1:numel(unsharpKValues)
        unsharpImages{kIdx} = unsharp_mask(baseImage, unsharpKValues(kIdx));
    end

    imwrite(inputImage, fullfile(resultsDir, [outputPrefix, '_input_low.png']));
    imwrite(baseImage, fullfile(resultsDir, [outputPrefix, '_base_enhanced_denoised.png']));
    imwrite(laplacianImage, fullfile(resultsDir, [outputPrefix, '_laplacian_sharpening.png']));

    for kIdx = 1:numel(unsharpKValues)
        kLabel = strrep(sprintf('%.1f', unsharpKValues(kIdx)), '.', '_');
        imwrite(unsharpImages{kIdx}, fullfile(resultsDir, [outputPrefix, '_unsharp_k_', kLabel, '.png']));
    end

    rowIdx = rowIdx + 1;
    resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, 'Original low-light', '', inputImage, baseImage, highReferenceImage, isColorImage, 'Αρχική εικόνα χαμηλού φωτισμού πριν από βελτίωση, αποθορυβοποίηση και όξυνση.');

    rowIdx = rowIdx + 1;
    resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, 'Base enhanced denoised', 'gamma 0.6 + contrast stretch + Gaussian denoise', baseImage, baseImage, highReferenceImage, isColorImage, 'Βασική βελτιωμένη και αποθορυβοποιημένη εικόνα που χρησιμοποιείται ως είσοδος για την όξυνση.');

    rowIdx = rowIdx + 1;
    laplacianComment = make_sharpening_comment('Laplacian sharpening', baseImage, laplacianImage, isColorImage);
    resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, 'Laplacian sharpening', '3x3 Laplacian mask', laplacianImage, baseImage, highReferenceImage, isColorImage, laplacianComment);

    for kIdx = 1:numel(unsharpKValues)
        kValue = unsharpKValues(kIdx);
        unsharpComment = make_unsharp_comment(kValue, baseImage, unsharpImages{kIdx}, isColorImage);
        rowIdx = rowIdx + 1;
        resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, 'Unsharp masking', sprintf('k = %.1f', kValue), unsharpImages{kIdx}, baseImage, highReferenceImage, isColorImage, unsharpComment);
    end

    fprintf(reportFid, 'Εικόνα %02d: %s\n', idx, imageFiles(idx).name);
    fprintf(reportFid, 'Αντίστοιχη φωτεινή εικόνα: %s\n', value_or_none(highReferenceName));
    fprintf(reportFid, 'Laplacian sharpening: %s\n', laplacianComment);
    for kIdx = 1:numel(unsharpKValues)
        fprintf(reportFid, 'Unsharp masking k=%.1f: %s\n', unsharpKValues(kIdx), make_unsharp_comment(unsharpKValues(kIdx), baseImage, unsharpImages{kIdx}, isColorImage));
    end
    fprintf(reportFid, '\n');

    if saveComparisonFigures
        imageList = {inputImage, baseImage, laplacianImage, unsharpImages{1}, unsharpImages{2}, unsharpImages{3}};
        titleList = {'Original low-light', 'Enhanced + denoised', 'Laplacian sharpening', 'Unsharp k=0.5', 'Unsharp k=1.0', 'Unsharp k=1.5'};
        save_image_grid(imageList, titleList, sprintf('Part E - Sharpening: %s', imageFiles(idx).name), fullfile(resultsDir, [outputPrefix, '_sharpening_comparison.png']));
    end

    baseStats = compute_image_stats(baseImage, isColorImage);
    laplacianStats = compute_image_stats(laplacianImage, isColorImage);
    unsharpStats = compute_image_stats(unsharpImages{2}, isColorImage);

    fprintf('%02d/%02d %s: gradient base %.4f -> Laplacian %.4f, Unsharp k=1.0 %.4f\n', idx, numel(imageFiles), imageFiles(idx).name, baseStats.GradientMean, laplacianStats.GradientMean, unsharpStats.GradientMean);
    drawnow;
end

resultRows = resultRows(1:rowIdx);
statsTable = struct2table(resultRows);
writetable(statsTable, fullfile(resultsDir, 'B3E_statistics.csv'));

if saveComparisonFigures
    save_e_summary_image(statsTable, fullfile(resultsDir, 'B3E_summary_statistics.png'));
end

fprintf('\nΤο Μέρος Ε ολοκληρώθηκε.\n');
if saveComparisonFigures
    fprintf('Αποθηκεύτηκαν εικόνες, figures, στατιστικά και σχόλια εδώ:\n%s\n', resultsDir);
else
    fprintf('Αποθηκεύτηκαν εικόνες, στατιστικά και σχόλια εδώ:\n%s\n', resultsDir);
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

function saveComparisonFigures = should_save_comparison_figures()
    saveComparisonFigures = true;
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

function baseImage = create_base_enhanced_denoised_image(inputImage)
    gammaImage = min(max(inputImage, 0), 1) .^ 0.6;
    stretchedImage = linear_contrast_stretch(gammaImage);
    baseImage = imgaussfilt(stretchedImage, 0.8, 'FilterSize', 3);
    baseImage = min(max(baseImage, 0), 1);
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

function sharpImage = laplacian_sharpen(inputImage)
    laplacianMask = [0 -1 0; -1 4 -1; 0 -1 0];
    laplacianComponent = imfilter(inputImage, laplacianMask, 'replicate');
    sharpImage = min(max(inputImage + 0.4 * laplacianComponent, 0), 1);
end

function sharpImage = unsharp_mask(inputImage, kValue)
    blurredImage = imgaussfilt(inputImage, 1.0, 'FilterSize', 5);
    detailImage = inputImage - blurredImage;
    sharpImage = min(max(inputImage + kValue * detailImage, 0), 1);
end

function stats = compute_image_stats(inputImage, isColorImage)
    grayImage = to_gray(inputImage, isColorImage);
    pixels = grayImage(:);
    stats.Mean = mean(pixels);
    stats.Std = std(pixels);
    stats.DarkPercent = 100 * mean(pixels <= 0.25);
    stats.SaturatedPercent = 100 * mean(pixels >= 0.98);
    stats.GradientMean = mean(gradient_magnitude(grayImage), 'all');
    stats.LaplacianEnergy = mean(abs(imfilter(grayImage, [0 -1 0; -1 4 -1; 0 -1 0], 'replicate')), 'all');
end

function grayImage = to_gray(inputImage, isColorImage)
    if isColorImage
        grayImage = rgb2gray(inputImage);
    else
        grayImage = inputImage;
    end
end

function magnitude = gradient_magnitude(grayImage)
    sobelX = [-1 0 1; -2 0 2; -1 0 1] / 8;
    sobelY = sobelX';
    gradientX = imfilter(grayImage, sobelX, 'replicate');
    gradientY = imfilter(grayImage, sobelY, 'replicate');
    magnitude = sqrt(gradientX .^ 2 + gradientY .^ 2);
end

function [mseValue, psnrValue] = reference_metrics(referenceImage, testImage)
    if isempty(referenceImage)
        mseValue = NaN;
        psnrValue = NaN;
        return;
    end
    if ~isequal(size(referenceImage), size(testImage))
        referenceImage = imresize(referenceImage, [size(testImage, 1), size(testImage, 2)]);
    end
    difference = min(max(testImage, 0), 1) - min(max(referenceImage, 0), 1);
    mseValue = mean(difference(:) .^ 2);
    if mseValue == 0
        psnrValue = Inf;
    else
        psnrValue = 10 * log10(1 / mseValue);
    end
end

function row = make_result_row(imageName, imageNumber, highReferenceName, methodName, parameterText, resultImage, baseImage, highReferenceImage, isColorImage, commentText)
    resultStats = compute_image_stats(resultImage, isColorImage);
    baseStats = compute_image_stats(baseImage, isColorImage);
    [mseToHigh, psnrToHigh] = reference_metrics(highReferenceImage, resultImage);
    gradientRatio = resultStats.GradientMean / (baseStats.GradientMean + eps);
    row = struct('Image', imageName, 'ImageNumber', imageNumber, 'HighReferenceImage', highReferenceName, 'Method', methodName, 'Parameter', parameterText, 'MeanBrightness', resultStats.Mean, 'StdContrast', resultStats.Std, 'GradientMean', resultStats.GradientMean, 'GradientRatioToBase', gradientRatio, 'LaplacianEnergy', resultStats.LaplacianEnergy, 'DarkPixelPercent', resultStats.DarkPercent, 'SaturatedPixelPercent', resultStats.SaturatedPercent, 'MSEToHigh', mseToHigh, 'PSNRToHigh', psnrToHigh, 'Comment', commentText);
end

function commentText = make_sharpening_comment(methodName, baseImage, sharpenedImage, isColorImage)
    baseStats = compute_image_stats(baseImage, isColorImage);
    sharpStats = compute_image_stats(sharpenedImage, isColorImage);
    gradientRatio = sharpStats.GradientMean / (baseStats.GradientMean + eps);
    saturationIncrease = sharpStats.SaturatedPercent - baseStats.SaturatedPercent;
    if gradientRatio > 1.15
        detailPart = sprintf('%s αυξάνει την ένταση των ακμών και αναδεικνύει λεπτομέρειες.', methodName);
    else
        detailPart = sprintf('%s έχει ήπια επίδραση στην ανάδειξη ακμών.', methodName);
    end
    if saturationIncrease > 2
        riskPart = 'Υπάρχει κίνδυνος υπερενίσχυσης, κορεσμού ή halos γύρω από έντονες ακμές.';
    elseif gradientRatio > 1.8
        riskPart = 'Η πολύ έντονη αύξηση των ακμών μπορεί να ενισχύσει και θόρυβο.';
    else
        riskPart = 'Η υπερενίσχυση παραμένει σχετικά περιορισμένη.';
    end
    commentText = [detailPart, ' ', riskPart];
end

function commentText = make_unsharp_comment(kValue, baseImage, sharpenedImage, isColorImage)
    baseStats = compute_image_stats(baseImage, isColorImage);
    sharpStats = compute_image_stats(sharpenedImage, isColorImage);
    gradientRatio = sharpStats.GradientMean / (baseStats.GradientMean + eps);
    if kValue <= 0.5
        strengthPart = 'Το k=0.5 δίνει ήπια όξυνση και συνήθως πιο φυσικό αποτέλεσμα.';
    elseif kValue <= 1.0
        strengthPart = 'Το k=1.0 δίνει πιο καθαρή ανάδειξη λεπτομερειών.';
    else
        strengthPart = 'Το k=1.5 δίνει έντονη όξυνση και χρειάζεται προσοχή.';
    end
    if sharpStats.SaturatedPercent > baseStats.SaturatedPercent + 2 || gradientRatio > 1.8
        riskPart = 'Η ενίσχυση μπορεί να κάνει πιο εμφανή τον θόρυβο ή halos γύρω από ακμές.';
    else
        riskPart = 'Δεν εμφανίζεται μεγάλη αύξηση κορεσμού ή υπερβολική ενίσχυση ακμών.';
    end
    commentText = sprintf('%s Ο λόγος gradient προς τη βάση είναι %.3f. %s', strengthPart, gradientRatio, riskPart);
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

function save_e_summary_image(statsTable, outputPath)
    methods = {'Base enhanced denoised', 'Laplacian sharpening', 'Unsharp masking'};
    labels = {'Base', 'Laplacian', 'Unsharp k=1.0'};
    metricNames = {'GradientMean', 'SaturatedPixelPercent'};
    metricTitles = {'Gradient mean', 'Saturated pixels (%)'};

    hFig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1200, 760]);
    cleanupObj = onCleanup(@() close(hFig));

    for metricIdx = 1:numel(metricNames)
        subplot(2, 1, metricIdx);
        hold on;
        for methodIdx = 1:numel(methods)
            rows = strcmp(statsTable.Method, methods{methodIdx});
            if strcmp(methods{methodIdx}, 'Unsharp masking')
                rows = rows & strcmp(statsTable.Parameter, 'k = 1.0');
            end
            if ~any(rows)
                continue;
            end
            [xValues, sortIdx] = sort(statsTable.ImageNumber(rows));
            yValues = statsTable.(metricNames{metricIdx})(rows);
            yValues = yValues(sortIdx);
            plot(xValues, yValues, '-o', 'LineWidth', 1.4, 'MarkerSize', 4, 'DisplayName', labels{methodIdx});
        end
        hold off;
        grid on;
        title(metricTitles{metricIdx});
        xlabel('Image number');
        ylabel(metricTitles{metricIdx});
        legend('Location', 'bestoutside');
    end

    try
        sgtitle('Part E - Sharpening summary');
    catch
    end

    try
        exportgraphics(hFig, outputPath, 'Resolution', 150);
    catch
        saveas(hFig, outputPath);
    end

    clear cleanupObj;
end

function canvas = draw_metric_chart(canvas, statsTable, methods, labels, metricName, titleText, rect)
    xSeries = cell(numel(methods), 1);
    ySeries = cell(numel(methods), 1);
    for methodIdx = 1:numel(methods)
        rows = strcmp(statsTable.Method, methods{methodIdx});
        if strcmp(methods{methodIdx}, 'Unsharp masking')
            rows = rows & strcmp(statsTable.Parameter, 'k = 1.0');
        end
        [xSeries{methodIdx}, sortIdx] = sort(statsTable.ImageNumber(rows));
        values = statsTable.(metricName)(rows);
        ySeries{methodIdx} = values(sortIdx);
    end
    canvas = draw_line_chart(canvas, xSeries, ySeries, labels, titleText, metricName, rect);
end

function canvas = draw_line_chart(canvas, xSeries, ySeries, labels, titleText, yLabel, rect)
    colors = [0.12 0.35 0.75; 0.85 0.33 0.10; 0.15 0.55 0.25; 0.55 0.25 0.70];
    panelLeft = rect(1);
    panelTop = rect(2);
    panelWidth = rect(3);
    panelHeight = rect(4);
    plotLeft = panelLeft + 75;
    plotTop = panelTop + 55;
    plotWidth = panelWidth - 150;
    plotHeight = panelHeight - 115;

    allX = [];
    allY = [];
    for idx = 1:numel(ySeries)
        allX = [allX; xSeries{idx}(:)]; %#ok<AGROW>
        allY = [allY; ySeries{idx}(:)]; %#ok<AGROW>
    end
    allY = allY(isfinite(allY));
    if isempty(allX) || isempty(allY)
        return;
    end
    xMin = min(allX);
    xMax = max(allX);
    yMin = min(allY);
    yMax = max(allY);
    if xMax <= xMin
        xMax = xMin + 1;
    end
    if yMax <= yMin
        yMax = yMin + 1;
    end
    yPad = 0.08 * (yMax - yMin);
    yMin = yMin - yPad;
    yMax = yMax + yPad;

    canvas = draw_line(canvas, plotLeft, plotTop + plotHeight, plotLeft + plotWidth, plotTop + plotHeight, [0 0 0], 2);
    canvas = draw_line(canvas, plotLeft, plotTop, plotLeft, plotTop + plotHeight, [0 0 0], 2);
    for gridIdx = 1:4
        yGrid = round(plotTop + plotHeight * gridIdx / 5);
        canvas = draw_line(canvas, plotLeft, yGrid, plotLeft + plotWidth, yGrid, [0.85 0.85 0.85], 1);
    end

    for idx = 1:numel(ySeries)
        xValues = xSeries{idx};
        yValues = ySeries{idx};
        valid = isfinite(xValues) & isfinite(yValues);
        xValues = xValues(valid);
        yValues = yValues(valid);
        if isempty(xValues)
            continue;
        end
        xPix = round(plotLeft + (xValues - xMin) / (xMax - xMin) * plotWidth);
        yPix = round(plotTop + plotHeight - (yValues - yMin) / (yMax - yMin) * plotHeight);
        colorValue = colors(1 + mod(idx - 1, size(colors, 1)), :);
        for pointIdx = 1:numel(xPix) - 1
            canvas = draw_line(canvas, xPix(pointIdx), yPix(pointIdx), xPix(pointIdx + 1), yPix(pointIdx + 1), colorValue, 3);
        end
        for pointIdx = 1:numel(xPix)
            canvas = draw_square(canvas, xPix(pointIdx), yPix(pointIdx), colorValue, 4);
        end
    end

    if exist('insertText', 'file') == 2
        canvas = insertText(canvas, [panelLeft + 10, panelTop + 8], titleText, 'FontSize', 22, 'BoxOpacity', 0, 'TextColor', 'black');
        canvas = insertText(canvas, [plotLeft, plotTop + plotHeight + 16], 'Image number', 'FontSize', 16, 'BoxOpacity', 0, 'TextColor', 'black');
        canvas = insertText(canvas, [panelLeft + 10, plotTop + 4], yLabel, 'FontSize', 16, 'BoxOpacity', 0, 'TextColor', 'black');
        for idx = 1:numel(labels)
            legendX = panelLeft + panelWidth - 230;
            legendY = panelTop + 42 + 26 * idx;
            canvas = draw_line(canvas, legendX, legendY + 9, legendX + 28, legendY + 9, colors(1 + mod(idx - 1, size(colors, 1)), :), 4);
            canvas = insertText(canvas, [legendX + 35, legendY], labels{idx}, 'FontSize', 15, 'BoxOpacity', 0, 'TextColor', 'black');
        end
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
    cols = min(3, numel(validIdx));
    rows = ceil(numel(validIdx) / cols);
    canvasHeight = topMargin + rows * (labelHeight + tileHeight) + (rows + 1) * gap;
    canvasWidth = cols * tileWidth + (cols + 1) * gap;
    canvas = ones(canvasHeight, canvasWidth, 3);
    if exist('insertText', 'file') == 2
        canvas = insertText(canvas, [round(canvasWidth / 2) - 260, 18], mainTitle, 'FontSize', 24, 'BoxOpacity', 0, 'TextColor', 'black');
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

function canvas = draw_line(canvas, x1, y1, x2, y2, colorValue, thickness)
    steps = max(abs(x2 - x1), abs(y2 - y1)) + 1;
    xValues = round(linspace(x1, x2, steps));
    yValues = round(linspace(y1, y2, steps));
    for idx = 1:numel(xValues)
        canvas = draw_square(canvas, xValues(idx), yValues(idx), colorValue, thickness);
    end
end

function canvas = draw_square(canvas, xCenter, yCenter, colorValue, radius)
    [height, width, ~] = size(canvas);
    xRange = max(1, xCenter - radius):min(width, xCenter + radius);
    yRange = max(1, yCenter - radius):min(height, yCenter + radius);
    for channelIdx = 1:3
        channel = canvas(:, :, channelIdx);
        channel(yRange, xRange) = colorValue(channelIdx);
        canvas(:, :, channelIdx) = channel;
    end
end
