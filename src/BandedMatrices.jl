__precompile__()

module BandedMatrices
    using Base


import Base: getindex,setindex!,*,.*,+,.+,-,.-,==,<,<=,>,
                >=,./,/,.^,^,\,transpose

export BandedMatrix, bandrange, bzeros,beye,brand,bones



##
# Represent a banded matrix
# [ a_11 a_12
#   a_21 a_22 a_23
#   a_31 a_32 a_33 a_34
#        a_42 a_43 a_44  ]
# ordering the data like (rows first)
#       [ *     *       a_31    a_42
#         *      a_21   a_32    a_43
#         a_11   a_22   a_33    A_44
#         a_12   a_23   a_34    *       ]
#  (columns first)
#       [ *      a_12   a_23    a_34
#         a_11   a_22   a_33    a_43
#         a_21   a_32   a_43    *
#         a_32   a_42   *       *       ]
###


type BandedMatrix{T} <: AbstractSparseMatrix{T,Int}
    data::Matrix{T}  # l+u+1 x n (# of rows)
    m::Int #Number of columns
    l::Int # lower bandwidth ≥0
    u::Int # upper bandwidth ≥0
    function BandedMatrix(data::Matrix{T},m,l,u)
        @assert size(data,1)==l+u+1
        new(data,m,l,u)
    end
end


BandedMatrix{T}(data::Matrix{T},m::Integer,a::Integer,b::Integer)=BandedMatrix{T}(data,m,a,b)

BandedMatrix{T}(::Type{T},n::Integer,m::Integer,a::Integer,b::Integer)=BandedMatrix{T}(Array(T,b+a+1,n),m,a,b)
BandedMatrix{T}(::Type{T},n::Integer,a::Integer,b::Integer)=BandedMatrix(T,n,n,a,b)
BandedMatrix{T}(::Type{T},n::Integer,::Colon,a::Integer,b::Integer)=BandedMatrix(T,n,n+b,a,b)


BandedMatrix{T}(data::Matrix{T},m::Integer,a)=BandedMatrix(data,m,-a[1],a[end])
BandedMatrix{T}(::Type{T},n::Integer,m::Integer,a)=BandedMatrix(T,n,m,-a[1],a[end])
BandedMatrix{T}(::Type{T},n::Integer,::Colon,a)=BandedMatrix(T,n,:,-a[1],a[end])
BandedMatrix{T}(::Type{T},n::Integer,a)=BandedMatrix(T,n,-a[1],a[end])

Base.eltype{T}(::BandedMatrix{T})=T
Base.convert{V}(::Type{BandedMatrix{V}},M::BandedMatrix) = BandedMatrix{V}(convert(Matrix{V},M.data),M.m,M.l,M.u)
function Base.convert{BM<:BandedMatrix}(::Type{BM},M::Matrix)
    ret=BandedMatrix(eltype(BM)==Any?eltype(M):promote_type(eltype(BM),eltype(M)),size(M,1),size(M,2),size(M,1)-1,size(M,2)-1)
    for k=1:size(M,1),j=1:size(M,2)
        ret[k,j]=M[k,j]
    end
    ret
end


Base.promote_rule{T,V}(::Type{BandedMatrix{T}},::Type{BandedMatrix{V}})=BandedMatrix{promote_type(T,V)}



for (op,bop) in ((:(Base.rand),:brand),(:(Base.zeros),:bzeros),(:(Base.ones),:bones))
    @eval begin
        $bop{T}(::Type{T},n::Integer,m::Integer,a::Integer,b::Integer)=BandedMatrix($op(T,b+a+1,n),m,a,b)
        $bop{T}(::Type{T},n::Integer,a::Integer,b::Integer)=$bop(T,n,n,a,b)
        $bop{T}(::Type{T},n::Integer,::Colon,a::Integer,b::Integer)=$bop(T,n,n+b,a,b)
        $bop{T}(::Type{T},::Colon,m::Integer,a::Integer,b::Integer)=$bop(T,m+a,m,a,b)
        $bop(n::Integer,m::Integer,a::Integer,b::Integer)=$bop(Float64,n,m,a,b)
        $bop(n::Integer,a::Integer,b::Integer)=$bop(n,n,a,b)

        $bop{T}(::Type{T},n::Integer,m::Integer,a)=$bop(T,n,m,-a[1],a[end])
        $bop{T}(::Type{T},n::Number,::Colon,a)=$bop(T,n,:,-a[1],a[end])
        $bop{T}(::Type{T},::Colon,m::Integer,a)=$bop(T,:,m,-a[1],a[end])
        $bop{T}(::Type{T},n::Integer,a)=$bop(T,n,-a[1],a[end])
        $bop(n::Integer,m::Integer,a)=$bop(Float64,n,m,-a[1],a[end])
        $bop(n::Integer,a)=$bop(n,-a[1],a[end])
    end
