clear;
clc;
close all;

% Για να επεξεργαστεί μια εικόνα, το όνομά της πρέπει να τελειώνει σε _low.png.

rng(1);

greekDesktop = char([933 960 959 955 959 947 953 963 964 942 962]);
projectDir = fullfile(getenv('USERPROFILE'), 'OneDrive', greekDesktop, 'project');
resultsDir = fullfile(projectDir, 'resultsB3D');

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

gaussianVariance = 0.005;
saltPepperDensity = 0.05;
filterNames = {'Mean filter', 'Gaussian filter', 'Median filter', 'Wiener filter'};
pipelineFilters = {'Gaussian filter', 'Median filter'};

reportFile = fullfile(resultsDir, 'B3D_denoising_comments.txt');
reportFid = fopen(reportFile, 'w', 'n', 'UTF-8');
if reportFid == -1
    error('Δεν ήταν δυνατή η δημιουργία του αρχείου: %s', reportFile);
end
reportCleanup = onCleanup(@() fclose(reportFid));

fprintf(reportFid, 'Μέρος Δ: Αποθορυβοποίηση εικόνας\n');
fprintf(reportFid, 'Φάκελος εικόνων: %s\n', projectDir);
fprintf(reportFid, 'Φάκελος αποτελεσμάτων: %s\n\n', resultsDir);
fprintf(reportFid, 'Κανόνας ονομάτων: *_low.png είναι η σκοτεινή εικόνα και *_high.png η φωτεινή αναφορά.\n');
fprintf(reportFid, 'Προστίθεται τεχνητά Gaussian θόρυβος με variance %.4f και Salt & Pepper θόρυβος με density %.3f.\n', gaussianVariance, saltPepperDensity);
fprintf(reportFid, 'Η αρχική low-light εικόνα χρησιμοποιείται ως αναφορά για τη μέτρηση μείωσης θορύβου, επειδή ο θόρυβος είναι τεχνητός.\n');
fprintf(reportFid, 'Για τη σύγκριση των σειρών επεξεργασίας χρησιμοποιείται ως αναφορά η βελτιωμένη εικόνα που προκύπτει από την καθαρή low-light εικόνα.\n\n');

rowTemplate = struct('Image', '', 'ImageNumber', 0, 'HighReferenceImage', '', 'NoiseType', '', 'Stage', '', 'Method', '', 'Sequence', '', 'Parameters', '', 'MSE', 0, 'PSNR', 0, 'MAE', 0, 'StdContrast', 0, 'GradientMean', 0, 'GradientRatio', 0, 'EdgeCorrelation', 0, 'DarkPixelPercent', 0, 'SaturatedPixelPercent', 0, 'Comment', '');
resultRows = repmat(rowTemplate, numel(imageFiles) * 24, 1);
rowIdx = 0;

