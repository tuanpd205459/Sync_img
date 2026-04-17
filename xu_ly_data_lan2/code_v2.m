clc; clear; close all;

%% =========================================================================
%  1. CẤU HÌNH THAM SỐ TỔNG (PARAMETERS CONFIGURATION)
% =========================================================================
cfg.defaultFolder = 'C:\Users\admin\Máy tính\sync_img_github\Sync_img\data_14_4_2026\mau2_30x\sau_lam_sach_Copy';
% Tham số Tiền xử lý & Nhị phân
cfg.gaussSigma       = 1;     % Độ làm mượt ảnh
cfg.sensCoef         = 0.65;   % Hệ số nhạy adaptive threshold
cfg.neighborhoodSize = 51;    % Kích thước vùng lân cận (phải là số lẻ)
% Tham số Skeleton & Làm sạch
cfg.minBranchLen1    = 8;     % Xóa nhánh cụt (bước 1)
cfg.minBranchLen2    = 30;    % Xóa nhánh cụt (bước 2 - sau khi clear branchpoints)
cfg.hBridgeMinLen    = 31;    % Ngưỡng độ dài tháo khớp H-Bridge
cfg.hBridgeRadius    = 4;     % Bán kính dãn nở tìm điểm nút
% BẢNG THAM SỐ NỐI VÂN
cfg.connectParams = [
    12,  6, cosd(15);  
    12, 12, cosd(15);  
    12, 25, cosd(30);  
     5, 50, cosd(40);  
    20, 50, cosd(15);  
    20, 50, cosd(30);  
    20, 50, cosd(30);  
    20, 60, cosd(80)   
];
% Tham số nối biên & Crop
cfg.borderMargin     = 30;
cfg.borderExtLen     = 30;
cfg.cropOffset       = 5;
cfg.finalOffset      = 7;

%% =========================================================================
%  2. ĐỌC NHIỀU FILE VÀ TẠO VÒNG LẶP (BATCH PROCESSING)
% =========================================================================
% Cho phép chọn nhiều file cùng lúc ('MultiSelect', 'on')
[filenames, folderPath] = uigetfile({'*.bmp;*.png;*.jpg'}, 'Chọn các file ảnh (có thể bôi đen chọn nhiều file)', cfg.defaultFolder, 'MultiSelect', 'on');
if isequal(filenames, 0)
    disp('Bạn đã hủy. Dừng chương trình.'); return;
end

% Nếu chỉ chọn 1 file, filenames là chuỗi -> Chuyển thành cell array
if ischar(filenames)
    filenames = {filenames};
end

numFiles = length(filenames);
fprintf('Đã chọn %d file data để xử lý.\n', numFiles);

% Biến cờ để lưu tọa độ Crop của ảnh đầu tiên
savedCrop = false; 
fourierCoords = []; % <--- Thêm dòng này để chuẩn bị lưu tọa độ phổ

%% BẮT ĐẦU VÒNG LẶP CHO TỪNG FILE
for imgIdx = 1:numFiles
    imgPath = fullfile(folderPath, filenames{imgIdx});
    fprintf('\n======================================================\n');
    fprintf('ĐANG XỬ LÝ FILE %d/%d: %s\n', imgIdx, numFiles, filenames{imgIdx});
    
    % Đọc và xoay ảnh
    hologram_original = imread(imgPath);
    if size(hologram_original, 3) == 3
        hologram_original = rgb2gray(hologram_original);
    end
    hologram_original = rot90(hologram_original, 1);
    
    %% =========================================================================
    %  [MỚI] CẮT ẢNH NGAY TỪ BAN ĐẦU (CROP INITIALIZATION)
    % =========================================================================
    % Nếu chưa có tọa độ (ảnh đầu tiên), yêu cầu người dùng vẽ
    if ~savedCrop
        disp('Vui lòng chọn vùng ảnh trên cửa sổ (Draw Rectangle)...');
        figCrop = figure; 
        imshow(hologram_original, []); 
        title('Vẽ khung chữ nhật để chọn vùng crop (Áp dụng cho toàn bộ file sau)');
        
        [~, xRec, yRec, widthRec, heightRec] = myDrawRec();
        
        % Kiểm tra nếu cửa sổ vẫn còn mở thì mới đóng
        if ishandle(figCrop)
            close(figCrop);
        end
        savedCrop = true; % Bật cờ để các ảnh sau không cần vẽ lại
    else
        disp('Đang tự động áp dụng khung cắt đã chọn từ ảnh đầu tiên...');
    end
    
    % Cắt trực tiếp trên ảnh gốc
    hologram_original = hologram_original(yRec : yRec + heightRec - 1, xRec : xRec + widthRec - 1);
    hologram = hologram_original;
    
    %% =========================================================================
    %  3. TIỀN XỬ LÝ, NHỊ PHÂN HÓA VÀ TRÍCH XUẤT XƯƠNG
    % =========================================================================
    % Lọc nhiễu và cân bằng sáng (trên ảnh đã crop)
    hologram = imgaussfilt(hologram, cfg.gaussSigma);
    hologram = adapthisteq(hologram);

    disp('Đang thực hiện Binarize và Skeletonize...');
    T = adaptthresh(hologram, cfg.sensCoef, 'NeighborhoodSize', [cfg.neighborhoodSize cfg.neighborhoodSize], 'Statistic', 'median');
    BW = imbinarize(hologram, T);
    
    % Open và bóc tách
    BW = imopen(BW, strel('disk', 1));
    BW = bwskel(BW, 'MinBranchLength', cfg.minBranchLen1);
    
    % Xử lý cắt điểm gần và fill holes
    BW = bwskel(BW, 'MinBranchLength', cfg.minBranchLen2);
    BW = bwfill(BW, 'holes');
    BW = bwskel(BW, 'MinBranchLength', cfg.minBranchLen2);
    
    % Ngắt kết nối H-Bridge
    B  = imdilate(bwmorph(BW, 'branchpoints'), strel('disk', cfg.hBridgeRadius));
    BW = BW & ~B; % Tháo khớp
    BW = bwareaopen(BW, cfg.hBridgeMinLen); % Lọc nhiễu
    BW = bwskel(BW, 'MinBranchLength', cfg.hBridgeMinLen);
    BW = BW | B;  % Lắp lại
    BW = bwmorph(BW, 'thin', Inf);
    
    % Tìm branchpoint và cắt
    BP = bwmorph(BW, 'branchpoints');
    BW = BW & ~BP;
    % Loại bỏ đoạn ngắn (đường nối nhỏ)
    BW = bwareaopen(BW, cfg.hBridgeMinLen);
    % Phình nhẹ 1 pixel để nối lại vân lớn
    BW = imdilate(BW, strel('disk', 1));
    % Skeleton lại (thin lại)
    BW = bwskel(BW);
    
    %% =========================================================================
    %  4. THUẬT TOÁN NỐI VÂN LIÊN TỤC (ITERATIVE FRINGE CONNECTION)
    % =========================================================================
    disp('Đang thực hiện nối các vân đứt gãy...');
    BW = bwmorph(BW, "bridge", Inf);
    BW = bwmorph(BW, "diag", Inf);
    BW = bwmorph(BW, "skeleton", Inf);
    BW = bwmorph(BW, 'spur', 2);
    numIterations = size(cfg.connectParams, 1);
    
    for count = 1:numIterations
        endPoints = bwmorph(BW, 'endpoints');
        vectors = fitEndpointVectors(BW, endPoints, 20); % Dùng 20 pixel fit PCA
        
        % Lấy tham số cấu hình cho vòng lặp hiện tại
        minCompSize = cfg.connectParams(count, 1);
        maxDist     = cfg.connectParams(count, 2);
        vecAlignThr = cfg.connectParams(count, 3);
        
        CC = bwconncomp(BW, 8);
        [BW, ~] = connectEndpoints(BW, vectors, CC, minCompSize, maxDist, vecAlignThr);
    end
    
    % Nối ở biên
    endPoints = bwmorph(BW, 'endpoints');
    vectors = fitEndpointVectors(BW, endPoints, 12);
    BW = extendLineNearBorder(BW, vectors, cfg.borderExtLen, cfg.borderMargin);
    
    %% =========================================================================
    %  5. HIỂN THỊ KẾT QUẢ VÀ ÁP DỤNG OFFSET CẠNH CHỐNG NHIỄU BIÊN
    % =========================================================================
    % Hiển thị vùng BW 
    figure;
    imshow(BW, []);
    title(sprintf('BW sau khi xử lý - File %d', imgIdx));

    %%
    % 1. Tìm và tách các branch points ra khỏi skeleton
    BP = bwmorph(BW, 'branchpoints');
    BP = imdilate(BP, strel('disk', 2));

    BW = BW & ~BP;
    % 2. Giữ lại các nhánh có chiều dài >= 20 pixel (thay thế hoàn toàn CC và vòng lặp for)
    BW = bwareaopen(BW, 20);
    BP = bwmorph(BW, 'branchpoints');
    BW = BW & ~BP;
 

    % Áp dụng Offset cạnh (Bỏ phần viền sát mép sau khi xử lý để tránh artifacts)
    BW = BW(cfg.cropOffset : end - cfg.cropOffset + 1, cfg.cropOffset : end - cfg.cropOffset + 1);
    
    %% =========================================================================
    %  6. TÁI TẠO VÀ UNWRAP PHASE (PHASE RECONSTRUCTION)
    % =========================================================================
    disp('Đang tái tạo pha...');
    [~, labels, hologram] = assign_fringe_order_v5(BW, true);
    [phi_est, ~] = reconSurface_linearPushed(hologram, labels, 632.8e-9, 'None', false);
    
    % Cắt biên cho phi_est
    phi_est = phi_est(5:end-5, 5:end-5);
    phi_est = phi_est - min(phi_est(:));
    
    % Tái tạo pha: Chỉ yêu cầu chọn phổ ở file đầu tiên, các file sau tự động cắt
    [wrapped_phase, fourierCoords] = reconstruct_phase_interactively_v2(hologram, fourierCoords);

    [hologram_original_cropped, hologram] = crop_multiple_to_smallest(hologram_original, hologram);
    [phi_est, wrapped_phase] = crop_multiple_to_smallest(phi_est, wrapped_phase);
    
    % Unwrap Phase
    [finalUnwrappedPhase, ~] = unwrapUsingEstimate(phi_est, wrapped_phase);
    
    % Cắt biên hiển thị (Refine artifacts points)
    finalUnwrappedPhase = finalUnwrappedPhase(cfg.finalOffset+1 : end-cfg.finalOffset, ...
                                              cfg.finalOffset+1 : end-cfg.finalOffset);
    
    % Hiển thị kết quả 3D
    figure; surf(finalUnwrappedPhase, "EdgeColor", "none"); 
    title(sprintf('Ảnh Final Unwrapped Phase - File %d', imgIdx)); colormap jet;
    
    disp(['Hoàn thành trích xuất pha cho ảnh: ', filenames{imgIdx}]);

    %% LOẠI BỎ PHA NGHIÊNG (TILT REMOVAL) BẰNG LEAST SQUARES
    % ========================================================
    [M, N] = size(finalUnwrappedPhase);
    [X, Y] = meshgrid(1:N, 1:M);
    
    % Dàn phẳng ma trận thành vector để tính toán
    x_col = X(:);
    y_col = Y(:);
    z_col = finalUnwrappedPhase(:);
    
    % Lọc các điểm hợp lệ (Phòng trường hợp ảnh có mask nền chứa NaN/Inf)
    valid_idx = ~isnan(z_col) & ~isinf(z_col);
    
    % Lập ma trận thiết kế cho hệ phương trình mặt phẳng: Z = a*X + b*Y + c
    A = [x_col(valid_idx), y_col(valid_idx), ones(sum(valid_idx), 1)];
    
    % Giải nghiệm hệ số [a; b; c] bằng ma trận giả nghịch đảo
    coeffs = A \ z_col(valid_idx); 
    
    % Tái tạo lại mặt phẳng pha nghiêng (Tilt plane)
    tilt_plane = coeffs(1)*X + coeffs(2)*Y + coeffs(3);
    
    % Trừ đi pha nghiêng khỏi pha gốc
    phase_no_tilt = finalUnwrappedPhase - tilt_plane;
    
    % Hiển thị kết quả sau khi san phẳng
    figure; surf(phase_no_tilt, "EdgeColor", "none"); 
    title(sprintf('Ảnh sau khi loại bỏ Tilt - File %d', imgIdx)); 
    colormap jet;
    % ========================================================
