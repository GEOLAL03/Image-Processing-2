# Image Processing

Repository για το Θέμα 3: βελτίωση εικόνων χαμηλού φωτισμού.

## Σημείωση

Για σωστή λειτουργεία πρέπει να τροποποιηθεί η μεταβλητή projectDir στην αρχή του κάθε κώδικα MATLAB.

Ο φάκελος που δείχνει το projectDir πρέπει να περιέχει:

- αριθμός_low.png για τις εικόνες χαμηλού φωτισμού
- αριθμός_high.png για τις αντίστοιχες φωτεινές εικόνες αναφοράς

Οι φάκελοι αποτελεσμάτων δημιουργούνται αυτόματα από τα scripts σε νέους φακέλους μέσα στον φάκελο που έχει οριστεί.

## Requirements

- MATLAB
- Image Processing Toolbox
- Signal Processing Toolbox

## MATLAB scripts

- eikonaB3A.m: ανάλυση εικόνων χαμηλού φωτισμού, grayscale, ιστογράμματα και στατιστικά.
- eikonaB3B.m: linear stretching, gamma correction και logarithmic transformation.
- eikonaB3C.m: global histogram equalization, CDF και CLAHE.
- eikonaB3D.m: προσθήκη θορύβου, φίλτρα αποθορυβοποίησης και σύγκριση σειράς επεξεργασίας.
- eikonaB3E.m: Laplacian sharpening και unsharp masking.
- eikonaB3FGH.m: πλήρη pipelines, Retinex, ποσοτική αξιολόγηση και edge detection.

## Repository structure

- Κώδικας: όλα τα MATLAB scripts.
- input_images/: ζεύγη *_low.png και *_high.png.
- results/by_image/: αποτελέσματα χωρισμένα ανά εικόνα.
- results/by_part/: συγκεντρωτικά αποτελέσματα ανά μέρος της άσκησης.

## Παραγόμενα αποτελέσματα

Τα scripts δημιουργούν:

- επεξεργασμένες εικόνες,
- συγκριτικά figures,
- CSV αρχεία με πλήρεις μετρικές,
- TXT αρχεία με σύντομα σχόλια και βασικές μετρικές,
- summary γραφήματα.

