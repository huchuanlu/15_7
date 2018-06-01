function boxes = computeScores_new(img,cue,params,windows)


if nargin<4
    %no windows provided - so generate them -> single cues
    
    switch cue
    
        case 'MS' %Multi-scale Saliency
            
            xmin = [];
            ymin = [];
            xmax = [];
            ymax = [];
            score = [];
            img = gray2rgb(img); %always have 3 channels
            [height width ~] = size(img);
            
            for sid = 1:length(params.MS.scale) %looping over the scales
                
                scale = params.MS.scale(sid);
                threshold = params.MS.theta(sid);
                min_width = max(2,round(params.min_window_width * scale/width));
                min_height = max(2,round(params.min_window_height * scale/height));
                
                samples = round(params.distribution_windows/(length(params.MS.scale)*3)); %number of samples per channel to be generated
                
                for channel = 1:3 %looping over the channels
                    
                    saliencyMAP = saliencyMapChannel(img,channel,params.MS.filtersize,scale);%compute the saliency map - for the current scale & channel
                    
                    thrmap = saliencyMAP >= threshold;
                    salmap = saliencyMAP .* thrmap;
                    thrmapIntegralImage = computeIntegralImage(thrmap);
                    salmapIntegralImage =  computeIntegralImage(salmap);
                    
                    scoreScale = slidingWindowComputeScore(double(saliencyMAP), scale, min_width, min_height, threshold, salmapIntegralImage, thrmapIntegralImage);%compute all the windows score
                    %keyboard;
                    indexPositives = find(scoreScale>0); %find the index of the windows with positive(>0) score
                    scoreScale = scoreScale(indexPositives);
                                        
                    indexSamples = scoreSampling(scoreScale, samples, 1);%sample from the distribution of the scores
                    scoreScale = scoreScale(indexSamples);                 

                    [xminScale yminScale xmaxScale ymaxScale] = retrieveCoordinates(indexPositives(indexSamples) - 1,scale);%                                        
                    xminScale = xminScale*width/scale;
                    xmaxScale = xmaxScale*width/scale;
                    yminScale = yminScale*height/scale;
                    ymaxScale = ymaxScale*height/scale;
                                        
                    score = [score;scoreScale];
                    xmin = [xmin ;xminScale];
                    ymin = [ymin ;yminScale];
                    xmax = [xmax ;xmaxScale];
                    ymax = [ymax ;ymaxScale];
                    
                end%loop channel
                
            end%loop sid
            
            boxes = [xmin ymin xmax ymax score];
            boxes = boxes(1:params.distribution_windows,:);%might be more than 100.000
            
        case 'CC'
            
            windows = generateWindows(img, 'uniform', params);%generate windows
            boxes = computeScores(img, cue, params, windows);
            
        case 'ED'                       
            
            windows = generateWindows(img, 'dense', params, cue);%generate windows           
            boxes = computeScores(img, cue, params, windows);
            
        case 'SS'
            windows = generateWindows(img,'dense', params, cue);
            boxes = computeScores(img, cue, params, windows);                                
            
        case 'LS' %exemplars - location scale - uniform sampling                                   
            struct = load(params.LS.ExemplarsMatFile,'exemplarsNormalized');            
            windowsNormalized = struct.exemplarsNormalized;
            params.LS.normalizedWindows = 1;
            boxes = computeScores(img, cue, params, windowsNormalized);                        
                               
    end
    