end

disp('==== ĐÃ XỬ LÝ XONG TOÀN BỘ DATA ====');





function [BW_new, linesConnected] = connectEndpoints(BW, vectors, CC, minCompSize, maxDist, vecAlignThr)
% BW           : skeleton binary
% vectors      : [cx cy vx vy] từ hàm computeEndpointVectors
% CC           : bwconncomp(BW,8)
% minCompSize  : kích thước tối thiểu của vân
% maxDist      : khoảng cách tối đa cho phép nối
% vecAlignThr  : ngưỡng cos(angle) hướng (ví dụ 0.7 ~ >45°)

BW_new = BW; % copy để cập nhật nối
linesConnected = {}; % cell lưu danh sách các đoạn đã nối

for i = 1:size(vectors,1)-1
    cx1 = vectors(i,1); cy1 = vectors(i,2);
    v1  = [vectors(i,3), vectors(i,4)];
    
    % kiểm tra component của endpoint i
    comp_id1 = findComponent(CC, [cy1,cx1]);
    if comp_id1==0 || numel(CC.PixelIdxList{comp_id1}) < minCompSize
        continue;
    end
    
    for j = i+1:size(vectors,1)
        cx2 = vectors(j,1); cy2 = vectors(j,2);
        v2  = [vectors(j,3), vectors(j,4)];

        % kiểm tra component j
        comp_id2 = findComponent(CC, [cy2,cx2]);
        if comp_id2==0 || numel(CC.PixelIdxList{comp_id2}) < minCompSize
            continue;
        end
        
        % --- khoảng cách Euclidean giữa 2 endpoint ---
        d = hypot(cx1-cx2, cy1-cy2);
        if d > maxDist, continue; end

        % --- kiểm tra hướng vector (cùng hướng nối) ---
        dir12 = [cx2-cx1, cy2-cy1];
        dir12 = dir12 / (norm(dir12)+eps);

        cond1 = dot(v1, dir12) > vecAlignThr;    % v1 hướng về P2
        cond2 = dot(v2, -dir12) > vecAlignThr;   % v2 hướng về P1

        if ~(cond1 && cond2), continue; end

        % --- kiểm tra thêm khoảng cách vuông góc ---
        % đường thẳng qua P2 với vector v2
        a = -v2(2);
        b =  v2(1);
        c =  v2(2)*cx2 - v2(1)*cy2;
        d_perp = abs(a*cx1 + b*cy1 + c) / sqrt(a^2 + b^2);

        if d_perp > 5, continue; end

        % --- nối 2 endpoint ---
        [BW_new, linePixels] = drawLine(BW_new, cx1, cy1, cx2, cy2);
        linesConnected{end+1} = linePixels; %#ok<AGROW>
    end
end
end
function vectors = fitEndpointVectors(BW, endPoints, Nfit)
% fitEndpointVectors - Tính vector hướng tại endpoint của skeleton
%
% Cú pháp:
%   vectors = fitEndpointVectors(BW, endPoints, Nfit)
%
% Input:
%   BW        - ảnh nhị phân skeleton
%   endPoints - ảnh nhị phân endpoint (1 tại endpoint)
%   Nfit      - số pixel dùng để fit PCA (ví dụ: 30)
%
% Output:
%   vectors - ma trận [N x 4], mỗi hàng:
%             [cx cy vx vy]
%             (cx, cy) = tọa độ endpoint
%             (vx, vy) = vector đơn vị hướng ra ngoài

    [y_idx, x_idx] = find(endPoints);  % tọa độ endpoints
    CC = bwconncomp(BW, 8);           % tìm các component
    vectors = [];

    for k = 1:length(x_idx)
        cx = x_idx(k); 
        cy = y_idx(k);

        % Kiểm tra endpoint thuộc component nào
        comp_id = 0;
        for c = 1:CC.NumObjects
            if ismember(sub2ind(size(BW), cy, cx), CC.PixelIdxList{c})
                comp_id = c; 
                break;
            end
        end

        if comp_id == 0, continue; end  % endpoint không thuộc component nào

        % Lấy tọa độ tất cả pixel trong component
        [yy, xx] = ind2sub(size(BW), CC.PixelIdxList{comp_id});

        % Tính khoảng cách từ endpoint
        dist2 = (xx - cx).^2 + (yy - cy).^2;
        [~, idx] = sort(dist2);
        idxN = idx(1:min(Nfit, numel(idx)));

        X = xx(idxN); 
        Y = yy(idxN);

        if numel(X) > 1
            % --- Fit hướng bằng PCA ---
            Xc = X - mean(X);
            Yc = Y - mean(Y);
            D = [Xc(:) Yc(:)];
            [~,~,V] = svd(D,'econ');
            v = V(:,1);  % vector chính (cột đầu tiên)
            v = v / norm(v);

            % --- Xác định hướng "ra ngoài" ---
            centroid = [mean(X); mean(Y)];
            c = centroid - [cx; cy];  % vector từ endpoint vào trong component
            if dot(v, c) > 0
                v = -v; % đảo dấu để hướng ra ngoài
            end
        else
            v = [0;0];
        end

        vectors = [vectors; cx cy v(1) v(2)];
    end
end
function comp_id = findComponent(CC, p)
% p = [row, col]
comp_id = 0;
idx = sub2ind(CC.ImageSize, p(1), p(2));
for c = 1:CC.NumObjects
    if ismember(idx, CC.PixelIdxList{c})
        comp_id = c;
        return;
    end
end
end

function [BW, linePix] = drawLine(BW, x1, y1, x2, y2)
% Vẽ line nối từ (x1,y1) đến (x2,y2) bằng thuật toán Bresenham
[h, w] = size(BW);
[lineX, lineY] = bresenham(x1, y1, x2, y2);

linePix = [lineX(:), lineY(:)];

for k = 1:length(lineX)
    cx = lineX(k);
    cy = lineY(k);
    if cx >= 1 && cx <= w && cy >= 1 && cy <= h
        BW(cy, cx) = 1;
    end
end

end

function [x, y] = bresenham(x1, y1, x2, y2)

% Thuật toán Bresenham
x1 = round(x1); y1 = round(y1);
x2 = round(x2); y2 = round(y2);

dx = abs(x2 - x1);
dy = abs(y2 - y1);

sx = sign(x2 - x1);
sy = sign(y2 - y1);

