 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Created by Marcus Tan
%%% Modified by Marcus Tan on 1/17/2015
%%% Copyright 2012 University of Illinois at Urbana-Champaign. All rights reserved
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%function Main
%%%%%%%%%%%%%%%%%%%%%%%%%
%  IGFEM Code  
%%%%%%%%%%%%%%%%%%%%%%%%%
%
clear
%
close all
format long e;

% paths
path(path, './M_geom_toolbox')
path(path, './M_preFEM')
path(path, './M_channels')
path(path, './M_FEM')
path(path, './mx_FEM')
path(path, './M_postprocessing')
path(path, './M_error_analysis')
path(path, '../NURBS/nurbs_toolbox')
path(path, './mesh_conforming_abaqus')
path(path, './mesh')
path(path, '../SISL/mx_SISL') % for windows
path(path, './ChannelFiles')
path(path, './InputFiles')
path(path, './blockedChannelFiles')
path(path, '../Opt-IGFEM-2D/M_optimization')
path(path, '../MatlabUsefulFunctions/export_fig')
%path(path, '../../SISL_linux') % for LINUX

totTimer = tic;
%% MESH AND USER INPUT
inputFile = 'square_PDMS.in';
 [mesh,gauss,tol,refine,...
  otherFlags,postprocess, ...
  moveNode] = read_inputs(inputFile);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Other user inputs that must be specified regardless of choice I or II
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Interface, analytical body source (if available) and analytical 
% solution (if available)
%channelFile = '3x3localRefLp075deg6.channel';
channelFile = '3x3Lp075deg6_nBlk1_optimal.channel';
blockedChannelFile = '3x3deg6nBlk1.blk';
%channelFile = 'DK_DP_check.channel';
options.suppressDesignParams = false;
options.selfIntersectTol = tol.channelSelfIntersect;
[channels,designParams] = preprocess_channels(channelFile,options);

blockedSets = read_blocked_channels(blockedChannelFile);
% calculate volume fraction
%domainVol = (mesh.boundary.xf - mesh.boundary.xi)*(mesh.boundary.yf - mesh.boundary.yi)*0.003; 
%fprintf('volume fraction = %g \n',channels.vol/domainVol);
%{
% create_channels.m were used at the early stages of the code when the
channel input files did not exist
% some of the examples still remain the script and have not been converted
into channel input files
[channels,mesh.heatSourceFunc,soln,u,uL2] = create_channels(mesh.boundary.xi,...
                                                           mesh.boundary.xf,...
                                                            mesh.boundary.yi,...
                                                            mesh.boundary.yf);
%}
%% Analytical distributed heat source
% Note: Only works for NURBS IGFEM !
% To specify analytical distributed heat source for polynomial IGFEM,
% modify the file body_source_functions.cpp in the directory mx_FEM
% mesh.heatSourceFunc = @(x,y) distributed_heat_source(x,y);
mesh.heatSourceFunc = [];
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Start of calculations
%stats = mesh_statistics(mesh.elem.elem_node,mesh.node.coords);
% label edges for refinement later
mesh.elem.elem_node = label(mesh.node.coords,mesh.elem.elem_node); 
%


% the edge_node information is generated by generate_conforming_mesh
fprintf('\ngenerate edge_node\n')
tic
mesh.edge.edge_node = find_edge_node(mesh.elem.elem_node);
toc

mesh.edge.length = find_edge_length(mesh.edge.edge_node,mesh.node.coords);

mesh.edge.minLength = min(mesh.edge.length);
tol.halfLineWidth = mesh.edge.minLength*tol.halfLineWidthFrac;
moveNode.dist = mesh.edge.minLength*moveNode.distFrac;

figure
options.showMesh = false;
options.showCtrlPts = true;
options.showDiamVals = false;
options.showNodeNums = false;
options.showElemNums = false;
options.showElemVals = false;
plot_mesh_curve(mesh.node.coords, ...
                mesh.elem.elem_node, ...
                mesh.elem.heatSource, ...
                channels,options)
