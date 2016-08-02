# We implement for pointers



if VERSION < v"0.5.0-dev"
    macro blasfunc(x)
       return :( $(BLAS.blasfunc(x) ))
    end
else
    import Base.BLAS.@blasfunc
end





for (fname, elty) in ((:dgbmv_,:Float64),
                      (:sgbmv_,:Float32),
                      (:zgbmv_,:Complex128),
                      (:cgbmv_,:Complex64))
    @eval begin
             # SUBROUTINE DGBMV(TRANS,M,N,KL,KU,ALPHA,A,LDA,X,INCX,BETA,Y,INCY)
             # *     .. Scalar Arguments ..
             #       DOUBLE PRECISION ALPHA,BETA
             #       INTEGER INCX,INCY,KL,KU,LDA,M,N
             #       CHARACTER TRANS
             # *     .. Array Arguments ..
             #       DOUBLE PRECISION A(LDA,*),X(*),Y(*)
        function gbmv!(trans::Char, m::Integer, kl::Integer, ku::Integer, alpha::($elty), A::Ptr{$elty}, n::Integer, st::Integer, x::Ptr{$elty}, beta::($elty), y::Ptr{$elty})
            ccall((@blasfunc($fname), libblas), Void,
                (Ptr{UInt8}, Ptr{BlasInt}, Ptr{BlasInt}, Ptr{BlasInt},
                 Ptr{BlasInt}, Ptr{$elty}, Ptr{$elty}, Ptr{BlasInt},
                 Ptr{$elty}, Ptr{BlasInt}, Ptr{$elty}, Ptr{$elty},
                 Ptr{BlasInt}),
                 &trans, &m, &n, &kl,
                 &ku, &alpha, A, &st,
                 x, &1, &beta, y, &1)
            y
        end
    end
end

# #TODO: Speed up the following
# function gbmv!{T}(trans::Char, m::Integer, kl::Integer, ku::Integer, alpha::T, A::Ptr{T}, n::Integer, st::Integer, x::Ptr{T}, beta::T, y::Ptr{T})
#     data=pointer_to_array(A,(kl+ku+1,n))
#     xx=pointer_to_array(x,n)
#     yy=pointer_to_array(y,m)
#
#     B=BandedMatrix(data,m,kl,ku)
#
#     for (k,j) in eachbandedindex(B)
#         yy[k] = beta*yy[k] + alpha*B[k,j]*xx[j]
#     end
#
#     yy
# end


# this is matrix*matrix

gbmm!{T}(α,A::BandedMatrix,B::BandedMatrix,β,C::BandedMatrix{T})=gbmm!(convert(T,α),
                                                                       convert(BandedMatrix{T},A),
                                                                       convert(BandedMatrix{T},B),
                                                                       convert(T,β),
                                                                       C)

# The following routines multiply
#
#  C[:,j] = α*A*B[:,j] + β* C[:,j]
#
#  But are divided into cases to minimize the calculated
#  rows.  We use A is n x ν, B is ν x m



# Equivalent to
#
#  C[1:min(Cl+j,n),j] = α*A[1:min(Cl+j,n),1:min(Bl+j,ν)]*B[1:min(Bl+j,ν),j]
#                       + β*C[1:min(Cl+j,n),j]
#
@inline function A11_Btop_Ctop_gbmv!(α,β,
                               n,ν,m,j,
                               sz,
                               a,Al,Au,sta,
                               b,Bl,Bu,stb,
                               c,Cl,Cu,stc)
   # A=BandedMatrix(pointer_to_array(a,(Al+Au+1,ν)),n,Al,Au)
   # B=BandedMatrix(pointer_to_array(b,(Bl+Bu+1,m)),ν,Bl,Bu)
   # C=BandedMatrix(pointer_to_array(c,(Cl+Cu+1,m)),n,Cl,Cu)
   #
   # nr=1:min(Cl+j,n)
   # νr=1:min(Bl+j,ν)
   #
   # cj = α*A[nr,νr]*B[νr,j] + β*C[nr,j]
   #
   # for k in nr
   #     C[k,j]=cj[k-first(nr)+1]
   # end
   #
   # c

   gbmv!('N',min(Cl+j,n),
          Al, Au,
          α,
          a, min(Bl+j,ν), sta,
          b+sz*((j-1)*stb+Bu-j+1), β,
          c+sz*((j-1)*stc+Cu-j+1))