err = dx - dy;

x = []; y = [];
while true
    x(end+1) = x1;
    y(end+1) = y1;
    if x1 == x2 && y1 == y2
        break;
    end
    e2 = 2 * err;
    if e2 > -dy
        err = err - dy;
        x1 = x1 + sx;
    end
    if e2 < dx
        err = err + dx;
        y1 = y1 + sy;
    end
end
end
%%

%% ========== Hàm chính ==========


function BW_out = extendLineNearBorder(BW, vectors, extendLen, margin)
% extendLineNearBorder - Nối dài endpoint ra ngoài NẾU nó gần biên ảnh
%
% Input:
%   BW        - ảnh nhị phân
%   vectors   - [cx, cy, vx, vy] cho mỗi endpoint
%   extendLen - số pixel muốn nối dài thêm
%   margin    - ngưỡng khoảng cách từ biên (ví dụ 5)
%
% Output:
%   BW_out    - ảnh nhị phân sau khi vẽ đoạn thẳng nối dài

[H,W] = size(BW);
BW_out = BW;

for i = 1:size(vectors,1)
    cx = vectors(i,1);
    cy = vectors(i,2);
    vx = vectors(i,3);
    vy = vectors(i,4);

    % --- CHỈ vẽ nếu endpoint gần biên ---
    if ~(cx <= margin || cx >= W-margin || cy <= margin || cy >= H-margin)
        continue; % bỏ qua nếu không gần biên
    end

    % Tính điểm mới (C = B + extendLen*v)
    x3 = cx + extendLen*vx;
    y3 = cy + extendLen*vy;

    % Bresenham từ (cx,cy) đến (x3,y3)
    [xLine, yLine] = bresenham2(round(cx), round(cy), round(x3), round(y3));

    % Loại pixel ngoài biên
    mask = xLine>=1 & xLine<=W & yLine>=1 & yLine<=H;
    xLine = xLine(mask);
    yLine = yLine(mask);

    % Vẽ vào ảnh
    BW_out(sub2ind([H,W], yLine, xLine)) = 1;
end

end
function [x,y] = bresenham2(x1,y1,x2,y2)
x1=round(x1); y1=round(y1);
x2=round(x2); y2=round(y2);

dx=abs(x2-x1); dy=abs(y2-y1);
sx=sign(x2-x1); sy=sign(y2-y1);

x=x1; y=y1;
xx=[]; yy=[];

if dx > dy
    err = dx/2;
    while x ~= x2
        xx(end+1)=x; yy(end+1)=y;
        x = x + sx;
        err = err - dy;
        if err < 0
            y = y + sy;
            err = err + dx;
        end
    end
else
    err = dy/2;
    while y ~= y2
        xx(end+1)=x; yy(end+1)=y;
        y = y + sy;
        err = err - dx;
        if err < 0
            x = x + sx;
            err = err + dy;
        end
    end
end
xx(end+1)=x2; yy(end+1)=y2;
x=xx; y=yy;
end

%%
function [pos, xRec, yRec, widthRec, heightRec] = myDrawRec()
% Cho phép người dùng vẽ một hình chữ nhật (ROI) trên ảnh hiện tại.
hFig = gcf;
hROI = drawrectangle();
centerRec = [hROI.Position(1) + hROI.Position(3)/2, hROI.Position(2) + hROI.Position(4)/2];
hold on;
hMarker = plot(centerRec(1), centerRec(2), 'r+', 'MarkerSize', 10, 'LineWidth', 2);
hold off;
addlistener(hROI, 'MovingROI', @(src, evt) updateCenterRectangle(src, hMarker));

% Đợi người dùng double-click để xác nhận
wait(hROI);

pos = round(hROI.Position);
xRec = pos(1); yRec = pos(2);
widthRec = pos(3); heightRec = pos(4);

% Đóng cửa sổ sau khi đã chọn xong
if ishandle(hFig)
    close(hFig);
end
end
% -------------------------------------------------------------------------
function updateCenterRectangle(roi, centerMarker)
% Cập nhật vị trí dấu cộng ở tâm ROI khi đang di chuyển.
centerMarker.XData = roi.Position(1) + roi.Position(3)/2;
centerMarker.YData = roi.Position(2) + roi.Position(4)/2;
drawnow;
end
function [fringe_order, fringe_labels, processed_image] = assign_fringe_order(input_image, display_result)
% ASSIGN_FRINGE_ORDER Gán bậc vân cho ảnh hologram đã được skeletonize
%
% Hàm này thực hiện gán nhãn bậc vân dựa trên vị trí tương đối so với tâm ảnh.
% Vân gần tâm nhất được gán bậc 0, các vân phía trên có bậc dương tăng dần,
% các vân phía dưới có bậc âm giảm dần.
%
% INPUT:
%   input_image    - Ảnh binary đã được skeletonize
%   display_result - (Optional) true/false để hiển thị kết quả (default: true)
%
% OUTPUT:
%   fringe_order     - Số lượng vân được phát hiện
%   fringe_labels    - Vector chứa nhãn bậc vân của từng vùng liên thông
%   processed_image  - Ảnh đã được cắt biên và xử lý
%
% EXAMPLE:
%   [order, labels, img] = assign_fringe_order(skeleton_image);
%   [order, labels, img] = assign_fringe_order(skeleton_image, false); % Không hiển thị

% --- Xử lý tham số đầu vào ---
if nargin < 1
    error('Thiếu tham số đầu vào: input_image');
end

if nargin < 2
    display_result = true; % Mặc định hiển thị kết quả
end

% --- Kiểm tra đầu vào ---
if isempty(input_image)
    error('Ảnh đầu vào không được để trống');
end

if ~islogical(input_image) && ~(isnumeric(input_image) && all(input_image(:) == 0 | input_image(:) == 1))
    error('Ảnh đầu vào phải là ảnh binary (logical hoặc 0/1)');
end

% Chuyển đổi sang logical nếu cần
if ~islogical(input_image)
    input_image = logical(input_image);
end

try
    % --- Bước 1: Cắt biên ảnh để tránh ảnh hưởng vùng biên ---
    offset = 0;
    [orig_H, orig_W] = size(input_image);

    % Kiểm tra kích thước ảnh
    if orig_H <= 2*offset || orig_W <= 2*offset
        warning('Ảnh quá nhỏ để cắt biên. Sử dụng ảnh gốc.');
        bw_crop = input_image;
        offset = 0;
    else
        bw_crop = input_image(offset+1:end-offset, offset+1:end-offset);
    end

    [H, W] = size(bw_crop);

    % --- Bước 2: Tìm các vùng liên thông (vân) ---

    cc = bwconncomp(bw_crop);

    if cc.NumObjects == 0
        warning('Không tìm thấy vân nào trong ảnh');
        fringe_order = 0;
        fringe_labels = [];
        processed_image = bw_crop;
        return;
    end

    labeled_matrix = labelmatrix(cc);
    stats = regionprops(cc, 'Centroid', 'BoundingBox');

    % --- Bước 3: Tìm nhóm gần tâm nhất làm gốc ---
    centroids = cat(1, stats.Centroid);
    image_center = [W/2, H/2];
    dist = vecnorm(centroids - image_center, 2, 2);
    [~, idx_center] = min(dist);

    % --- Bước 4: Khởi tạo và gán nhãn ---
    labels = nan(cc.NumObjects, 1);
    labels(idx_center) = 0; % Nhóm gốc đặt nhãn 0

    queue = idx_center; % Hàng đợi để duyệt lan truyền nhãn
    processed_groups = false(cc.NumObjects, 1);
    processed_groups(idx_center) = true;

    % --- Bước 5: Lan truyền nhãn ---
    while ~isempty(queue)
        current_group = queue(1);
        queue(1) = [];

        current_label = labels(current_group);
        pixels = cc.PixelIdxList{current_group};
        [rows, cols] = ind2sub([H, W], pixels);

        visited_gid = []; % Tránh xét lại nhóm cùng vòng lặp

        for i = 1:length(rows)
            r = rows(i);
            c = cols(i);

            % Lan truyền lên trên theo cột
            for y = r-1:-1:1
                gid = labeled_matrix(y, c);
                if gid > 0 && ~processed_groups(gid) && ~ismember(gid, visited_gid)
                    labels(gid) = current_label + 1; % Nhãn tăng dần lên trên
                    queue(end+1) = gid;
                    processed_groups(gid) = true;
                    visited_gid(end+1) = gid;
                    break;
                elseif gid > 0 && processed_groups(gid)
                    break;
                end
            end

            % Lan truyền xuống dưới theo cột
            for y = r+1:H
                gid = labeled_matrix(y, c);
                if gid > 0 && ~processed_groups(gid) && ~ismember(gid, visited_gid)
                    labels(gid) = current_label - 1; % Nhãn giảm dần xuống dưới
                    queue(end+1) = gid;
                    processed_groups(gid) = true;
                    visited_gid(end+1) = gid;
                    break;
                elseif gid > 0 && processed_groups(gid)
                    break;
                end
            end
        end
    end

    % --- Bước 6: Chuẩn hóa nhãn thành số nguyên dương bắt đầu từ 1 ---
    valid_labels = labels(~isnan(labels));

    if isempty(valid_labels)
        warning('Không thể gán nhãn cho bất kỳ vân nào');
        fringe_order = 0;
        fringe_labels = [];
        processed_image = bw_crop;
        return;
    end

    unique_labels = unique(valid_labels);
    labels_new = nan(size(labels));
    for i = 1:length(unique_labels)
        labels_new(labels == unique_labels(i)) = i;
    end
    labels = labels_new;

    % --- Bước 7: Hiển thị kết quả (nếu được yêu cầu) ---
    if display_result
        figure('Name', 'Kết quả gán bậc vân', 'NumberTitle', 'off');
        imshow(bw_crop);
        hold on;

        for k = 1:cc.NumObjects
            if ~isnan(labels(k))
                pixels = cc.PixelIdxList{k};
                [rows, cols] = ind2sub([H, W], pixels);
                coords = [cols, rows]; % [x, y]

                % Tính khoảng cách từ tâm ảnh để đặt nhãn ở vị trí gần tâm nhất
                dists = sqrt((coords(:,1) - image_center(1)).^2 + (coords(:,2) - image_center(2)).^2);
                [~, min_idx] = min(dists);
                label_pos = coords(min_idx, :);

                text(label_pos(1), label_pos(2), num2str(labels(k)), ...
                    'Color', 'r', 'FontSize', 11, 'FontWeight', 'bold', ...
                    'HorizontalAlignment', 'center');
            end
        end

        title('Gán bậc vân', 'FontSize', 12);
        hold off;
    end

    % --- Bước 8: Trả về kết quả ---
    fringe_order = cc.NumObjects;
    fringe_labels = labels;
    processed_image = bw_crop;

