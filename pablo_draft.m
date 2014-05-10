clear all
clc
close all

%% IMPORT MESH

eleType = 'AHMAD9';
n = 10;
switch eleType
    case 'AHMAD9'
        nodes_per_ele = 9;
        vdof = [1:3 6:8 11:13 16:18 21:23 26:28 31:33 36:38 41:43];
        coords_in = load(['tests/scordelis/nodos' num2str(n) '_9.txt']);
        connect_in = load(['tests/scordelis/elementos' num2str(n) '_9.txt']);
    case 'AHMAD8'
        nodes_per_ele = 8;
        vdof = [1:3 6:8 11:13 16:18 21:23 26:28 31:33 36:38];
        coords_in = load(['tests/scordelis/nodos' num2str(n) '_8.txt']);
        connect_in = load(['tests/scordelis/elementos' num2str(n) '_8.txt']);
    case 'AHMAD4'
        nodes_per_ele = 4;
        vdof = [1:3 6:8 11:13 16:18];
        coords_in = load(['tests/scordelis/nodos' num2str(n) '_4.txt']);
        connect_in = load(['tests/scordelis/elementos' num2str(n) '_4.txt']);        
end

% Format Input Mesh

% Remove Extra Columns
coords_in(:,[1 end]) = [];
connect_in(:,1) = [];
% Clean and reformat mesh.connect Matrix
connect_in(connect_in == 0) = [];
connect_in = reshape(connect_in,[],nodes_per_ele);

to = 0.0025;
t = to*ones(1,size(coords_in,1));

mesh = Mesh(eleType,coords_in,connect_in,t);
dofs_per_node = 5;                      % Dofs per Node
dofs_per_ele = 0;
n_dofs = mesh.n_dofs(dofs_per_node,dofs_per_ele);


%% BC

bc = false(mesh.n_nodes,dofs_per_node);
tol = 1e-3;
bc(coords_in(:,1) < tol,[2 3]) = true;       % borde apoyado
bc(coords_in(:,2) < tol,[2 4]) = true;       % simetría longitudinal
bc(coords_in(:,1) > 25 - tol,[1 5]) = true;  % simetría transversal

% nodalForces = zeros(mesh.n_nodes,dofs_per_node);

% Draw_Placas(mesh.connect,coords,'k')

%% PHYSICAL PROPERTIES


E = 4.32E8;
nu = 0.0;
material = Material(E,nu,1);
% D1 = E/(1 - nu^2);
% G = 0.5*E/(1 + nu);
% c = 5/6;
% D = [    D1 nu*D1  0   0   0
%       nu*D1    D1  0   0   0
%           0     0  G   0   0
%           0     0  0 c*G   0
%           0     0  0   0 c*G ];

%% Matriz de rigidez
K = zeros(n_dofs);

%% Flexión y membrana
% Puntos y pesos de Gauss
% How many gauss points along each direction?
rstInt = 3*ones(1,3);
[wgauss, gpts, ng] = Integral.gauss(rstInt);
% wgauss:   Gauss Weights
% gpts:     Evaluation points for each coordinates
% ng:       Number of evaluation points

% Loop through all mesh.connect, computing their stiffness matrix
for iele = 1:mesh.n_ele
    Ks = zeros(dofs_per_node*nodes_per_ele);
    element = mesh.ele(eleType,iele);
    
%     % Integrate Ks with #ng gauss points
%     for ig = 1:ng
%         ksi  = gpts(ig,1);
%         eta  = gpts(ig,2);
%         zeta = gpts(ig,3);
%         
% %         jac = element.shelljac(ksi,eta,zeta);
% %         dJac = det(jac);
% % 
% %         B = element.B(dofs_per_node,ksi,eta,zeta);
% %         T = Element.T(jac);
% %         
% %         B = T*B;    % Cook [7.3-10]
% %         
% %         K_in_point = B'*D*B*dJac*wgauss(ig);
%         % Integration.
%         Ks = Ks + K_in_point;
%     end
    Ks = Physics.K_Shell2(element,material,3);
    eleDofs = node2dof(mesh.ele_nodes(iele),dofs_per_node);
    K(eleDofs,eleDofs) = K(eleDofs,eleDofs) + Ks;
end

%% Vector de cargas

% Puntos y pesos de Gauss
rstInt = 3*ones(1,3);
[wgauss, gpts, ng] = Integral.gauss(rstInt);

R = zeros(n_dofs,1);
b = [0 0 -360]';
for iele = 1:mesh.n_ele
    re = zeros((dofs_per_node - 2)*nodes_per_ele,1);
    element = mesh.ele(eleType,iele);
    elecoords = mesh.connect(iele,:);
    v = mesh.normals(:,:,elecoords);
    v3 = squeeze(v(:,3,:));
    tEle = t(elecoords);
    nodalCoords = coords_in(elecoords,:);
    for ig = 1:ng
        ksi  = gpts(ig,1);
        eta  = gpts(ig,2);
        zeta = gpts(ig,3);
        [N,NN]  = Element.shapefuns([ksi,eta],eleType);
        dN = Element.shapefunsder([ksi,eta],eleType);
        jac = element.shelljac(ksi,eta,zeta);
%         jac = Element.shelljac(N,dN,zeta,nodalCoords,tEle,v3);
        dJac = det(jac);

        re = re + NN'*dJac*wgauss(ig)*b;
    end
    eleDofs = node2dof(elecoords,dofs_per_node);
    R(eleDofs(vdof)) = R(eleDofs(vdof)) + re;
end
%%

% nodalForces = nodalForces';
% R = nodalForces(:);

fixed = reshape(bc',[],1);
free = ~fixed;

Ur = K(free,free)\R(free);

U = zeros(n_dofs,1);
U(free) = Ur;

U = (reshape(U,[],mesh.n_nodes))';

max(abs(U))

% Draw_Placas(mesh.connect,coords + U(:,1:3),'b')

% para t = 2.5000 Dz = -0.0266792 (ADINA) 1/10
% -0.026570686677499 AHMAD9
% para t = 0.2500 Dz = -0.3024  (REF)   -0.302397 (ADINA) 1/100
% -0.299240246836452 AHMAD9
% para t = 0.0250 Dz = -3.21412 (ADINA) 1/1000
% -2.072900027933127 AHMAD9
% para t = 0.0025 Dz = -3.25761E+01  (ADINA) 1/10000
% -2.800824498499196 AHMAD9

