using Base.Test
using BandedMatrices

# size and friends
let    
    a = brand(5, 4, 3, 1)
    @test size(a) == (5, 4) 
    @test size(a, 1) == 5 
    @test size(a, 2) == 4 
    @test eltype(a) == Float64
    @test ndims(a) == 2
    @test Base.linearindexing(a) == Base.LinearSlow()
end