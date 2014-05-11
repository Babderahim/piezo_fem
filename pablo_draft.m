clear all
clc
close all

%% IMPORT MESH

ele_type = 'AHMAD9';
n = 10;
switch ele_type
    case 'AHMAD9'
        nodes_per_ele = 9;
        % vdof: DOFs in K that are not rotational
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

mesh = Mesh(ele_type,coords_in,connect_in,t);
dofs_per_node = 5;                      % Dofs per Node
dofs_per_ele = 0;
n_dofs = mesh.n_dofs(dofs_per_node,dofs_per_ele);

%% PHYSICAL PROPERTIES

E = 4.32E8;
nu = 0.0;
material = Material(E,nu,1);

%% FEM

fun_in = @(element) Physics.K_Shell2(element,material,3);
physics = Physics(dofs_per_node,dofs_per_ele,fun_in);
fem = FemCase(mesh,physics);

%% Vector de cargas

% Puntos y pesos de Gauss
rstInt = 3*ones(1,3);
[wgauss, gpts, ng] = Integral.gauss(rstInt);

R = zeros(n_dofs,1);
q = [0 0 -360]';

% R = mesh.assembly_vector(dofs_per_node,dofs_per_ele,fun_in);
% Assembly
for e = 1:mesh.n_ele
    element = mesh.ele(e);
    elecoords = mesh.connect(e,:);
    re = Physics.apply_load(element,3,q);
    ele_dofs = mesh.all_eles_dofs(dofs_per_node,dofs_per_ele,e);
    R(ele_dofs(vdof)) = R(ele_dofs(vdof)) + re;
end

fem.loads.node_vals.dof_list_in(R);

%% BC

bc = false(mesh.n_nodes,dofs_per_node);
tol = 1e-3;
bc(coords_in(:,1) < tol,[2 3]) = true;       % borde apoyado
bc(coords_in(:,2) < tol,[2 4]) = true;       % simetría longitudinal
bc(coords_in(:,1) > 25 - tol,[1 5]) = true;  % simetría transversal

fem.bc.node_vals.vals = bc;

%% Solution

fem.solve();

U = fem.dis.node_vals.vals;

max(abs(U))

%% PLOT 

scale = 1;
PlotMesh(mesh.coords + scale*fem.dis.node_vals.vals(:,1:3), ...
    mesh.connect, ...
    ~fem.bc.node_vals.vals, ...
                fem.reactions.node_vals.vals);

%% Expected Solutions

% Draw_Placas(mesh.connect,coords + U(:,1:3),'b')

% para t = 2.5000 Dz = -0.0266792 (ADINA) 1/10
% -0.026570686677499 AHMAD9
% para t = 0.2500 Dz = -0.3024  (REF)   -0.302397 (ADINA) 1/100
% -0.299240246836452 AHMAD9
% para t = 0.0250 Dz = -3.21412 (ADINA) 1/1000
% -2.072900027933127 AHMAD9
% para t = 0.0025 Dz = -3.25761E+01  (ADINA) 1/10000
% -2.800824498499196 AHMAD9

