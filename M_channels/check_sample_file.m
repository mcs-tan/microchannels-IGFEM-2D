close all
clear all
path(path,'../../Opt-IGFEM-2D/M_optimization')
path(path,'../../NURBS/nurbs_toolbox')
path(path,'../M_geom_toolbox')
path(path,'../../MatlabUsefulFunctions/export_fig')
channelFile = '../ChannelFiles/4x4refLp1.channel';
polygonFile = '../GeomConstrFiles/4x4Lp1NE.polygon';
nSamples = 24;
nlconfun = @nonlinear_constraints;
%nlconfun = [];
nlcon.minPolyArea = 0.001*0.15*0.2;
nlcon.sinMinPolyAngle = sin(0.5*pi/180);
nlcon.minSidePolyArea = 0.001*0.15*0.2;
nlcon.sinMinSidePolyAngle = sin(0.5*pi/180);
[fileName,pathName] = uigetfile({'*.rand';'*.lhs';'*.rand1';'*.rand2';'*.smmp'}, ...
                                 'Open','../SampleFiles/');   
sampleFile = [pathName,fileName];
%sampleFile = 'parallelTwo_NE_a.rand1';
                                        

[channels,designParams] = read_channels(channelFile);
[designParams,channels.designParamNum] ...
        = design_params2channel_params_map(designParams,...
                                           channels);
[channels.polygons, channels.vertexCoords,...
     designParams.vertices2params,...
     restrictedParams.nParams, ...
     restrictedParams.iniVals, ...
     restrictedParams.paramPairs, ...
     sideTriangles] ...
        = read_polygon_file(polygonFile);     
[channels.polygons.isSideTriangle] = deal(false);
[channels.polygons(sideTriangles).isSideTriangle] = deal(true);    
del = zeros(designParams.nParams+restrictedParams.nParams,1); 
%{
figure
plot_channel_polygons(channels.polygons, ...
                      channels.vertexCoords, ...
                      channels.nurbs, ...
                      designParams, ...
                      true)   
%}
for i = 1:10
    %i = 1;
    designParams.iniVals = read_sample_file(sampleFile,i);
    restrictedParams.iniVals ...
        = update_restricted_params_ini_vals(designParams, ...
                                        restrictedParams);
    channels = update_channels([designParams.iniVals;restrictedParams.iniVals],...
                               designParams, ...
                               restrictedParams, ...
                               channels, ...
                               'replace',...
                               false);                                  
    %if (any(nlconfun(del,designParams,restrictedParams,channels,nlcon,[],[],[]) > 0))
    %    warning('sample %i fails to satisfy nonlinear constraint',i)
    %end
    
    figure
    plotOptions.showChannels = true;
    plotOptions.showPts = false;
    plotOptions.showDesignParams = true;
    plotOptions.plotStyle = 2;
    plotOptions.showParamBounds = false;
    plot_channels_and_design_parameters(channels.contvty,channels.pts,channels.nurbs,...
                                        designParams,plotOptions)
    %{
    figure
    plot_channel_polygons(channels.polygons, ...
                          channels.vertexCoords, ...
                          channels.nurbs, ...
                          designParams, ...
                          true)  
    %}
end

                                        