end


# Equivalent to
#
#  C[1:min(Cl+j,n),j] = α*A[1:min(Cl+j,n),p:min(p+Bl+Bu+1,ν)]*
#                               B[p:min(p+Bl+Bu+1,ν),j]
#                       + β*C[1:min(Cl+j,n),j]
# for p = j-B.u
#


@inline function Atop_Bmid_Ctop_gbmv!(α,β,
                               n,ν,m,j,
                               sz,
                               a,Al,Au,sta,
                               b,Bl,Bu,stb,
                               c,Cl,Cu,stc)
   # p=j-Bu

   # A=BandedMatrix(pointer_to_array(a,(Al+Au+1,ν)),n,Al,Au)
   # B=BandedMatrix(pointer_to_array(b,(Bl+Bu+1,m)),ν,Bl,Bu)
   # C=BandedMatrix(pointer_to_array(c,(Cl+Cu+1,m)),n,Cl,Cu)
   #
   # nr=1:min(Cl+j,n)
   # νr=p:min(p+Bl+Bu+1,ν)
   #
   # cj = α*A[nr,νr]*B[νr,j] + β*C[nr,j]
   #
   # for k in nr
   #     C[k,j]=cj[k-first(nr)+1]
   # end
   #
   # c

   gbmv!('N', min(Cl+j,n),
           Al+j-Bu-1, Au-j+Bu+1,
           α,
           a+sz*(j-Bu-1)*sta, min(Bl+Bu+1,ν-j+Bu+1), sta,
           b+sz*(j-1)*stb, β,
           c+sz*((j-1)*stc+Cu-j+1))
end


# Equivalent to
#
#  C[nr,j] = α*A[nr,νr]*B[νr,j] + β*C[nr,j]
#
# for p  = j-B.u
#     nr = p-Au : min(p+Al,n)
#     νr = p    : min(p+Bl+Bu+1,ν)
#
#

@inline function Amid_Bmid_Cmid_gbmv!(α,β,
                               n,ν,m,j,
                               sz,
                               a,Al,Au,sta,
                               b,Bl,Bu,stb,
                               c,Cl,Cu,stc)
   p = j-Bu
   # A = BandedMatrix(pointer_to_array(a,(Al+Au+1,ν)),n,Al,Au)
   # B = BandedMatrix(pointer_to_array(b,(Bl+Bu+1,m)),ν,Bl,Bu)
   # C = BandedMatrix(pointer_to_array(c,(Cl+Cu+1,m)),n,Cl,Cu)
   #
   # nr= j-Cu : min(j+Cl,n)
   # νr= p    : min(p+Bl+Bu+1,ν)
   # if !isempty(nr) && !isempty(νr)
   #     cj = α*A[nr,νr]*B[νr,j] + β*C[nr,j]
   #
   #     for k in nr
   #         C[k,j]=cj[k-first(nr)+1]
   #     end
   # end
   #
   # c
   gbmv!('N', min(Cl+Cu+1,n-j+Cu+1),
           Al+Au, 0,
           α,
           a+sz*(j-Bu-1)*sta, min(Bl+Bu+1,ν-p+1), sta,
           b+sz*(j-1)*stb, β,
           c+sz*(j-1)*stc)
end

# Equivalent to
#
#  C[nr,j] =  β*C[nr,j]
#
# for nr= max(1,j-Cu) : min(j+Cl,n)
#


@inline function Anon_Bnon_C_gbmv!(α,β,
                               n,ν,m,j,
                               sz,
                               a,Al,Au,sta,
                               b,Bl,Bu,stb,
                               c,Cl,Cu,stc)
   # C = BandedMatrix(pointer_to_array(c,(Cl+Cu+1,m)),n,Cl,Cu)
   #
   # nr= max(1,j-Cu) : min(j+Cl,n)
   #
   # if !isempty(nr)
   #     cj =  β*C[nr,j]
   #
   #     for k in nr
   #         C[k,j]=cj[k-first(nr)+1]
   #     end
   # end
   #
   # c

   BLAS.scal!(Cu+Cl+1,β,c+sz*(j-1)*stc,1)