end



function beye{T}(::Type{T},n::Integer,a...)
    ret=bzeros(T,n,a...)
    for k=1:n
         ret[k,k]=one(T)
    end
    ret
end
beye{T}(::Type{T},n::Integer)=beye(T,n,0,0)
beye(n::Integer)=beye(n,0,0)
beye(n::Integer,a...)=beye(Float64,n,a...)



Base.size(A::BandedMatrix,k)=ifelse(k==1,size(A.data,2),A.m)
Base.size(A::BandedMatrix)=size(A.data,2),A.m
bandinds(A::BandedMatrix)=-A.l,A.u
bandrange(A::BandedMatrix)=-A.l:A.u



# returns a vector of each index in the banded part of a matrix
# TODO: make a special iterator, to avoid allocating memory
function eachbandedindex(B::BandedMatrix)
    ret=Array(CartesianIndex{2},0)
    for j=1:size(B,2),k=max(1,j-B.u):min(j+B.l,size(B,1))
        push!(ret,CartesianIndex((k,j)))
    end
    ret
end



unsafe_getindex(A::BandedMatrix,k::Integer,j::Integer)=A.data[j-k+A.l+1,k]
unsafe_getindex(A::BandedMatrix,k::Integer,jr::Range)=vec(A.data[jr-k+A.l+1,k])
getindex(A::BandedMatrix,k::Integer,j::Integer)=(-A.l≤j-k≤A.u)?unsafe_getindex(A,k,j):(j≤A.m?zero(eltype(A)):throw(BoundsError()))
getindex(A::BandedMatrix,k::Integer,jr::Range)=-A.l≤jr[1]-k≤jr[end]-k≤A.u?unsafe_getindex(A,k,jr):[A[k,j] for j=jr].'
getindex(A::BandedMatrix,kr::Range,j::Integer)=[A[k,j] for k=kr]
getindex(A::BandedMatrix,kr::Range,jr::Range)=[A[k,j] for k=kr,j=jr]
Base.full(A::BandedMatrix)=A[1:size(A,1),1:size(A,2)]


function Base.sparse(B::BandedMatrix)
    i=Array(Int,length(B.data));j=Array(Int,length(B.data))
    n,m=size(B.data)
    Bm=size(B,2)
    vb=copy(vec(B.data))
    for k=1:n,ℓ=1:m
        i[k+n*(ℓ-1)]=ℓ
        jj=k+ℓ-B.l-1
        if jj <1 || jj > Bm
            vb[k+n*(ℓ-1)] = 0
        end
        j[k+n*(ℓ-1)]=min(max(jj,1),Bm)
    end
    sparse(i,j,vb)
end




# pass standard routines to full matrix

Base.norm(B::BandedMatrix,opts...)=norm(full(B),opts...)


# We turn off bound checking to allow nicer syntax without branching
#setindex!(A::BandedMatrix,v,k::Integer,j::Integer)=((A.l≤j-k≤A.u)&&k≤A.n)?ussetindex!(A,v,k,j):throw(BoundsError())
#setindex!(A::BandedMatrix,v,kr::Range,j::Integer)=(A.l≤j-kr[end]≤j-kr[1]≤A.u&&kr[end]≤A.n)?ussetindex!(A,v,kr,j):throw(BoundsError())


unsafe_setindex!(A::BandedMatrix,v,k::Integer,j::Integer)=(@inbounds A.data[j-k+A.l+1,k]=v)

