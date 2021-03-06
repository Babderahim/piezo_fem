clear all
clc
%% PRELIMINARY ANALYSIS AND PARAMETERS
% Geometry
a       = 0.5;          % X Side length [m]
b       = 0.05;         % Y Side length [m]
t_al    = 1e-3;         % Shell Thickness [m]
t_pzt   = 0.7e-3;       % Piezo Stripe thicknes [m]

% Aluminum properties
E_al    = 69e9;         % Elasticity Modulus [Pa]
nu_al   = 0.3;          % Poisson Coefficient
rho_al  = 2700;         % Density [kg/m3]

% PZT properties, we assume it adds no rigdity or mass
E_pzt   = 0;
nu_pzt  = 0;
rho_pzt = 0;
d13 = -0.046*(1e3);     % [(1e-3)C/m2] Piezo constant
e3  = (1e3)*0.01062e-9; % [(1e-3)C/Nm2] Permitivity

% Beam Theory analysis
A = b*t_al;        % Area [m2]
I = b*(t_al^3)/12; % Second moment of Area [m4]
F = 5e6;

% Expected Frequencies
c = sqrt(E_al*I/(A*rho_al*a^4));
lambda = [1.875,4.694,7.885]';
expected_f = (lambda.^2)*c/(2*pi);

%% Laminate and Material
piezo_matrix = zeros(3,6);
piezo_matrix(3,1:3) = [d13 d13 0];
pzt = Material.Piezo(E_pzt,nu_pzt,rho_pzt,piezo_matrix,[0 0 e3]);
aluminum = Material(E_pzt,nu_al,rho_al);

% Add a dummy material to aluminum instead of the pzt to keep a constant 
% thickness in all layers -> t_layers
empty_mat   = Material(0,0,0);
t_layers    = [t_al,t_pzt];
al_layer    = Laminate([aluminum,empty_mat],t_layers);
composite   = Laminate([aluminum,pzt],t_layers);

%% FEM and MESH
% Elements along the side
dofs_per_node = 5;
dofs_per_ele = 0;
n = 8;

% Start the mesh with aluminum, then correct it
mesh = Factory.ShellMesh(EleType.AHMAD8,al_layer,[2*n,n],[a,b,t_al]);

% Assign the Laminates to the elements.
stripe_length = 70e-3;
stripe_start   = 30e-3;
f_in_stripe = @(x,y,z) ((x > stripe_start) && (x < stripe_length + stripe_start));
in_stripe_n = find(mesh.find_nodes(f_in_stripe));
% If the elemnt contains a node in it, it's in it.
ele_ids = [];
for i = 1:length(in_stripe_n)
    node_id = in_stripe_n(i);
    aux = mesh.node_eles(node_id);
    ele_ids = [ele_ids aux{1}];
end
ele_ids = unique(ele_ids);
% Filter elements. Must have at least 6 nodes
pzt_eles = [];
for i = 1:length(ele_ids)
    ele_nodes = mesh.ele_nodes(ele_ids(i));
    node_count = 0;
    for j = 1:length(ele_nodes)
        if any(in_stripe_n == ele_nodes(j))
            node_count = node_count + 1;
        end
    end
    if node_count >= 6
        pzt_eles = [pzt_eles ele_ids(i)];
    end
end

mesh.laminate_ids(1:end)    = 1;
mesh.laminate_ids(pzt_eles) = 2;
mesh.laminates = [al_layer,composite];

%% Accelerometer
total_mass = 0.006;
tol = 1e-9;
between = @(a,b,x) ((x >= a) && (x <= b));
f_acc = @(x,y,z) (between(0.4,0.45,x) && between(0.02,0.03,y));
accelerometer_nodes = find(mesh.find_nodes(f_acc));
total_nodes = length(accelerometer_nodes);
mass_values = total_mass*ones(total_nodes,1)/total_nodes;
mesh = mesh.add_point_mass(accelerometer_nodes,mass_values);
mesh.plot();
axis equal

M = @(element) Physics.M_Shell(element,3);
K = @(element) Physics.K_Shell(element,3);
physics = Physics.Dynamic(dofs_per_node,dofs_per_ele,K,M);
fem = FemCase(mesh,physics);

%% BC
% Fixed End
tol = 1e-9;
x0_edge = (@(x,y,z) (abs(x) < tol));
base = mesh.find_nodes(x0_edge);
fem.bc.node_vals.set_val(base,true);

%% LOADS
% Load the other side
f_border = (@(x,y,z) (abs(x-a) < tol));
border = find(mesh.find_nodes(f_border));
q = [0 0 F 0 0]';
load_fun = @(element,sc,sv) Physics.apply_surface_load( ...
    element,2,q,sc,sv);
L = mesh.integral_along_surface(dofs_per_node,dofs_per_ele, ...
    border,load_fun);
fem.loads.node_vals.dof_list_in(L);

%% Assembly
m = mesh.all_node_dofs(dofs_per_node);
u = mesh.all_element_dofs(dofs_per_node,dofs_per_ele);
F = ~fem.bc.all_dofs;
S = fem.S;
Kmm = S(m,m);
Kmu = S(m,u);
Kuu = S(u,u);
M = fem.M;
R = fem.loads.all_dofs;

%% Damping
alpha = 0.0012;     % Return 0.0137 for damping_first_mode
beta  = 0.05;
C = alpha*S + beta*M;

%% EigenValues
number_of_modes = 3;
n_dofs = mesh.n_dofs(dofs_per_node,dofs_per_ele);
[V,S2] = eigs(S(F,F),M(F,F),number_of_modes,'SM');
S2 = diag(S2);
M2 = diag(V'*M(F,F)*V);
for i = 1:size(V,2)
    V(:,i) = V(:,i) / (norm(V(:,i))*sqrt(M2(i)));
end
C2 = diag(V'*C(F,F)*V);
R2 = V'*R(F);

Z0 = R2 ./ S2;

%% Function handle for solver

A = [zeros(number_of_modes)    eye(number_of_modes);
    -diag(S2)                  -diag(C2) ];
B = zeros(number_of_modes*2,1);

diff_z = @(t,z) (A*z + B);
z0     = zeros(number_of_modes*2,1);
[T,Z] = ode45(diff_z,[0 12],[Z0 ; zeros(number_of_modes,1)]);
plot(T,Z(:,1))

%% Modal Decomposition
dt = 5e-3;

% S2 = diag(V'*S(F,F)*V);
aux = V'*C(F,F)*V;
damping_first_mode = aux(1,1)/(2*sqrt(S2(1,1)))

%% Rebuild w(t) for one node

node_id = border(1);
node_dofs = mesh.node_dofs(dofs_per_node,node_id);
w_t = V(node_dofs(3),:)*Z(:,1:3)';
plot(T,w_t)

%% Rebuild D, final value
D = fem.compound_function(0);
aux = D.all_dofs;
aux(F) = V*Z(1,1:3)';
D.dof_list_in(aux);
dz = max(abs(D.node_vals.vals(:,3)));
%% Static Solution
fem.solve();
max_dz = max(fem.dis.node_vals.vals(:,3));
%% Compare
error = abs((dz - max_dz)/max_dz);
testCase.verifyTrue(100*error < 1); % Error < 1%