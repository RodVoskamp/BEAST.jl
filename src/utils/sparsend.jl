module SparseND

import BEAST

struct Banded3D{T} <: AbstractArray{T,3}
    k0::Array{Int,2}
    data::Array{T,3}
    maxk0::Int
    maxk1::Int
    function Banded3D{T}(k0,data,maxk1) where T
        @assert size(k0) == size(data)[2:3]
        return new(k0,data,maximum(k0),maxk1)
    end
end

Banded3D(k0,data::Array{T},maxk1) where {T} = Banded3D{T}(k0,data,maxk1)

bandwidth(A::Banded3D) = size(A.data,1)

import Base: size, getindex, setindex!

# size(A::Banded3D) = size(A.data)
size(A::Banded3D) = tuple(size(A.k0)..., A.maxk1)

function getindex(A::Banded3D, m::Int, n::Int, k::Int)
    k0 = A.k0[m,n]
    k0 == 0 && return zero(eltype(A))
    l = k - k0 + 1
    l < 1 && return zero(eltype(A))
    l > bandwidth(A) && return zero(eltype(A))
    A.data[l,m,n]
end

function setindex!(A::Banded3D, v, m, n, k)
    k0 = A.k0[m,n]
    @assert k0 != 0 "Failed: $v, $m, $n, $k"
    @assert A.k0[m,n] <= k <= A.k0[m,n] + bandwidth(A) - 1
    A.data[k-A.k0[m,n]+1,m,n] = v
end


function Base.:+(A::Banded3D{T}, B::Banded3D{T}) where {T}

    M = size(A,1)
    N = size(A,2)

    @assert M == size(B,1)
    @assert N == size(B,2)

    Abw = size(A.data,1)
    Bbw = size(B.data,1)

    # keep track of empty columns
    Az = findall(A.k0 .== 0)
    Bz = findall(B.k0 .== 0)

    K0 = min.(A.k0, B.k0)
    K0[Az] = B.k0[Az]
    K0[Bz] = A.k0[Bz]

    AK1 = A.k0 .+ (Abw - 1); AK1[Az] .= -1
    BK1 = B.k0 .+ (Bbw - 1); BK1[Bz] .= -1
    K1 = max.(AK1, BK1)

    bw = maximum(K1 - K0 .+ 1)
    @assert bw > 0
    @assert bw >= Abw
    @assert bw >= Bbw
    data = zeros(T, bw, M, N)
    for m in axes(A.data,2)
        for n in axes(A.data,3)
            k0 = K0[m,n]
            @assert k0 != 0

            Ak0 = A.k0[m,n]
            if Ak0 != 0
                for Al in 1:Abw
                    k = Ak0 + Al - 1
                    l = k - k0 + 1
                    data[l,m,n] += A.data[Al,m,n]
                end
            end

            Bk0 = B.k0[m,n]
            if Bk0 != 0
                for Bl in 1:Bbw
                    k = Bk0 + Bl - 1
                    l = k - k0 + 1
                    l < 1 && @show m, n, k0, k, Bk0, Bl
                    d = data[l,m,n]
                    data[l,m,n] = d + B.data[Bl,m,n]
                end
            end
        end
    end

    Banded3D(K0, data, max(A.maxk1, B.maxk1))
end

function BEAST.convolve(Z::SparseND.Banded3D,x,j,k_start)
    T = promote_type(eltype(Z), eltype(x))
    M,N,L = size(Z)
    K = size(Z.data,1)
    @assert M == size(x,1)
    y = zeros(T,M)
    for n in 1:N
        for m in 1:M
            k0 = Z.k0[m,n] # k0 is 1-based
            l0 = max(1, k_start - k0 + 1)
            l1 = min(K, j - k0 + 1)
            for l in l0 : l1
                k = k0 + l - 1
                # j - k + 1 < 1 && break
                y[m] += Z.data[l,m,n] * x[n,j - k + 1]
            end
        end
    end
    return y
end


struct MatrixOfConvolutions{T} <: AbstractArray{Vector{T},2}
    banded::AbstractArray{T,3}
end

function Base.eltype(x::MatrixOfConvolutions{T}) where {T}
    Vector{T}
end
Base.size(x::MatrixOfConvolutions) = size(x.banded)[1:2]
function Base.getindex(x::MatrixOfConvolutions, m, n)
    return x.banded[m,n,:]
end


struct SpaceTimeData{T} <: AbstractArray{Vector{T},1}
    data::Array{T,2}
end

Base.eltype(x::SpaceTimeData{T}) where {T} = Vector{T}
Base.size(x::SpaceTimeData) = (size(x.data)[1],)
Base.getindex(x::SpaceTimeData, i::Int) = x.data[i,:]

end # module