fprintf('Μέρος Δ: βρέθηκαν %d εικόνες χαμηλού φωτισμού.\n', numel(imageFiles));
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

    gaussianNoisy = imnoise(inputImage, 'gaussian', 0, gaussianVariance);
    saltPepperNoisy = imnoise(inputImage, 'salt & pepper', saltPepperDensity);
    idealEnhanced = enhance_image(inputImage);

    imwrite(inputImage, fullfile(resultsDir, [outputPrefix, '_input_low.png']));
    imwrite(gaussianNoisy, fullfile(resultsDir, [outputPrefix, '_gaussian_noisy.png']));
    imwrite(saltPepperNoisy, fullfile(resultsDir, [outputPrefix, '_saltpepper_noisy.png']));
    imwrite(idealEnhanced, fullfile(resultsDir, [outputPrefix, '_ideal_enhanced_clean.png']));

    noiseImages = {gaussianNoisy, saltPepperNoisy};
    noiseTypes = {'Gaussian noise', 'Salt & Pepper noise'};

    fprintf(reportFid, 'Εικόνα %02d: %s\n', idx, imageFiles(idx).name);
    fprintf(reportFid, 'Αντίστοιχη φωτεινή εικόνα: %s\n', value_or_none(highReferenceName));

    for noiseIdx = 1:numel(noiseImages)
        noisyImage = noiseImages{noiseIdx};
        noiseType = noiseTypes{noiseIdx};
        noisyMetrics = compute_metrics(inputImage, noisyImage, isColorImage);

        rowIdx = rowIdx + 1;
        resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, noiseType, 'Noisy image', 'No filtering', '', '', inputImage, noisyImage, isColorImage, 'Εικόνα μετά την τεχνητή προσθήκη θορύβου.');

        filteredImages = cell(numel(filterNames), 1);
        filteredMetrics = cell(numel(filterNames), 1);

        for filterIdx = 1:numel(filterNames)
            filterName = filterNames{filterIdx};
            filteredImages{filterIdx} = apply_filter(noisyImage, filterName);
            filteredMetrics{filterIdx} = compute_metrics(inputImage, filteredImages{filterIdx}, isColorImage);
            filterSafeName = make_safe_filename([lower(strrep(filterName, ' ', '_')), '_', lower(strrep(noiseType, ' ', '_'))]);
            imwrite(filteredImages{filterIdx}, fullfile(resultsDir, [outputPrefix, '_', filterSafeName, '.png']));

            rowIdx = rowIdx + 1;
            filterComment = make_filter_comment(noiseType, filterName, noisyMetrics, filteredMetrics{filterIdx});
            resultRows(rowIdx) = make_result_row(imageFiles(idx).name, imageIds(idx), highReferenceName, noiseType, 'Denoising', filterName, 'filter only', filter_parameters(filterName), inputImage, filteredImages{filterIdx}, isColorImage, filterComment);
            fprintf(reportFid, '%s - %s: %s\n', noiseType, filterName, filterComment);
        end

        for pipelineIdx = 1:numel(pipelineFilters)
            selectedFilter = pipelineFilters{pipelineIdx};
            denoisedFirst = apply_filter(noisyImage, selectedFilter);
            pipelineDenoiseThenEnhance = enhance_image(denoisedFirst);
            enhancedFirst = enhance_image(noisyImage);
            pipelineEnhanceThenDenoise = apply_filter(enhancedFirst, selectedFilter);

            pipelineSafeName = make_safe_filename([lower(strrep(selectedFilter, ' ', '_')), '_', lower(strrep(noiseType, ' ', '_'))]);
            imwrite(pipelineDenoiseThenEnhance, fullfile(resultsDir, [outputPrefix, '_pipeline_denoise_then_enhance_', pipelineSafeName, '.png']));
            imwrite(pipelineEnhanceThenDenoise, fullfile(resultsDir, [outputPrefix, '_pipeline_enhance_then_denoise_', pipelineSafeName, '.png']));

            metricsDenoiseThenEnhance = compute_metrics(idealEnhanced, pipelineDenoiseThenEnhance, isColorImage);
            metricsEnhanceThenDenoise = compute_metrics(idealEnhanced, pipelineEnhanceThenDenoise, isColorImage);
            [commentDenoiseThenEnhance, commentEnhanceThenDenoise] = make_pipeline_comments(noiseType, selectedFilter, metricsDenoiseThenEnhance, metricsEnhanceThenDenoise);

            rowIdx = rowIdx + 1;
            resultRows(rowIdx) = make_result_row_from_metrics(imageFiles(idx).name, imageIds(idx), highReferenceName, noiseType, 'Final enhanced image', selectedFilter, 'denoise -> enhance', 'gamma 0.6 + contrast stretch', metricsDenoiseThenEnhance, commentDenoiseThenEnhance);

            rowIdx = rowIdx + 1;
            resultRows(rowIdx) = make_result_row_from_metrics(imageFiles(idx).name, imageIds(idx), highReferenceName, noiseType, 'Final enhanced image', selectedFilter, 'enhance -> denoise', 'gamma 0.6 + contrast stretch', metricsEnhanceThenDenoise, commentEnhanceThenDenoise);

            fprintf(reportFid, '%s - %s - denoise -> enhance: %s\n', noiseType, selectedFilter, commentDenoiseThenEnhance);
            fprintf(reportFid, '%s - %s - enhance -> denoise: %s\n', noiseType, selectedFilter, commentEnhanceThenDenoise);
        end
    end

    fprintf(reportFid, '\n');

    if saveComparisonFigures
        hNoise = figure('Name', ['B3D Noisy - ', imageFiles(idx).name], 'Color', 'w', 'Visible', figureVisibility, 'Position', [80 80 1250 650]);
        add_top_title(hNoise, sprintf('Μέρος Δ - Τεχνητός θόρυβος: %s', imageFiles(idx).name));
        noiseLayout = tiledlayout(hNoise, 1, 3, 'Padding', 'loose', 'TileSpacing', 'loose');
        noiseLayout.Units = 'normalized';
        noiseLayout.Position = [0.05 0.08 0.90 0.82];
        show_image_tile(inputImage, 'Original low-light');
        show_image_tile(gaussianNoisy, 'Gaussian noise');
        show_image_tile(saltPepperNoisy, 'Salt & Pepper noise');
        save_figure_png(hNoise, fullfile(resultsDir, [outputPrefix, '_noise_comparison.png']));
        close(hNoise);

        make_filter_figure(imageFiles(idx).name, outputPrefix, resultsDir, gaussianNoisy, inputImage, apply_filter(gaussianNoisy, 'Mean filter'), apply_filter(gaussianNoisy, 'Gaussian filter'), apply_filter(gaussianNoisy, 'Median filter'), apply_filter(gaussianNoisy, 'Wiener filter'), 'Gaussian noise', figureVisibility);
        make_filter_figure(imageFiles(idx).name, outputPrefix, resultsDir, saltPepperNoisy, inputImage, apply_filter(saltPepperNoisy, 'Mean filter'), apply_filter(saltPepperNoisy, 'Gaussian filter'), apply_filter(saltPepperNoisy, 'Median filter'), apply_filter(saltPepperNoisy, 'Wiener filter'), 'Salt & Pepper noise', figureVisibility);
        make_pipeline_figure(imageFiles(idx).name, outputPrefix, resultsDir, idealEnhanced, gaussianNoisy, saltPepperNoisy, figureVisibility);
    end

    metricsGaussianNoisy = compute_metrics(inputImage, gaussianNoisy, isColorImage);
    metricsSaltPepperNoisy = compute_metrics(inputImage, saltPepperNoisy, isColorImage);
    metricsGaussianFiltered = compute_metrics(inputImage, apply_filter(gaussianNoisy, 'Gaussian filter'), isColorImage);
    metricsSaltPepperFiltered = compute_metrics(inputImage, apply_filter(saltPepperNoisy, 'Median filter'), isColorImage);

    fprintf('%02d/%02d %s: Gaussian PSNR %.2f -> %.2f, Salt & Pepper PSNR %.2f -> %.2f\n', idx, numel(imageFiles), imageFiles(idx).name, metricsGaussianNoisy.PSNR, metricsGaussianFiltered.PSNR, metricsSaltPepperNoisy.PSNR, metricsSaltPepperFiltered.PSNR);
    drawnow;