end



# function Amid_Bbot_Cmid_gbmv!(α,β,
#                                n,ν,m,j,
#                                sz,
#                                a,Al,Au,sta,
#                                b,Bl,Bu,stb,
#                                c,Cl,Cu,stc)
#    gbmv!('N', Cl+Cu+1,
#            Al+Au, 0,
#            α,
#            a+sz*(j-Bu-1)*sta, ν-j+1, sta,
#            b+sz*(j-1)*stb, β,
#            c+sz*(j-1)*stc)
# end
#
#
# function Abot_Bbot_Cbot_gbmv!(α,β,
#                                n,ν,m,j,
#                                sz,
#                                a,Al,Au,sta,
#                                b,Bl,Bu,stb,
#                                c,Cl,Cu,stc)
#    gbmv!('N', n-j+C.u+1,
#            A.l+A.u, 0,
#            α,
#            a+sz*(j-B.u-1)*sta, B.l+B.u+1-(j-ν+B.l), sta,
#            b+sz*(j-1)*stb, β,
#            c+sz*(j-1)*stc)
# end



function gbmm!{T<:BlasFloat}(α::T,A::BandedMatrix{T},B::BandedMatrix{T},β::T,C::BandedMatrix{T})
    n,ν=size(A)
    m=size(B,2)

    @assert n==size(C,1)
    @assert ν==size(B,1)
    @assert m==size(C,2)

    # only tested at the moment for this case
    # TODO: implement when C.u,C.l ≥
    @assert C.u==A.u+B.u
    @assert C.l==A.l+B.l


    a=pointer(A.data)
    b=pointer(B.data)
    c=pointer(C.data)
    sta=max(1,stride(A.data,2))
    stb=max(1,stride(B.data,2))
    stc=max(1,stride(C.data,2))
    sz=sizeof(T)

    Al=A.l;Au=A.u
    Bl=B.l;Bu=B.u
    Cl=C.l;Cu=C.u


    # Multiply columns j where B[1,j]≠0: A is at 1,1 and C[1,j]≠0
    for j=1:min(m,1+B.u)
        A11_Btop_Ctop_gbmv!(α,β,
                            n,ν,m,j,
                            sz,
                            a,Al,Au,sta,
                            b,Bl,Bu,stb,
                            c,Cl,Cu,stc)
    end

    # Multiply columns j where B[k,j]=0 for k<p=(j-B.u-1), A is at 1,1+p and C[1,j]≠0
    # j ≤ ν + B.u since then 1+p ≤ ν, so inside the columns of A

    for j=2+B.u:min(1+C.u,ν+B.u,m)
        Atop_Bmid_Ctop_gbmv!(α,β,
                            n,ν,m,j,
                            sz,
                            a,Al,Au,sta,
                            b,Bl,Bu,stb,
                            c,Cl,Cu,stc)
    end


    # multiply columns where A and B are mid and C is bottom
    for j=2+C.u:min(m,ν+B.u,n+C.u)
        Amid_Bmid_Cmid_gbmv!(α,β,
                            n,ν,m,j,
                            sz,
                            a,Al,Au,sta,
                            b,Bl,Bu,stb,
                            c,Cl,Cu,stc)
    end

    # scale columns of C by β that aren't impacted by α*A*B
    for j=ν+B.u+1:min(m,n+C.u)
        Anon_Bnon_C_gbmv!(α,β,
                            n,ν,m,j,
                            sz,
                            a,Al,Au,sta,
                            b,Bl,Bu,stb,
                            c,Cl,Cu,stc)
    end

    C
end

