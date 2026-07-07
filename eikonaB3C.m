clear;
clc;
close all;

% Για να επεξεργαστεί μια εικόνα, το όνομά της πρέπει να τελειώνει σε _low.png.

greekDesktop = char([933 960 959 955 959 947 953 963 964 942 962]);
% Replace with your path
projectDir = fullfile(getenv('USERPROFILE'), 'OneDrive', greekDesktop, 'project');
resultsDir = fullfile(projectDir, 'resultsB3C');
expectedFolderName = 'resultsB3C';

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
showFigures = should_show_figures();
claheSettings = [4 4 0.01; 8 8 0.01; 8 8 0.03; 16 16 0.01];

reportFile = fullfile(resultsDir, 'B3C_histogram_equalization_comments.txt');
reportFid = fopen(reportFile, 'w', 'n', 'UTF-8');
if reportFid == -1
    error('Δεν ήταν δυνατή η δημιουργία του αρχείου: %s', reportFile);
end
reportCleanup = onCleanup(@() fclose(reportFid));

fprintf(reportFid, 'Μέρος Γ: Ισοστάθμιση ιστογράμματος\n');
fprintf(reportFid, 'Φάκελος εικόνων: %s\n', projectDir);
fprintf(reportFid, 'Φάκελος αποτελεσμάτων: %s\n\n', resultsDir);
fprintf(reportFid, 'Κανόνας ονομάτων: *_low.png είναι η σκοτεινή εικόνα και *_high.png η φωτεινή αναφορά.\n');
fprintf(reportFid, 'Η global ισοστάθμιση υλοποιείται από το ιστόγραμμα, την CDF και τον μετασχηματισμό s_k=(L-1)CDF(k).\n');
fprintf(reportFid, 'Η adaptive ισοστάθμιση εφαρμόζεται ως CLAHE με διαφορετικά tiles και clip limit.\n\n');

rowTemplate = struct('Image', '', 'ImageNumber', 0, 'HighReferenceImage', '', 'Method', '', 'Parameter', '', 'ApproxTileSize', '', 'MeanBrightness', 0, 'IntensityVariance', 0, 'StdContrast', 0, 'EntropyValue', 0, 'DarkPixelPercent', 0, 'BrightPixelPercent', 0, 'SaturatedPixelPercent', 0, 'MichelsonContrast', 0, 'Comment', '');
resultRows = repmat(rowTemplate, numel(imageFiles) * (2 + size(claheSettings, 1)), 1);
rowIdx = 0;

fprintf('Μέρος Γ: βρέθηκαν %d εικόνες χαμηλού φωτισμού.\n', numel(imageFiles));
fprintf('Τα αποτελέσματα θα αποθηκευτούν εδώ:\n%s\n\n', resultsDir);

