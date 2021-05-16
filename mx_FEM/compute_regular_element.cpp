/*
Created by Marcus Tan on 8/10/2014
Updated on 10/7/2015
Copyright 2014 University of Illinois 
Purpose: this function calculates the element stiffness matrix and load vector 
         of one element
INPUT:
    see "assemble.h" for def
    gauss.elem: a (number of dimensions+1)x number of gauss points for integration over elements.
             the last row is the weights.
    gauss.line: a 2 x number of gauss points for integration over lines. 
              the number of cols does not have to be the same as that for element integration.         
    parent.channel: a vector of n channel labels
    parent.channelNodes: a 2x number of channels matrix of the end nodes of the n channels

    channel.mcf: a vector of the mass flow rate times heat capacity of all the channels
OUTPUT:
*/
#include "assemble.h"
#include <cstddef>
//#include <iostream>
#include <mex.h>
#include "armadillo"

//#define SOURCE_FUNCTION
//#define HUGHES_SUPG

namespace igfem
{
void compute_regular_element(arma::mat& Kel, 
                             arma::vec& Pel, 
                             const arma::mat& nodeCoords,
                             const arma::uvec& elemNodes, 
                             double elemHeatSource,
                             const Convection& convect,
                             const gauss& gauss1,
                             const parent& parent1,
                             const chanNetwork& channels,
                             bool supg) 
{
    // initialization
    Kel.zeros(elemNodes.n_rows,elemNodes.n_rows);
    Pel.zeros(elemNodes.n_rows);  
 
    arma::mat Cmat = parent1.conductivity
                    *arma::eye<arma::mat>(nodeCoords.n_rows,  
                                          nodeCoords.n_rows); 
   

    arma::mat Xel = nodeCoords.cols(elemNodes);
    
    // calculate B matrix once
    arma::vec locCoord = arma::zeros<arma::vec>(nodeCoords.n_rows); 
    arma::vec N(elemNodes.n_elem); // N: column vector with length number of nodes
    arma::mat DN(elemNodes.n_elem,nodeCoords.n_rows);  //DN: number of nodes x number of dimensions matrix  
    shape_function_2D(N,DN,locCoord); 
                                
    arma::mat J = Xel*DN;
    double detJ  = arma::det(J);   
    if (detJ <= JACTOL)
    {
        //std::cerr << "warning: computer_regular_element: det J <= 0"
        //          << std::endl;
        mexWarnMsgIdAndTxt("compute_regular_element:detJ","compute_regular_element vanishing or negative Jacobian");
         
    }
    arma::mat B = arma::solve(J.t(), DN.t()); // B: number of dimensions x number of nodes
    
    // perform gauss integration and assemble element stiffness matrix and load vector
    double factor;
    arma::vec Xglo(nodeCoords.n_rows);

    arma::vec Bsw;

    elemHeatSource += convect.coef*convect.Tref; // effect of convection
    if (supg && parent1.channelNum.n_elem)
    {
        double he;
        Bsw = arma::zeros<arma::vec>(elemNodes.n_elem);
        arma::vec Bsw1(elemNodes.n_elem);
        arma::vec Wfunc(elemNodes.n_elem);
        arma::vec channelVec(nodeCoords.n_rows);
                        
        #ifdef HUGHES_SUPG
            //Brooks-Hughes SUPG
            double paramsupg = 0.0;
            double summdotsq = 0.0;
            for (std::size_t i = 0; i < parent1.channelNum.n_elem; i++)
            {
                if (fabs(channels.mcf(parent1.channelNum(i))) < MCFTOL)
                    continue;
                channelVec = sgn(channels.mcf(parent1.channelNum(i)))
                            *(nodeCoords(arma::span::all,parent1.channelNodes(1,i))
                              -nodeCoords(arma::span::all,parent1.channelNodes(0,i)));
                channelVec = channelVec/arma::norm(channelVec);
                streamwise_elem_length(he,Bsw1,channelVec,B);
                paramsupg += he*channels.mcf(parent1.channelNum(i));
                summdotsq += channels.mcf(parent1.channelNum(i))*channels.mcf(parent1.channelNum(i));
            }
            paramsupg /= summdotsq;
            for (std::size_t i = 0; i < parent1.channelNum.n_elem; i++)
            {
                if (fabs(channels.mcf(parent1.channelNum(i))) < MCFTOL)
                    continue;
                channelVec = sgn(channels.mcf(parent1.channelNum(i)))
                            *(nodeCoords(arma::span::all,parent1.channelNodes(1,i))
                              -nodeCoords(arma::span::all,parent1.channelNodes(0,i)));
                channelVec = channelVec/arma::norm(channelVec);
                streamwise_elem_length(he,Bsw1,channelVec,B);
                Bsw += paramsupg*channels.mcf(parent1.channelNum(i))*Bsw1;
            }
            // End of Brooks-Hughes SUPG
        #else 
            // My SUPG      
            for (std::size_t i = 0; i < parent1.channelNum.n_elem; i++)
            {
                if (fabs(channels.mcf(parent1.channelNum(i))) < MCFTOL)
                    continue;
                channelVec = sgn(channels.mcf(parent1.channelNum(i)))
                            *(nodeCoords(arma::span::all,parent1.channelNodes(1,i))
                              -nodeCoords(arma::span::all,parent1.channelNodes(0,i)));
                channelVec = channelVec/arma::norm(channelVec);
                streamwise_elem_length(he,Bsw1,channelVec,B);
                Bsw += he*Bsw1;
            }
        #endif 

        for (std::size_t i = 0; i < gauss1.elem.n_cols; i++)
        {
            shape_function_2D(N,DN,gauss1.elem(arma::span(0,gauss1.elem.n_rows-2),i));
            factor = detJ*gauss1.elem(gauss1.elem.n_rows-1,i);            
            Wfunc =  N+Bsw;            
            Kel += (B.t()*Cmat*B + convect.coef*Wfunc*N.t())*factor;
            Pel += Wfunc*elemHeatSource*factor;
            Xglo = Xel*N;
            #ifdef SOURCE_FUNCTION
                Pel += Wfunc*body_source(Xglo)*factor;
            #endif
        }
          
    }
    else
        for (std::size_t i = 0; i < gauss1.elem.n_cols; i++)
        {
            shape_function_2D(N,DN,gauss1.elem(arma::span(0,gauss1.elem.n_rows-2),i));
            factor = detJ*gauss1.elem(gauss1.elem.n_rows-1,i);
            Kel += (B.t()*Cmat*B + convect.coef*N*N.t())*factor;
            Pel += N*elemHeatSource*factor;
            
            Xglo = Xel*N;
            #ifdef SOURCE_FUNCTION
                Pel += N*body_source(Xglo)*factor;
            #endif
        }
       

    if (parent1.channelNum.is_empty())
        return;

    // add contribution of channels or line sources
    // mean temperature model or model type 1
    if (channels.model == MEAN_TEMP)
    {
        arma::vec channelVec(nodeCoords.n_rows);
        if (supg)
            for (std::size_t i = 0; i < parent1.channelNum.n_elem; i++)
            {
                if (fabs(channels.mcf(parent1.channelNum(i))) < MCFTOL)
                    continue;
                channelVec = nodeCoords(arma::span::all,parent1.channelNodes(1,i))-nodeCoords(arma::span::all,parent1.channelNodes(0,i));
                for (std::size_t j = 0; j < gauss1.line.n_cols; j++)
                {
                    Xglo = nodeCoords(arma::span::all,parent1.channelNodes(0,i)) + gauss1.line(0,j)*channelVec;
                    locCoord = local_coord_2D(Xglo,Xel);
                    shape_function_2D(N,DN,locCoord);
                    Kel +=
                    0.5*channels.mcf(parent1.channelNum(i))*(N+Bsw)*arma::trans(channelVec)*B*gauss1.line(1,j);
                }
            }
        else
            for (std::size_t i = 0; i < parent1.channelNum.n_elem; i++)
            {
                if (fabs(channels.mcf(parent1.channelNum(i))) < MCFTOL)
                    continue;
                channelVec = nodeCoords(arma::span::all,parent1.channelNodes(1,i))-nodeCoords(arma::span::all,parent1.channelNodes(0,i));
                for (std::size_t j = 0; j < gauss1.line.n_cols; j++)
                {
                    Xglo = nodeCoords(arma::span::all,parent1.channelNodes(0,i)) + gauss1.line(0,j)*channelVec;
                    locCoord = local_coord_2D(Xglo,Xel);
                    shape_function_2D(N,DN,locCoord);
                    Kel +=
                    0.5*channels.mcf(parent1.channelNum(i))*N*arma::trans(channelVec)*B*gauss1.line(1,j);
                }
            }
    }
    else if (channels.model == CONST_HEAT)
    {
        arma::vec channelVec(nodeCoords.n_rows);
        arma::vec N1D(2), DN1D(2);
        for (std::size_t i = 0; i < parent1.channelNum.n_elem; i++)
        {
            if (fabs(channels.mcf(parent1.channelNum(i))) < MCFTOL)
                continue;
            channelVec = nodeCoords(arma::span::all,parent1.channelNodes(1,i))
                        -nodeCoords(arma::span::all,parent1.channelNodes(0,i));
            for (std::size_t j = 0; j < gauss1.line.n_cols; j++)
            {
                Xglo = nodeCoords(arma::span::all,parent1.channelNodes(0,i)) 
                    + gauss1.line(0,j)*channelVec;
                locCoord = local_coord_2D(Xglo,Xel);
                shape_function_2D(N,DN,locCoord);
                shape_function_1D(N1D,DN1D,gauss1.line(0,j));
                factor = arma::dot(parent1.channelNurbsParam(arma::span::all,i),N1D) 
                            * channels.lengths(parent1.channelNum(i));  //distance to inlet
                factor = conductance(factor,
                                      channels.kapf(parent1.channelNum(i)),
                                      channels.mcf(parent1.channelNum(i)),
                                      channels.eigvalsq,
                                      channels.CR1s);
                factor *= 0.5*arma::norm(channelVec)*gauss1.line(1,j);
                Kel += (N*arma::trans(N))*factor;
                Pel += N*channels.Tin*factor;
            }
        }      
    }
      
}
}
