module ModelTest

using Test
using Elsa

@test Onsite(1) isa Elsa.Onsite{Int64,Missing}
# @test Onsite(1, sublats = 1) isa Elsa.Onsite{Int64,Tuple{Tuple{Int64,Int64}}}
# @test Onsite([1 2; 3 4], 1) isa Elsa.OnsiteConst{Tuple{Int64},2,Int64,4}
# @test Onsite([1 2; 3 4.0], 1) isa Elsa.OnsiteConst{Tuple{Int64},2,Float64,4}
# @test Onsite(@SMatrix[1 2; 3 4.0], 1) isa Elsa.OnsiteConst{Tuple{Int64},2,Float64,4}
@test Onsite(r -> @SMatrix[r[1] 0; 0 r[2]]) isa Elsa.Onsite{<:Function, Missing}

# @test Hopping(@SMatrix[1 2.0; 3 4], (1,1)) isa Elsa.HoppingConst{Tuple{Tuple{Int,Int}},2,2,Float64,4}
# @test Hopping(@SMatrix[1 2.0; 3 4]) isa Elsa.HoppingConst{Missing,2,2,Float64,4}

# @test_throws DimensionMismatch Model(Onsite([1 2], 3)) # Non-square onsite matrix!
# @test_throws MethodError Model(Onsite(@SMatrix[1 2])) # Non-square onsite matrix!
# @test_throws DimensionMismatch Model(Hopping(@SMatrix[1 2], (1,1)))  # Non-square intra-sublattice hopping matrix!
# @test_throws DimensionMismatch Model(Hopping([1 2]))  # Non-square intra-sublattice hopping matrix!

# @test isempty(Elsa.nzonsites(Model()))

end