"unsafe_pluseq!(A,v,k,j) is an unsafe versoin of A[k,j] += v"
unsafe_pluseq!(A::BandedMatrix,v,k::Integer,j::Integer)=(@inbounds A.data[j-k+A.l+1,k]+=v)
setindex!(A::BandedMatrix,v,k::Integer,j::Integer)=(A.data[j-k+A.l+1,k]=v)

function setindex!(A::BandedMatrix,v,kr::Range,jr::Range)
    for j in jr
        A[kr,j]=slice(v,:,j)
    end
end
function setindex!(A::BandedMatrix,v,k::Integer,jr::Range)
    for j in jr
        A[k,j]=v[j]
    end
end



## ALgebra and other funcrtions

function Base.maximum(B::BandedMatrix)
    m=zero(eltype(B))
    for k=1:size(B,1), j=max(1,k-B.l):min(B.m,k+B.u)
        m=max(B[k,j],m)
    end
    m
end


for OP in (:*,:.*,:+,:.+,:-,:.-)
    @eval begin
        $OP(B::BandedMatrix{Bool},x::Bool)=BandedMatrix($OP(B.data,x),B.m,B.l,B.u)
        $OP(x::Bool,B::BandedMatrix{Bool})=BandedMatrix($OP(x,B.data),B.m,B.l,B.u)
        $OP(B::BandedMatrix,x::Number)=BandedMatrix($OP(B.data,x),B.m,B.l,B.u)
        $OP(x::Number,B::BandedMatrix)=BandedMatrix($OP(x,B.data),B.m,B.l,B.u)
    end
end

function +{T,V}(A::BandedMatrix{T},B::BandedMatrix{V})
    if size(A) != size(B)
        throw(DimensionMismatch("+"))
    end
    n,m=size(A,1),size(A,2)

    ret = bzeros(promote_type(T,V),n,m,max(A.l,B.l),max(A.u,B.u))
    for k=1:n,j=max(1,k-A.l):min(m,k+A.u)
        unsafe_pluseq!(ret,unsafe_getindex(A,k,j),k,j)
    end
    for k=1:n,j=max(1,k-B.l):min(m,k+B.u)
        unsafe_pluseq!(ret,unsafe_getindex(B,k,j),k,j)
    end

    ret
end

function -{T,V}(A::BandedMatrix{T},B::BandedMatrix{V})
    if size(A) != size(B)
        throw(DimensionMismatch("+"))
    end
    n,m=size(A,1),size(A,2)

    ret = bzeros(promote_type(T,V),n,m,max(A.l,B.l),max(A.u,B.u))
    for k=1:n,j=max(1,k-A.l):min(m,k+A.u)
        unsafe_pluseq!(ret,unsafe_getindex(A,k,j),k,j)
    end
    for k=1:n,j=max(1,k-B.l):min(m,k+B.u)
        unsafe_pluseq!(ret,-unsafe_getindex(B,k,j),k,j)
    end

    ret
end



function *{T,V}(A::BandedMatrix{T},B::BandedMatrix{V})
    if size(A,2)!=size(B,1)
        throw(DimensionMismatch("*"))
    end
    n,m=size(A,1),size(B,2)
    bmultiply!(bzeros(promote_type(T,V),n,m,A.l+B.l,A.u+B.u),A,B)
end

function *{T,V}(A::BandedMatrix{T},B::Matrix{V})
    if size(A,2)!=size(B,1)
        throw(DimensionMismatch("*"))
    end
    n,m=size(A,1),size(B,2)
    bmultiply!(zeros(promote_type(T,V),n,m),A,B)
end


function *{T,V}(A::BandedMatrix{T},b::Vector{V})
    if size(A,2)!=length(b)
        throw(DimensionMismatch("*"))
    end
    n=size(A,1)
    bmultiply!(zeros(promote_type(T,V),n),A,b)
end



function Base.transpose(B::BandedMatrix)
    Bt=bzeros(size(B,2),size(B,1),B.u,B.l)
    for k=1:size(B,1),j=max(1,k-B.l):min(size(B,2),k+B.u)
       Bt[j,k]=B[k,j]
    end
    Bt
