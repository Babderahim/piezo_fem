classdef Physics
    properties
        dofs_per_node
        dofs_per_ele
        k
        m
    end
    methods
        function obj = Physics(dofs_per_node,dofs_per_ele,fun_in)
            require(all(~mod([dofs_per_node,dofs_per_ele],1)), ...
                'ArgumentError: dof numbers should be integers');
            require(isa(fun_in,'function_handle'), ...
                'ArgumentError: fun_in should be a function handle');
            obj.dofs_per_node = dofs_per_node;
            obj.dofs_per_ele = dofs_per_ele;
            obj.k = fun_in;
        end
    end
    methods (Static)
        function B = B_H8(element,ksi,eta,zeta)
            AUX = zeros(6,9);
            AUX([1 10 18 22 26 35 42 47 51]) = 1;
            Tinv = inv(element.jacobian(ksi,eta,zeta));
            Ndevsparse = EleType.dN_sparse(ksi,eta,zeta);
            AUX2 = zeros(9);
            for i = 1:3
                AUX2((1+(i-1)*3:3*i),(1+(i-1)*3:3*i)) = Tinv;
            end
            B = AUX*AUX2*Ndevsparse;
        end
        function obj = Dynamic(dofs_per_node,dofs_per_ele,k,m)
            require(isa(m,'function_handle'), ...
                'ArgumentError: m should be a function handle');
            obj = Physics(dofs_per_node,dofs_per_ele,k);
            obj.m = m;            
        end
        function K = K_PiezoShell(element,laminate,order)
            % K = K_PiezoShell(element,material,order)
            % K [ele_dof x ele_dof][Float] Stiffness as calculated in
            % Cook 361 12.4-14
            % element [Element]: Requires methods jacobian and B
            % material[Material]: Requires methods E, nu, and D
            % order [Int]: Gauss integration order
            % Constitutive Relationship
            % Both material properties skip 3rd col because it is a plain
            % stress problem
            % Function to be integrated
            n_l = laminate.n_layers;
            function K_in_point = K_in_point(ksi,eta,zeta)
                % Piezo Part, generates the Electric Field (only z
                % component from 2 or 1 voltage element dof.
                %% Get Layer's contribution
                layer = laminate.material(zeta);
                l = laminate.mat_num(zeta);
                elastic = Physics.ElasticShell(layer);
                piezo = -layer.D(:,[1 2 4 5 6]);  
                electric = -diag(layer.e);
                %% Put the layer's electric contribution in the general matrix
                all_piezo = zeros(n_l*size(piezo,1),size(piezo,2));
                all_piezo(index_range(size(piezo,1),l),:) = piezo;
                all_electric = zeros(size(electric,1)*n_l);
                e_index = index_range(size(electric,2),l);
                all_electric(e_index,e_index) = electric;
                C = [   elastic     all_piezo';
                        all_piezo   all_electric];
                %% B_matrix
                B = Physics.B_PiezoShell(element,n_l,l,ksi,eta,zeta);
                jac = element.jacobian(ksi,eta,zeta);
                K_in_point = B'*C*B*det(jac);
            end
            %% Generates gauss points for a series for zeta (with laminate) and ksi and eta
            [zeta_p, zeta_w] = laminate.quadrature(2);
            [g_p,g_w] = Integral.lgwt(order,-1,1);
            points  = {g_p,g_p,zeta_p'};
            weights = {g_w,g_w,zeta_w'};
            fun_in = @(ksi,eta,zeta) (K_in_point(ksi,eta,zeta));
            K = Integral.quadrature(points,weights,fun_in);
        end
        function B = B_PiezoShell(element,dofs_per_ele,layer_num,ksi,eta,zeta)
            jac = element.jacobian(ksi,eta,zeta);
            cosines = Element.direction_cosines(jac);
            inv_jac = jac \ eye(3);
            dof_per_layer = 1;
            if dof_per_layer == 2
                dN_ele = zeros(3,2);
                % V_bottom is first, V_top goes second.
                % Together they form E_z = V_top - V_bottom
                dN_ele(3,:) = [-1 1];
            else
                dN_ele = [0 0 1]';
                dN_xyz = inv_jac*dN_ele;
            end
            all_dN = zeros(dofs_per_ele*size(dN_xyz));
            all_dN(index_range(3,layer_num),layer_num) = cosines*dN_xyz;
            % Mechanics Part
            B_mech = Physics.B_Shell(element,ksi,eta,zeta); % Cook [7.3-10]
            % Join both and trasform the coordinates
            B = blkdiag(Element.T(cosines)*B_mech,all_dN);
        end
        function L = apply_surface_load(element,order,q,s_coord,s_val)
            % L = apply_load(element,order,q)
            % Generates a load dof vector by integrating a constant load along
            % an element's surface.
            % L [n_ele_dofs x 1][Float]: Load vector
            % element [Element]
            % order [Int]: Gauss integration order
            % q [dof x 1][Float]: Constant applied load
            % s_coord [Int]: coordinate that defines the surface, if ksi,2
            % s_val [Float]: value that the coordinate takes, i.e. ksi = -1;
            function L = apply_point_load(element,q,s_coord,ksi,eta,zeta)
                % L = apply_point_load(element,q,ksi,eta,zeta)
                % Used as lambda in apply_surface_load and apply_volume_load
                jac = element.jacobian(ksi,eta,zeta);
                aux = 1:3;  aux(s_coord) = [];
                v1 = jac(aux(1),:)';
                v2 = jac(aux(2),:)';
                NN = Element.shape_to_diag(length(q),element.N(ksi,eta,0));
                L = NN'*norm(cross(v1,v2))*q;
            end
            switch (s_coord)
                case 1
                    ksi = s_val;
                    fun_in = @(eta,zeta) (apply_point_load( ...
                                        element,q,s_coord,ksi,eta,zeta));
                case 2
                    eta = s_val;
                    fun_in = @(ksi,zeta) (apply_point_load( ...
                                        element,q,s_coord,ksi,eta,zeta));
                case 3
                    zeta = s_val;
                    fun_in = @(ksi,eta) (apply_point_load( ...
                                        element,q,s_coord,ksi,eta,zeta));
            end
            L = Integral.Surface2D(fun_in,order,-1,1);
        end
        function L = apply_volume_load(element,order,q)
            % L = apply_load(element,order,q)
            % Generates a load dof vector by integrating a constant load along
            % the element.
            % L [n_ele_dofs x 1][Float]: Load vector
            % element [Element]
            % order [Int]: Gauss integration order
            % q [dof x 1][Float]: Constant applied load
            function L = apply_point_load(element,q,ksi,eta,zeta)
                % L = apply_point_load(element,q,ksi,eta,zeta)
                % Used as lambda in apply_surface_load and apply_volume_load
                NN = Element.shape_to_diag(length(q),element.N(ksi,eta,0));
                L = NN'*det(element.jacobian(ksi,eta,zeta))*q;
            end
            fun_in = @(ksi,eta,zeta) (apply_point_load(element,q, ...
                ksi,eta,zeta));
            L = Integral.Volume3D(fun_in,order,-1,1);
        end
        function M = M_Shell(element,laminate,order)
            % M = M_Shell(element,material,order)
            % M [n_dofxn_dof][Float] Mass as calculated in Cook 361 13.2-5
            % element [Element]: Requires methods jacobian and B
            % material[Material]: Requires property rho
            % order [Int]: Gauss integration order
            function M_in_point = M_in_point(ksi,eta,zeta)
                rho = laminate.material(zeta).rho;
                jac = element.jacobian(ksi,eta,zeta);
                N   = element.ShellN(ksi,eta,zeta);
                M_in_point = rho*(N')*N*det(jac);
            end
            [zeta_p, zeta_w] = laminate.quadrature(2);
            [g_p,g_w] = Integral.lgwt(order,-1,1);
            points  = {g_p,g_p,zeta_p'};
            weights = {g_w,g_w,zeta_w'};
            fun_in = @(xi,eta,mu) (M_in_point(xi,eta,mu));
            M = Integral.quadrature(points,weights,fun_in);
        end
        function K = K_Shell(element,laminate,order)
            % K = K_Shell(element,material,order)
            % K [n_dofxn_dof][Float] Stiffness as calculated in Cook 361 12.4-14
            % element [Element]: Requires methods jacobian and B
            % material[Material]: Requires properties E and nu
            % order [Int]: Gauss integration order
            function K_in_point = K_in_point(ksi,eta,zeta)
                C = Physics.ElasticShell(laminate.material(zeta));
                jac = element.jacobian(ksi,eta,zeta);
                cosines = Element.direction_cosines(jac);
                B = Element.T(cosines)* ...
                    Physics.B_Shell(element,ksi,eta,zeta); % Cook [7.3-10]
                K_in_point = B'*C*B*det(jac);
            end
            %% Generates gauss points for a series for zeta (with laminate) and ksi and eta
            [zeta_p, zeta_w] = laminate.quadrature(2);
            [g_p,g_w] = Integral.lgwt(order,-1,1);
            points  = {g_p,g_p,zeta_p'};
            weights = {g_w,g_w,zeta_w'};
            fun_in = @(ksi,eta,zeta) (K_in_point(ksi,eta,zeta));
            K = Integral.quadrature(points,weights,fun_in);
        end
        function K = K_Shell_selective(element,laminate,normal_order,shear_order)
            % K = K_Shell_selective(element,material,normal_order,shear_order)
            % K [n_dofxn_dof][Float] Stiffness as calculated in Cook 361 12.4-14
            % with selective integration
            % element [Element]: Requires methods jacobian and B
            % material[Material]: Requires methods E and nu
            % normal_order [Int]: Gauss integration order for normal part
            % shear_order  [Int]: Gauss integration order for shear part
            function K_in_point = K_in_point(normal_bool,ksi,eta,zeta)
                C = Physics.ElasticShell(laminate.material(zeta));
                if normal_bool
                    C(1:3,1:3) = 0;
                else
                    C(4:5,4:5) = 0;
                end
                jac = element.jacobian(ksi,eta,zeta);
                cosines = Element.direction_cosines(jac);
                B = Element.T(cosines)* ...
                    Physics.B_Shell(element,ksi,eta,zeta); % Cook [7.3-10]
                K_in_point = B'*C*B*det(jac);
            end
            % Normal Part
            fun_n = @(xi,eta,mu) (K_in_point(true,xi,eta,mu));
            K_n = Integral.Volume3D(fun_n,normal_order,-1,1);
            % Shear Part
            fun_shear = @(xi,eta,mu) (K_in_point(false,xi,eta,mu));
            K_s = Integral.Volume3D(fun_shear,shear_order,-1,1);
            K = K_s + K_n;
        end
        function C = Elastic(material)
            % Computes the Elastic Tensor in matrix form for an Isotropic
            % material
            E = material.E;
            nu = material.nu;
            C = E/((1+nu)*(1-2*nu))* ...
                    [1-nu   nu      nu      0          0          0
                    nu      1-nu	nu      0          0          0
                    nu      nu      1-nu    0          0          0
                    0       0       0       (1-2*nu)/2 0          0
                    0       0       0       0          (1-2*nu)/2 0
                    0       0       0       0          0          (1-2*nu)/2];
        end
        function C = ElasticPlainStress(material)
            % Computes the Elastic Tensor in matrix form for an Isotropic
            % material
            E = material.E;
            nu = material.nu;
            aux = E/(1-nu^2)* ...
                    [1  nu  nu
                     nu 1   nu
                     nu nu  1];
            C = blkdiag(aux,0.5*E*(1+nu)*eye(3));
        end
        function C = ElasticShell(material)
            % Returns the Elastic Tensor for Plain Stress in a shell
            % Cook pg 361 12.5-12
            C = Physics.ElasticPlainStress(material);
            c = 5/6;
            C(5,5) = c*C(5,5);
            C(6,6) = c*C(6,6);
            C(3,:) = [];
            C(:,3) = [];
        end
        function B = B_Shell(element,ksi,eta,zeta)
            % B = B_Shell(element,ksi,eta,zeta)
            % B [Float][6 x n_ele_dofs]: Relates the element's dof values 
            % with the mechanical strain vector. Cook [12.5-10]
            % element [Element]
            % ksi, eta, zeta [Float][Scalar] in [-1,1] local coordinates            
            dofs_per_node = 5;
            % Prepare values
            v = element.normals;
            N  = element.N(ksi,eta,zeta);
            invJac = element.jacobian(ksi,eta,zeta) \ eye(3);
            dN = invJac(:,1:2)*element.dN(ksi,eta,zeta);
            B  = zeros(6,element.n_nodes*dofs_per_node);
            % B matrix has the same structure for each node, 
            % written as [aux1 aux2].
            % Loop through the mesh.connect coords and get each B_node, 
            % then add it to its columns in the B matrix
            for n = 1:element.n_nodes
                v1 = v(:,1,n);  % In Cook [12.5-3] as {l1i,m1i,n1i} 
                v2 = v(:,2,n);  % In Cook [12.5-3] as {l2i,m2i,n2i} 
                dZN = dN(:,n)*zeta + N(n)*invJac(:,3);
                % aux1: Part of node's B unrelated to rotational dofs and zeta
                aux1 = [ dN(1,n)    0           0
                         0          dN(2,n)     0
                         0          0           dN(3,n)
                         dN(2,n)    dN(1,n)     0
                         0          dN(3,n)     dN(2,n)
                         dN(3,n)    0           dN(1,n) ];
                % aux2: Part of node's B related to rotational dofs and zeta
                aux2 = [ -v2.*dZN                        v1.*dZN
                         -v2(1)*dZN(2) - v2(2)*dZN(1)    v1(1)*dZN(2) + v1(2)*dZN(1)
                         -v2(2)*dZN(3) - v2(3)*dZN(2)    v1(2)*dZN(3) + v1(3)*dZN(2)
                         -v2(1)*dZN(3) - v2(3)*dZN(1)    v1(1)*dZN(3) + v1(3)*dZN(1) ]*0.5*element.thickness(n);
                % Add that node's part to the complete B
                B(:,index_range(dofs_per_node,n)) = [aux1 aux2];
            end
        end
        function H_out = H
            % H_out = H
            % H_out [6x9] Cook pg 181 [6.7-5]
            % goes from diff_U_xyz to Strain vector
            H_out = zeros(6,9);
            H_out([1 10 18 22 26 35 42 47 51]) = 1;
        end
    end
end
    