% find intersection points and enrichment nodes
if(~otherFlags.isConformingMesh)
    %{
    if (otherFlags.calcItrsectVel)
        fprintf('checking for original nodes that are intersection points \n')
        fprintf('and kinks or branch points on element edges \n')
        nodeTimer = tic;

        mesh.node.coords ...
                = eliminate_original_node_intersections(mesh.node.coords,...
                                                        mesh.edge.edge_node,...                      
                                                        channels.nurbs,...
                                                        channels.branch_kinks.XX',...
                                                        mesh.boundary,...
                                                        tol.boundary,...
                                                        tol.node,...
                                                        moveNode.maxAttempts,...
                                                        moveNode.dist,...
                                                        moveNode.randDirection);
  
        toc(nodeTimer);
    end
    %}
    fprintf('\nfinding intersection points \n')
    [mesh.edge,...
     mesh.node,...
     mesh.elem,...
     channels.itrsectParams,...
     refineLevels]...
         =edges_curves_intersect(mesh.edge,mesh.node,...
                                 mesh.elem, ...
                                 channels, ...
                                 tol, ...
                                 refine, ...
                                 otherFlags.calcItrsectVel);
    if refineLevels || isempty(mesh.DT)
        % reconstruct DT if refinement has been carried out
        % or construct DT if DT is empty
        % update other members of mesh.elem
        [mesh.DT,mesh.elem] ...
            = update_mesh_DT_n_elem(mesh.node.coords(1:mesh.node.nOriginalNode,:), ...
                                    mesh.edge.edge_node, ...
                                    mesh.elem);
        
    end
    mesh.elem.elem_edge = find_elem_edge(mesh.elem.elem_node, ...
                                          mesh.edge.edge_node, ...
                                          mesh.node.nOriginalNode);                         
    [mesh.elem.branch_kinks, ...
     mesh.node.coords, ...
     mesh.node.n_node, ...
     mesh.edge.itrsect] ...
                = elem_branching_n_kinks(mesh.DT,...
                                         mesh.elem.elem_edge,...
                                         mesh.edge.itrsect,...
                                         mesh.node.coords,...
                                         mesh.node.n_node,...
                                         channels.branch_kinks,...
                                         channels.itrsectParams,...
                                         tol.nurbsParam, ...
                                         tol.bary, ...
                                         channels.designParamNum, ...
                                         otherFlags.calcItrsectVel);
     % nOriginalEnrichNode only includes enrichment nodes that arise due to 
    % the intersections
    % If NURBS-IGFEM is used, additional enrichment nodes corresponding to
    % additional control points may arise
    mesh.node.nOriginalEnrichNode = mesh.node.n_node;                                   
else
    fprintf('\nconforming mesh\n')

    % find edges sharing a node
    fprintf('generate node_edges\n')
    tic
    mesh.node.node_edges = find_node_edges(mesh.edge.edge_node,...
                                          size(mesh.node.coords,1));
    toc
    fprintf('\nfinding intersection points\n')
    intersectTimer = tic;
    mesh.edge.itrsect = edge_intersect_conforming(mesh.edge.edge_node,...
                                mesh.node.coords, mesh.node.node_edges, ...
                                mesh.elem.elem_edge, mesh.elem.region, channels);
    toc(intersectTimer);
    
    mesh.elem.junc = [];  
    
    fprintf('\ngenerate elem_edge\n')
    tic
    mesh.elem.elem_edge = find_elem_edge(mesh.elem.elem_node, ...
                                     mesh.edge.edge_node, ...
                                     size(mesh.node.coords,1));
    toc
    
end



