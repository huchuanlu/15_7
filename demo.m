% code (release version) of the Label Propagation Saliency published
% in the IEEE Transactions on Image Processing, 2015.

clc;
close all; clear;
addpath('./utility');
addpath('./feature_affmat');
addpath('./lps');
addpath('./objectness_release_v2.3');
global para row col dim superpixels spnum w

%% Setup
para.scale1 = 10;           % scale = 1/(sigma^2), weight matrix; Lab
para.scale2 = 10;           % for gradient
para.about = '205';
para.compactness = '20';
para.k = 2;                 % k=1 or k=2, regular graph
para.constraint = 1;        % constraint=1 or 0
para.drop = 0.3;            % delete some boundary labels
para.pos = 150;
para.neg = 2;
para.compactThres = 1.6;    % classify initial maps
para.numberSamples = 1000;  % objectness
para.thres = 0.8;
alpha = 0.6;
beta = 0.4;
para.k1 = 1/5;
para.k2 = 1/100;
cue_num = 3;                % in the release version, the cue LS is disabled.

in_path = './image/*.jpg';
out_path = './result/';
mkdir(out_path);
pic_dir = dir(in_path);

%% Main Algorithm
for k = 1:length(pic_dir)
    
    fprintf('Processing #%d image... \n', k);
    name = pic_dir(k).name;
    ori_im = imread([in_path(1:end-5) name]);
    [im,w] = removeframe(ori_im);
    [row, col, dim] = size(im);
    im_double = double(im);
    % a fast implementation of SLIC
    ImgVecR = reshape( im_double(:,:,1)', row*col, 1);
    ImgVecG = reshape( im_double(:,:,2)', row*col, 1);
    ImgVecB = reshape( im_double(:,:,3)', row*col, 1);
    ImgProp = [row, col, str2double(para.about), str2double(para.compactness), row*col];
    [ raw_label, ~, ~, ~, spnum ] = SLIC(ImgVecR,ImgVecG,ImgVecB,ImgProp);
    label = reshape(raw_label, col, row);
    superpixels = label' + 1;
    % end of fast SLIC
    
    reg_prop = regionprops(superpixels);
    % range 0:1
    im = im2double(im);
    % extract features based on regions (superpixels)
    [ feature, bound_ind_temp ] = extract_feat_( im );
    [ P_Lab, W_Lab, adjloop ] = CalP_( feature(:,1:3), para.scale1, 0 );
    
    % drop some boundary nodes
    W_Lab = full(W_Lab);
    W_Lab_bound = W_Lab(bound_ind_temp,bound_ind_temp);
    Aff_bound = sum( W_Lab_bound, 2 );
    [~,ind] = sort(Aff_bound);
    new = ind( floor(para.drop*length(bound_ind_temp)):end );
    bound_ind = bound_ind_temp(new);
    
    %% Label Propagation
    sim = simNewRank_([], bound_ind, P_Lab);
    SIM = 1 - normVector_(sim,0);
    score = compact_(reg_prop, SIM);     % eqn.6 in the paper
    
    if score >= para.compactThres
        fprintf('Compact score is %f \n', score);
        % Implement objectness, see parameters in 'objectMap_'.
        % objMap: [0,1]
        [objMap, ~] = objectMap_( im, para.numberSamples, cue_num );      
        regObj = zeros(spnum,1);
        for i = 1:spnum
            temp1 = (superpixels==i);
            temp2 = sum(sum(temp1.*objMap));
            regObj(i) = temp2/reg_prop(i).Area;
        end
        regObj = normVector_(regObj,0);
        label = regObj > para.thres;
        obj_ind = find(label == 1);
        [sim1, sim2] = coTrans_v2_(obj_ind, bound_ind, P_Lab);
        SIM1 = 1 - normVector_(sim1,0);
        SIM2 = normVector_(sim2,0);
        temp = alpha*SIM1 + beta*SIM2;
        SIM = normVector_(temp,0);
    end
    
    % the final saliency map
    pixel_map = pixel_refine_v1_( feature, reg_prop, adjloop, im, SIM); % [0,1]
    pixel_map_final = uint8(pixel_map*255);
    final = uint8(zeros(w(1), w(2)));
    final(w(3):w(4), w(5):w(6)) = pixel_map_final;
    imwrite(final, [out_path name(1:end-4) '_LPS.png']);
       
end
disp('Done! cheers!');