end

resultRows = resultRows(1:rowIdx);
statsTable = struct2table(resultRows);
writetable(statsTable, fullfile(resultsDir, 'B3D_statistics.csv'));

if saveComparisonFigures
    hSummary = figure('Name', 'B3D - Summary statistics', 'Color', 'w', 'Visible', figureVisibility, 'Position', [120 120 1350 900]);
    tiledlayout(hSummary, 2, 1, 'Padding', 'loose', 'TileSpacing', 'compact');

    nexttile;
    plot_filter_summary(statsTable, 'Gaussian noise');

    nexttile;
    plot_filter_summary(statsTable, 'Salt & Pepper noise');

    sgtitle('Μέρος Δ - Σύγκριση φίλτρων αποθορυβοποίησης', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
    save_figure_png(hSummary, fullfile(resultsDir, 'B3D_summary_statistics.png'));
    close(hSummary);
end

fprintf('\nΤο Μέρος Δ ολοκληρώθηκε.\n');
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

function filteredImage = apply_filter(inputImage, filterName)
    switch filterName
        case 'Mean filter'
            kernel = ones(3, 3) / 9;
            filteredImage = imfilter(inputImage, kernel, 'replicate');
        case 'Gaussian filter'
            filteredImage = imgaussfilt(inputImage, 1.0, 'FilterSize', 5);
        case 'Median filter'
            filteredImage = apply_channel_filter(inputImage, @(channel) medfilt2(channel, [3 3], 'symmetric'));
        case 'Wiener filter'
            filteredImage = apply_channel_filter(inputImage, @(channel) wiener2(channel, [5 5]));
        otherwise
            error('Άγνωστο φίλτρο: %s', filterName);
    end
    filteredImage = min(max(filteredImage, 0), 1);
end

function outputImage = apply_channel_filter(inputImage, filterFunction)
    if ndims(inputImage) == 3
        outputImage = zeros(size(inputImage));
        for channelIdx = 1:size(inputImage, 3)
            outputImage(:, :, channelIdx) = filterFunction(inputImage(:, :, channelIdx));
        end
    else
        outputImage = filterFunction(inputImage);
    end
end

function outputImage = enhance_image(inputImage)
    gammaImage = min(max(inputImage, 0), 1) .^ 0.6;
    outputImage = linear_contrast_stretch(gammaImage);
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

function metrics = compute_metrics(referenceImage, testImage, isColorImage)
    referenceImage = min(max(referenceImage, 0), 1);
    testImage = min(max(testImage, 0), 1);
    diffImage = testImage - referenceImage;
    metrics.MSE = mean(diffImage(:) .^ 2);
    if metrics.MSE == 0
        metrics.PSNR = Inf;
    else
        metrics.PSNR = 10 * log10(1 / metrics.MSE);
    end
    metrics.MAE = mean(abs(diffImage(:)));
    testGray = to_gray(testImage, isColorImage);
    referenceGray = to_gray(referenceImage, isColorImage);
    pixels = testGray(:);
    metrics.StdContrast = std(pixels);
    metrics.DarkPixelPercent = 100 * mean(pixels <= 0.25);
    metrics.SaturatedPixelPercent = 100 * mean(pixels >= 0.98);
    referenceGradient = gradient_magnitude(referenceGray);
    testGradient = gradient_magnitude(testGray);
    metrics.GradientMean = mean(testGradient(:));
    referenceGradientMean = mean(referenceGradient(:));
    metrics.GradientRatio = metrics.GradientMean / (referenceGradientMean + eps);
    metrics.EdgeCorrelation = safe_correlation(referenceGradient(:), testGradient(:));
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

function value = safe_correlation(valuesA, valuesB)
    if std(valuesA) == 0 || std(valuesB) == 0
        value = 0;
    else
        correlationMatrix = corrcoef(valuesA, valuesB);
        value = correlationMatrix(1, 2);
    end
end

function row = make_result_row(imageName, imageNumber, highReferenceName, noiseType, stageName, methodName, sequenceName, parameterText, referenceImage, resultImage, isColorImage, commentText)
    metrics = compute_metrics(referenceImage, resultImage, isColorImage);
    row = make_result_row_from_metrics(imageName, imageNumber, highReferenceName, noiseType, stageName, methodName, sequenceName, parameterText, metrics, commentText);
end

function row = make_result_row_from_metrics(imageName, imageNumber, highReferenceName, noiseType, stageName, methodName, sequenceName, parameterText, metrics, commentText)
    row = struct('Image', imageName, 'ImageNumber', imageNumber, 'HighReferenceImage', highReferenceName, 'NoiseType', noiseType, 'Stage', stageName, 'Method', methodName, 'Sequence', sequenceName, 'Parameters', parameterText, 'MSE', metrics.MSE, 'PSNR', metrics.PSNR, 'MAE', metrics.MAE, 'StdContrast', metrics.StdContrast, 'GradientMean', metrics.GradientMean, 'GradientRatio', metrics.GradientRatio, 'EdgeCorrelation', metrics.EdgeCorrelation, 'DarkPixelPercent', metrics.DarkPixelPercent, 'SaturatedPixelPercent', metrics.SaturatedPixelPercent, 'Comment', commentText);
end

function textValue = filter_parameters(filterName)
    switch filterName
        case 'Mean filter'
            textValue = '3x3 average kernel';
        case 'Gaussian filter'
            textValue = 'sigma=1.0, filter size=5';
        case 'Median filter'
            textValue = '3x3 median';
        case 'Wiener filter'
            textValue = '5x5 adaptive Wiener';
        otherwise
            textValue = '';
    end
end

function commentText = make_filter_comment(noiseType, filterName, noisyMetrics, filteredMetrics)
    psnrGain = filteredMetrics.PSNR - noisyMetrics.PSNR;
    if psnrGain > 2
        noisePart = sprintf('Το φίλτρο μειώνει αισθητά τον θόρυβο, με κέρδος PSNR %.2f dB.', psnrGain);
    elseif psnrGain > 0
        noisePart = sprintf('Το φίλτρο μειώνει μέτρια τον θόρυβο, με κέρδος PSNR %.2f dB.', psnrGain);
    else
        noisePart = sprintf('Το φίλτρο δεν βελτιώνει τη μετρική PSNR σε αυτή την περίπτωση, με μεταβολή %.2f dB.', psnrGain);
    end
    if filteredMetrics.GradientRatio < 0.75
        detailPart = 'Παρατηρείται πιθανή θόλωση λεπτομερειών και ακμών.';
    elseif filteredMetrics.GradientRatio > 1.25
        detailPart = 'Οι ακμές παραμένουν έντονες, αλλά μπορεί να παραμένει και θόρυβος.';
    else
        detailPart = 'Η ένταση των ακμών διατηρείται σε λογικά επίπεδα.';
    end
    if strcmp(noiseType, 'Salt & Pepper noise') && strcmp(filterName, 'Median filter')
        typePart = 'Το median filter είναι ιδιαίτερα κατάλληλο για Salt & Pepper θόρυβο.';
    elseif strcmp(noiseType, 'Gaussian noise') && strcmp(filterName, 'Gaussian filter')
        typePart = 'Το Gaussian filter είναι φυσική επιλογή για Gaussian θόρυβο.';
    elseif strcmp(filterName, 'Mean filter')
        typePart = 'Το mean filter εξομαλύνει τον θόρυβο αλλά συχνά θολώνει περισσότερο τις λεπτομέρειες.';
    elseif strcmp(filterName, 'Wiener filter')
        typePart = 'Το Wiener filter προσαρμόζεται στην τοπική διακύμανση της εικόνας.';
    else
        typePart = 'Η καταλληλότητα εξαρτάται από το είδος του θορύβου και τη λεπτομέρεια της εικόνας.';
    end
    commentText = [noisePart, ' ', detailPart, ' ', typePart];
end

function [commentDenoiseThenEnhance, commentEnhanceThenDenoise] = make_pipeline_comments(noiseType, filterName, metricsDenoiseThenEnhance, metricsEnhanceThenDenoise)
    if metricsDenoiseThenEnhance.PSNR >= metricsEnhanceThenDenoise.PSNR
        betterText = 'Η σειρά πρώτα αποθορυβοποίηση και μετά ενίσχυση δίνει καλύτερη ποσοτική προσέγγιση στην καθαρή βελτιωμένη εικόνα.';
    else
        betterText = 'Η σειρά πρώτα ενίσχυση και μετά αποθορυβοποίηση δίνει καλύτερη ποσοτική προσέγγιση στην καθαρή βελτιωμένη εικόνα.';
    end
    commentDenoiseThenEnhance = sprintf('%s Για %s με %s, το PSNR είναι %.2f dB.', betterText, noiseType, filterName, metricsDenoiseThenEnhance.PSNR);
    commentEnhanceThenDenoise = sprintf('%s Για %s με %s, το PSNR είναι %.2f dB.', betterText, noiseType, filterName, metricsEnhanceThenDenoise.PSNR);
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

function make_filter_figure(imageName, outputPrefix, resultsDir, noisyImage, originalImage, meanImage, gaussianImage, medianImage, wienerImage, noiseTitle, figureVisibility)
    hFilter = figure('Name', ['B3D Filters - ', imageName, ' - ', noiseTitle], 'Color', 'w', 'Visible', figureVisibility, 'Position', [45 45 1500 870]);
    add_top_title(hFilter, sprintf('Μέρος Δ - Φίλτρα αποθορυβοποίησης: %s - %s', imageName, noiseTitle));
    filterLayout = tiledlayout(hFilter, 2, 3, 'Padding', 'loose', 'TileSpacing', 'loose');
    filterLayout.Units = 'normalized';
    filterLayout.Position = [0.045 0.055 0.91 0.86];
    show_image_tile(originalImage, 'Original low-light');
    show_image_tile(noisyImage, noiseTitle);
    show_image_tile(meanImage, 'Mean filter');
    show_image_tile(gaussianImage, 'Gaussian filter');
    show_image_tile(medianImage, 'Median filter');
    show_image_tile(wienerImage, 'Wiener filter');
    save_figure_png(hFilter, fullfile(resultsDir, [outputPrefix, '_filters_', make_safe_filename(noiseTitle), '.png']));
    close(hFilter);
end

function make_pipeline_figure(imageName, outputPrefix, resultsDir, idealEnhanced, gaussianNoisy, saltPepperNoisy, figureVisibility)
    gaussianFilter = 'Gaussian filter';
    medianFilter = 'Median filter';
    gaussianDenoiseThenEnhance = enhance_image(apply_filter(gaussianNoisy, gaussianFilter));
    gaussianEnhanceThenDenoise = apply_filter(enhance_image(gaussianNoisy), gaussianFilter);
    saltDenoiseThenEnhance = enhance_image(apply_filter(saltPepperNoisy, medianFilter));
    saltEnhanceThenDenoise = apply_filter(enhance_image(saltPepperNoisy), medianFilter);
    hPipeline = figure('Name', ['B3D Pipelines - ', imageName], 'Color', 'w', 'Visible', figureVisibility, 'Position', [45 45 1500 870]);
    add_top_title(hPipeline, sprintf('Μέρος Δ - Σειρές επεξεργασίας: %s', imageName));
    pipelineLayout = tiledlayout(hPipeline, 2, 3, 'Padding', 'loose', 'TileSpacing', 'loose');
    pipelineLayout.Units = 'normalized';
    pipelineLayout.Position = [0.045 0.055 0.91 0.86];
    show_image_tile(idealEnhanced, 'Clean enhanced reference');
    show_image_tile(gaussianDenoiseThenEnhance, 'Gaussian: denoise -> enhance');
    show_image_tile(gaussianEnhanceThenDenoise, 'Gaussian: enhance -> denoise');
    show_image_tile(idealEnhanced, 'Clean enhanced reference');
    show_image_tile(saltDenoiseThenEnhance, 'S&P: denoise -> enhance');
    show_image_tile(saltEnhanceThenDenoise, 'S&P: enhance -> denoise');
    save_figure_png(hPipeline, fullfile(resultsDir, [outputPrefix, '_pipeline_comparison.png']));
    close(hPipeline);
end

function plot_filter_summary(statsTable, noiseType)
    rows = strcmp(statsTable.NoiseType, noiseType) & strcmp(statsTable.Stage, 'Denoising');
    methods = {'Mean filter', 'Gaussian filter', 'Median filter', 'Wiener filter'};
    hold on;
    for methodIdx = 1:numel(methods)
        methodRows = rows & strcmp(statsTable.Method, methods{methodIdx});
        plot(statsTable.ImageNumber(methodRows), statsTable.PSNR(methodRows), '-o', 'LineWidth', 1.2, 'DisplayName', methods{methodIdx});
    end
    hold off;
    grid on;
    xlabel('Image number');
    ylabel('PSNR (dB)');
    title(noiseType);
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