%     % Hiển thị thống kê
%     fprintf('Đã phát hiện %d vân\n', fringe_order);
%     fprintf('Số vân được gán nhãn: %d\n', sum(~isnan(labels)));
%     if ~isempty(valid_labels)
%         fprintf('Phạm vi bậc vân: %d đến %d\n', min(unique_labels), max(unique_labels));
%     end

catch ME
    % Xử lý lỗi
    error_msg = sprintf('Lỗi trong quá trình gán bậc vân:\n%s', ME.message);
    error(error_msg);
end

end
function [recons_surface, figure_handle] = reconSurface_linearPushed(BW, fringe_labels, lambda, tilt_option, show_figure)
% RECONSURFACE_LINEARPUSHED Tái tạo bề mặt 3D từ ảnh vân giao thoa
%
% Cú pháp:
%   [recons_surface, figure_handle] = reconSurface_linearPushed(BW, fringe_labels, lambda, tilt_option, show_figure)
%
% Tham số đầu vào:
%   BW            - Ảnh nhị phân đã cắt biên (logical matrix)
%   fringe_labels - Vector chứa nhãn của các vân (double array)
%   lambda        - Bước sóng ánh sáng (double)
%   tilt_option   - Tùy chọn xử lý ('None', 'Remove tilt', 'Invert', 'Remove + Invert')
%   show_figure   - Có hiển thị figure hay không (logical, optional, default: true)
%
% Tham số đầu ra:
%   recons_surface - Ma trận bề mặt 3D đã tái tạo
%   figure_handle  - Handle của figure (nếu show_figure = true)
%
% Ví dụ:
%   [surface, fig] = reconSurface_linearPushed(BW, [1,2,3,4,5], 632.8e-9, 'Remove tilt');

% Xử lý tham số đầu vào
if nargin < 5
    show_figure = true;
end

% Kiểm tra tham số đầu vào
if isempty(fringe_labels)
    error('Bạn cần gán nhãn vân trước khi nội suy.');
end

if ~islogical(BW)
    error('BW phải là ảnh nhị phân (logical matrix).');
end

% Thiết lập khoảng cách giữa các vân
khoang_cach_van = lambda/2;

% Tìm các thành phần liên thông
cc = bwconncomp(BW);
L = labelmatrix(cc);

% Khởi tạo các mảng điểm 3D
num_labels = max(L(:));
X = []; Y = []; Z = [];

for i = 1:num_labels
    % Tìm các điểm thuộc vân có nhãn i
    [y, x] = find(L == i);

    if i <= length(fringe_labels)
        % Tính độ cao z dựa trên nhãn vân
        z = ones(size(x)) * (fringe_labels(i)) * khoang_cach_van;
        X = [X; x];
        Y = [Y; y];
        Z = [Z; z];
    end
end

% Kiểm tra xem có dữ liệu để nội suy không
if isempty(X)
    error('Không có dữ liệu để nội suy. Kiểm tra lại fringe_labels và BW.');
end

% Nội suy để tạo mặt 3D mượt
[xq, yq] = meshgrid(1:size(BW,2), 1:size(BW,1));
F = scatteredInterpolant(X, Y, Z, 'natural', 'nearest');
Zq = F(xq, yq);
Zq(~isfinite(Zq)) = 0;

% %
% Z_grid_cubic = griddata(X, Y, Z, xq, yq, 'cubic');
% Z_grid_cubic(~isfinite(Z_grid_cubic)) = 0;
% 
% % 6. Làm mượt hậu xử lý cho cubic
% Z_cubic_smooth = imgaussfilt(Z_grid_cubic, 2);
% Zq = Z_cubic_smooth;
% %

% Chuyển từ mét sang radian
phi_rad = (4 * pi / lambda) * Zq;
Zq = phi_rad;

% Cắt biên để hiển thị tốt hơn

Z_crop = Zq;


[M, N] = size(Z_crop);
[xGrid, yGrid] = meshgrid(1:N, 1:M);
x = xGrid(:);
y = yGrid(:);
z = Z_crop(:);

% Xử lý theo lựa chọn của người dùng
switch tilt_option
    case 'None'
        Z_processed = Z_crop;

    case 'Remove tilt'
        good = ~isnan(z);
        if sum(good) < 3
            warning('Không đủ điểm hợp lệ để loại bỏ độ nghiêng.');
            Z_processed = Z_crop;
        else
            A = [x, y, ones(size(x))];
            coeff = A(good,:) \ z(good);
            Z_fit = reshape(A * coeff, size(Z_crop));
            Z_processed = Z_crop - Z_fit;
        end

    case 'Invert'
        Z_processed = max(Z_crop(:)) - Z_crop;

    case 'Remove + Invert'
        good = ~isnan(z);
        if sum(good) < 3
            warning('Không đủ điểm hợp lệ để loại bỏ độ nghiêng.');
            Z_leveled = Z_crop;
        else
            A = [x, y, ones(size(x))];
            coeff = A(good,:) \ z(good);
            Z_fit = reshape(A * coeff, size(Z_crop));
            Z_leveled = Z_crop - Z_fit;
        end
        Z_processed = max(Z_leveled(:)) - Z_leveled;

    otherwise
        warning('Tùy chọn không hợp lệ. Sử dụng "None".');
        Z_processed = Z_crop;
end

% Chuẩn hóa bắt đầu từ 0
Z_offset = Z_processed - min(Z_processed(:));

% Gán kết quả đầu ra
recons_surface = Z_offset;

% Hiển thị bề mặt 3D nếu được yêu cầu
if show_figure
    figure_handle = figure;
    surf(xGrid, yGrid, Z_offset);
    shading interp;
    xlabel('X (px)');
    ylabel('Y (px)');
    zlabel('rad');
    title(['3D Surface Linear (Option: ', tilt_option, ')']);
    colormap parula;
    colorbar;
else
    figure_handle = [];
end

end
function wrappedPhase = reconstruct_phase_interactively(hologram)
% RECONSTRUCT_PHASE_INTERACTIVELY_MASK Tái tạo pha từ hologram bằng cách
% dùng MẶT NẠ để lọc phổ bậc +1 một cách tương tác.
%
%   Input:
%       hologram - Ảnh hologram đầu vào (có thể là ảnh màu hoặc ảnh xám).
%       params   - Một struct chứa các tham số (tùy chọn).
%
%   Output:
%       wrappedPhase - Pha đã tái tạo (bị gói trong khoảng [-pi, pi]).
%       params       - Struct tham số được cập nhật (tùy chọn).

% 1. Chuyển đổi hologram sang ảnh xám nếu cần thiết.
if size(hologram, 3) == 3
    hologramGray = rgb2gray(hologram);
else
    hologramGray = hologram;
end

[numRows, numCols] = size(hologramGray);

% 2. Thực hiện biến đổi Fourier 2D và dịch chuyển thành phần tần số 0 về tâm.
fourierTransform = fftshift(fft2(double(hologramGray)));

% 3. Hiển thị phổ Fourier để người dùng lựa chọn.
figure('Name', 'Fourier Spectrum - Select +1 Order');
imshow(log(1 + abs(fourierTransform)), []);
title('Vẽ một hình chữ nhật quanh phổ bậc +1 rồi double-click');
xlabel('Tần số không gian (u)');
ylabel('Tần số không gian (v)');

% 4. Cho phép người dùng chọn vùng quan tâm (ROI) bằng tay.
[~, xRec, yRec, widthRec, heightRec] = myDrawRec();

% 5. TẠO MỘT MẶT NẠ (MASK) TỪ VÙNG ĐÃ CHỌN
%    Tạo một ma trận toàn số 0...
mask = zeros(numRows, numCols);
%    ...và đặt vùng chữ nhật đã chọn thành 1.
mask(yRec:yRec+heightRec-1, xRec:xRec+widthRec-1) = 1;

% 6. ÁP DỤNG MẶT NẠ VÀ DỊCH CHUYỂN VỀ TÂM
%    Nhân phổ gốc với mặt nạ để loại bỏ các tần số bên ngoài vùng chọn.
filteredSpectrum = fourierTransform .* mask;


