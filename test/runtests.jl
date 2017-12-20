using JuMP
using LightGraphs
using MetaGraphs

using GraphJuMP

using Base.Test
using Cbc

@testset "GraphJuMP" begin
  @testset "Integration tests" begin
    @testset "Edge flow formulation" begin
      @testset "Case 1: basic" begin
        g = CompleteDiGraph(4)
        mg = MetaDiGraph(g)

        m = Model(solver=CbcSolver())
        GraphJuMP.GraphModelExt{Int64, Float64}(mg)
        setgraph!(m, mg)
      end
    end
  end
end
