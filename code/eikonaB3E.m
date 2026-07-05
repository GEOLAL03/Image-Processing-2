clear;
clc;
close all;

% Για να επεξεργαστεί μια εικόνα, το όνομά της πρέπει να τελειώνει σε _low.png.

greekDesktop = char([933 960 959 955 959 947 953 963 964 942 962]);
projectDir = fullfile(getenv('USERPROFILE'), 'OneDrive', greekDesktop, 'project');
resultsDir = fullfile(projectDir, 'resultsB3E');

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
        hComparison = figure('Name', ['B3E - ', imageFiles(idx).name], 'Color', 'w', 'Visible', figureVisibility, 'Position', [45 45 1500 870]);
        add_top_title(hComparison, sprintf('Μέρος Ε - Όξυνση και ανάδειξη λεπτομερειών: %s', imageFiles(idx).name));
        comparisonLayout = tiledlayout(hComparison, 2, 3, 'Padding', 'loose', 'TileSpacing', 'loose');
        comparisonLayout.Units = 'normalized';
        comparisonLayout.Position = [0.045 0.055 0.91 0.86];
        show_image_tile(inputImage, 'Original low-light');
        show_image_tile(baseImage, 'Enhanced + denoised');
        show_image_tile(laplacianImage, 'Laplacian sharpening');
        show_image_tile(unsharpImages{1}, 'Unsharp k=0.5');
        show_image_tile(unsharpImages{2}, 'Unsharp k=1.0');
        show_image_tile(unsharpImages{3}, 'Unsharp k=1.5');
        save_figure_png(hComparison, fullfile(resultsDir, [outputPrefix, '_sharpening_comparison.png']));
        close(hComparison);
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
    hSummary = figure('Name', 'B3E - Summary statistics', 'Color', 'w', 'Visible', figureVisibility, 'Position', [120 120 1350 900]);
    tiledlayout(hSummary, 2, 1, 'Padding', 'loose', 'TileSpacing', 'compact');
    nexttile;
    plot_summary_by_method(statsTable, 'GradientMean', 'Gradient mean');
    nexttile;
    plot_summary_by_method(statsTable, 'SaturatedPixelPercent', 'Saturated pixels (%)');
    sgtitle('Μέρος Ε - Σύγκριση μεθόδων όξυνσης', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
    save_figure_png(hSummary, fullfile(resultsDir, 'B3E_summary_statistics.png'));
    close(hSummary);
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
    saveComparisonFigures = false;
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

function add_top_title(figureHandle, titleText)
    annotation(figureHandle, 'textbox', [0.02 0.94 0.96 0.045], 'String', titleText, 'Interpreter', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'EdgeColor', 'none', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
end

function show_image_tile(inputImage, titleText)
    nexttile;
    imshow(inputImage);
    title(titleText, 'Interpreter', 'none', 'Color', 'k');
end

function plot_summary_by_method(statsTable, metricName, titleText)
    methods = {'Base enhanced denoised', 'Laplacian sharpening', 'Unsharp masking'};
    hold on;
    for methodIdx = 1:numel(methods)
        rows = strcmp(statsTable.Method, methods{methodIdx});
        if strcmp(methods{methodIdx}, 'Unsharp masking')
            rows = rows & strcmp(statsTable.Parameter, 'k = 1.0');
            displayName = 'Unsharp k=1.0';
        else
            displayName = methods{methodIdx};
        end
        plot(statsTable.ImageNumber(rows), statsTable.(metricName)(rows), '-o', 'LineWidth', 1.2, 'DisplayName', displayName);
    end
    hold off;
    grid on;
    xlabel('Image number');
    ylabel(metricName);
    title(titleText);
    legend('Location', 'best');
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
