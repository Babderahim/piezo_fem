classdef Element
    properties
        type
        coords
        normals
        thickness
    end
    properties (Dependent)
        n_nodes
        v3
    end
    methods
        function obj = Element(type,coords,normals,t_in)
        % function obj = Element(type,coords,normals,t_in)
%             require(size(coords,1)==4, ...
%                 'ArgumentError: only 4 nodes');
%             require(size(coords)==size(normals), ...
%                 'ArgumentError: coords and normals should have same size');
            obj.coords = coords;
            obj.thickness = t_in;
            obj.normals = normals;
            obj.type = type;
        end
        function jac = jacobian(element,ksi,eta,zeta)
            % jac_out = jacobian(element,ksi,eta,zeta)
            % jac_out [3x3][Float]: Jacobian Matrix
            % ksi, eta, zeta [Float] between [-1,1], checking done in N
            % Computes the jacobian for Shell Elements
            % Cook [6.7-2] gives Isoparametric Jacobian
            % Cook [12.5-4] & [12.5-2] gives Shells Derivatives.
            N  = element.N(ksi,eta);
            dN = element.dN(ksi,eta);
            t = element.thickness;
            tt = [t; t; t];
            v3t = (element.v3.*tt)';
            jac = [ dN*(element.coords + zeta*v3t/2);
                N*(v3t)/2 ];
        end
        function out = get.n_nodes(element)
            % out = get.n_nodes(element)
            % Number of nodes in the element
            out = size(element.coords,1);
        end
        function out = get.v3(element)
            out = squeeze(element.normals(:,3,:));
        end
        function dN = dN(element,ksi,eta)
            require(isnumeric([ksi eta]), ...
                'ArgumentError: Both ksi and eta should be numeric')
            require(-1<=ksi && ksi<=1, ...
                'ArgumetnError: ksi should be -1<=ksi<=1')
            require(-1<=eta && eta<=1, ...
                'ArgumetnError: eta should be -1<=eta<=1')
            switch element.type
                case {'Q9', 'AHMAD9'}
                    dN = Element.dN_Q9(ksi,eta);
                case {'Q8', 'AHMAD8'}
                    dN = Element.dN_Q8(ksi,eta);
                case {'Q4', 'AHMAD4'}
                    dN = Element.dN_Q4(ksi,eta);                    
            end
        end
        function N = N(element,ksi,eta)
            require(isnumeric([ksi eta]), ...
                'ArgumentError: Both ksi and eta should be numeric')
            require(-1<=ksi && ksi<=1, ...
                'ArgumetnError: ksi should be -1<=ksi<=1')
            require(-1<=eta && eta<=1, ...
                'ArgumetnError: eta should be -1<=eta<=1')
            switch element.type
                case {'Q4', 'AHMAD4'}
                    N = Element.N_Q4(ksi,eta);                                       
                case {'Q8','AHMAD8'}
                    N = Element.N_Q8(ksi,eta);
                case {'Q9','AHMAD9'}
                    N = Element.N_Q9(ksi,eta);
            end
        end
    end
    methods (Static)
        function T = T(jac)
            % sistema de coordenadas local 123 en [ksi eta zeta]
            dir1 = jac(1,:);
            dir3 = cross(dir1,jac(2,:));
            dir2 = cross(dir3,dir1);

            % Transformation of Strain, Cook pg 212: 
            % Cook [7.3-5]
            M1 = [ dir1/norm(dir1); dir2/norm(dir2); dir3/norm(dir3) ];
            M2 = M1(:,[2 3 1]);
            M3 = M1([2 3 1],:);
            M4 = M2([2 3 1],:);
            T = [ M1.^2     M1.*M2;
                  2*M1.*M3  M1.*M4 + M3.*M2 ];
            % Since sigma_zz is ignored, we eliminate the appropriate row.
            T(3,:) = [];
        end
        function NN = shape_to_diag(dim,N)
            % NN = shape_to_diag(dim,N)
            % NN [Float][dim x n_nodes]: Repeated values of N
            % N [Float] [1 x n_nodes]: Evaluated shape functions
            % dim [Int]: dimension of the problem, 2 or 3.
            % Rearranges for some surface integral for loads
            n_nodes = length(N);
            NN = zeros(dim,n_nodes);
            I = eye(dim);
            for n = 1:n_nodes
                i = index_range(dim,n);
                NN(:,i) = N(n)*I;
            end
        end
        function N = N_Q4(ksi,eta)
            N4 = 0.25*(1 - ksi)*(1 + eta);
            N3 = 0.25*(1 + ksi)*(1 + eta);
            N2 = 0.25*(1 + ksi)*(1 - eta);
            N1 = 0.25*(1 - ksi)*(1 - eta);
            N = [N1 N2 N3 N4];
        end
        function dN = dN_Q4(ksi,eta)
            dN = [  % dN ksi
            -0.25*(1 - eta),    ...
            0.25*(1 - eta),     ...
            0.25*(1 + eta),     ...
            -0.25*(1 + eta)
            % dN deta
            -0.25*(1 - ksi),    ...
            -0.25*(1 + ksi),    ...
            0.25*(1 + ksi),     ...
            0.25*(1 - ksi) ];
        end
        function N = N_Q8(ksi,eta)
            N8 = 0.50*(1 - ksi  )*(1 - eta^2);
            N7 = 0.50*(1 - ksi^2)*(1 + eta  );
            N6 = 0.50*(1 + ksi  )*(1 - eta^2);
            N5 = 0.50*(1 - ksi^2)*(1 - eta  );
            N4 = 0.25*(1 - ksi  )*(1 + eta  ) - 0.5*(N7 + N8);
            N3 = 0.25*(1 + ksi  )*(1 + eta  ) - 0.5*(N6 + N7);
            N2 = 0.25*(1 + ksi  )*(1 - eta  ) - 0.5*(N5 + N6);
            N1 = 0.25*(1 - ksi  )*(1 - eta  ) - 0.5*(N5 + N8);
            N = [N1 N2 N3 N4 N5 N6 N7 N8];
            
        end
        function dN = dN_Q8(ksi,eta)
            dN = [  % dN ksi
            -0.25*(-1+eta)*(eta+2*ksi),     ...
            -0.25*(-1+eta)*(-eta+2*ksi),    ...
            0.25*(1+eta)*(eta+2*ksi),       ...
            0.25*(1+eta)*(-eta+2*ksi),      ...
            ksi*(-1+eta),                   ...
            -0.5*(-1+eta)*(1+eta),          ...
            -ksi*(1+eta),                   ...
            0.5*(-1+eta)*(1+eta);
            % dN deta
            -0.25*(-1+ksi)*(ksi+2*eta),     ...
            -0.25*(1+ksi)*(ksi-2*eta),      ...
            0.25*(1+ksi)*(ksi+2*eta),       ...
            0.25*(-1+ksi)*(ksi-2*eta),      ...
            0.5*(-1+ksi)*(1+ksi),           ...
            -(1+ksi)*eta,                   ...
            -0.5*(-1+ksi)*(1+ksi),          ...
            (-1+ksi)*eta ];
        end
        function N = N_Q9(ksi,eta)
            N9 =      (1 - ksi^2)*(1 - eta^2);
            N8 = 0.50*(1 - ksi  )*(1 - eta^2) - 0.5*N9;
            N7 = 0.50*(1 - ksi^2)*(1 + eta  ) - 0.5*N9;
            N6 = 0.50*(1 + ksi  )*(1 - eta^2) - 0.5*N9;
            N5 = 0.50*(1 - ksi^2)*(1 - eta  ) - 0.5*N9;
            N4 = 0.25*(1 - ksi  )*(1 + eta  ) - 0.5*(N7 + N8 + 0.5*N9);
            N3 = 0.25*(1 + ksi  )*(1 + eta  ) - 0.5*(N6 + N7 + 0.5*N9);
            N2 = 0.25*(1 + ksi  )*(1 - eta  ) - 0.5*(N5 + N6 + 0.5*N9);
            N1 = 0.25*(1 - ksi  )*(1 - eta  ) - 0.5*(N5 + N8 + 0.5*N9);
            N  = [N1 N2 N3 N4 N5 N6 N7 N8 N9];
        end
        function dN = dN_Q9(ksi,eta)
            dN = [   % dN ksi
                0.25*eta*(-1+eta)*(2*ksi-1),    ...
                0.25*eta*(-1+eta)*(2*ksi+1),    ...
                0.25*eta*(1+eta)*(2*ksi+1),     ...
                0.25*eta*( 1+eta)*(2*ksi-1),    ...
                -ksi*eta*(-1+eta),              ...
                -1/2*(-1+eta)*(1+eta)*(2*ksi+1),...
                -ksi*eta*(1+eta),               ...
                -1/2*(-1+eta)*(1+eta)*(2*ksi-1),...
                2*ksi*(-1+eta)*(1+eta);
                % dN eta
                0.25*ksi*(-1+2*eta)*(ksi-1),    ...
                0.25*ksi*(-1+2*eta)*(1+ksi),    ...
                0.25*ksi*(2*eta+1)*(1+ksi),     ...
                0.25*ksi*(2*eta+1)*(ksi-1),     ...
                -0.5*(ksi-1)*(1+ksi)*(-1+2*eta),...
                -ksi*eta*(1+ksi),               ...
                -0.5*(ksi-1)*(1+ksi)*(2*eta+1), ...
                -ksi*eta*(ksi-1),               ...
                2*(ksi-1)*(1+ksi)*eta ];
        end
    end
end