else
    %windows are provided so score them
    switch cue                
            
        case 'CC'                         
            
            [height width ~] = size(img);
            
            imgLAB = rgb2lab(img);%get the img in LAB space
            Q = computeQuantMatrix(imgLAB,params.CC.quant);
            integralHistogram = computeIntegralHistogramMex(double(Q), height, width, prod(params.CC.quant));
            
            xmin = round(windows(:,1));
            ymin = round(windows(:,2));
            xmax = round(windows(:,3));
            ymax = round(windows(:,4));                             
            
            score = computeScoreContrast(double(integralHistogram), height, width, xmin, ymin, xmax, ymax, params.CC.theta, prod(params.CC.quant), size(windows,1));%compute the CC score for the windows                      
            boxes = [windows score];
            
        case 'ED'
                        
            [~, ~, temp] = size(img);                        
            if temp==3
                edgeMap = edge(rgb2gray(img),'canny');%compute the canny map for 3 channel images
            else
                edgeMap = edge(img,'canny');%compute the canny map for grey images
            end            
            
            h = computeIntegralImage(edgeMap);  
            
            xmin = round(windows(:,1));
            ymin = round(windows(:,2));
            xmax = round(windows(:,3));
            ymax = round(windows(:,4));                                                                       
            
            xmaxInner = round((xmax*(200+params.ED.theta)/(params.ED.theta+100) + xmin*params.ED.theta/(params.ED.theta+100)+100/(params.ED.theta+100)-1)/2);
            xminInner  = round(xmax + xmin - xmaxInner);
            ymaxInner = round((ymax*(200+params.ED.theta)/(params.ED.theta+100) + ymin*params.ED.theta/(params.ED.theta+100)+100/(params.ED.theta+100)-1) /2);
            yminInner  = round(ymax + ymin - ymaxInner);            
            
            scoreWindows = computeIntegralImageScores(h,[xmin ymin xmax ymax]);
            scoreInnerWindows = computeIntegralImageScores(h,[xminInner yminInner xmaxInner ymaxInner]);
            areaWindows = (xmax - xmin + 1) .* (ymax - ymin +1);
            areaInnerWindows = (xmaxInner - xminInner + 1) .* (ymaxInner - yminInner + 1);
            areaDiff = areaWindows - areaInnerWindows;
            areaDiff(areaDiff == 0) = inf;
            
            score = ((xmax - xmaxInner + ymax - ymaxInner)/2) .* (scoreWindows - scoreInnerWindows) ./ areaDiff;
            boxes = [windows score];
            