% 7. Thực hiện biến đổi Fourier ngược để tái tạo trường sóng phức.
complexField = ifft2(ifftshift(filteredSpectrum));

% 8. Lấy pha từ trường phức.
wrappedPhase = angle(complexField);

end
function [unwrappedPhase, kMap] = unwrapUsingEstimate(estimatedPhase, wrappedPhase)
    % Giải Wrapped pha `wrappedPhase` dựa trên pha ước lượng `estimatedPhase`.
    % wrappedEstimate = wrapToPi(estimatedPhase);
    kMap = round((estimatedPhase - wrappedPhase) / (2*pi));
    unwrappedPhase = wrappedPhase + 2*pi * kMap;
    % ta có: estimated ~ unwraping_phase
    % mà un_phase = wwrapped + k.2pi
    % thay 2 vào 1, có: estiamted - wrapped ~ k.2pi
    % Suy ra: k ~ (estimated - wrapped)/2pi
end
function varargout = crop_multiple_to_smallest(varargin)
    % Giả định tất cả các biến là 2D ma trận
    n = nargin;
    sizes = cellfun(@size, varargin, 'UniformOutput', false);

    % Tìm kích thước nhỏ nhất theo từng chiều
    min_rows = min(cellfun(@(s) s(1), sizes));
    min_cols = min(cellfun(@(s) s(2), sizes));

    varargout = cell(1, n);
    for i = 1:n
        mat = varargin{i};
        [m, n_] = size(mat);
        
        % Tính chỉ số cắt đều 4 phía
        row_start = floor((m - min_rows)/2) + 1;
        col_start = floor((n_ - min_cols)/2) + 1;
        row_end = row_start + min_rows - 1;
        col_end = col_start + min_cols - 1;
        
        varargout{i} = mat(row_start:row_end, col_start:col_end);
    end
end
function [corrected_unwrapped_phase, num_iterations, convergence_history] = correct_sparse_artifacts_iterative(unwrapped_phase_input, varargin)
% Hàm cải tiến: Xử lý các điểm nhiễu sparse với thuật toán lặp và ràng buộc biên
% Dựa trên phương pháp lọc trung vị để xác định và hiệu chỉnh các điểm lỗi.
% Lặp đến khi hội tụ (không còn thay đổi k hoặc thay đổi < epsilon)
%
% Inputs:
%   unwrapped_phase_input - Ma trận pha unwrapped đầu vào
%   varargin - Các tham số tùy chọn:
%       'FilterSize' - Kích thước bộ lọc [default: [15 15]]
%       'Epsilon' - Ngưỡng hội tụ [default: 1e-6]
%       'MaxIterations' - Số lần lặp tối đa [default: 50]
%       'Verbose' - Hiển thị thông tin debug [default: false]
%       'BoundaryCondition' - Điều kiện biên ['zero'|'symmetric'|'replicate'|'circular'] [default: 'symmetric']
%       'BoundaryWidth' - Độ rộng vùng biên không được hiệu chỉnh [default: 0]
%       'PreserveBoundary' - Giữ nguyên giá trị biên [default: true]
%       'MaxDeltaK' - Giới hạn tối đa cho |delta_k| [default: 10]
%       'MaskInvalid' - Mask cho các pixel không hợp lệ [default: []]
%
% Outputs:
%   corrected_unwrapped_phase - Pha đã được hiệu chỉnh
%   num_iterations - Số lần lặp thực tế
%   convergence_history - Lịch sử hội tụ (RMS của delta_k)

    % Xử lý tham số đầu vào
    p = inputParser;
    addParameter(p, 'FilterSize', [5 5], @(x) isnumeric(x) && length(x) == 2);
    addParameter(p, 'Epsilon', 1e-6, @(x) isnumeric(x) && x > 0);
    addParameter(p, 'MaxIterations', 100, @(x) isnumeric(x) && x > 0);
    addParameter(p, 'Verbose', false, @islogical);
    addParameter(p, 'BoundaryCondition', 'symmetric', @(x) ischar(x) && ismember(x, {'zero', 'symmetric', 'replicate', 'circular'}));
    addParameter(p, 'BoundaryWidth', 5, @(x) isnumeric(x) && x >= 0);
    addParameter(p, 'PreserveBoundary', true, @islogical);
    addParameter(p, 'MaxDeltaK', 2, @(x) isnumeric(x) && x > 0);
    addParameter(p, 'MaskInvalid', [], @(x) isempty(x) || islogical(x));
    parse(p, varargin{:});
    
    filter_size = p.Results.FilterSize;
    epsilon = p.Results.Epsilon;
    max_iterations = p.Results.MaxIterations;
    verbose = p.Results.Verbose;
    boundary_condition = p.Results.BoundaryCondition;
    boundary_width = p.Results.BoundaryWidth;
    preserve_boundary = p.Results.PreserveBoundary;
    max_delta_k = p.Results.MaxDeltaK;
    mask_invalid = p.Results.MaskInvalid;
    
    % Khởi tạo
    [rows, cols] = size(unwrapped_phase_input);
    current_phase = unwrapped_phase_input;
    original_phase = unwrapped_phase_input; % Lưu pha gốc để tham chiếu biên
    convergence_history = [];
    num_iterations = 0;
    previous_delta_k = [];
    
    % Tạo mask cho vùng biên nếu cần
    if preserve_boundary && boundary_width > 0
        boundary_mask = create_boundary_mask(rows, cols, boundary_width);
    else
        boundary_mask = false(rows, cols);
    end

% Hàm hỗ trợ: Tạo mask cho vùng biên
function boundary_mask = create_boundary_mask(rows, cols, width)
    boundary_mask = false(rows, cols);
    if width > 0
        boundary_mask(1:width, :) = true;           % Biên trên
        boundary_mask(end-width+1:end, :) = true;   % Biên dưới
        boundary_mask(:, 1:width) = true;           % Biên trái
        boundary_mask(:, end-width+1:end) = true;   % Biên phải
    end
end

% Hàm hỗ trợ: Áp dụng điều kiện biên
function phase_with_boundary = apply_boundary_condition(phase, condition, filter_size)
    [rows, cols] = size(phase);
    pad_rows = floor(filter_size(1)/2);
    pad_cols = floor(filter_size(2)/2);
    
    switch lower(condition)
        case 'zero'
            phase_with_boundary = padarray(phase, [pad_rows, pad_cols], 0, 'both');
        case 'symmetric'
            phase_with_boundary = padarray(phase, [pad_rows, pad_cols], 'symmetric', 'both');
        case 'replicate'
            phase_with_boundary = padarray(phase, [pad_rows, pad_cols], 'replicate', 'both');
        case 'circular'
            phase_with_boundary = padarray(phase, [pad_rows, pad_cols], 'circular', 'both');
        otherwise
            phase_with_boundary = padarray(phase, [pad_rows, pad_cols], 'symmetric', 'both');
    end
end

% Hàm hỗ trợ: Ràng buộc tính liên tục không gian
function delta_k_constrained = apply_spatial_continuity_constraint(delta_k, current_phase)
    % Kiểm tra gradient địa phương để tránh các thay đổi đột ngột
    [rows, cols] = size(delta_k);
    delta_k_constrained = delta_k;
    
    % Tính gradient của pha hiện tại
    [grad_x, grad_y] = gradient(current_phase);
    grad_magnitude = sqrt(grad_x.^2 + grad_y.^2);
    
    % Định nghĩa ngưỡng gradient (vùng có gradient cao được phép thay đổi nhiều hơn)
    grad_threshold = prctile(grad_magnitude(:), 75); % 75th percentile
    
    % Áp dụng ràng buộc dựa trên gradient
    for i = 2:rows-1
        for j = 2:cols-1
            if abs(delta_k(i,j)) > 1 && grad_magnitude(i,j) < grad_threshold
                % Nếu thay đổi lớn nhưng gradient thấp, hạn chế thay đổi
                neighbors = delta_k(i-1:i+1, j-1:j+1);
                median_neighbor = median(neighbors(:));
                
                % Chỉ cho phép thay đổi không quá 1 bước so với median của lân cận
                if abs(delta_k(i,j) - median_neighbor) > 1
                    delta_k_constrained(i,j) = median_neighbor + sign(delta_k(i,j) - median_neighbor);
                end
            end
        end
    end
