function [varargout] = estimate_SAGA(varargin)
% estimate SAGA horizontal drift velocities and ellipse
warning off;

if nargin == 0
    clear;
    close all;
    load va1.mat;
    format short g
    dbstop if error;
else
    [H, YN, Y, CCVALN, CCVAL, CCERR, wflag, COMBOS, RHO0, RXILOC, RCVRID] = varargin{:};
    save('va.mat');
end

%hardcoded correlation cut off for SAGA
rho_c = 0.65;

% remove invalid observations
[badrows, badcols] = find(CCVAL < rho_c | CCVAL > 1);

%%
Y(badrows, :) = [];
YN(badrows, :) = [];
YNhat = mean(YN, 2, 'omitnan');
H(badrows, :) = [];
CCVALN(badrows, :) = [];
CCERR(badrows, :) = [];
COMBOS(badrows, :) = [];
RHO0(badrows, :) = [];
RXILOC(badrows, :) = [];

[nanrows, nancols] = find(isnan(YN));
if ~isempty(Y) && nargin == 0
    figobs = figure;
    hold on;
    hyn = plot(YN, 'g.');
    hy = plot(Y, 'k', 'linewidth', 1.5);
    legend([hyn(1, :); hy], {'$\tilde{Y}$', '$Y$'}, 'location', 'best');
    title('Original observations and noisy ensembles');
    tightfig;
    saveas(gcf, '../Observations.png');
    close(figobs);
    fignu = figure;
    errarr = YN - repmat(Y, 1, size(YN, 2));
    hist = histogram(errarr);
    set(gca, 'yscale', 'log');
    title('$\nu = \tilde{Y} - Y, Y = Hx$');
    tightfig;
    saveas(gcf, '../Nu.pdf');
    close(fignu);
end

if wflag == 0
    W = eye(size(YN, 1));
