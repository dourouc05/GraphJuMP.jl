module GraphJuMP

using JuMP
using LightGraphs
using MetaGraphs

export setgraph!, removegraph!, addpath!

const extKey = :GraphJuMP

"""
Several formulations of the flows are possible: 

* `EdgeFlow`: each edge of the graph is explicitly modelled. This model tends to scale poorly to large number of nodes 
  and edges in the graph
* `Path`: only some paths in the graph are modelled. This formulation is typical for column-generation schemes
  (set `delayed=true` for this)

To create a new formulation, subtype `GraphFormulation` and `GraphFormulationExt`; implement the required functions: 

* `supportspath(::GraphFormulation)`: whether this formulation uses the notion of path. This implies that functions like 
  `addpath!` must be supported. 
* `buildformulation(m::Model, gf::GraphFormulation)`: builds the formulation, i.e. creates the required JuMP variables and
  constraints for the formulation. 
"""
abstract type GraphFormulation end
struct EdgeFlow <: GraphFormulation end
struct Path <: GraphFormulation end

supportspath(::GraphFormulation) = false
supportspath(::Path) = true

"""
Each formulation should have its subtype of `GraphFormulationExt` to store its internal parameters. 
"""
abstract type GraphFormulationExt end

mutable struct EdgeFlowFormulationExt <: GraphFormulationExt
  flows::Matrix{Variable} # First index: edge; second index: commodity. 
  id_to_edge::Dict{Int, Edge} # Mapping an integer index (used in the model) to a graph edge. 
  edge_to_id::Dict{Edge, Int} # Reverse mapping: from a graph edge to an integer index. 
end

"""
Stores the internal state of the graph model. 
"""
mutable struct GraphModelExt{T <: Int, U <: Real}
  graph::MetaDiGraph{T, U} # The graph below this model. Must be a "meta" graph, as many properties might be useful for each edge or vertex (such as max capacity). 
  formulation::GraphFormulation # A graph formulation, see GraphFormulation enumeration. 
  delayed::Bool # For a path formulation, controls when paths are computed: false, before solving; true, after solving. 
  flowcategory::Symbol # The JuMP category for flow variables. For now, these are: :Cont, :Int, :Bin, :SemiCont, :SemiInt, :SDP
  commodities::Vector{String} # Whether several commodities are present. 
  formulationext::Union{GraphFormulationExt, Void} # The formulation object, once it is built (after calling `buildformulation`). 

  function GraphModelExt{T, U}(graph::MetaDiGraph{T, U}, formulation::GraphFormulation=EdgeFlow(), 
                               delayed::Bool=false, flowcategory::Symbol=:Cont, commodities::Vector{String}=String["default"]
                              ) where{T, U}
    return new(graph, formulation, delayed, flowcategory, commodities, nothing)
  end
end

# Link between GraphModelExt and JuMP's model. 
hasgraph(m::Model) = haskey(m.ext, extKey)
checkgraph(m::Model) = hasgraph(m) || error("The model has no associated graph model.")
getgraphext(m::Model) = hasgraph(m) && m.ext[extKey]
getgraph(m::Model) = getgraphext(m).graph

hasformulation(m::Model) = getgraphext(m).formulationext !== nothing
checkformulation(m::Model) = hasformulation(m) || error("The model has no associated graph formulation. " * 
  "Did you forget to call `buildformulation` or to link the graph model to a JuMP model with `setgraph!`?")

function setgraph!(m::Model, graph::GraphModelExt)
  if hasgraph(m)
    warn("Model already has an associated graph model! It will be replaced.")
  end
  m.ext[extKey] = graph
  m.ext[extKey].formulationext = buildformulation(m)
end

setgraph!{T, U}(m::Model, graph::MetaDiGraph{T, U}, args...) = setgraph!(m, GraphModelExt{T, U}(graph, args...))
setgraph!{T}(m::Model, graph::AbstractMetaGraph{T}, args...) = error("GraphJuMP only uses graphs with metadata from the MetaGraphs.jl package. " * 
  "You can convert your `graph` to a MetaGraph using `MetaGraph(graph)`. ")

function removegraph!(m::Model)
  if hasgraph(m)
    delete!(m.ext, extKey)
  end
  # No error if there is no graph. 
end

# Build the formulations. 
function buildformulation(m::Model) # Makes a dispatch on the formulation. 
  checkgraph(m)
  return buildformulation(m, getgraphext(m).formulation)
end

function buildformulation(m::Model, gf::EdgeFlow)
  # Create the flow variables, one per edge and per commodity. 
  n_edges = ne(getgraph(m))
  n_commodities = length(getgraphext(m).commodities)
  flows = @variable(m, [e=1:n_edges, c=1:n_commodities], category=getgraphext(m).flowcategory)

  # Map edge and their IDs in the model. 
  id_to_edge = Dict([idx => edge for (idx, edge) in enumerate(edges(getgraph(m)))])
  edge_to_id = map(reverse, id_to_edge)

  # Give names to the flow variables. 
  for e in 1:n_edges
    for c in 1:n_commodities
      edge = id_to_edge[e]
      setname(flows[e, c], "flow_" * string(edge.src) * "_to_" * string(edge.dst) * "_commodity_" * string(getgraphext(m).commodities[c]))
    end
  end

  # Done! 
  return EdgeFlowFormulationExt(flows, id_to_edge, edge_to_id)
end

# For path formulations. 
function addpath!(m::Model, path)
  checkgraph(m)

  if ! supportspath(getgraphext(m).formulation)
    error("addpath! can only be called on graph models using a path-based formulation, such as `Path`.")
  end

  # TODO!
end

end 