end
    
    % Xử lý mask invalid
    if isempty(mask_invalid)
        mask_invalid = false(rows, cols);
    else
        if ~isequal(size(mask_invalid), [rows, cols])
            error('MaskInvalid phải có cùng kích thước với unwrapped_phase_input');
        end
    end
    
    % Mask tổng hợp (vùng không được hiệu chỉnh)
    protection_mask = boundary_mask | mask_invalid;
    
    if verbose
        fprintf('Bắt đầu quá trình hiệu chỉnh lặp với ràng buộc biên...\n');
        fprintf('Image size: %dx%d\n', rows, cols);
        fprintf('Filter size: [%d %d], Epsilon: %.2e, Max iterations: %d\n', ...
                filter_size(1), filter_size(2), epsilon, max_iterations);
        fprintf('Boundary condition: %s, Boundary width: %d\n', boundary_condition, boundary_width);
        fprintf('Protected pixels: %d (%.2f%%)\n', sum(protection_mask(:)), 100*sum(protection_mask(:))/(rows*cols));
    end
    
    % Vòng lặp chính
    for iter = 1:max_iterations
        % Bước 1: Xử lý điều kiện biên trước khi lọc
        phase_with_boundary = apply_boundary_condition(current_phase, boundary_condition, filter_size);
        
        % Bước 2: Áp dụng bộ lọc trung vị với xử lý biên
        filtered_phase = medfilt2(phase_with_boundary, filter_size, 'symmetric');
        
        % Cắt về kích thước ban đầu nếu cần
        if ~isequal(size(filtered_phase), [rows, cols])
            filtered_phase = filtered_phase(1:rows, 1:cols);
        end
        
        % Bước 3: Tính toán sự khác biệt về "thứ tự vân" 
        % delta_k = Round[(Phi_filtered - Phi_current) / 2π]
        delta_k = round((filtered_phase - current_phase) / (2*pi));
        
        % Bước 4: Áp dụng các ràng buộc
        % Giới hạn |delta_k|
        delta_k = sign(delta_k) .* min(abs(delta_k), max_delta_k);
        
        % Bảo vệ vùng biên và các pixel không hợp lệ
        delta_k(protection_mask) = 0;
        
        % Bước 5: Kiểm tra tính liên tục không gian (spatial continuity constraint)
        delta_k = apply_spatial_continuity_constraint(delta_k, current_phase);
        
        % Tính toán metric hội tụ (RMS của delta_k chỉ trên vùng được phép thay đổi)
        active_pixels = ~protection_mask;
        if sum(active_pixels(:)) > 0
            rms_delta_k = sqrt(mean((delta_k(active_pixels)).^2));
        else
            rms_delta_k = 0;
        end
        
        convergence_history(end+1) = rms_delta_k;
        num_iterations = iter;
        
        if verbose
            num_corrections = sum(delta_k(:) ~= 0);
            fprintf('Iteration %d: RMS(delta_k) = %.6f, Corrections: %d, Unique values: %d\n', ...
                    iter, rms_delta_k, num_corrections, length(unique(delta_k(:))));
        end
        
        % Kiểm tra điều kiện hội tụ
        if iter > 1
            % Kiểm tra xem delta_k có thay đổi không
            if isequal(delta_k, previous_delta_k)
                if verbose
                    fprintf('Hội tụ đạt được: delta_k không thay đổi (iteration %d)\n', iter);
                end
                break;
            end
            
            % Kiểm tra xem thay đổi có nhỏ hơn epsilon không
            if rms_delta_k < epsilon
                if verbose
                    fprintf('Hội tụ đạt được: RMS(delta_k) < epsilon (iteration %d)\n', iter);
                end
                break;
            end
            
            % Kiểm tra thay đổi tương đối giữa các lần lặp
            relative_change = abs(convergence_history(end) - convergence_history(end-1)) / ...
                             (convergence_history(end-1) + eps);
            if relative_change < epsilon
                if verbose
                    fprintf('Hội tụ đạt được: Thay đổi tương đối < epsilon (iteration %d)\n', iter);
                end
                break;
            end
        end
        
        % Bước 3: Hiệu chỉnh pha với ràng buộc biên
        % Phi_corrected = Phi_current + delta_k * 2π
        current_phase = current_phase + delta_k * (2*pi);
        
        % Khôi phục giá trị biên gốc nếu cần
        if preserve_boundary
            current_phase(protection_mask) = original_phase(protection_mask);
        end
        
        % Lưu delta_k hiện tại để so sánh ở lần lặp tiếp theo
        previous_delta_k = delta_k;
        
        % Kiểm tra nếu đạt số lần lặp tối đa
        if iter == max_iterations
            if verbose
                fprintf('Cảnh báo: Đạt số lần lặp tối đa (%d) mà chưa hội tụ hoàn toàn\n', max_iterations);
            end
        end
    end
    
    corrected_unwrapped_phase = current_phase;
    
    if verbose
        fprintf('Hoàn thành sau %d lần lặp\n', num_iterations);
        fprintf('RMS cuối cùng của delta_k: %.6f\n', convergence_history(end));
    end
end

function [wrappedPhase, fourierCoords] = reconstruct_phase_interactively_v2(hologram, fourierCoords)
% RECONSTRUCT_PHASE_INTERACTIVELY Tái tạo pha từ hologram bằng cách
% dùng MẶT NẠ để lọc phổ bậc +1. Tự động áp dụng nếu đã có tọa độ.

% 1. Chuyển đổi hologram sang ảnh xám nếu cần thiết.
if size(hologram, 3) == 3
    hologramGray = rgb2gray(hologram);
else
    hologramGray = hologram;
end
[numRows, numCols] = size(hologramGray);

% 2. Thực hiện biến đổi Fourier 2D và dịch chuyển thành phần tần số 0 về tâm.
fourierTransform = fftshift(fft2(double(hologramGray)));

% 3 & 4. XỬ LÝ LỌC PHỔ (Thủ công hoặc Tự động)
if nargin < 2 || isempty(fourierCoords)
    % Nếu chưa có tọa độ, yêu cầu vẽ
    figFourier = figure('Name', 'Fourier Spectrum - Select +1 Order');
    imshow(log(1 + abs(fourierTransform)), []);
    title('Vẽ một hình chữ nhật quanh phổ bậc +1 rồi double-click');
    xlabel('Tần số không gian (u)');
    ylabel('Tần số không gian (v)');
    
    [~, xRec, yRec, widthRec, heightRec] = myDrawRec();
    
    % Lưu lại tọa độ để dùng cho các ảnh sau
    fourierCoords = round([xRec, yRec, widthRec, heightRec]);
    
    % Tự động đóng cửa sổ phổ sau khi chọn xong để tránh rác màn hình
    if ishandle(figFourier)
        close(figFourier);
    end
else
    % Đã có tọa độ từ ảnh đầu tiên, lấy ra dùng luôn
    xRec      = fourierCoords(1);
    yRec      = fourierCoords(2);
    widthRec  = fourierCoords(3);
    heightRec = fourierCoords(4);
    disp('Đang tự động áp dụng mặt nạ lọc phổ Fourier đã chọn...');
end

% 5. TẠO MỘT MẶT NẠ (MASK) TỪ VÙNG ĐÃ CHỌN
mask = zeros(numRows, numCols);
mask(yRec : yRec+heightRec-1, xRec : xRec+widthRec-1) = 1;

% 6. ÁP DỤNG MẶT NẠ VÀ DỊCH CHUYỂN VỀ TÂM
filteredSpectrum = fourierTransform .* mask;

% 7. Thực hiện biến đổi Fourier ngược để tái tạo trường sóng phức.
complexField = ifft2(ifftshift(filteredSpectrum));

% 8. Lấy pha từ trường phức.
wrappedPhase = angle(complexField);
end

function [fringe_order, fringe_labels, processed_image] = assign_fringe_order_v2(input_image, display_result)
% ASSIGN_FRINGE_ORDER_V3
% Gán nhãn bậc vân bằng pixel propagation + component median
%
% Ý tưởng:
% 1. Tìm connected components
% 2. Chọn component gần tâm nhất làm gốc -> label = 1
% 3. Lan truyền nhãn theo pixel:
%       quét lên: +1
%       quét xuống: -1
% 4. Khi toàn bộ pixel đã có nhãn:
%       mỗi component lấy median label
% 5. Chuẩn hóa nhãn từ 1..N
%
% INPUT:
%   input_image     : ảnh nhị phân
%   display_result  : true / false
%
% OUTPUT:
%   fringe_order
%   fringe_labels
%   processed_image

%% -------------------------
% Input
%% -------------------------
if nargin < 1
    error('Thiếu input_image');
end

if nargin < 2
    display_result = true;
end

if isempty(input_image)
    error('Ảnh rỗng');
end

if ~islogical(input_image)
    input_image = logical(input_image);
end

processed_image = input_image;
bw = processed_image;

[H,W] = size(bw);

%% -------------------------
% Connected Components
%% -------------------------
cc = bwconncomp(bw,8);

if cc.NumObjects == 0
    fringe_order  = 0;
    fringe_labels = [];
    return;
end

N = cc.NumObjects;

L = labelmatrix(cc);
stats = regionprops(cc,'PixelList');

%% -------------------------
% Tìm component gần tâm nhất
%% -------------------------
center = [W/2 , H/2];

mind = inf(N,1);

for k = 1:N

    pts = stats(k).PixelList;   % [x y]

    d = sqrt((pts(:,1)-center(1)).^2 + ...
             (pts(:,2)-center(2)).^2);

    mind(k) = min(d);
end

[~, root_gid] = min(mind);

%% -------------------------
% Pixel label map
%% -------------------------
pixel_label = nan(H,W);

%% -------------------------
% Gán root = 1
%% -------------------------
root_pix = cc.PixelIdxList{root_gid};
pixel_label(root_pix) = 1;

queue_r = [];
queue_c = [];

[r0,c0] = ind2sub([H,W], root_pix);

queue_r = r0(:);
queue_c = c0(:);

head = 1;

%% -------------------------
% BFS pixel propagation
%% -------------------------
while head <= numel(queue_r)

    r = queue_r(head);
    c = queue_c(head);
    head = head + 1;

    current_label = pixel_label(r,c);

    %% ===== Quét lên =====
    for y = r-1:-1:1

        if bw(y,c)

            if isnan(pixel_label(y,c))
                pixel_label(y,c) = current_label + 1;

                queue_r(end+1,1) = y;
                queue_c(end+1,1) = c;
            end

            break;
        end
    end

    %% ===== Quét xuống =====
    for y = r+1:H

        if bw(y,c)

            if isnan(pixel_label(y,c))
                pixel_label(y,c) = current_label - 1;

                queue_r(end+1,1) = y;
                queue_c(end+1,1) = c;
            end

            break;
        end
    end