#TODO: Speedup
function gbmm!{T}(α::T,A::BandedMatrix{T},B::BandedMatrix{T},β::T,C::BandedMatrix{T})
    for (k,j) in eachbandedindex(C)
        C[k,j]*=β
    end

    m=size(C,2)

    for (k,ν) in eachbandedindex(A)
        for j=max(ν-B.l,1):min(ν+B.u,m)
            C[k,j]+=α*A[k,ν]*B[ν,j]
        end
    end

    C
end


function gbmm!{T<:BlasFloat}(α,A::BandedMatrix{T},B::Matrix{T},β,C::Matrix{T})
    st=max(1,stride(A.data,2))
    n,ν=size(A)
    a=pointer(A.data)


    b=pointer(B)

    m=size(B,2)

    @assert size(C,1)==n
    @assert size(C,2)==m

    c=pointer(C)

    sz=sizeof(T)

    for j=1:m
        gbmv!('N',n,A.l,A.u,α,a,ν,st,b+(j-1)*sz*ν,β,c+(j-1)*sz*n)
    end
    C
end

function banded_axpy!(a::Number,X,Y::BandedMatrix)
    @assert size(X)==size(Y)
    @assert bandwidth(X,1) ≤ bandwidth(Y,1) && bandwidth(X,2) ≤ bandwidth(Y,2)
    for (k,j) in eachbandedindex(X)
        @inbounds Y.data[k-j+Y.u+1,j]+=a*unsafe_getindex(X,k,j)
    end
    Y
end


function banded_axpy!{T,BM<:BandedMatrix}(a::Number,X,S::SubArray{T,2,BM})
    @assert size(X)==size(S)

    Y=parent(S)
    kr,jr=parentindexes(S)

    if isempty(kr) || isempty(jr)
        return S
    end

    shft=bandshift(S)

    @assert 0 ≤ bandwidth(X,1) ≤ bandwidth(Y,1)-shft && 0 ≤ bandwidth(X,2) ≤ bandwidth(Y,2)+shft


    for (k,j) in eachbandedindex(X)
        @inbounds Y.data[kr[k]-jr[j]+Y.u+1,jr[j]]+=a*unsafe_getindex(X,k,j)
    end

    S
end

Base.BLAS.axpy!(a::Number,X::BandedMatrix,Y::BandedMatrix) =
    banded_axpy!(a,X,Y)

Base.BLAS.axpy!{T,BM<:BandedMatrix}(a::Number,X::BandedMatrix,S::SubArray{T,2,BM}) =
    banded_axpy!(a,X,S)

function Base.BLAS.axpy!{T1,T2,BM1<:BandedMatrix,BM2<:BandedMatrix}(a::Number,
                                                           X::SubArray{T1,2,BM1},
                                                           Y::SubArray{T2,2,BM2})
    if bandwidth(X,1) < 0
        jr=1-bandwidth(X,1):size(X,2)
        banded_axpy!(a,view(X,:,jr),view(Y,:,jr))
    elseif bandwidth(X,2) < 0
        kr=1-bandwidth(X,2):size(X,1)
        banded_axpy!(a,view(X,kr,:),view(Y,kr,:))
    else
        banded_axpy!(a,X,Y)
    end
end

function Base.BLAS.axpy!{T,BM<:BandedMatrix}(a::Number,X::SubArray{T,2,BM},Y::BandedMatrix)
    if bandwidth(X,1) < 0
        jr=1-bandwidth(X,1):size(X,2)
        banded_axpy!(a,view(X,:,jr),view(Y,:,jr))
    elseif bandwidth(X,2) < 0
        kr=1-bandwidth(X,2):size(X,1)
        banded_axpy!(a,view(X,kr,:),view(Y,kr,:))
    else
        banded_axpy!(a,X,Y)
    end
end

function Base.BLAS.axpy!(a::Number,X::BandedMatrix,Y::AbstractMatrix)
    @assert size(X)==size(Y)
    for (k,j) in eachbandedindex(X)
        @inbounds Y[k,j]+=a*unsafe_getindex(X,k,j)
    end
    Y
end






## A_mul_B! overrides

Base.A_mul_B!(C::Matrix,A::BandedMatrix,B::Matrix) = gbmm!(1.0,A,B,0.,C)

