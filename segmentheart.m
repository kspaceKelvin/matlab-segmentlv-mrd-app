classdef segmentheart < handle
    % Linting warning suppression:
    %#ok<*INUSD>  Input argument '' might be unused.  If this is OK, consider replacing it by ~
    %#ok<*NASGU>  The value assigned to variable '' might be unused.
    %#ok<*INUSL>  Input argument '' might be unused, although a later one is used.  Ronsider replacing it by ~
    %#ok<*AGROW>  The variable '' appear to change in size on every loop  iteration. Consider preallocating for speed.

    properties
        trainedNet = [];
    end

    methods
        function obj = segmentheart()
            disp("Loading pre-trained LV segmentation model...")
            t = tic;
            net = load("pretrainedLeftVentricleSegmentationModel.mat");
            obj.trainedNet = net.trainedNet;
            fprintf("Completed in %.1f seconds...\n", toc(t));
        end

        function process(obj, connection, config, metadata, logging)
            % logging.info('Config: \n%s', config);

            % Metadata should be MRD formatted header, but may be a string
            % if it failed conversion earlier
            try
                logging.info("Incoming dataset contains %d encodings", numel(metadata.encoding))
                % logging.info("First encoding is of type '%s', with field of view of (%g x %g x %g)mm^3, matrix size of (%g x %g x %g), and %g coils", ...
                %     metadata.encoding(1).trajectory, ...
                %     metadata.encoding(1).encodedSpace.fieldOfView_mm.x, ...
                %     metadata.encoding(1).encodedSpace.fieldOfView_mm.y, ...
                %     metadata.encoding(1).encodedSpace.fieldOfView_mm.z, ...
                %     metadata.encoding(1).encodedSpace.matrixSize.x, ...
                %     metadata.encoding(1).encodedSpace.matrixSize.y, ...
                %     metadata.encoding(1).encodedSpace.matrixSize.z, ...
                %     metadata.acquisitionSystemInformation.receiverChannels)

                strEncoding = sprintf("First encoding is of type '%s', with field of view of (%g x %g x %g)mm^3, matrix size of (%g x %g x %g)", ...
                    metadata.encoding(1).trajectory, ...
                    metadata.encoding(1).encodedSpace.fieldOfView_mm.x, ...
                    metadata.encoding(1).encodedSpace.fieldOfView_mm.y, ...
                    metadata.encoding(1).encodedSpace.fieldOfView_mm.z, ...
                    metadata.encoding(1).encodedSpace.matrixSize.x, ...
                    metadata.encoding(1).encodedSpace.matrixSize.y, ...
                    metadata.encoding(1).encodedSpace.matrixSize.z);
                if isfield(metadata.acquisitionSystemInformation, 'receiverChannels')
                    strEncoding = [strEncoding sprintf(", and %g coils", metadata.acquisitionSystemInformation.receiverChannels)];
                end
            catch
                logging.info("Improperly formatted metadata: \n%s", metadata)
            end

            % Continuously parse incoming data parsed from MRD messages
            imgGroup = cell(1,0); % ismrmrd.Image;
            try
                while true
                    item = next(connection);

                    % ----------------------------------------------------------
                    % Raw k-space data messages
                    % ----------------------------------------------------------
                    if isa(item, 'ismrmrd.Acquisition')
                        error('Raw data is not supported by this module')

                    % ----------------------------------------------------------
                    % Image data messages
                    % ----------------------------------------------------------
                    elseif isa(item, 'ismrmrd.Image')
                        % Only process magnitude images -- send phase images back without modification
                        if (item.head.image_type == item.head.IMAGE_TYPE.MAGNITUDE)
                            imgGroup{end+1} = item;
                        else
                            connection.send_image(item);
                            continue
                        end

                        % When this criteria is met, run process_group() on the accumulated
                        % data, which returns images that are sent back to the client.
                        % TODO: logic for grouping images
                        if false
                            logging.info("Processing a group of images")
                            image = obj.process_images(imgGroup, config, metadata, logging);
                            logging.debug("Sending image to client")
                            connection.send_image(image);
                            imgGroup = cell(1,0);
                        end

                    elseif isempty(item)
                        break;

                    else
                        logging.error("Unhandled data type: %s", class(item))
                    end
                end
            catch ME
                logging.error(sprintf('%s\nError in %s (%s) (line %d)', ME.message, ME.stack(1).('name'), ME.stack(1).('file'), ME.stack(1).('line')));
            end

            % Process any remaining groups of image data.  This can 
            % happen if the trigger condition for these groups are not met.
            % This is also a fallback for handling image data, as the last
            % image in a series is typically not separately flagged.
            if ~isempty(imgGroup)
                logging.info("Processing a group of images (untriggered)")
                image = obj.process_images(imgGroup, config, metadata, logging);
                logging.debug("Sending image to client")
                connection.send_image(image);
                imgGroup = cell(1,0);
            end

            connection.send_close();
            return
        end

        function images = process_images(obj, group, config, metadata, logging)
            % Extract image data
            cData = cellfun(@(x) x.data, group, 'UniformOutput', false);
            data = cat(3, cData{:});

            % % Normalize and convert to short (int16)
            % data = data .* (32767./max(data(:)));
            % data = int16(round(data));
            % 
            % % Invert image contrast
            % data = int16(abs(32767-data));

            % Re-slice back into 2D MRD images
            images = cell(1, size(data,3));
            for iImg = 1:size(data,3)
                % Create MRD Image object, set image data and (matrix_size, channels, and data_type) in header
                image = ismrmrd.Image(data(:,:,iImg));

                t = tic;
                boundaries = SegmentSAX(data(:,:,iImg)', obj.trainedNet);

                % Remove small ROIs
                areaThreshold = 5;
                boundAreas = cellfun(@(x) polyarea(x(:,1), x(:,2)), boundaries');
                strRemovedRoi = "";
                if any(boundAreas < areaThreshold)
                    strRemovedRoi = sprintf(" (removed %d ROIs smaller than %d pixels)", sum(boundAreas < areaThreshold), areaThreshold);
                    boundaries((boundAreas < areaThreshold)) = [];
                end

                if numel(boundaries) > 0
                    strBoundaries = sprintf("Image %g/%g: Detected %g LV SAX ROIs in %.1fs with areas: %s", iImg, size(data,3), numel(boundaries), toc(t), sprintf('%.1f, ', cellfun(@(x) polyarea(x(:,1), x(:,2)), boundaries')));
                    strBoundaries = strBoundaries{1}(1:end-2);
                    strBoundaries = [strBoundaries strRemovedRoi{1}];
                else
                    strBoundaries = sprintf("Image %g/%g: Did not detect any LV SAX ROIs%s in %.1fs", iImg, size(data,3), strRemovedRoi, toc(t));
                end
                logging.info(strBoundaries)

                % Copy original image header, but keep the new data_type and channels
                newHead = image.head;
                image.head = group{iImg}.head;
                image.head.data_type = newHead.data_type;
                image.head.channels  = newHead.channels;

                % Add to ImageProcessingHistory
                meta = ismrmrd.Meta.deserialize(group{iImg}.attribute_string);
                meta = ismrmrd.Meta.appendValue(meta, 'ImageProcessingHistory', 'INVERT');
                meta.Keep_image_geometry = 1;
                
                % Add detected LV ROIs
                for i = 1:numel(boundaries)
                    meta.(sprintf('ROI_LV_%g', i)) = create_roi(boundaries{i}(:,2), boundaries{i}(:,1));
                end

                image = image.set_attribute_string(ismrmrd.Meta.serialize(meta));

                images{iImg} = image;
            end
        end
    end
end