end

%% -------------------------
% Nếu còn pixel chưa label
% lặp bổ sung
%% -------------------------
changed = true;

while changed

    changed = false;

    [rr,ccol] = find(bw & isnan(pixel_label));

    for p = 1:length(rr)

        r = rr(p);
        c = ccol(p);

        best_dist  = inf;
        best_label = nan;

        %% quét lên
        for y = r-1:-1:1

            if bw(y,c) && ~isnan(pixel_label(y,c))

                d = r-y;

                if d < best_dist
                    best_dist  = d;
                    best_label = pixel_label(y,c) + 1;
                end
                break;
            end
        end

        %% quét xuống
        for y = r+1:H

            if bw(y,c) && ~isnan(pixel_label(y,c))

                d = y-r;

                if d < best_dist
                    best_dist  = d;
                    best_label = pixel_label(y,c) - 1;
                end
                break;
            end
        end

        if ~isnan(best_label)
            pixel_label(r,c) = best_label;
            changed = true;
        end

    end
end

%% -------------------------
% Tính label cho từng component = median
%% -------------------------
fringe_labels = nan(N,1);

for k = 1:N

    pix = cc.PixelIdxList{k};

    vals = pixel_label(pix);
    vals = vals(~isnan(vals));

    if isempty(vals)
        fringe_labels(k) = 1;
    else
        fringe_labels(k) = round(median(vals));
    end
end

%% -------------------------
% Chuẩn hóa nhãn từ 1
%% -------------------------
min_label = min(fringe_labels);
fringe_labels = fringe_labels - min_label + 1;

%% -------------------------
% Số fringe thực tế
%% -------------------------
fringe_order = max(fringe_labels);

%% -------------------------
% Display
%% -------------------------
if display_result

    figure('Name','Assigned Fringe Order V3',...
           'NumberTitle','off');

    imshow(bw);
    hold on;

    for k = 1:N

        pts = stats(k).PixelList;

        d = sqrt((pts(:,1)-center(1)).^2 + ...
                 (pts(:,2)-center(2)).^2);

        [~,id] = min(d);
        pos = pts(id,:);

        text(pos(1),pos(2),num2str(fringe_labels(k)),...
            'Color','r',...
            'FontSize',11,...
            'FontWeight','bold',...
            'HorizontalAlignment','center');
    end

    title('Fringe Labels V3');
    hold off;
end

end


function [fringe_order, fringe_labels, processed_image] = assign_fringe_order_v4(input_image, display_result)
% ASSIGN_FRINGE_ORDER_V4
% Component-wise propagation:
% 1) Chọn fringe gốc gần tâm -> label = 1
% 2) Xử lý theo connected component:
%    - Quét toàn bộ pixel của component hiện tại theo cột
%    - Thu thập vote label cho các component chưa biết:
%         phía trên  -> current + 1
%         phía dưới  -> current - 1
%    - Sau khi quét HẾT component hiện tại:
%         mỗi component đích nhận median(votes)
%         gán thống nhất 1 label cho toàn bộ component đó
%    - Component mới gán đưa vào queue
% 3) Nếu còn component chưa gán:
%    fallback tìm theo cột từ component đã biết gần nhất
% 4) Chuẩn hóa label từ 1..K

%% -------------------------
% Input
%% -------------------------
if nargin < 1
    error('Thiếu input_image');
end

if nargin < 2
    display_result = true;
end

if isempty(input_image)
    error('Ảnh rỗng');
end

if ~islogical(input_image)
    input_image = logical(input_image);
end

processed_image = input_image;
bw = processed_image;

[H,W] = size(bw);

%% -------------------------
% Connected Components
%% -------------------------
cc = bwconncomp(bw,8);

if cc.NumObjects == 0
    fringe_order = 0;
    fringe_labels = [];
    return;
end

N = cc.NumObjects;
L = labelmatrix(cc);
stats = regionprops(cc,'PixelList');

%% -------------------------
% Chọn root gần tâm
%% -------------------------
center = [W/2 , H/2];
mind = inf(N,1);

for k = 1:N
    pts = stats(k).PixelList;
    d = hypot(pts(:,1)-center(1), pts(:,2)-center(2));
    mind(k) = min(d);
end

[~, root_gid] = min(mind);

%% -------------------------
% Khởi tạo
%% -------------------------
fringe_labels = nan(N,1);
fringe_labels(root_gid) = 1;

queue = root_gid;
head = 1;

%% -------------------------
% BFS theo component
%% -------------------------
while head <= numel(queue)

    current_gid = queue(head);
    head = head + 1;

    current_label = fringe_labels(current_gid);
    pts = stats(current_gid).PixelList;   % [x y]

    % vote labels cho component khác
    votes = cell(N,1);

    % --------------------------------
    % Quét HẾT component hiện tại trước
    % --------------------------------
    for i = 1:size(pts,1)

        c = pts(i,1);
        r = pts(i,2);

        %% ===== Quét lên =====
        for y = r-1:-1:1

            if bw(y,c)

                gid2 = L(y,c);

                if gid2 ~= current_gid

                    if isnan(fringe_labels(gid2))
                        votes{gid2}(end+1) = current_label + 1;
                    end

                    break;
                end
            end
        end

        %% ===== Quét xuống =====
        for y = r+1:H

            if bw(y,c)

                gid2 = L(y,c);

                if gid2 ~= current_gid

                    if isnan(fringe_labels(gid2))
                        votes{gid2}(end+1) = current_label - 1;
                    end

                    break;
                end
            end
        end

    end

    % --------------------------------
    % Sau khi quét xong -> thống nhất label
    % --------------------------------
    for gid2 = 1:N

        if isnan(fringe_labels(gid2)) && ~isempty(votes{gid2})

            fringe_labels(gid2) = round(median(votes{gid2}));
            queue(end+1) = gid2;

        end
    end

end

%% -------------------------
% Fallback cho component còn thiếu
%% -------------------------
missing = find(isnan(fringe_labels));

while ~isempty(missing)

    changed = false;

    for t = 1:length(missing)

        k = missing(t);
        pts = stats(k).PixelList;

        cand = [];

        for i = 1:size(pts,1)

            c = pts(i,1);
            r = pts(i,2);

            %% lên
            for y = r-1:-1:1
                gid2 = L(y,c);

                if gid2 > 0 && gid2 ~= k && ~isnan(fringe_labels(gid2))
                    cand(end+1) = fringe_labels(gid2) + 1;
                    break;
                end
            end

            %% xuống
            for y = r+1:H
                gid2 = L(y,c);

                if gid2 > 0 && gid2 ~= k && ~isnan(fringe_labels(gid2))
                    cand(end+1) = fringe_labels(gid2) - 1;
                    break;
                end
            end

        end

        if ~isempty(cand)
            fringe_labels(k) = round(median(cand));
            changed = true;
        end

    end

    if ~changed
        % nếu vẫn kẹt thì gán 1 để tránh loop vô hạn
        fringe_labels(isnan(fringe_labels)) = 1;
    end

    missing = find(isnan(fringe_labels));

end

%% -------------------------
% Chuẩn hóa nhãn
%% -------------------------
min_label = min(fringe_labels);
fringe_labels = fringe_labels - min_label + 1;

fringe_labels = round(fringe_labels);
fringe_order = max(fringe_labels);