## Matrix*Vector Multiplicaiton



Base.A_mul_B!(c::Vector,A::BandedMatrix,b::Vector) =
    BLAS.gbmv!('N',A.m,A.l,A.u,1.0,A.data,b,0.,c)



## Matrix*Matrix Multiplication


Base.A_mul_B!(C::BandedMatrix,A::BandedMatrix,B::BandedMatrix) = gbmm!(1.0,A,B,0.0,C)



## Method definitions for generic eltypes - will make copies

# Direct and transposed algorithms
for typ in [BandedMatrix, BandedLU]
    for fun in [:A_ldiv_B!, :At_ldiv_B!]
        @eval function $fun{T<:Number, S<:Number}(A::$typ{T}, B::StridedVecOrMat{S})
            checksquare(A)
            AA, BB = _convert_to_blas_type(A, B)
            $fun(lufact(AA), BB) # call BlasFloat versions
        end
    end
    # \ is different because it needs a copy, but we have to avoid ambiguity
    @eval function (\){T<:BlasReal}(A::$typ{T}, B::VecOrMat{Complex{T}})
        checksquare(A)
        A_ldiv_B!(convert($typ{Complex{T}}, A), copy(B)) # goes to BlasFloat call
    end
    @eval function (\){T<:Number, S<:Number}(A::$typ{T}, B::StridedVecOrMat{S})
        checksquare(A)
        TS = _promote_to_blas_type(T, S)
        A_ldiv_B!(convert($typ{TS}, A), copy_oftype(B, TS)) # goes to BlasFloat call
    end
end

# Hermitian conjugate
for typ in [BandedMatrix, BandedLU]
    @eval function Ac_ldiv_B!{T<:Complex, S<:Number}(A::$typ{T}, B::StridedVecOrMat{S})
        checksquare(A)
        AA, BB = _convert_to_blas_type(A, B)
        Ac_ldiv_B!(lufact(AA), BB) # call BlasFloat versions
    end
    @eval Ac_ldiv_B!{T<:Real, S<:Real}(A::$typ{T}, B::StridedVecOrMat{S}) =
        At_ldiv_B!(A, B)
    @eval Ac_ldiv_B!{T<:Real, S<:Complex}(A::$typ{T}, B::StridedVecOrMat{S}) =
        At_ldiv_B!(A, B)
end


# Method definitions for BlasFloat types - no copies

# Direct and transposed algorithms
for (ch, fname) in zip(('N', 'T'), (:A_ldiv_B!, :At_ldiv_B!))
    # provide A*_ldiv_B!(::BandedLU, ::StridedVecOrMat) for performance
    @eval function $fname{T<:BlasFloat}(A::BandedLU{T}, B::StridedVecOrMat{T})
        checksquare(A)
        gbtrs!($ch, A.l, A.u, A.m, A.data, A.ipiv, B)
    end
    # provide A*_ldiv_B!(::BandedMatrix, ::StridedVecOrMat) for generality
    @eval function $fname{T<:BlasFloat}(A::BandedMatrix{T}, B::StridedVecOrMat{T})
        checksquare(A)
        $fname(lufact(A), B)
    end
end

# Hermitian conjugate algorithms - same two routines as above
function Ac_ldiv_B!{T<:BlasComplex}(A::BandedLU{T}, B::StridedVecOrMat{T})
    checksquare(A)
    gbtrs!('C', A.l, A.u, A.m, A.data, A.ipiv, B)
end

function Ac_ldiv_B!{T<:BlasComplex}(A::BandedMatrix{T}, B::StridedVecOrMat{T})
    checksquare(A)
    Ac_ldiv_B!(lufact(A), B)
end

# fall back for real inputs
Ac_ldiv_B!{T<:BlasReal}(A::BandedLU{T}, B::StridedVecOrMat{T}) =
    At_ldiv_B!(A, B)
Ac_ldiv_B!{T<:BlasReal}(A::BandedMatrix{T}, B::StridedVecOrMat{T}) =
    At_ldiv_B!(A, B)