end

function Base.ctranspose(B::BandedMatrix)
    Bt=bzeros(size(B,2),size(B,1),B.u,B.l)
    for k=1:size(B,1),j=max(1,k-B.l):min(size(B,2),k+B.u)
       Bt[j,k]=conj(B[k,j])
    end
    Bt
end


function Base.diag{T}(A::BandedMatrix{T})
    n=size(A,1)
    @assert n==size(A,2)

    vec(A.data[A.l+1,1:n])
end


## Matrix*Vector Multiplicaiton

function bmultiply!(c::Vector,A::BandedMatrix,b::Vector)
    for k=1:size(A,1)  # rows of c
        @simd for l=max(1,k-A.l):min(k+A.u,size(A,2)) # columns of A/rows of b
             @inbounds c[k]+=A.data[l-k+A.l+1,k]*b[l]
        end
    end
    c
end




## Matrix*Matrix Multiplication




function bmultiply!(C::BandedMatrix,A::BandedMatrix,B::BandedMatrix,ri::Integer=0,ci::Integer=0,rs::Integer=1,cs::Integer=1)
    n=size(A,1);m=size(B,2)
    @assert size(C,1)≥rs*n+ri&&size(C,2)≥cs*m+ci
    for k=1:n  # rows of C
        for l=max(1,k-A.l):min(k+A.u,size(A,2)) # columns of A
            @inbounds Aj=A.data[l-k+A.l+1,k]


            #  A[k,j] == A.data[j-k+A.l+1,k]
            shB=-l+B.l+1
            ks=rs*k+ri
            shC=ci-ks+C.l+1
            @simd for j=max(1,l-B.l):min(B.u+l,m) # columns of C/B
                @inbounds C.data[cs*j+shC,ks]+=Aj*B.data[j+shB,l]
            end
        end
    end
    C
end

function bmultiply!(C::Matrix,A::BandedMatrix,B::Matrix,ri::Integer=0,ci::Integer=0,rs::Integer=1,cs::Integer=1)
    n=size(A,1);m=size(B,2)
    @assert size(C,1)≥rs*n+ri&&size(C,2)≥cs*m+ci
    for k=1:n  # rows of C
        for l=max(1,k-A.l):min(k+A.u,size(A,2)) # columns of A
            @inbounds Aj=A.data[l-k+A.l+1,k]

             @simd for j=1:m # columns of C/B
                 @inbounds C[rs*k+ri,cs*j+ci]+=Aj*B[l,j]
             end
        end
    end
    C
end

## Matrix.*Matrix

function .*(A::BandedMatrix,B::BandedMatrix)
    @assert size(A,1)==size(B,1)&&size(A,2)==size(B,2)

    l=min(A.l,B.l);u=min(A.u,B.u)
    ret=BandedMatrix(promote_type(eltype(A),eltype(B)),size(A,1),size(A,2),l,u)

    for k=1:size(A,1),j=max(1,k-l):min(size(A,2),k+u)
        @inbounds ret[k,j]=A[k,j]*B[k,j]
    end
    ret
end


#implements fliplr(flipud(A))
function fliplrud(A::BandedMatrix)
    n,m=size(A)
    l=A.u+n-m
    u=A.l+m-n
    ret=BandedMatrix(eltype(A),n,m,l,u)
    for k=1:n,j=max(1,k-l):min(m,k+u)
        @inbounds ret[k,j]=A[n-k+1,m-j+1]
    end
    ret
end



## Show

type PrintShow
    str
end
Base.show(io::IO,N::PrintShow)=print(io,N.str)

function Base.showarray(io::IO,B::BandedMatrix;
                   header::Bool=true, limit::Bool=Base._limit_output,
                   sz = (s = Base.tty_size(); (s[1]-4, s[2])), repr=false)
    header && print(io,summary(B))

    if !isempty(B)
        header && println(io,":")
        M=Array(Any,size(B)...)
        fill!(M,PrintShow(""))
        for kj=eachbandedindex(B)
            M[kj]=B[kj]
        end

        Base.showarray(io,M;header=false)
    end
end


end #module
