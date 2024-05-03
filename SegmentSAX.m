function boundaries = SegmentSAX(img, trainedNet)
    % Segment the left ventricle from MRI cines
    % https://www.mathworks.com/help/medical-imaging/ug/cardiac-left-ventricle-segmentation-from-cine-mri-images.html
    %
    %     Input:
    %         - img        : A 2D image
    %         - trainedNet : Pre-trained U-net from pretrainedLeftVentricleSegmentationModel.mat
    %     Output:
    %         - boundaries : 1 x n cell array, with each entry being a polygonal ROI boundaries of the detected regions

    % Pre-process
    if ~ismatrix(img)
        error('Only 2D data supported')
    end

    % Zero-pad to make square
    sz = size(img(:,:,1));
    padSize = max(sz)*[1 1] - sz;
    img = padarray(img,floor(padSize/2),'pre');
    img = padarray(img,ceil( padSize/2),'post');

    % Resize to match training data
    targetSize = [256 256 3];
    img = imresize(img,targetSize(1:2));

    if size(img,3) == 1
        img = repmat(img,[1 1 targetSize(3)]);
    end

    % Segment image
    segmentedImg = semanticseg(img, trainedNet);

    % Convert mask to poly
    lvMask = (segmentedImg == 'LeftVentricle');
    boundaries = bwboundaries(lvMask);

    % Un-pre-process ROIs back to original image dimensions
    scaleFactor = size(img,1)/max(sz);
    shiftFactor = floor(padSize/2);

    for i = 1:numel(boundaries)
        boundaries{i} = boundaries{i}/scaleFactor - shiftFactor;
    end
end