else
    W = inv(cov(YN', 'partialrows'));
end
% State with noise
XN = (H' * W * H) \ H' * W * YN;
% State without noise
X = (H' * W * H) \ H' * W * Y;
rowsX = mat2cell(X, ones(1, size(X, 1)));
covxn = (H' * W * H) \ H' * W * cov(YN', 'partialrows') * W' * H / (H' * W' * H);

%%
if all(XN == 0)
    fprintf('max corr value smaller than hardcoded threshold %g \n', rho_c);
end
rowsXN = mat2cell(XN, ones(1, size(XN, 1)));
[a, h, b, f, g] = rowsXN{:};
badcolspd = find(a.*b-h.^2 <= 0 | a <= 0 | b <= 0);
fprintf('%i/%i columns do not meet positive-definite conditions\n', ...
    length(badcolspd), size(YN, 2));
a(badcolspd) = [];
a_ = a(~isnan(a));
h(badcolspd) = [];
h_ = h(~isnan(h));
b(badcolspd) = [];
b_ = b(~isnan(b));
f(badcolspd) = [];
f_ = f(~isnan(f));
g(badcolspd) = [];
g_ = g(~isnan(g));
X_ = [a; h; b; f; g];
%recompute the \hat{Y}
YH = YN;
YH(:, badcolspd) = [];
covxh = (H' * W * H) \ H' * W * cov(YH', 'partialrows') * W' * H / (H' * W' * H);

[estbarn, Jn, majorn, minorn, stdestn] = solve_SAGA(a, h, b, f, g);
[estbar, J, major, minor, ~] = solve_SAGA(rowsX{:});
estbarncell = num2cell(estbarn);
[vmagn, vangn, vge, vgn, arn, Psi_an, vc] = estbarncell{:};
covestn = Jn * covxn * Jn';
covesth = Jn * covxh * Jn';
display([estbar, estbarn, stdestn, diag(sqrt(covestn)), diag(sqrt(covesth))], '1 2 3 4 5');
CCVALN(:, badcolspd) = [];
%     [RHO0(:,badcolspd), RXILOC(:,badcolspd)] = deal([]);
plotellipse(arn, majorn, minorn, Psi_an, vmagn, vangn, rho_c, ...
    CCVALN, COMBOS, RHO0, RXILOC, RCVRID);

varargout = {estbarn, covesth, size(X_, 2) / size(YN, 2) * 100, estbar};
% varargout = {estbar, diag(stdest_).^2, size(X_,2)/size(YN,2)};
end

function [varargout] = solve_SAGA(varargin)
% given [a h b f g]', compute drift velocity, axial ratio and orientation
% the mapping matrix M is the jacobian wrt [a h b f g]
% [v;theta;ve;vn;ar;psi;vc] = M*[a;h;b;f;g]
%   0<=alpha<=1

[a, h, b, f, g] = varargin{:};

v = sqrt((g .* h - f .* b).^2+(f .* h - g .* a).^2) ./ (a .* b - h.^2);
v1 = f ./ (sqrt(a.^2+h.^2));
v2 = g ./ (sqrt(h.^2+b.^2));
theta = atan2(f.*h-g.*a, g.*h-f.*b);
ve = v .* cos(theta);
vn = v .* sin(theta);
alpha = 2 .* sqrt(a.*b-h.^2) ./ (a + b);
ar = sqrt((1 + sqrt(1-alpha.^2))./(1 - sqrt(1-alpha.^2)));
psi = atan2(2.*h, a-b) ./ 2;

minus_ind = find(psi < 0);
psi(minus_ind) = pi + psi(minus_ind);
minus_ind = find(theta < 0);
theta(minus_ind) = 2 * pi + theta(minus_ind);

% characteristic velocity
vc = sqrt((a .* b - h.^2)./(a .* g.^2 - 2 .* f .* g .* h + b .* f.^2)-1) .* v;
vc1 = sqrt((a.^3 + 2 .* a .* h.^2 + b .* h.^2)./(g .* h + a .* f).^2-1) .* v;
vc2 = sqrt((b.^3 + 2 .* b .* h.^2 + a .* h.^2)./(f .* h + b .* g).^2-1) .* v;

if all(ar >= 10)
    %     vc = min(vc1,vc2);
    %     v = min(v1,v2);
end

% major and minor axes
major = sqrt(2./(a + b - sqrt((a - b).^2+4*h.^2)));
minor = sqrt(2./(a + b + sqrt((a - b).^2+4*h.^2)));

% Compute Jacobian at expected values
meancell = num2cell(mean([a; h; b; f; g], 2, 'omitnan'));
[abar, hbar, bbar, fbar, gbar] = meancell{:};

if nargin == 0
    abar = 10;
    hbar = 6;
    bbar = 4;
    Q = [abar, hbar, fbar; ...
        hbar, bbar, gbar; ...
        fbar, gbar, 1];
    
    Q = [abar, hbar; ...
        hbar, bbar];
    
    psibar = atan2(2.*hbar, abar-bbar) ./ 2;
    R = [cos(psibar), -sin(psibar); ...
        sin(psibar), cos(psibar)];
    
    [V, D] = eig(Q);
    % covellipsoid(V',D,[0 0 0],0.4,1,100);
end

dv = [(-1) .* (bbar .* fbar + (-1) .* gbar .* hbar) .* ((-1) .* abar .* bbar + hbar.^2), ...
    .^(-2) .* (bbar.^2 .* fbar + (-1) .* (abar + bbar) .* gbar .* hbar + fbar .* ...
    hbar.^2) .* ((abar .* gbar + (-1) .* fbar .* hbar).^2 + (bbar .* fbar + (-1) .* ...
    gbar .* hbar).^2).^(-1 / 2), ((-1) .* abar .* bbar + hbar.^2).^(-2) .* ((-1) .* ...
    abar .* bbar .* (abar + bbar) .* fbar .* gbar + (bbar .* (abar + 2 .* bbar) .* ...
    fbar.^2 + abar .* (2 .* abar + bbar) .* gbar.^2) .* hbar + (-3) .* (abar + bbar) .* ...
    fbar .* gbar .* hbar.^2 + (fbar.^2 + gbar.^2) .* hbar.^3) .* ((abar .* gbar + (-1) ...
    .* fbar .* hbar).^2 + (bbar .* fbar + (-1) .* gbar .* hbar).^2).^(-1 / 2), (-1) .* ( ...
    abar .* gbar + (-1) .* fbar .* hbar) .* ((-1) .* abar .* bbar + hbar.^2).^(-2) .* ( ...
    abar.^2 .* gbar + (-1) .* (abar + bbar) .* fbar .* hbar + gbar .* hbar.^2) .* (( ...
    abar .* gbar + (-1) .* fbar .* hbar).^2 + (bbar .* fbar + (-1) .* gbar .* hbar).^2), ...
    .^(-1 / 2), (abar .* bbar + (-1) .* hbar.^2).^(-1) .* (bbar.^2 .* fbar + (-1) .* ( ...
    abar + bbar) .* gbar .* hbar + fbar .* hbar.^2) .* ((abar .* gbar + (-1) .* fbar .* ...
    hbar).^2 + (bbar .* fbar + (-1) .* gbar .* hbar).^2).^(-1 / 2), (abar .* bbar + ( ...
    -1) .* hbar.^2).^(-1) .* (abar.^2 .* gbar + (-1) .* (abar + bbar) .* fbar .* hbar + ...
    gbar .* hbar.^2) .* ((abar .* gbar + (-1) .* fbar .* hbar).^2 + (bbar .* fbar + (-1) ...
    .* gbar .* hbar).^2).^(-1 / 2)];

dtheta = [(-1) .* gbar .* ((-1) .* bbar .* fbar + gbar .* hbar) .* ((abar .* gbar + (-1) .* ...
    fbar .* hbar).^2 + (bbar .* fbar + (-1) .* gbar .* hbar).^2).^(-1), ((-1) .* ...
    bbar .* fbar.^2 + abar .* gbar.^2) .* (bbar.^2 .* fbar.^2 + abar.^2 .* gbar.^2 + ( ...
    -2) .* (abar + bbar) .* fbar .* gbar .* hbar + (fbar.^2 + gbar.^2) .* hbar.^2).^( ...
    -1), (-1) .* fbar .* (abar .* gbar + (-1) .* fbar .* hbar) .* ((abar .* gbar + (-1) .* ...
    fbar .* hbar).^2 + (bbar .* fbar + (-1) .* gbar .* hbar).^2).^(-1), gbar .* ((-1) ...
    .* abar .* bbar + hbar.^2) .* (bbar.^2 .* fbar.^2 + abar.^2 .* gbar.^2 + (-2) .* ( ...
    abar + bbar) .* fbar .* gbar .* hbar + (fbar.^2 + gbar.^2) .* hbar.^2).^(-1), ...
    fbar .* (abar .* bbar + (-1) .* hbar.^2) .* (bbar.^2 .* fbar.^2 + abar.^2 .* ...
    gbar.^2 + (-2) .* (abar + bbar) .* fbar .* gbar .* hbar + (fbar.^2 + gbar.^2) .* ...
    hbar.^2).^(-1)];

dve = [bbar .* (bbar .* fbar + (-1) .* gbar .* hbar) .* ((-1) .* abar .* bbar + hbar.^2), ...
    .^(-2), ((-1) .* abar .* bbar + hbar.^2).^(-2) .* (abar .* bbar .* gbar + hbar .* ( ...
    (-2) .* bbar .* fbar + gbar .* hbar)), hbar .* ((-1) .* abar .* gbar + fbar .* hbar), ...
    .* ((-1) .* abar .* bbar + hbar.^2).^(-2), bbar .* ((-1) .* abar .* bbar + ...
    hbar.^2).^(-1), hbar .* (abar .* bbar + (-1) .* hbar.^2).^(-1)];

dvn = [hbar .* ((-1) .* bbar .* fbar + gbar .* hbar) .* ((-1) .* abar .* bbar + hbar.^2), ...
    .^(-2), ((-1) .* abar .* bbar + hbar.^2).^(-2) .* (abar .* bbar .* fbar + (-2) .* ...
    abar .* gbar .* hbar + fbar .* hbar.^2), abar .* (abar .* gbar + (-1) .* fbar .* ...
    hbar) .* ((-1) .* abar .* bbar + hbar.^2).^(-2), hbar .* (abar .* bbar + (-1) .* ...
    hbar.^2).^(-1), abar .* ((-1) .* abar .* bbar + hbar.^2).^(-1)];

dar = [(1 / 2) .* (abar + bbar).^(-1) .* ((abar + (-1) .* bbar) .* bbar + (-2) .* hbar.^2), ...
    .* (abar .* bbar + (-1) .* hbar.^2).^(-1) .* ((abar + bbar).^(-2) .* ((abar + ( ...
    -1) .* bbar).^2 + 4 .* hbar.^2)).^(-1 / 2) .* ((-1) .* ((-1) + ((abar + bbar).^( ...
    -2) .* ((abar + (-1) .* bbar).^2 + 4 .* hbar.^2)).^(1 / 2)).^(-1) .* (1 + ((abar + ...
    bbar).^(-2) .* ((abar + (-1) .* bbar).^2 + 4 .* hbar.^2)).^(1 / 2))).^(1 / 2), ...
    hbar .* (abar .* bbar + (-1) .* hbar.^2).^(-1) .* ((abar + bbar).^(-2) .* (( ...
    abar + (-1) .* bbar).^2 + 4 .* hbar.^2)).^(-1 / 2) .* ((-1) .* ((-1) + ((abar + ...
    bbar).^(-2) .* ((abar + (-1) .* bbar).^2 + 4 .* hbar.^2)).^(1 / 2)).^(-1) .* (1 + ...
    ((abar + bbar).^(-2) .* ((abar + (-1) .* bbar).^2 + 4 .* hbar.^2)).^(1 / 2))).^( ...
    1 / 2), (-1 / 2) .* (abar + bbar).^(-1) .* (abar .* bbar + (-1) .* hbar.^2).^(-1), .* , ...
    (abar.^2 + (-1) .* abar .* bbar + 2 .* hbar.^2) .* ((abar + bbar).^(-2) .* ((abar + ...
    (-1) .* bbar).^2 + 4 .* hbar.^2)).^(-1 / 2) .* ((-1) .* ((-1) + ((abar + bbar).^( ...
    -2) .* ((abar + (-1) .* bbar).^2 + 4 .* hbar.^2)).^(1 / 2)).^(-1) .* (1 + ((abar + ...
    bbar).^(-2) .* ((abar + (-1) .* bbar).^2 + 4 .* hbar.^2)).^(1 / 2))).^(1 / 2), 0, ...
    0];

dpsi = [(-1) .* hbar .* ((abar + (-1) .* bbar).^2 + 4 .* hbar.^2).^(-1), (abar + (-1) .* ...
    bbar) .* ((abar + (-1) .* bbar).^2 + 4 .* hbar.^2).^(-1), hbar .* ((abar + (-1) .* ...
    bbar).^2 + 4 .* hbar.^2).^(-1), 0, 0];

dvc = [(1 / 2) .* ((-1) .* abar .* bbar + hbar.^2).^(-2) .* ((abar .* gbar + (-1) .* ...
    fbar .* hbar).^2 + (bbar .* fbar + (-1) .* gbar .* hbar).^2).^(-1 / 2) .* ((-1) + ( ...
    bbar .* fbar.^2 + abar .* gbar.^2 + (-2) .* fbar .* gbar .* hbar).^(-1) .* (abar .* ...
    bbar + (-1) .* hbar.^2)).^(-1 / 2) .* ((bbar .* fbar + (-1) .* gbar .* hbar).^2 .* ( ...
    abar .* bbar + (-1) .* hbar.^2) .* (bbar.^2 .* fbar.^2 + abar.^2 .* gbar.^2 + (-2) ...
    .* (abar + bbar) .* fbar .* gbar .* hbar + (fbar.^2 + gbar.^2) .* hbar.^2) .* ( ...
    bbar .* fbar.^2 + gbar .* (abar .* gbar + (-2) .* fbar .* hbar)).^(-2) + (-2) .* ...
    gbar .* ((-1) .* abar .* gbar + fbar .* hbar) .* (abar .* bbar + (-1) .* hbar.^2) .* ( ...
    (-1) + (bbar .* fbar.^2 + abar .* gbar.^2 + (-2) .* fbar .* gbar .* hbar).^(-1) .* ( ...
    abar .* bbar + (-1) .* hbar.^2)) + (-2) .* bbar .* (bbar.^2 .* fbar.^2 + abar.^2 .* ...
    gbar.^2 + (-2) .* (abar + bbar) .* fbar .* gbar .* hbar + (fbar.^2 + gbar.^2) .* ...
    hbar.^2) .* ((-1) + (bbar .* fbar.^2 + abar .* gbar.^2 + (-2) .* fbar .* gbar .* ...
    hbar).^(-1) .* (abar .* bbar + (-1) .* hbar.^2))), (1 / 2) .* ((-1) .* abar .* ...
    bbar + hbar.^2).^(-2) .* ((abar .* gbar + (-1) .* fbar .* hbar).^2 + (bbar .* ...
    fbar + (-1) .* gbar .* hbar).^2).^(-1 / 2) .* ((-1) + (bbar .* fbar.^2 + abar .* ...
    gbar.^2 + (-2) .* fbar .* gbar .* hbar).^(-1) .* (abar .* bbar + (-1) .* hbar.^2)), ...
    .^(-1 / 2) .* (2 .* (abar .* gbar + (-1) .* fbar .* hbar) .* (bbar .* fbar + (-1) .* ...
    gbar .* hbar) .* (abar .* bbar + (-1) .* hbar.^2) .* (bbar.^2 .* fbar.^2 + ...
    abar.^2 .* gbar.^2 + (-2) .* (abar + bbar) .* fbar .* gbar .* hbar + (fbar.^2 + ...
    gbar.^2) .* hbar.^2) .* (bbar .* fbar.^2 + gbar .* (abar .* gbar + (-2) .* fbar .* ...
    hbar)).^(-2) + 2 .* ((-1) .* (abar + bbar) .* fbar .* gbar + (fbar.^2 + gbar.^2) .* ...
    hbar) .* (abar .* bbar + (-1) .* hbar.^2) .* ((-1) + (bbar .* fbar.^2 + abar .* ...
    gbar.^2 + (-2) .* fbar .* gbar .* hbar).^(-1) .* (abar .* bbar + (-1) .* hbar.^2)) ...
    +4 .* hbar .* (bbar.^2 .* fbar.^2 + abar.^2 .* gbar.^2 + (-2) .* (abar + bbar) .* ...
    fbar .* gbar .* hbar + (fbar.^2 + gbar.^2) .* hbar.^2) .* ((-1) + (bbar .* ...
    fbar.^2 + abar .* gbar.^2 + (-2) .* fbar .* gbar .* hbar).^(-1) .* (abar .* bbar + ( ...
    -1) .* hbar.^2))), (1 / 2) .* ((-1) .* abar .* bbar + hbar.^2).^(-2) .* ((abar .* ...
    gbar + (-1) .* fbar .* hbar).^2 + (bbar .* fbar + (-1) .* gbar .* hbar).^2).^( ...
    -1 / 2) .* ((-1) + (bbar .* fbar.^2 + abar .* gbar.^2 + (-2) .* fbar .* gbar .* hbar) ...
    .^(-1) .* (abar .* bbar + (-1) .* hbar.^2)).^(-1 / 2) .* ((abar .* gbar + (-1) .* ...
    fbar .* hbar).^2 .* (abar .* bbar + (-1) .* hbar.^2) .* (bbar.^2 .* fbar.^2 + ...
    abar.^2 .* gbar.^2 + (-2) .* (abar + bbar) .* fbar .* gbar .* hbar + (fbar.^2 + ...
    gbar.^2) .* hbar.^2) .* (bbar .* fbar.^2 + gbar .* (abar .* gbar + (-2) .* fbar .* ...
    hbar)).^(-2) + (-2) .* fbar .* ((-1) .* bbar .* fbar + gbar .* hbar) .* (abar .* ...
    bbar + (-1) .* hbar.^2) .* ((-1) + (bbar .* fbar.^2 + abar .* gbar.^2 + (-2) .* ...
    fbar .* gbar .* hbar).^(-1) .* (abar .* bbar + (-1) .* hbar.^2)) + (-2) .* abar .* ( ...
    bbar.^2 .* fbar.^2 + abar.^2 .* gbar.^2 + (-2) .* (abar + bbar) .* fbar .* gbar .* ...
    hbar + (fbar.^2 + gbar.^2) .* hbar.^2) .* ((-1) + (bbar .* fbar.^2 + abar .* ...
    gbar.^2 + (-2) .* fbar .* gbar .* hbar).^(-1) .* (abar .* bbar + (-1) .* hbar.^2)) ...
    ), ((abar .* gbar + (-1) .* fbar .* hbar).^2 + (bbar .* fbar + (-1) .* gbar .* hbar) ...
    .^2).^(-1 / 2) .* ((-1) + (bbar .* fbar.^2 + abar .* gbar.^2 + (-2) .* fbar .* ...
    gbar .* hbar).^(-1) .* (abar .* bbar + (-1) .* hbar.^2)).^(-1 / 2) .* (((-1) .* ...
    bbar .* fbar + gbar .* hbar) .* (bbar .* fbar.^2 + gbar .* (abar .* gbar + (-2) .* ...
    fbar .* hbar)).^(-2) .* ((abar .* gbar + (-1) .* fbar .* hbar).^2 + (bbar .* fbar + ...
    (-1) .* gbar .* hbar).^2) + (abar .* bbar + (-1) .* hbar.^2).^(-1) .* (bbar.^2 .* ...
    fbar + (-1) .* (abar + bbar) .* gbar .* hbar + fbar .* hbar.^2) .* ((-1) + (bbar .* ...
    fbar.^2 + abar .* gbar.^2 + (-2) .* fbar .* gbar .* hbar).^(-1) .* (abar .* bbar + ( ...
    -1) .* hbar.^2))), ((abar .* gbar + (-1) .* fbar .* hbar).^2 + (bbar .* fbar + (-1) ...
    .* gbar .* hbar).^2).^(-1 / 2) .* ((-1) + (bbar .* fbar.^2 + abar .* gbar.^2 + (-2) ...
    .* fbar .* gbar .* hbar).^(-1) .* (abar .* bbar + (-1) .* hbar.^2)).^(-1 / 2) .* (( ...
    (-1) .* abar .* gbar + fbar .* hbar) .* (bbar .* fbar.^2 + gbar .* (abar .* gbar + ( ...
    -2) .* fbar .* hbar)).^(-2) .* ((abar .* gbar + (-1) .* fbar .* hbar).^2 + (bbar .* ...
    fbar + (-1) .* gbar .* hbar).^2) + (abar .* bbar + (-1) .* hbar.^2).^(-1) .* ( ...
    abar.^2 .* gbar + (-1) .* (abar + bbar) .* fbar .* hbar + gbar .* hbar.^2) .* ((-1) + ...
    (bbar .* fbar.^2 + abar .* gbar.^2 + (-2) .* fbar .* gbar .* hbar).^(-1) .* ( ...
    abar .* bbar + (-1) .* hbar.^2)))];

J = [dv; dtheta; dve; dvn; dar; dpsi; dvc];

if vc >= v
    disp('Warning! Characteristic Velocity is larger than Apparent Velocity');
elseif imag(vc) == abs(vc)
    disp('Warning! Characteristic Velocity is imaginary')
end

varargout = {mean([v; theta; ve; vn; ar; psi; vc], 2, 'omitnan'), ...
    J, mean(major, 'omitnan'), mean(minor, 'omitnan'), ...
    std([v; theta; ve; vn; ar; psi; vc], 0, 2, 'omitnan')};
end