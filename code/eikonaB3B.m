clear;
clc;
close all;

% Για να επεξεργαστεί μια εικόνα, το όνομά της πρέπει να τελειώνει σε _low.png.

greekDesktop = char([933 960 959 955 959 947 953 963 964 942 962]);
projectDir = fullfile(getenv('USERPROFILE'), 'OneDrive', greekDesktop, 'project');
resultsDir = fullfile(projectDir, 'resultsB3B');

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
gammaValues = [0.4 0.6 0.8 1.2];

reportFile = fullfile(resultsDir, 'B3B_transform_comments.txt');
reportFid = fopen(reportFile, 'w', 'n', 'UTF-8');
if reportFid == -1
    error('Δεν ήταν δυνατή η δημιουργία του αρχείου: %s', reportFile);
end
reportCleanup = onCleanup(@() fclose(reportFid));

fprintf(reportFid, 'Μέρος Β: Γραμμικοί και μη γραμμικοί μετασχηματισμοί φωτεινότητας\n');
fprintf(reportFid, 'Φάκελος εικόνων: %s\n', projectDir);
fprintf(reportFid, 'Φάκελος αποτελεσμάτων: %s\n\n', resultsDir);
fprintf(reportFid, '*_low.png είναι η σκοτεινή εικόνα και *_high.png η φωτεινή reference.\n');
fprintf(reportFid, 'Στο Μέρος Β εφαρμόζονται μετασχηματισμοί μόνο στις εικόνες *_low.png.\n\n');
fprintf(reportFid, 'Γενικά σχόλια:\n');
fprintf(reportFid, 'Η γραμμική επέκταση δυναμικού εύρους βοηθά όταν η εικόνα έχει χρήσιμη πληροφορία σε μικρό εύρος εντάσεων, αλλά μπορεί να κάνει πιο εμφανή και τον θόρυβο.\n');
fprintf(reportFid, 'Για gamma < 1 οι σκοτεινές περιοχές φωτίζονται περισσότερο. Όσο μικρότερη είναι η gamma, τόσο εντονότερη είναι η ενίσχυση και τόσο μεγαλύτερος ο κίνδυνος υπερενίσχυσης θορύβου.\n');
fprintf(reportFid, 'Για gamma = 1.2 η εικόνα συνήθως σκοτεινιάζει, άρα η τιμή αυτή λειτουργεί κυρίως συγκριτικά.\n');
fprintf(reportFid, 'Ο λογαριθμικός μετασχηματισμός φωτίζει τις σκιές και συμπιέζει τις υψηλές εντάσεις, συνήθως πιο ήπια από gamma 0.4.\n\n');

totalRows = numel(imageFiles) * (3 + numel(gammaValues));
emptyRow = struct('Image', '', 'ImageNumber', 0, 'HighReferenceImage', '', 'Method', '', 'Parameter', '', 'MeanBrightness', 0, 'IntensityVariance', 0, 'StdContrast', 0, 'MinIntensity', 0, 'MaxIntensity', 0, 'DarkPixelPercent', 0, 'BrightPixelPercent', 0, 'SaturatedPixelPercent', 0, 'MichelsonContrast', 0, 'Comment', '');
resultRows = repmat(emptyRow, totalRows, 1);
rowIdx = 0;

fprintf('Μέρος Β: βρέθηκαν %d εικόνες χαμηλού φωτισμού.\n', numel(imageFiles));
fprintf('Τα αποτελέσματα θα αποθηκευτούν εδώ:\n%s\n\n', resultsDir);

