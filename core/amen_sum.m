function [y,z]=amen_sum(X, c, tol, varargin)
%Approximate the linear combination of TT tensors via the AMEn iteration
%   [y,z]=amen_sum(X, v, tol, varargin)
%   Attempts to approximate the y(j) = sum_i X{i}*c(i,j)
%   with accuracy TOL using the AMEn+ALS iteration.
%
%   Options are provided in form
%   'PropertyName1',PropertyValue1,'PropertyName2',PropertyValue2 and so
%   on. The parameters are set to default (in brackets in the following)
%   The list of option names and default values are:
%       o y0 - initial approximation to y [rand rank-2]
%       o nswp - maximal number of sweeps [20]
%       o verb - verbosity level, 0-silent, 1-sweep info, 2-block info [1]
%       o kickrank - compression rank of the error, 
%         i.e. enrichment size [3]
%       o init_qr - perform QR of the input (save some time in ts, etc) [true]
%       o renorm - Orthog. and truncation methods: direct (svd,qr) or gram
%         (apply svd to the gram matrix, faster for m>>n) [direct]
%       o fkick - Perform solution enrichment during forward sweeps [false]
%         (rather questionable yet; false makes error higher, but "better
%         structured": it does not explode in e.g. subsequent matvecs)
%       o z0 - initial approximation to the error Ax-y [rand rank-kickrank]
%
%
%********
%   For description of adaptive ALS please see
%   Sergey V. Dolgov, Dmitry V. Savostyanov,
%   Alternating minimal energy methods for linear systems in higher dimensions. 
%   Part I: SPD systems, http://arxiv.org/abs/1301.6068,
%   Part II: Faster algorithm and application to nonsymmetric systems, http://arxiv.org/abs/1304.1222
%
%   Use {sergey.v.dolgov, dmitry.savostyanov}@gmail.com for feedback
%********
%
% TT-Toolbox 2.2, 2009-2012
%
%This is TT Toolbox, written by Ivan Oseledets et al.
%Institute of Numerical Mathematics, Moscow, Russia
%webpage: http://spring.inm.ras.ru/osel
%
%For all questions, bugs and suggestions please mail
%ivan.oseledets@gmail.com
%---------------------------

if (~isempty(varargin))
    v1 = varargin{1};
    if (isa(v1, 'cell'))
        varargin=v1;
    end;
end;

nswp = 20;
kickrank = 4;
verb = 1;
y = [];
z = [];
init_qr = true;
renorm = 'direct';
% renorm = 'gram';
fkick = false;
% fkick = true;

for i=1:2:length(varargin)-1
    switch lower(varargin{i})
        case 'nswp'
            nswp=varargin{i+1};
        case 'y0'
            y=varargin{i+1};
        case 'z0'
            z=varargin{i+1};            
        case 'verb'
            verb=varargin{i+1};
        case 'kickrank'
            kickrank=varargin{i+1};
        case 'init_qr'
            init_qr = varargin{i+1};
        case 'renorm'
            renorm = varargin{i+1};
        case 'fkick'
            fkick = varargin{i+1};            
            
        otherwise
            warning('Unrecognized option: %s\n',varargin{i});
    end
end

N = size(c,1);
M = size(c,2);

for j=1:N
    if (isa(X{j}, 'tt_tensor'))
        if (j==1)
            d = X{j}.d;
            n = X{j}.n;
            rx = zeros(d+1,N);
        end;
        rx(:,j) = X{j}.r;
        X{j} = core2cell(X{j});
        vectype = 1; % tt_tensor        
    else
        if (j==1)
            d = numel(X{j});
            n = zeros(d,1);
            rx = ones(d+1,N);
            for i=1:d
                n(i) = size(X{j}{i}, 2);
            end;
        end;
        for i=1:d
            rx(i+1,j) = size(X{j}{i}, 3);
        end;
        vectype = 0; % cell
    end;
end;

if (isempty(y))
    y = cell(d,1);
    y{1} = rand(1, n(1), 2);
    for i=2:d-1
        y{i} = rand(2, n(i), 2);
    end;
    y{d} = rand(2, n(d), 1);
else
    if (isa(y, 'tt_tensor'))
        y = core2cell(y);
    end;
end;
ry = ones(d+1,1);
for i=1:d
    ry(i+1) = size(y{i}, 3);
end;

if (kickrank>0)
    if (isempty(z))
        z = cell(d,1);
        rz = [1; kickrank*ones(d-1, 1); 1];
        z{1} = rand(1, n(1), kickrank);
        for i=2:d-1
            z{i} = rand(kickrank, n(i), kickrank);
        end;
        z{d} = rand(kickrank, n(d), 1);
    else
        if (isa(z, 'tt_tensor'))
            z = core2cell(z);
        end;
        rz = ones(d+1,1);
        for i=1:d
            rz(i+1) = size(z{i}, 3);
        end;
    end;
    
    phizx = cell(d+1,N); 
    for j=1:N
        phizx{1,j}=1; phizx{d+1,j}=1;
    end;
    phizy = cell(d+1,1); phizy{1}=1; phizy{d+1}=1;
end;

phiyx = cell(d+1,N);
for j=1:N
    phiyx{1,j}=1; phiyx{d+1,j}=1;
end;

% Initial ort
for i=1:d-1
    if (init_qr)
        cr = reshape(y{i}, ry(i)*n(i), ry(i+1));
        if (strcmp(renorm, 'gram'))&&(ry(i)*n(i)>5*ry(i+1))
            [cr,s,R]=svdgram(cr);
        else
            [cr,R]=qr(cr, 0);
        end;
        cr2 = reshape(y{i+1}, ry(i+1), n(i+1)*ry(i+2));
        cr2 = R*cr2;
        ry(i+1) = size(cr, 2);
        y{i} = reshape(cr, ry(i), n(i), ry(i+1));
        y{i+1} = reshape(cr2, ry(i+1), n(i+1), ry(i+2));
    end;
    for j=1:N
        phiyx{i+1,j} = compute_next_Phi(phiyx{i,j}, y{i}, [], X{j}{i}, 'lr');
    end;
    
    if (kickrank>0)
        cr = reshape(z{i}, rz(i)*n(i), rz(i+1));
        if (strcmp(renorm, 'gram'))&&(rz(i)*n(i)>5*rz(i+1))
            [cr,s,R]=svdgram(cr);
        else
            [cr,R]=qr(cr, 0);
        end;
        cr2 = reshape(z{i+1}, rz(i+1), n(i+1)*rz(i+2));
        cr2 = R*cr2;
        rz(i+1) = size(cr, 2);
        z{i} = reshape(cr, rz(i), n(i), rz(i+1));
        z{i+1} = reshape(cr2, rz(i+1), n(i+1), rz(i+2));
        for j=1:N
            phizx{i+1,j} = compute_next_Phi(phizx{i,j}, z{i}, [], X{j}{i}, 'lr');
        end;
        phizy{i+1} = compute_next_Phi(phizy{i}, z{i}, [], y{i}, 'lr');
    end;
end;

i = d;
dir = -1;
swp = 1;
max_dx = 0;
y{d} = reshape(y{d}, ry(d)*n(d), ry(d+1));
y{d} = y{d}(:,1:min(ry(d+1), M));
y{d} = [y{d}, zeros(ry(d)*n(d), M-ry(d+1))];
y{d} = reshape(y{d}, ry(d), n(d), 1, M);
ry(d+1) = 1;

while (swp<=nswp)
    % Project the sum
    cry = zeros(ry(i)*n(i)*ry(i+1), N);
    for j=1:N
        cryj = reshape(X{j}{i}, rx(i,j), n(i)*rx(i+1,j));
        cryj = phiyx{i,j}*cryj;
        cryj = reshape(cryj, ry(i)*n(i), rx(i+1,j));
        cryj = cryj*phiyx{i+1,j};
        cry(:,j) = reshape(cryj, ry(i)*n(i)*ry(i+1), 1);
    end;
    cry = cry*c;
    
    y{i} = reshape(y{i}, ry(i)*n(i)*ry(i+1), M);
    dx = norm(cry-y{i}, 'fro')/norm(cry, 'fro');
    max_dx = max(max_dx, dx);
    
    % Truncation and enrichment
    if ((dir>0)&&(i<d))
        cry = reshape(cry, ry(i)*n(i), ry(i+1)*M);
        if (strcmp(renorm, 'gram'))
            [u,s,v]=svdgram(cry, tol/sqrt(d));
            v = v.';
            r = size(u,2);
        else
            [u,s,v]=svd(cry, 'econ');
            s = diag(s);
            r = my_chop2(s, tol*norm(s)/sqrt(d));
            u = u(:,1:r);
            v = conj(v(:,1:r))*diag(s(1:r));
        end;        
        
        % Prepare enrichment, if needed
        if (kickrank>0)
            cry = u*v.';
            cry = reshape(cry, ry(i)*n(i)*ry(i+1), M);
            % For updating z
            crys = cry.';
            crys = reshape(crys, M*ry(i)*n(i), ry(i+1));
            crys = crys*phizy{i+1};
            crys = reshape(crys, M, ry(i)*n(i)*rz(i+1));
            crys = crys.';
            cryz = reshape(crys, ry(i), n(i)*rz(i+1)*M);
            cryz = phizy{i}*cryz;
            cryz = reshape(cryz, rz(i)*n(i)*rz(i+1), M);
            crz = zeros(rz(i)*n(i)*rz(i+1), N);
            for j=1:N
                crzj = reshape(X{j}{i}, rx(i,j), n(i)*rx(i+1,j));
                crzj = phizx{i,j}*crzj;
                crzj = reshape(crzj, rz(i)*n(i), rx(i+1,j));
                crzj = crzj*phizx{i+1,j};
                crz(:,j) = reshape(crzj, rz(i)*n(i)*rz(i+1), 1);
            end;
            crz = crz*c;
            crz = crz - cryz;
            crz = reshape(crz, rz(i)*n(i), rz(i+1)*M);
            [crz,sz,vz]=svd(crz, 'econ');
            crz = crz(:, 1:min(size(crz,2), kickrank));
            % For adding into solution
            if (fkick)
                crs = zeros(ry(i)*n(i)*rz(i+1), N);
                for j=1:N
                    crsj = reshape(X{j}{i}, rx(i,j), n(i)*rx(i+1,j));
                    crsj = phiyx{i,j}*crsj;
                    crsj = reshape(crsj, ry(i)*n(i), rx(i+1,j));
                    crsj = crsj*phizx{i+1,j};
                    crs(:,j) = reshape(crsj, ry(i)*n(i)*rz(i+1), 1);
                end;
                crs = crs*c;
                crs = crs - crys;
                crs = reshape(crs, ry(i)*n(i), rz(i+1)*M);
                [crs,sz,vz]=svd(crs, 'econ');
                crs = crs(:, 1:min(size(crs,2), kickrank));
                u = [u,crs];
                if (strcmp(renorm, 'gram'))&&(ry(i)*n(i)>5*(ry(i+1)+rz(i+1)))
                    [u,s,R]=svdgram(u);
                else
                    [u,R]=qr(u, 0);
                end;
                v = [v, zeros(ry(i+1)*M, size(crs,2))];
                v = v*R.';
                r = size(u, 2);
            end;
        end;
        y{i} = reshape(u, ry(i), n(i), r);
        
        cr2 = reshape(y{i+1}, ry(i+1), n(i+1)*ry(i+2));
        v = reshape(v, ry(i+1), M*r);
        cr2 = v.'*cr2;
        cr2 = reshape(cr2, M, r*n(i+1)*ry(i+2));
        y{i+1} = reshape(cr2.', r, n(i+1), ry(i+2), M);
        
        ry(i+1) = r;
        
        for j=1:N
            phiyx{i+1,j} = compute_next_Phi(phiyx{i,j}, y{i}, [], X{j}{i}, 'lr');
        end;
        
        if (kickrank>0)
            rz(i+1) = size(crz, 2);
            z{i} = reshape(crz, rz(i), n(i), rz(i+1));
            % z{i+1} will be recomputed from scratch in the next step
            for j=1:N
                phizx{i+1,j} = compute_next_Phi(phizx{i,j}, z{i}, [], X{j}{i}, 'lr');
            end;
            phizy{i+1} = compute_next_Phi(phizy{i}, z{i}, [], y{i}, 'lr');
        end;
    elseif ((dir<0)&&(i>1))
        cry = reshape(cry.', M*ry(i), n(i)*ry(i+1));
        [u,s,v]=svd(cry, 'econ');
        s = diag(s);
        r = my_chop2(s, tol*norm(s)/sqrt(d));
        u = u(:,1:r)*diag(s(1:r));
        v = conj(v(:,1:r));
        
        % Prepare enrichment, if needed
        if (kickrank>0)
            cry = u*v.';
            cry = reshape(cry, M, ry(i)*n(i)*ry(i+1));
            % For updating z
            crys = cry.';
            crys = reshape(crys, ry(i), n(i)*ry(i+1)*M);
            crys = phizy{i}*crys;
            crys = reshape(crys, rz(i)*n(i)*ry(i+1), M);
            cryz = reshape(crys.', M*rz(i)*n(i), ry(i+1));
            cryz = cryz*phizy{i+1};
            cryz = reshape(cryz, M, rz(i)*n(i)*rz(i+1));
            cryz = cryz.';
            crz = zeros(rz(i)*n(i)*rz(i+1), N);
            for j=1:N
                crzj = reshape(X{j}{i}, rx(i,j), n(i)*rx(i+1,j));
                crzj = phizx{i,j}*crzj;
                crzj = reshape(crzj, rz(i)*n(i), rx(i+1,j));
                crzj = crzj*phizx{i+1,j};
                crz(:,j) = reshape(crzj, rz(i)*n(i)*rz(i+1), 1);
            end;
            crz = crz*c;
            crz = crz - cryz;
            crz = reshape(crz.', M*rz(i), n(i)*rz(i+1));
            [vz,sz,crz]=svd(crz, 'econ');
            crz = crz(:, 1:min(size(crz,2), kickrank));
            crz = crz';
            % For adding into solution
                crs = zeros(rz(i)*n(i)*ry(i+1), N);
                for j=1:N
                    crsj = reshape(X{j}{i}, rx(i,j), n(i)*rx(i+1,j));
                    crsj = phizx{i,j}*crsj;
                    crsj = reshape(crsj, rz(i)*n(i), rx(i+1,j));
                    crsj = crsj*phiyx{i+1,j};
                    crs(:,j) = reshape(crsj, rz(i)*n(i)*ry(i+1), 1);
                end;
                crs = crs*c;
                crs = crs - crys;
                crs = reshape(crs.', M*rz(i), n(i)*ry(i+1));
                [vz,sz,crs]=svd(crs, 'econ');
                crs = crs(:, 1:min(size(crs,2), kickrank));
                v = [v,conj(crs)];
                if (strcmp(renorm, 'gram'))&&(ry(i+1)*n(i)>5*(ry(i)+rz(i)))
                    [v,s,R]=svdgram(v);
                else
                    [v,R]=qr(v, 0);
                end;
                u = [u, zeros(M*ry(i), size(crs,2))];
                u = u*R.';
                r = size(v, 2);
        end;
        y{i} = reshape(v.', r, n(i), ry(i+1));
        
        cr2 = reshape(y{i-1}, ry(i-1)*n(i-1), ry(i));
        u = reshape(u, M, ry(i)*r);
        u = u.';
        u = reshape(u, ry(i), r*M);
        cr2 = cr2*u;
        cr2 = reshape(cr2, ry(i-1), n(i-1), r, M);
        y{i-1} = cr2;
        
        ry(i) = r;
        
        for j=1:N
            phiyx{i,j} = compute_next_Phi(phiyx{i+1,j}, y{i}, [], X{j}{i}, 'rl');
        end;
        
        if (kickrank>0)
            rz(i) = size(crz, 1);
            z{i} = reshape(crz, rz(i), n(i), rz(i+1));
            % z{i+1} will be recomputed from scratch in the next step
            for j=1:N
                phizx{i,j} = compute_next_Phi(phizx{i+1,j}, z{i}, [], X{j}{i}, 'rl');
            end;
            phizy{i} = compute_next_Phi(phizy{i+1}, z{i}, [], y{i}, 'rl');
        end;
    else
        y{i} = reshape(y{i}, ry(i), n(i), ry(i+1), M);
    end;
    
    if (verb>1)
        fprintf('amen-sum: swp=[%d,%d], dx=%3.3e, r=%d\n', swp, i, dx, r);
    end;
    
    % Stopping or reversing
    if ((dir>0)&&(i==d))||((dir<0)&&(i==1))
        if (verb>0)
            fprintf('amen-sum: swp=%d{%d}, max_dx=%3.3e, max_r=%d\n', swp, (1-dir)/2, max_dx, max(ry));
        end;
        if ((max_dx<tol)||(swp==nswp))&&(dir>0)
            break;
        end;
        if (dir<0); max_dx = 0; end;
        if (dir>0); swp = swp+1; end;
        dir = -dir;
    else
        i = i+dir;
    end;
end;
y{d} = reshape(cry, ry(d), n(d), M);
if (vectype==1)
    y = cell2core(tt_tensor, y);
    z = cell2core(tt_tensor, z);
end;
end


% new
function [Phi] = compute_next_Phi(Phi_prev, x, A, y, direction)
% Performs the recurrent Phi (or Psi) matrix computation
% Phi = Phi_prev * (x'Ay).
% If direction is 'lr', computes Psi
% if direction is 'rl', computes Phi
% A can be empty, then only x'y is computed.

% Phi1: rx1, ry1, ra1, or {rx1, ry1}_ra, or rx1, ry1
% Phi2: ry2, ra2, rx2, or {ry2, rx2}_ra, or ry2, rx2


rx1 = size(x,1); n = size(x,2); rx2 = size(x,3);
ry1 = size(y,1); m = size(y,2); ry2 = size(y,3);
if (~isempty(A))
    if (isa(A, 'cell'))
        % A is a canonical block
        ra = numel(A); 
    else
        % Just full format
        ra1 = size(A,1)/n; ra2 = size(A,2)/m;
    end;
else
    ra1 = 1; ra2 = 1;
end;

if (isa(Phi_prev, 'cell'))
    Phi = cell(ra, 1);
    if (strcmp(direction, 'lr'))
        %lr: Phi1
        x = reshape(x, rx1, n*rx2);
        y = reshape(y, ry1*m, ry2);
        for i=1:ra
            Phi{i} = x'*Phi_prev{i};
            Phi{i} = reshape(Phi{i}, n, rx2*ry1);            
            Phi{i} = Phi{i}.';            
            Phi{i} = Phi{i}*A{i};
            Phi{i} = reshape(Phi{i}, rx2, ry1*m);
            Phi{i} = Phi{i}*y;
        end;
    else
        %rl: Phi2
        y = reshape(y, ry1, m*ry2);
        x = reshape(x, rx1*n, rx2);
        for i=1:ra
            Phi{i} = Phi_prev{i}*x';
            Phi{i} = reshape(Phi{i}, ry2*rx1, n);
            Phi{i} = Phi{i}*A{i};
            Phi{i} = Phi{i}.';
            Phi{i} = reshape(Phi{i}, m*ry2, rx1);
            Phi{i} = y*Phi{i};
        end;
    end;
else
    if (strcmp(direction, 'lr'))
        %lr: Phi1
        x = reshape(x, rx1, n*rx2);
        Phi = reshape(Phi_prev, rx1, ry1*ra1);
        Phi = x'*Phi;
        if (~isempty(A))
            Phi = reshape(Phi, n*rx2*ry1, ra1);
            Phi = Phi.';
            Phi = reshape(Phi, ra1*n, rx2*ry1);
            Phi = A.'*Phi;
            Phi = reshape(Phi, m, ra2*rx2*ry1);
        else
            Phi = reshape(Phi, n, rx2*ry1);
        end;
        Phi = Phi.';
        Phi = reshape(Phi, ra2*rx2, ry1*m);        
        y = reshape(y, ry1*m, ry2);
        Phi = Phi*y;
        if (~isempty(A))
            Phi = reshape(Phi, ra2, rx2*ry2);
            Phi = Phi.';
        end;
        Phi = reshape(Phi, rx2, ry2, ra2);
    else
        %rl: Phi2
        y = reshape(y, ry1*m, ry2);
        Phi = reshape(Phi_prev, ry2, ra2*rx2);
        Phi = y*Phi;
        if (~isempty(A))
            Phi = reshape(Phi, ry1, m*ra2*rx2);
            Phi = Phi.';
            Phi = reshape(Phi, m*ra2, rx2*ry1);
            Phi = A*Phi;
            Phi = reshape(Phi, ra1*n*rx2, ry1);
            Phi = Phi.';
        end;        
        Phi = reshape(Phi, ry1*ra1, n*rx2);
        x = reshape(x, rx1, n*rx2);
        Phi = Phi*x';
        if (~isempty(A))
            Phi = reshape(Phi, ry1, ra1, rx1);
        else
            Phi = reshape(Phi, ry1, rx1);
        end;
    end;
end;

end