%
%plot_mesh_curve_itrsect_junc(mesh.node,mesh.elem.elem_node,channels,...
%                   mesh.edge.itrsect,mesh.elem.junc,mesh.elem.kinks,false,false);
%plot_mesh_labels(mesh.node.coords,mesh.elem.elem_node,true,true,mesh.edge.edge_node)
%
%% Set boundary conditions
fprintf('\nsetting boundary conditions \n')
tic
[mesh.elem, mesh.node] = set_boundary_conditions(mesh.BCs,...
                                                 mesh.elem,...
                                                 mesh.node,...
                                                 mesh.boundary,...
                                                 tol.boundary);
toc

%% enrichment functions and integration subdomains
% creat parent elements
fprintf('\nconstructing parent elements\n')
tic
mesh.elem.parent = element_intersections(mesh.elem.elem_node, ...
                                         mesh.elem.dualedge, ...
                                         mesh.edge.edge_node, ...
                                         mesh.edge.itrsect, ...
                                         otherFlags.calcItrsectVel);
%
[mesh.elem.parent, ...
 mesh.elem.cstrElems, ...
 mesh.elem.nIGFEMelems] ...
                 = parent_elements_nurbs(mesh.elem.parent,...
                                         mesh.elem.elem_node,...
                                         mesh.elem.material,...
                                         mesh.material,...
                                         mesh.elem.branch_kinks,...
                                         mesh.node.coords,...
                                         mesh.node.nOriginalNode,...
                                         mesh.node.constraint,...
                                         channels,...
                                         tol.nurbsParam,...
                                         otherFlags.polyIGFEM,...
                                         otherFlags.calcItrsectVel);


toc
%{
elem2plot = [];
plot_mesh_nurbs_parent(mesh.node.coords,mesh.node.nOriginalNode,...
                       mesh.elem.elem_node,mesh.elem.parent,channels,...
                       false,false,elem2plot);
%}

if(mesh.node.n_node==mesh.node.nOriginalNode)
    fprintf('\nconforming mesh\n')
else
    fprintf('\nnon-conforming mesh\n')
    fprintf('constructing child elements\n')
    tic
    
    [mesh.elem.parent,mesh.node]...edge, Dirichlet, nodeCoords, boundary
        =child_elements_nurbs(mesh.elem.parent,... 
                              mesh.node,...
                              tol.collinear,...
                              tol.slender,...
                              otherFlags.polyIGFEM);
    toc                      
    % the global equation number of additional equations for 
    % Lagrange multiplier method                     
    for i = 1:numel(mesh.elem.cstrElems)
        mesh.elem.parent(mesh.elem.cstrElems(i)).cstrRows...
                =  mesh.elem.parent(mesh.elem.cstrElems(i)).cstrRows ...
                 + size(mesh.node.coords,1); 
    end
   
    %plot_mesh_nurbs_child(mesh.node.coords,mesh.elem.elem_node,...
    %                      mesh.elem.parent,false,false,elem2plot)
end