for idx = 1:numel(imageFiles)
    imagePath = fullfile(projectDir, imageFiles(idx).name);
    [inputImage, isColorImage] = read_image_as_double(imagePath);

    [~, baseName] = fileparts(imageFiles(idx).name);
    safeBaseName = make_safe_filename(baseName);
    outputPrefix = sprintf('%02d_%s', idx, safeBaseName);

    highReferenceName = sprintf('%d_high.png', imageIds(idx));
    if exist(fullfile(projectDir, highReferenceName), 'file') ~= 2
        highReferenceName = '';
    end

    originalImage = inputImage;
    linearImage = linear_contrast_stretch(inputImage);
    logImage = logarithmic_transform(inputImage);
    gammaImages = cell(numel(gammaValues), 1);

    for gammaIdx = 1:numel(gammaValues)
        gammaImages{gammaIdx} = gamma_transform(inputImage, gammaValues(gammaIdx));
    end

    imwrite(originalImage, fullfile(resultsDir, [outputPrefix, '_input_low.png']));
    imwrite(linearImage, fullfile(resultsDir, [outputPrefix, '_linear_stretch.png']));
    for gammaIdx = 1:numel(gammaValues)
        gammaLabel = strrep(sprintf('%.1f', gammaValues(gammaIdx)), '.', '_');
        imwrite(gammaImages{gammaIdx}, fullfile(resultsDir, [outputPrefix, '_gamma_', gammaLabel, '.png']));
    end
    imwrite(logImage, fullfile(resultsDir, [outputPrefix, '_log_transform.png']));

    rowIdx = rowIdx + 1;
    resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, 'Original low-light', '', originalImage, isColorImage, 'Αρχική εικόνα χαμηλού φωτισμού πριν από τους μετασχηματισμούς.');

    rowIdx = rowIdx + 1;
    resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, 'Linear stretch', 'full range [0,1]', linearImage, isColorImage, make_linear_comment(originalImage, linearImage, isColorImage));

    for gammaIdx = 1:numel(gammaValues)
        gammaValue = gammaValues(gammaIdx);
        rowIdx = rowIdx + 1;
        resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, 'Gamma correction', sprintf('gamma = %.1f', gammaValue), gammaImages{gammaIdx}, isColorImage, make_gamma_comment(gammaValue, originalImage, gammaImages{gammaIdx}, isColorImage));
    end

    rowIdx = rowIdx + 1;
    resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, 'Log transform', 'log(1+I)/log(2)', logImage, isColorImage, make_log_comment(originalImage, logImage, gammaImages{1}, isColorImage));

    fprintf(reportFid, 'Εικόνα %02d: %s\n', idx, imageFiles(idx).name);
    fprintf(reportFid, 'Αντίστοιχη φωτεινή εικόνα: %s\n', value_or_none(highReferenceName));
    fprintf(reportFid, 'Linear stretch: %s\n', make_linear_comment(originalImage, linearImage, isColorImage));
    for gammaIdx = 1:numel(gammaValues)
        fprintf(reportFid, 'Gamma %.1f: %s\n', gammaValues(gammaIdx), make_gamma_comment(gammaValues(gammaIdx), originalImage, gammaImages{gammaIdx}, isColorImage));
    end
    fprintf(reportFid, 'Log transform: %s\n\n', make_log_comment(originalImage, logImage, gammaImages{1}, isColorImage));

    if showFigures
        hComparison = figure('Name', ['B3B - ', imageFiles(idx).name], 'Color', 'w', 'Visible', 'on', 'Position', [45 45 1500 980]);
        comparisonTitle = sprintf('Μέρος Β - Σύγκριση μετασχηματισμών φωτεινότητας: %s', imageFiles(idx).name);
        annotation(hComparison, 'textbox', [0.02 0.94 0.96 0.045], 'String', comparisonTitle, 'Interpreter', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'EdgeColor', 'none', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
        comparisonLayout = tiledlayout(hComparison, 2, 4, 'Padding', 'loose', 'TileSpacing', 'loose');
        comparisonLayout.Units = 'normalized';
        comparisonLayout.Position = [0.035 0.055 0.93 0.86];

        show_image_tile(originalImage, 'Original low-light');
        show_image_tile(linearImage, 'Linear stretch');
        show_image_tile(gammaImages{1}, 'Gamma 0.4');
        show_image_tile(gammaImages{2}, 'Gamma 0.6');
        show_image_tile(gammaImages{3}, 'Gamma 0.8');
        show_image_tile(gammaImages{4}, 'Gamma 1.2');
        show_image_tile(logImage, 'Log transform');

        nexttile;
        axis off;
        originalStats = compute_image_stats(originalImage, isColorImage);
        linearStats = compute_image_stats(linearImage, isColorImage);
        gamma04Stats = compute_image_stats(gammaImages{1}, isColorImage);
        logStats = compute_image_stats(logImage, isColorImage);
        text(0.02, 0.78, sprintf('Mean original: %.3f', originalStats.Mean), 'FontSize', 11);
        text(0.02, 0.60, sprintf('Mean linear: %.3f', linearStats.Mean), 'FontSize', 11);
        text(0.02, 0.42, sprintf('Mean gamma 0.4: %.3f', gamma04Stats.Mean), 'FontSize', 11);
        text(0.02, 0.24, sprintf('Mean log: %.3f', logStats.Mean), 'FontSize', 11);
        text(0.02, 0.06, sprintf('Dark pixels after linear: %.1f%%', linearStats.DarkPercent), 'FontSize', 11);

        save_figure_png(hComparison, fullfile(resultsDir, [outputPrefix, '_comparison.png']));
    end

    originalStats = compute_image_stats(originalImage, isColorImage);
    linearStats = compute_image_stats(linearImage, isColorImage);
    gamma04Stats = compute_image_stats(gammaImages{1}, isColorImage);
    logStats = compute_image_stats(logImage, isColorImage);

    fprintf('%02d/%02d %s: μέση φωτεινότητα %.4f -> linear %.4f, gamma 0.4 %.4f, log %.4f\n', idx, numel(imageFiles), imageFiles(idx).name, originalStats.Mean, linearStats.Mean, gamma04Stats.Mean, logStats.Mean);
    drawnow;
end

resultRows = resultRows(1:rowIdx);
statsTable = struct2table(resultRows);
writetable(statsTable, fullfile(resultsDir, 'B3B_statistics.csv'));

if showFigures
    hSummary = figure('Name', 'B3B - Summary statistics', 'Color', 'w', 'Visible', 'on', 'Position', [120 120 1350 900]);
    methodOrder = {'Original low-light', 'Linear stretch', 'Gamma correction', 'Log transform'};
    tiledlayout(hSummary, 2, 1, 'Padding', 'loose', 'TileSpacing', 'compact');

    nexttile;
    plot_summary_by_method(statsTable, methodOrder, 'MeanBrightness', 'Mean brightness');

    nexttile;
    plot_summary_by_method(statsTable, methodOrder, 'StdContrast', 'Std contrast');

    sgtitle('Μέρος Β - Συνοπτική σύγκριση μεθόδων', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
    save_figure_png(hSummary, fullfile(resultsDir, 'B3B_summary_statistics.png'));
end

fprintf('\nΤο Μέρος Β ολοκληρώθηκε.\n');
if showFigures
    fprintf('Αποθηκεύτηκαν μετασχηματισμένες εικόνες, figures, στατιστικά και σχόλια εδώ:\n%s\n', resultsDir);
else
    fprintf('Αποθηκεύτηκαν μετασχηματισμένες εικόνες, στατιστικά και σχόλια εδώ:\n%s\n', resultsDir);
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

function outputImage = linear_contrast_stretch(inputImage)
    inputMin = min(inputImage(:));
    inputMax = max(inputImage(:));
    if inputMax <= inputMin
        outputImage = zeros(size(inputImage));
    else
        outputImage = (inputImage - inputMin) / (inputMax - inputMin);
    end
end

function outputImage = gamma_transform(inputImage, gammaValue)
    outputImage = min(max(inputImage, 0), 1) .^ gammaValue;
end

function outputImage = logarithmic_transform(inputImage)
    outputImage = log(1 + min(max(inputImage, 0), 1)) / log(2);
end

function stats = compute_image_stats(inputImage, isColorImage)
    if isColorImage
        grayImage = rgb2gray(inputImage);
    else
        grayImage = inputImage;
    end
    pixels = grayImage(:);
    stats.Mean = mean(pixels);
    stats.Variance = mean((pixels - stats.Mean) .^ 2);
    stats.Std = sqrt(stats.Variance);
    stats.Min = min(pixels);
    stats.Max = max(pixels);
    stats.DarkPercent = 100 * mean(pixels <= 0.25);
    stats.BrightPercent = 100 * mean(pixels >= 0.75);
    stats.SaturatedPercent = 100 * mean(pixels >= 0.98);
    stats.Michelson = (stats.Max - stats.Min) / (stats.Max + stats.Min + eps);
end

function row = make_result_row(imageName, imageNumber, highReferenceName, methodName, parameterText, resultImage, isColorImage, commentText)
    stats = compute_image_stats(resultImage, isColorImage);
    row = struct('Image', imageName, 'ImageNumber', imageNumber, 'HighReferenceImage', highReferenceName, 'Method', methodName, 'Parameter', parameterText, 'MeanBrightness', stats.Mean, 'IntensityVariance', stats.Variance, 'StdContrast', stats.Std, 'MinIntensity', stats.Min, 'MaxIntensity', stats.Max, 'DarkPixelPercent', stats.DarkPercent, 'BrightPixelPercent', stats.BrightPercent, 'SaturatedPixelPercent', stats.SaturatedPercent, 'MichelsonContrast', stats.Michelson, 'Comment', commentText);
end

function commentText = make_linear_comment(originalImage, linearImage, isColorImage)
    originalStats = compute_image_stats(originalImage, isColorImage);
    linearStats = compute_image_stats(linearImage, isColorImage);
    if linearStats.SaturatedPercent > originalStats.SaturatedPercent + 2
        highlightPart = 'Παράλληλα αυξάνονται τα σχεδόν κορεσμένα pixels, άρα οι φωτεινές πηγές μπορεί να γίνουν υπερβολικές.';
    else
        highlightPart = 'Δεν δημιουργείται έντονος κορεσμός στις φωτεινές περιοχές.';
    end
    if linearStats.Std > originalStats.Std
        contrastPart = 'Η αντίθεση αυξάνεται επειδή το εύρος εντάσεων απλώνεται στο πλήρες δυναμικό εύρος.';
    else
        contrastPart = 'Η αντίθεση δεν αυξάνεται έντονα επειδή το αρχικό εύρος ήταν ήδη αρκετά μεγάλο.';
    end
    commentText = [contrastPart, ' Ο θόρυβος στις σκοτεινές περιοχές ενισχύεται μαζί με τη χρήσιμη λεπτομέρεια. ', highlightPart];
end

function commentText = make_gamma_comment(gammaValue, originalImage, gammaImage, isColorImage)
    originalStats = compute_image_stats(originalImage, isColorImage);
    gammaStats = compute_image_stats(gammaImage, isColorImage);
    meanChange = gammaStats.Mean - originalStats.Mean;
    if gammaValue < 1
        if gammaValue <= 0.4
            strengthPart = 'Η μικρή τιμή gamma δίνει ισχυρή φωτεινότητα στις σκοτεινές περιοχές.';
        else
            strengthPart = 'Η τιμή gamma φωτίζει τις σκοτεινές περιοχές πιο ήπια.';
        end
    else
        strengthPart = 'Επειδή η gamma είναι μεγαλύτερη από 1, η εικόνα σκοτεινιάζει αντί να βελτιώνεται για χαμηλό φωτισμό.';
    end
    if gammaStats.SaturatedPercent > originalStats.SaturatedPercent + 2
        riskPart = 'Η ενίσχυση μπορεί να κάνει πιο εμφανή τον θόρυβο και τα highlights.';
    else
        riskPart = 'Ο κορεσμός των φωτεινών περιοχών παραμένει περιορισμένος.';
    end
    commentText = sprintf('%s Η μέση φωτεινότητα αλλάζει κατά %.4f. %s', strengthPart, meanChange, riskPart);
end

function commentText = make_log_comment(originalImage, logImage, strongGammaImage, isColorImage)
    originalStats = compute_image_stats(originalImage, isColorImage);
    logStats = compute_image_stats(logImage, isColorImage);
    strongGammaStats = compute_image_stats(strongGammaImage, isColorImage);
    if logStats.Mean < strongGammaStats.Mean
        comparisonPart = 'Σε σύγκριση με gamma 0.4, ο λογαριθμικός μετασχηματισμός είναι πιο ήπιος.';
    else
        comparisonPart = 'Σε αυτή την εικόνα ο λογαριθμικός μετασχηματισμός πλησιάζει ή ξεπερνά τη φωτεινότητα του gamma 0.4.';
    end
    commentText = sprintf('Ανεβάζει τη μέση φωτεινότητα από %.4f σε %.4f και συμπιέζει τις υψηλές εντάσεις. %s', originalStats.Mean, logStats.Mean, comparisonPart);
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

function show_image_tile(inputImage, titleText)
    nexttile;
    imshow(inputImage);
    title(titleText, 'Interpreter', 'none', 'Color', 'k');
end

function plot_summary_by_method(statsTable, methodOrder, metricName, titleText)
    hold on;
    for methodIdx = 1:numel(methodOrder)
        methodName = methodOrder{methodIdx};
        rows = strcmp(statsTable.Method, methodName);
        if strcmp(methodName, 'Gamma correction')
            rows = rows & strcmp(statsTable.Parameter, 'gamma = 0.6');
            displayName = 'Gamma 0.6';
        else
            displayName = methodName;
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
