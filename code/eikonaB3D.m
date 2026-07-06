clear;
clc;
close all;

% Για να επεξεργαστεί μια εικόνα, το όνομά της πρέπει να τελειώνει σε _low.png.

rng(1);

greekDesktop = char([933 960 959 955 959 947 953 963 964 942 962]);
% Replace with your path
projectDir = fullfile(getenv('USERPROFILE'), 'OneDrive', greekDesktop, 'project');
resultsDir = fullfile(projectDir, 'resultsB3D');
expectedFolderName = 'resultsB3D';

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
        save_image_grid({inputImage, gaussianNoisy, saltPepperNoisy}, {'Original low-light', 'Gaussian noise', 'Salt & Pepper noise'}, sprintf('Part D - Noise: %s', imageFiles(idx).name), fullfile(resultsDir, [outputPrefix, '_noise_comparison.png']));

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
    save_d_summary_image(statsTable, fullfile(resultsDir, 'B3D_summary_statistics.png'));
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

function make_filter_figure(imageName, outputPrefix, resultsDir, noisyImage, originalImage, meanImage, gaussianImage, medianImage, wienerImage, noiseTitle, ~)
    imageList = {originalImage, noisyImage, meanImage, gaussianImage, medianImage, wienerImage};
    titleList = {'Original low-light', noiseTitle, 'Mean filter', 'Gaussian filter', 'Median filter', 'Wiener filter'};
    save_image_grid(imageList, titleList, sprintf('Part D - Filters: %s - %s', imageName, noiseTitle), fullfile(resultsDir, [outputPrefix, '_filters_', make_safe_filename(noiseTitle), '.png']));
end

function make_pipeline_figure(imageName, outputPrefix, resultsDir, idealEnhanced, gaussianNoisy, saltPepperNoisy, ~)
    gaussianFilter = 'Gaussian filter';
    medianFilter = 'Median filter';
    gaussianDenoiseThenEnhance = enhance_image(apply_filter(gaussianNoisy, gaussianFilter));
    gaussianEnhanceThenDenoise = apply_filter(enhance_image(gaussianNoisy), gaussianFilter);
    saltDenoiseThenEnhance = enhance_image(apply_filter(saltPepperNoisy, medianFilter));
    saltEnhanceThenDenoise = apply_filter(enhance_image(saltPepperNoisy), medianFilter);
    imageList = {idealEnhanced, gaussianDenoiseThenEnhance, gaussianEnhanceThenDenoise, idealEnhanced, saltDenoiseThenEnhance, saltEnhanceThenDenoise};
    titleList = {'Clean enhanced', 'Gaussian denoise -> enhance', 'Gaussian enhance -> denoise', 'Clean enhanced', 'S&P denoise -> enhance', 'S&P enhance -> denoise'};
    save_image_grid(imageList, titleList, sprintf('Part D - Processing order: %s', imageName), fullfile(resultsDir, [outputPrefix, '_pipeline_comparison.png']));
end

function save_d_summary_image(statsTable, outputPath)
    canvas = ones(900, 1200, 3);
    if exist('insertText', 'file') == 2
        canvas = insertText(canvas, [285, 18], 'Part D - Denoising filters summary', 'FontSize', 26, 'BoxOpacity', 0, 'TextColor', 'black');
    end
    methods = {'Mean filter', 'Gaussian filter', 'Median filter', 'Wiener filter'};
    canvas = draw_filter_chart(canvas, statsTable, 'Gaussian noise', methods, [45, 85, 1110, 350]);
    canvas = draw_filter_chart(canvas, statsTable, 'Salt & Pepper noise', methods, [45, 505, 1110, 350]);
    imwrite(canvas, outputPath);
end

function canvas = draw_filter_chart(canvas, statsTable, noiseType, methods, rect)
    xSeries = cell(numel(methods), 1);
    ySeries = cell(numel(methods), 1);
    for methodIdx = 1:numel(methods)
        rows = strcmp(statsTable.NoiseType, noiseType) & strcmp(statsTable.Stage, 'Denoising') & strcmp(statsTable.Method, methods{methodIdx});
        [xSeries{methodIdx}, sortIdx] = sort(statsTable.ImageNumber(rows));
        values = statsTable.PSNR(rows);
        ySeries{methodIdx} = values(sortIdx);
    end
    canvas = draw_line_chart(canvas, xSeries, ySeries, methods, noiseType, 'PSNR (dB)', rect);
end

function canvas = draw_line_chart(canvas, xSeries, ySeries, labels, titleText, yLabel, rect)
    colors = [0.12 0.35 0.75; 0.85 0.33 0.10; 0.15 0.55 0.25; 0.55 0.25 0.70; 0.20 0.20 0.20];
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
            legendX = panelLeft + panelWidth - 250;
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