%         case 'SS'
%             
%             currentDir = pwd;            
%             soft_dir = params.SS.soft_dir;
%             basis_sigma = params.SS.basis_sigma;
%             basis_k = params.SS.theta;
%             basis_min_area = params.SS.basis_min_area;            
%             imgType = params.imageType;                                                                                                                 
%             imgBase = tempname(params.tempdir);%find a unique name for a file in params.tempdir                  
%             imgBase = imgBase(length(params.tempdir)+1:end);                                                         
%             imgName = [imgBase '.' imgType];                        
%             cd(params.tempdir);            
%             imwrite(img,imgName,imgType);            
%             segmFileName = [imgBase '_segm.ppm'];    
%             
%             if not(exist(segmFileName,'file'))                
%                 % convert image to ppm
%                 if not(strcmp(imgType, 'ppm'))
%                     cmd = [ 'convert "' imgName '" "' imgBase '.ppm"' ];            
%                     system(cmd);
%                 end                
%                 % setting segmentation params
%                 I = imread([imgBase '.ppm']);
%                 Iarea = size(I,1)*size(I,2);
%                 sf = sqrt(Iarea/(300*200));
%                 sigma = basis_sigma*sf;
%                 min_area = basis_min_area*sf;
%                 k = basis_k;                                            
%                 % segment image                
%                 cmd = [soft_dir '/segment ' num2str(sigma) ' ' num2str(k) ' ' num2str(min_area) ' "' imgBase '.ppm' '" "' segmFileName '"' ];                
%                 system(cmd);                
%                 % delete image ppm
%                 if not(strcmp(imgType, 'ppm'))
%                     delete([imgBase '.ppm']);
%                     delete(imgName);
%                 end                
%                 S = imread(segmFileName);
%                 delete(segmFileName);
%             else    % segmentation file found
%                 S = imread(segmFileName);
%             end         
%             
%             cd(currentDir);            
%             
%             N = numerizeLabels(S);
%             superpixels = segmentArea(N);            
%             
%             integralHist = integralHistSuperpixels(N);                        
%             
%             xmin = round(windows(:,1));
%             ymin = round(windows(:,2));
%             xmax = round(windows(:,3));
%             ymax = round(windows(:,4));
%                                                
%             areaSuperpixels = [superpixels(:).area];
%             areaWindows = (xmax - xmin + 1) .* (ymax - ymin + 1);
%             
%             intersectionSuperpixels = zeros(length(xmin),size(integralHist,3));
%                         
%             for dim = 1:size(integralHist,3)                
%                 intersectionSuperpixels(:,dim) = computeIntegralImageScores(integralHist(:,:,dim),windows);                
%             end
%                                     
%             score = ones(size(windows,1),1) - (sum(min(intersectionSuperpixels,repmat(areaSuperpixels,size(windows,1),1) - intersectionSuperpixels),2)./areaWindows);
%             boxes = [windows score];


        case 'SS'            
       
            basis_sigma = params.SS.basis_sigma;
            basis_k = params.SS.theta;
            basis_min_area = params.SS.basis_min_area;            

            I = img;
            Iarea = size(I,1)*size(I,2);
            sf = sqrt(Iarea/(300*200));
            sigma = basis_sigma*sf;
            min_area = basis_min_area*sf;
            k = basis_k;
            
            S = segmentmex(I,sigma,k,min_area);
         
            [~,~,S] = unique(S);
            S = reshape(S,size(I,1),size(I,2));
            superpixels = segmentArea(S);            
            
            integralHist = integralHistSuperpixels(S);                        
            
            xmin = round(windows(:,1));
            ymin = round(windows(:,2));
            xmax = round(windows(:,3));
            ymax = round(windows(:,4));
                                               
            areaSuperpixels = [superpixels(:).area];
            areaWindows = (xmax - xmin + 1) .* (ymax - ymin + 1);
            
            intersectionSuperpixels = zeros(length(xmin),size(integralHist,3));
                        
            for dim = 1:size(integralHist,3)                
                intersectionSuperpixels(:,dim) = computeIntegralImageScores(integralHist(:,:,dim),windows);                
            end
                                    
            score = ones(size(windows,1),1) - (sum(min(intersectionSuperpixels,repmat(areaSuperpixels,size(windows,1),1) - intersectionSuperpixels),2)./areaWindows);
            boxes = [windows score];








            
        case 'LS' %location scale - uniform sampling                           
            if params.LS.normalizedWindows == 0
               %normalize the windows
               imgSize = size(img);
               hImg = imgSize(1);%height of the img    
               wImg = imgSize(2);%width  of the img
               hRF = params.LS.referenceFrame(1);%height of the RF - 100
               wRF = params.LS.referenceFrame(2);%width  of the RF - 100
               normVector = [wRF hRF wRF hRF] ./ [wImg hImg wImg hImg];            
               windows = windows .* repmat(normVector,size(windows,1),1);
               windows(:,1) = min(max(1,windows(:,1)),100);
               windows(:,2) = max(min(100,windows(:,2)),1);
               windows(:,3) = min(max(1,windows(:,3)),100);
               windows(:,4) = max(min(100,windows(:,4)),1);               
            end
            normWindows = windows;
            
            %unnormalize windows
            imgSize = size(img);    
            hImg = imgSize(1);%height of the img    
            wImg = imgSize(2);%width  of the img
            hRF = params.LS.referenceFrame(1);%height of the RF - 100
            wRF = params.LS.referenceFrame(2);%width  of the RF - 100
            unnormVector = [wImg hImg wImg hImg] ./ [wRF hRF wRF hRF];
            windows = windows .* repmat(unnormVector,size(windows,1),1);
            
            struct = load(['density' num2str(params.LS.kNN) 'NN.mat'],'density');
            densityWindows4D = struct.density;
            
            scores = zeros(size(windows,1),1);
            
            for widx = 1:size(normWindows,1)
                currentWindow = normWindows(widx,:);                
                Xc = ceil(0.5*(currentWindow(1)+currentWindow(3)));%X centre
                Yc = ceil(0.5*(currentWindow(2)+currentWindow(4)));%Y centre
                W  = min(ceil(currentWindow(3)-currentWindow(1)+1),100);%width
                H  = min(ceil(currentWindow(4)-currentWindow(2)+1),100);%height
                scores(widx) = densityWindows4D(Xc,Yc,W,H);
            end           
            boxes = [windows scores];
            
        otherwise
            error('Option not known: check the cue names');            
    end
end

end



function saliencyMAP = saliencyMapChannel(inImg,channel,filtersize,scale)

inImg = im2double(inImg(:,:,channel));
inImg = imresize(inImg,[scale,scale],'bilinear');

%Spectral Residual
myFFT = fft2(inImg);
myLogAmplitude = log(abs(myFFT));
myPhase = angle(myFFT);
mySmooth = imfilter(myLogAmplitude,fspecial('average',filtersize),'replicate');
mySpectralResidual = myLogAmplitude-mySmooth;
saliencyMAP = abs(ifft2(exp(mySpectralResidual+1i*myPhase))).^2;

%After Effect
saliencyMAP = imfilter(saliencyMAP,fspecial('disk',filtersize));
saliencyMAP = mat2gray(saliencyMAP);
end