%%  Finite Element Code  
%%%%%%%%%%%%%%%%%%%%%%%%%  
% gauss quadrature schemes
if(otherFlags.performFEM)
    fprintf('\nperforming FEM\n')
    % eq_num:  Equation number assigned to each node
    % n_dof: The number of degree of freedom in the model
    [n_dof, eq_num] = initialize(size(mesh.node.coords,1) ...
                                 +numel(mesh.node.constraint.temp_node), ...
                                 mesh.node.Dirichlet.n_pre_temp, ...
                                 mesh.node.Dirichlet.temp_node);
    gausspp = gauss;
    % Assemble the stiffness matrix
    maxTmax = -inf;
    maxTmaxDelP = nan;
    maxTmaxSet = nan;
    maxTave = nan;
    iniDiams = channels.diams;
    for i = 1:numel(blockedSets) 
        channels.diams(blockedSets{i}) = 0.0;
        [~,mass] = network_pressure_mass_flow_rate(channels.contvty,...
                                                  channels.nurbs,...
                                                  channels.diams,...
                                                  channels.heights,...
                                                  channels.viscosity,...
                                                  channels.inletEndPoint,...
                                                  channels.massin,...
                                                  channels.powerXdensity,...
                                                  channels.pressureOutletEndPoint,...
                                                  channels.pressureOut,...
                                                  channels.crossSection);
        channels.mcf = mass*channels.heatCapacity;                                              
        if (otherFlags.polyIGFEM)
            fprintf('\nassembly of polynomial IGFEM stiffness matrix\n')
            UP =  assemble_prescribed_node(mesh.node.Dirichlet,eq_num);
            [KFF,KFP,KPF,KPP,PF,PP] ...
                        = mx_assemble_sparse(mesh.node.coords',...
                                             mesh.elem.elem_node',...
                                             mesh.elem.heatSource,...
                                             mesh.convect,...
                                             eq_num,...
                                             gauss,...
                                             mesh.elem.parent,...
                                             channels,...
                                             mesh.node.Dirichlet,...
                                             mesh.elem.Neumann,...
                                             otherFlags.supg);
        else
            fprintf('assembly \n')
            [KPP,KPF,KFP,KFF,PP,PF,UP] = ...
                assemble (mesh, eq_num, n_dof,channels,gauss,otherFlags.supg);
        end
       
        fprintf('\nsolving equation\n')
        [UUR, PUR] = solve_matrix_eqn(KPP,KPF,KFP,KFF,PP,PF,UP, eq_num);             

        fprintf('\nupdate enrichment node values\n')
        UUR2 = update_enrichment_node_value(UUR,mesh.node,mesh.elem,mesh.edge);

        %fprintf('\n total simulation time %g \n',toc(totTimer))
        %fprintf('\noutput paraview file\n')
        %matlab2vtk_scalar([outfile,'.vtk'],scalarname,mesh.elem,mesh.node,UUR2);
        %save(outfile,'mesh','channels','UUR')

        %fprintf('\n average temp = %g \n',average_temp(mesh.elem,mesh.node.coords,UUR2));
        Tmax = max(UUR2);
        fprintf('\n max T for current set = %4.12g  \n',Tmax);
       
        %normp = 8;
        %gausspp.elem = gauss_points_and_weights(true,16 ,2,'combined');
        %pnormT = field_p_norm(mesh.elem,mesh.node.coords,UUR,...
        %                      normp,Tmax,gausspp);

        %fprintf('\n %i-norm temp = %4.12g \n',normp,pnormT);
        %[Tvar,Tave,totArea] = field_variance(mesh.elem,mesh.node.coords,UUR,gausspp);
        Tave = average_temp(mesh.elem,mesh.node.coords,UUR2);
        %fprintf('\n Tave = %4.12g , SD = %4.12g  \n',Tave,sqrt(Tvar));

        nu = kinematic_viscosity(channels.viscosity,channels.density,Tave, ...
                                 channels.viscosityModel);
        [pressure,mass] = network_pressure_mass_flow_rate(channels.contvty,...
                                                          channels.nurbs,...
                                                          channels.diams,...
                                                          channels.heights,...
                                                          nu,...
                                                          channels.inletEndPoint,...
                                                          channels.massin,...
                                                          channels.powerXdensity,...
                                                          channels.pressureOutletEndPoint,...
                                                          channels.pressureOut,...
                                                          channels.crossSection);
        if Tmax > maxTmax
            maxTmax = Tmax;
            maxTmaxDelP = pressure(channels.inletEndPoint);
            maxTmaxSet = i;
            maxTave = Tave;
        end                                              
        channels.diams = iniDiams;                                              
    end
    str = repmat('%i ',1,numel(blockedSets{maxTmaxSet}));
    fprintf(['\n Worst set = %i, channel(s) blocked = ',str,'\n'],maxTmaxSet,blockedSets{maxTmaxSet});
    fprintf('Tave = %g, Tmax = %g, delP = %g\n',maxTave, maxTmax,maxTmaxDelP);
end