for idx = 1:numel(imageFiles)
    imagePath = fullfile(projectDir, imageFiles(idx).name);
    [inputImage, isColorImage] = read_image_as_double(imagePath);
    inputBrightness = extract_brightness(inputImage, isColorImage);

    [globalBrightness, histBefore, cdfValues, histGlobal] = global_hist_equalize(inputBrightness);
    globalImage = replace_brightness(inputImage, globalBrightness, isColorImage);

    claheImages = cell(size(claheSettings, 1), 1);
    claheBrightness = cell(size(claheSettings, 1), 1);
    histClahe = cell(size(claheSettings, 1), 1);

    for settingIdx = 1:size(claheSettings, 1)
        numTiles = claheSettings(settingIdx, 1:2);
        clipLimit = claheSettings(settingIdx, 3);
        claheBrightness{settingIdx} = adapthisteq(inputBrightness, 'NumTiles', numTiles, 'ClipLimit', clipLimit, 'Distribution', 'uniform');
        claheImages{settingIdx} = replace_brightness(inputImage, claheBrightness{settingIdx}, isColorImage);
        histClahe{settingIdx} = intensity_histogram(claheBrightness{settingIdx});
    end

    histInput = histBefore;
    cdfTable = table((0:255)', histInput(:), cdfValues(:), histGlobal(:), 'VariableNames', {'IntensityLevel', 'InputHistogram', 'InputCDF', 'GlobalEqualizedHistogram'});

    [~, baseName] = fileparts(imageFiles(idx).name);
    safeBaseName = make_safe_filename(baseName);
    outputPrefix = sprintf('%02d_%s', idx, safeBaseName);

    highReferenceName = sprintf('%d_high.png', imageIds(idx));
    if exist(fullfile(projectDir, highReferenceName), 'file') ~= 2
        highReferenceName = '';
    end

    imwrite(inputImage, fullfile(resultsDir, [outputPrefix, '_input_low.png']));
    imwrite(globalImage, fullfile(resultsDir, [outputPrefix, '_global_histeq.png']));

    rowIdx = rowIdx + 1;
    resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, 'Original low-light', '', '', inputBrightness, 'Αρχική εικόνα χαμηλού φωτισμού πριν από την ισοστάθμιση.');

    rowIdx = rowIdx + 1;
    globalComment = make_global_comment(inputBrightness, globalBrightness);
    resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, 'Global histogram equalization', 'CDF mapping', '', globalBrightness, globalComment);

    for settingIdx = 1:size(claheSettings, 1)
        numTiles = claheSettings(settingIdx, 1:2);
        clipLimit = claheSettings(settingIdx, 3);
        tileSizeText = make_tile_size_text(size(inputBrightness), numTiles);
        parameterText = sprintf('NumTiles=[%d %d], ClipLimit=%.2f', numTiles(1), numTiles(2), clipLimit);
        outputName = sprintf('%s_clahe_%dx%d_clip_%s.png', outputPrefix, numTiles(1), numTiles(2), strrep(sprintf('%.2f', clipLimit), '.', '_'));
        imwrite(claheImages{settingIdx}, fullfile(resultsDir, outputName));

        cdfTable.(sprintf('CLAHE_%dx%d_clip_%s_Histogram', numTiles(1), numTiles(2), strrep(sprintf('%.2f', clipLimit), '.', '_'))) = histClahe{settingIdx}(:);
        if settingIdx == size(claheSettings, 1)
            writetable(cdfTable, fullfile(resultsDir, [outputPrefix, '_histograms_cdf.csv']));
        end

        rowIdx = rowIdx + 1;
        claheComment = make_clahe_comment(inputBrightness, globalBrightness, claheBrightness{settingIdx}, numTiles, clipLimit);
        resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, 'Adaptive histogram equalization', parameterText, tileSizeText, claheBrightness{settingIdx}, claheComment);
    end


    fprintf(reportFid, 'Εικόνα %02d: %s\n', idx, imageFiles(idx).name);
    fprintf(reportFid, 'Αντίστοιχη φωτεινή εικόνα: %s\n', value_or_none(highReferenceName));
    fprintf(reportFid, 'Global histogram equalization: %s\n', globalComment);
    for settingIdx = 1:size(claheSettings, 1)
        numTiles = claheSettings(settingIdx, 1:2);
        clipLimit = claheSettings(settingIdx, 3);
        fprintf(reportFid, 'CLAHE NumTiles=[%d %d], ClipLimit=%.2f: %s\n', numTiles(1), numTiles(2), clipLimit, make_clahe_comment(inputBrightness, globalBrightness, claheBrightness{settingIdx}, numTiles, clipLimit));
    end
    fprintf(reportFid, '\n');

    if showFigures
        hGlobal = figure('Name', ['B3C Global - ', imageFiles(idx).name], 'Color', 'w', 'Visible', 'on', 'Position', [60 60 1250 900]);
        globalTitle = sprintf('Μέρος Γ1 - Global histogram equalization: %s', imageFiles(idx).name);
        annotation(hGlobal, 'textbox', [0.02 0.94 0.96 0.045], 'String', globalTitle, 'Interpreter', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'EdgeColor', 'none', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
        globalLayout = tiledlayout(hGlobal, 2, 2, 'Padding', 'loose', 'TileSpacing', 'loose');
        globalLayout.Units = 'normalized';
        globalLayout.Position = [0.055 0.06 0.89 0.84];

        show_image_tile(inputImage, 'Εικόνα πριν');
        show_image_tile(globalImage, 'Εικόνα μετά');
        show_histogram_tile(histBefore, 'Ιστόγραμμα πριν');
        show_histogram_tile(histGlobal, 'Ιστόγραμμα μετά');
        save_figure_png(hGlobal, fullfile(resultsDir, [outputPrefix, '_global_histeq_comparison.png']));

        hClahe = figure('Name', ['B3C CLAHE - ', imageFiles(idx).name], 'Color', 'w', 'Visible', 'on', 'Position', [45 45 1500 980]);
        claheTitle = sprintf('Μέρος Γ2 - Adaptive histogram equalization: %s', imageFiles(idx).name);
        annotation(hClahe, 'textbox', [0.02 0.94 0.96 0.045], 'String', claheTitle, 'Interpreter', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'EdgeColor', 'none', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
        claheLayout = tiledlayout(hClahe, 2, 3, 'Padding', 'loose', 'TileSpacing', 'loose');
        claheLayout.Units = 'normalized';
        claheLayout.Position = [0.045 0.055 0.91 0.86];

        show_image_tile(inputImage, 'Original low-light');
        show_image_tile(globalImage, 'Global histeq');
        for settingIdx = 1:size(claheSettings, 1)
            numTiles = claheSettings(settingIdx, 1:2);
            clipLimit = claheSettings(settingIdx, 3);
            show_image_tile(claheImages{settingIdx}, sprintf('CLAHE %dx%d, clip %.2f', numTiles(1), numTiles(2), clipLimit));
        end
        save_figure_png(hClahe, fullfile(resultsDir, [outputPrefix, '_clahe_comparison.png']));
    end

    inputStats = compute_channel_stats(inputBrightness);
    globalStats = compute_channel_stats(globalBrightness);
    bestClaheStats = compute_channel_stats(claheBrightness{2});

    fprintf('%02d/%02d %s: mean %.4f -> global %.4f, CLAHE 8x8 %.4f | std %.4f -> global %.4f\n', idx, numel(imageFiles), imageFiles(idx).name, inputStats.Mean, globalStats.Mean, bestClaheStats.Mean, inputStats.Std, globalStats.Std);
    drawnow;
end

resultRows = resultRows(1:rowIdx);
statsTable = struct2table(resultRows);
writetable(statsTable, fullfile(resultsDir, 'B3C_statistics.csv'));

if showFigures
    hSummary = figure('Name', 'B3C - Summary statistics', 'Color', 'w', 'Visible', 'on', 'Position', [120 120 1350 900]);
    tiledlayout(hSummary, 2, 1, 'Padding', 'loose', 'TileSpacing', 'compact');

    nexttile;
    plot_summary_by_method(statsTable, 'MeanBrightness', 'Mean brightness');

    nexttile;
    plot_summary_by_method(statsTable, 'StdContrast', 'Std contrast');

    sgtitle('Μέρος Γ - Συνοπτική σύγκριση ισοστάθμισης', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
    save_figure_png(hSummary, fullfile(resultsDir, 'B3C_summary_statistics.png'));
end

fprintf('\nΤο Μέρος Γ ολοκληρώθηκε.\n');
if showFigures
    fprintf('Αποθηκεύτηκαν εικόνες, figures, CDF/ιστογράμματα, στατιστικά και σχόλια εδώ:\n%s\n', resultsDir);
else
    fprintf('Αποθηκεύτηκαν εικόνες, CDF/ιστογράμματα, στατιστικά και σχόλια εδώ:\n%s\n', resultsDir);
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

function [equalizedChannel, histBefore, cdfValues, histAfter] = global_hist_equalize(channelImage)
    channelImage = min(max(channelImage, 0), 1);
    uintValues = uint8(round(255 * channelImage));
    histBefore = histcounts(double(uintValues(:)), -0.5:1:255.5);
    probabilities = histBefore / sum(histBefore);
    cdfValues = cumsum(probabilities);
    equalizedChannel = reshape(cdfValues(double(uintValues(:)) + 1), size(channelImage));
    histAfter = intensity_histogram(equalizedChannel);
end

function counts = intensity_histogram(channelImage)
    channelImage = min(max(channelImage, 0), 1);
    uintValues = uint8(round(255 * channelImage));
    counts = histcounts(double(uintValues(:)), -0.5:1:255.5);
end

function stats = compute_channel_stats(channelImage)
    pixels = channelImage(:);
    stats.Mean = mean(pixels);
    stats.Variance = mean((pixels - stats.Mean) .^ 2);
    stats.Std = sqrt(stats.Variance);
    stats.Min = min(pixels);
    stats.Max = max(pixels);
    stats.DarkPercent = 100 * mean(pixels <= 0.25);
    stats.BrightPercent = 100 * mean(pixels >= 0.75);
    stats.SaturatedPercent = 100 * mean(pixels >= 0.98);
    stats.Michelson = (stats.Max - stats.Min) / (stats.Max + stats.Min + eps);
    stats.Entropy = compute_entropy(channelImage);
end

function entropyValue = compute_entropy(channelImage)
    counts = intensity_histogram(channelImage);
    probabilities = counts / sum(counts);
    probabilities = probabilities(probabilities > 0);
    entropyValue = -sum(probabilities .* log2(probabilities));
end

function row = make_result_row(imageName, imageNumber, highReferenceName, methodName, parameterText, tileSizeText, brightnessChannel, commentText)
    stats = compute_channel_stats(brightnessChannel);
    row = struct('Image', imageName, 'ImageNumber', imageNumber, 'HighReferenceImage', highReferenceName, 'Method', methodName, 'Parameter', parameterText, 'ApproxTileSize', tileSizeText, 'MeanBrightness', stats.Mean, 'IntensityVariance', stats.Variance, 'StdContrast', stats.Std, 'EntropyValue', stats.Entropy, 'DarkPixelPercent', stats.DarkPercent, 'BrightPixelPercent', stats.BrightPercent, 'SaturatedPixelPercent', stats.SaturatedPercent, 'MichelsonContrast', stats.Michelson, 'Comment', commentText);
end

function commentText = make_global_comment(inputBrightness, globalBrightness)
    inputStats = compute_channel_stats(inputBrightness);
    globalStats = compute_channel_stats(globalBrightness);
    if globalStats.Std > inputStats.Std
        contrastPart = 'Η global ισοστάθμιση αυξάνει την αντίθεση επειδή απλώνει το ιστόγραμμα σε μεγαλύτερο εύρος.';
    else
        contrastPart = 'Η global ισοστάθμιση δεν αυξάνει έντονα την αντίθεση σε αυτή την εικόνα.';
    end
    if globalStats.SaturatedPercent > inputStats.SaturatedPercent + 3
        riskPart = 'Παράλληλα εμφανίζεται αυξημένος κορεσμός, άρα υπάρχει κίνδυνος υπερενίσχυσης.';
    elseif globalStats.Std > inputStats.Std * 1.8
        riskPart = 'Η ισχυρή αύξηση της αντίθεσης μπορεί να κάνει πιο ορατό τον θόρυβο στις σκοτεινές περιοχές.';
    else
        riskPart = 'Η υπερενίσχυση παραμένει σχετικά περιορισμένη.';
    end
    commentText = [contrastPart, ' ', riskPart];
end

function commentText = make_clahe_comment(inputBrightness, globalBrightness, claheBrightness, numTiles, clipLimit)
    inputStats = compute_channel_stats(inputBrightness);
    globalStats = compute_channel_stats(globalBrightness);
    claheStats = compute_channel_stats(claheBrightness);
    if claheStats.Std > inputStats.Std
        detailPart = 'Η τοπική ισοστάθμιση αποκαλύπτει περισσότερες λεπτομέρειες στις σκοτεινές περιοχές.';
    else
        detailPart = 'Η τοπική ισοστάθμιση είναι ήπια και δεν αυξάνει πολύ την τοπική αντίθεση.';
    end
    if claheStats.SaturatedPercent < globalStats.SaturatedPercent || clipLimit <= 0.01
        clipPart = 'Το clip limit περιορίζει την υπερβολική ενίσχυση του θορύβου.';
    else
        clipPart = 'Το μεγαλύτερο clip limit δίνει πιο έντονη αντίθεση αλλά μπορεί να ενισχύσει θόρυβο.';
    end
    if max(numTiles) >= 16
        tilePart = 'Τα περισσότερα tiles αντιστοιχούν σε μικρότερα τοπικά παράθυρα και δίνουν πιο έντονη τοπική προσαρμογή.';
    elseif max(numTiles) <= 4
        tilePart = 'Τα λιγότερα tiles αντιστοιχούν σε μεγαλύτερα τοπικά παράθυρα και πιο ομαλή μεταβολή.';
    else
        tilePart = 'Η επιλογή 8x8 tiles δίνει ενδιάμεση ισορροπία ανάμεσα σε τοπική λεπτομέρεια και φυσικό αποτέλεσμα.';
    end
    commentText = [detailPart, ' ', clipPart, ' ', tilePart];
end

function tileSizeText = make_tile_size_text(imageSize, numTiles)
    tileRows = ceil(imageSize(1) / numTiles(1));
    tileCols = ceil(imageSize(2) / numTiles(2));
    tileSizeText = sprintf('about %dx%d pixels', tileRows, tileCols);
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

function show_histogram_tile(histCounts, titleText)
    nexttile;
    bar(0:255, histCounts, 1, 'FaceColor', [0.25 0.25 0.25], 'EdgeColor', 'none');
    xlim([0 255]);
    grid on;
    title(titleText, 'Color', 'k');
    xlabel('Intensity level');
    ylabel('Pixels');
end

function plot_summary_by_method(statsTable, metricName, titleText)
    hold on;
    rowsOriginal = strcmp(statsTable.Method, 'Original low-light');
    rowsGlobal = strcmp(statsTable.Method, 'Global histogram equalization');
    rowsClahe = strcmp(statsTable.Method, 'Adaptive histogram equalization') & strcmp(statsTable.Parameter, 'NumTiles=[8 8], ClipLimit=0.01');
    plot(statsTable.ImageNumber(rowsOriginal), statsTable.(metricName)(rowsOriginal), '-o', 'LineWidth', 1.2, 'DisplayName', 'Original');
    plot(statsTable.ImageNumber(rowsGlobal), statsTable.(metricName)(rowsGlobal), '-o', 'LineWidth', 1.2, 'DisplayName', 'Global histeq');
    plot(statsTable.ImageNumber(rowsClahe), statsTable.(metricName)(rowsClahe), '-o', 'LineWidth', 1.2, 'DisplayName', 'CLAHE 8x8 clip 0.01');
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
