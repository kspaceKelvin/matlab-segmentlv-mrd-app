%% Check required licenses
if ~license('test', 'video_and_image_blockset')
    error("Could not find valid license for Computer Vision Toolbox")
end

if ~license('test', 'Image_Toolbox')
    error("Could not find valid license for Image Processing Toolbox")
end

if ~license('test', 'Neural_Network_Toolbox')
    error("Could not find valid license for Deep Learning Toolbox")
end

%% Download pre-trained network from MathWorks
modelzipfile = "pretrainedLeftVentricleSegmentation.zip";
modelfile = "pretrainedLeftVentricleSegmentationModel.mat";
if ~exist(modelfile, "file")
    if ~exist(modelzipfile, "file")
        disp("Downloading model file...")
        websave(modelzipfile, "https://ssd.mathworks.com/supportfiles/medical/pretrainedLeftVentricleSegmentation.zip")
    end
    unzip(modelzipfile);
    disp('Done')
else
    disp("Model file already downloaded")
end

%% Download images from MathWorks
datazipfile = "CardiacMRI.zip";
datafolder = "Cardiac MRI";
if ~exist(datafolder, "dir")
    if ~exist(datazipfile, "file")
        disp("Downloading example images...")
        websave(datazipfile, "https://ssd.mathworks.com/supportfiles/medical/CardiacMRI.zip")
    end
    unzip(datazipfile);
    disp('Done')
else
    disp("Example images already downloaded")
end

%% Load pre-trained model into memory
net = load("pretrainedLeftVentricleSegmentationModel.mat");

%% Load example image and segment
% Load image
filepath = pwd;
imageDir = fullfile(filepath,"Cardiac MRI");
testImg = dicomread(fullfile(imageDir,"images","SC-HF-I-01","SC-HF-I-01_rawdcm_099.dcm"));

% Call segmentation
rois = SegmentSAX(testImg, net.trainedNet);

% Show result
figure
imagesc(testImg), hold on
for iRoi = 1:numel(rois)
    plot(rois{iRoi}(:,2), rois{iRoi}(:,1), 'g', 'LineWidth', 2);
end
axis image
colormap(gray)