%% -------------------------
% Display
%% -------------------------
if display_result

    figure('Name','Assigned Fringe Order V4', ...
           'NumberTitle','off');

    imshow(bw);
    hold on;

    for k = 1:N

        pts = stats(k).PixelList;

        d = hypot(pts(:,1)-center(1), pts(:,2)-center(2));
        [~,id] = min(d);
        pos = pts(id,:);

        text(pos(1), pos(2), num2str(fringe_labels(k)), ...
            'Color','r', ...
            'FontSize',11, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','center');
    end

    title('Fringe Labels V4');
    hold off;
end

end

function [fringe_order, fringe_labels, processed_image] = assign_fringe_order_v5(input_image, display_result)
% ASSIGN_FRINGE_ORDER_V5
%
% Pixel proposal + finalize when connected-component is sufficiently covered
%
% Ý tưởng:
% 1. Tách connected components
% 2. Chọn fringe gần tâm làm root => label = 1
% 3. Root quét dọc theo cột:
%       pixel khác nhận proposal label
% 4. Một component CHỈ finalize khi:
%       số lượng pixel nhận được proposal đạt một ngưỡng nhất định (VD: >= 60%)
% 5. Khi finalize:
%       component_label = median(all valid proposals)
%       component đó được đưa vào hàng đợi để tiếp tục lan truyền
% 6. Lặp tới khi hàng đợi trống. Các component rác không tới được sẽ gán mặc định.

%% -------------------------------------------------
% Input
%% -------------------------------------------------
if nargin < 1
    error('Thiếu input_image');
end

if nargin < 2
    display_result = true;
end

if isempty(input_image)
    error('Ảnh rỗng');
end

if ~islogical(input_image)
    input_image = logical(input_image);
end

processed_image = input_image;
bw = processed_image;

[H,W] = size(bw);

%% -------------------------------------------------
% Connected components
%% -------------------------------------------------
cc = bwconncomp(bw,8);

if cc.NumObjects == 0
    fringe_order = 0;
    fringe_labels = [];
    return;
end

N = cc.NumObjects;

L = labelmatrix(cc);
stats = regionprops(cc,'PixelList');

%% -------------------------------------------------
% Root gần tâm
%% -------------------------------------------------
center = [W/2 , H/2];

mind = inf(N,1);

for k = 1:N
    pts = stats(k).PixelList;
    d = hypot(pts(:,1)-center(1), pts(:,2)-center(2));
    mind(k) = min(d);
end

[~, root_gid] = min(mind);

%% -------------------------------------------------
% Khởi tạo
%% -------------------------------------------------
fringe_labels = nan(N,1);      % final label component
proposal_map  = nan(H,W);      % proposal label per pixel

% Tính sẵn số lượng pixel của mỗi component để xét điều kiện %
num_pixels_per_comp = zeros(N,1);
for k = 1:N
    num_pixels_per_comp(k) = numel(cc.PixelIdxList{k});
end

% Root = 1
fringe_labels(root_gid) = 1;

root_pix = cc.PixelIdxList{root_gid};
proposal_map(root_pix) = 1;

queue = root_gid;
head = 1;

% Ngưỡng coverage (60%)
COVERAGE_THRESHOLD = 0.6; 

%% -------------------------------------------------
% BFS propagation
%% -------------------------------------------------
while head <= numel(queue)

    current_gid = queue(head);
    head = head + 1;

    current_label = fringe_labels(current_gid);
    pts = stats(current_gid).PixelList;   % [x y]

    %% ---------------------------------
    % 1. Propagate proposal
    %% ---------------------------------
    for i = 1:size(pts,1)

        c = pts(i,1);
        r = pts(i,2);

        %% ===== Quét lên =====
        for y = r-1:-1:1
            if bw(y,c)
                gid2 = L(y,c);
                if gid2 ~= current_gid
                    if isnan(proposal_map(y,c))
                        proposal_map(y,c) = current_label + 1;
                    end
                    break;
                end
            end
        end

        %% ===== Quét xuống =====
        for y = r+1:H
            if bw(y,c)
                gid2 = L(y,c);
                if gid2 ~= current_gid
                    if isnan(proposal_map(y,c))
                        proposal_map(y,c) = current_label - 1;
                    end
                    break;
                end
            end
        end

    end

    %% ---------------------------------
    % 2. Check component nào đủ % proposal
    %% ---------------------------------
    for gid = 1:N
        if isnan(fringe_labels(gid))

            pix = cc.PixelIdxList{gid};
            vals = proposal_map(pix);
            valid_vals = vals(~isnan(vals)); % Lọc bỏ các giá trị NaN

            % Kiểm tra xem số pixel có proposal đã đạt ngưỡng chưa
            if numel(valid_vals) >= ceil(num_pixels_per_comp(gid) * COVERAGE_THRESHOLD)
                
                % Đủ điều kiện => finalize
                fringe_labels(gid) = round(median(valid_vals));
                
                % Đưa vào queue để nó tiếp tục lan truyền
                queue(end+1) = gid; 
            end
        end
    end

end

%% -------------------------------------------------
% Fallback cho component bị cô lập
%% -------------------------------------------------
% Các component này có thể là nhiễu hoặc ở quá xa rìa, không nhận được proposal nào
missing = isnan(fringe_labels);
if any(missing)
    % Gán tạm mức 1 hoặc có thể gán nan tùy ý đồ hiển thị của bạn
    fringe_labels(missing) = 1; 
end

%% -------------------------------------------------
% Normalize
%% -------------------------------------------------
min_label = min(fringe_labels);

fringe_labels = fringe_labels - min_label + 1;
fringe_labels = round(fringe_labels);

fringe_order = max(fringe_labels);

%% -------------------------------------------------
% Display
%% -------------------------------------------------
if display_result

    figure('Name','Assigned Fringe Order V5',...
           'NumberTitle','off');

    imshow(bw);
    hold on;

    for k = 1:N
        pts = stats(k).PixelList;
        d = hypot(pts(:,1)-center(1), pts(:,2)-center(2));

        [~,id] = min(d);
        pos = pts(id,:);

        text(pos(1),pos(2),num2str(fringe_labels(k)),...
            'Color','r',...
            'FontSize',11,...
            'FontWeight','bold',...
            'HorizontalAlignment','center');
    end

    title('Fringe Labels V5 (Threshold 60%)');
    hold off;

end

end


function [fringe_order, fringe_labels, processed_image] = assign_fringe_order_v6(input_image, display_result)
% ASSIGN_FRINGE_ORDER_V6_STRICT
% Theo giả định lý tưởng:
% 1. Root là vân lớn nhất/dài nhất bao trùm ảnh.
% 2. Yêu cầu quét full 100% pixel của component mới được lan truyền tiếp.
% 3. Lan truyền tích lũy (nhận proposal từ nhiều vân khác nhau).

if nargin < 1, error('Thiếu input_image'); end
if nargin < 2, display_result = true; end

bw = logical(input_image);
[H,W] = size(bw);
processed_image = bw;

cc = bwconncomp(bw,8);
if cc.NumObjects == 0
    fringe_order = 0;
    fringe_labels = [];
    return;
end

N = cc.NumObjects;
L = labelmatrix(cc);
stats = regionprops(cc,'PixelList', 'Area');

%% 1. CHỌN ROOT LÀ VÂN LỚN NHẤT (Dài nhất/bao trùm nhất)
areas = [stats.Area];
[~, root_gid] = max(areas); 

%% 2. KHỞI TẠO
fringe_labels = nan(N,1);      
fringe_labels(root_gid) = 1;

% Dùng cell array để 1 pixel có thể nhận nhiều proposal từ các vân khác nhau (C và A cùng truyền cho B)
proposal_map = cell(H,W); 
root_pix = cc.PixelIdxList{root_gid};
for p = 1:numel(root_pix)
    proposal_map{root_pix(p)} = 1;
end

has_scanned = false(N,1); % Đánh dấu vân nào đã phát tia quét

%% 3. BÒ LƯỚI KÉP (ITERATIVE SWEEP) VỚI ĐIỀU KIỆN 100%
keep_looping = true;
while keep_looping
    keep_looping = false; % Sẽ bật lại nếu có vân mới được chốt
    
    % Tìm các vân ĐÃ CHỐT nhưng CHƯA QUÉT
    active_sources = find(~isnan(fringe_labels) & ~has_scanned);
    
    for idx = 1:length(active_sources)
        current_gid = active_sources(idx);
        current_label = fringe_labels(current_gid);
        pts = stats(current_gid).PixelList;
        
        % Phát tia quét dọc theo cột Y
        for i = 1:size(pts,1)
            c = pts(i,1); r = pts(i,2);
            
            % Quét lên
            for y = r-1:-1:1
                if bw(y,c)
                    gid2 = L(y,c);
                    if gid2 ~= current_gid
                        proposal_map{y,c} = [proposal_map{y,c}, current_label + 1];
                        break; % Vẫn giữ break để tuân thủ tính chất che khuất của quang học
                    end
                end
            end
            
            % Quét xuống
            for y = r+1:H
                if bw(y,c)
                    gid2 = L(y,c);
                    if gid2 ~= current_gid
                        proposal_map{y,c} = [proposal_map{y,c}, current_label - 1];
                        break;
                    end
                end
            end
        end
        has_scanned(current_gid) = true; % Đã quét xong
    end
    
    % 4. KIỂM TRA ĐIỀU KIỆN 100% COVERAGE ĐỂ CHỐT VÂN MỚI
    for gid = 1:N
        if isnan(fringe_labels(gid))
            pix = cc.PixelIdxList{gid};
            
            % Đếm số pixel đã nhận ít nhất 1 proposal
            covered_pixels = 0;
            all_proposals = [];
            for p = 1:numel(pix)
                if ~isempty(proposal_map{pix(p)})
                    covered_pixels = covered_pixels + 1;
                    all_proposals = [all_proposals, proposal_map{pix(p)}];
                end
            end
            
            % ĐIỀU KIỆN STRICT: Bắt buộc 100% pixel phải có data
            if covered_pixels == numel(pix) 
                fringe_labels(gid) = round(median(all_proposals));
                keep_looping = true; % Có vân mới được chốt -> Kích hoạt vòng quét tiếp theo
            end
        end
    end
end

%% 5. CHUẨN HÓA VÀ HIỂN THỊ
missing = isnan(fringe_labels);
if any(missing)
    fringe_labels(missing) = 1; % Gán dự phòng nếu hệ thống bị đứng
end

fringe_labels = round(fringe_labels - min(fringe_labels) + 1);
fringe_order = max(fringe_labels);

if display_result
    figure('Name','Strict Fringe Order V6','NumberTitle','off');
    imshow(bw); hold on;
    center = [W/2 , H/2];
    for k = 1:N
        pts = stats(k).PixelList;
        d = hypot(pts(:,1)-center(1), pts(:,2)-center(2));
        [~,id] = min(d);
        text(pts(id,1), pts(id,2), num2str(fringe_labels(k)), ...
            'Color','r', 'FontSize',11, 'FontWeight','bold', 'HorizontalAlignment','center');
    end
    title('Fringe Labels V6 (Strict 100% Coverage & Longest Root)');
    hold off;
end
end