extended_eps(T) = 10_000*eps(T)
extended_eps() = 10_000*eps(Float64)

toSMatrix() = toSMatrix(Float64)
toSMatrix(::Type{T}) where {T} = zero(SMatrix{0,0,T,0})
toSMatrix(::Type{T}, s::SMatrix{N,M}) where {T,N,M} = convert(SMatrix{N,M,T}, s)
toSMatrix(::Type{T}, m::AbstractMatrix) where {T} = convert(SMatrix{size(m,1), size(m,2), T}, m)
toSMatrix(::Type{T}, vs...) where {T} = hcat(toSVector.(T, vs)...)
toSMatrix(vs...) = hcat(toSVector.(vs)...)
toSMatrix(m::AbstractMatrix) = convert(SMatrix{size(m,1), size(m,2), eltype(m)}, m)

toSVector(::Type{T} = Float64) where {T} = SVector{0,T}()
toSVector(v) = isempty(v) ? toSVector() : _toSVector(v)
toSVector(::Type{T}, v) where {T} = isempty(v) ? toSVector(T) : _toSVector(T, v)
_toSVector(::Type{T}, v) where {T} = SVector(ntuple(i -> T(v[i]), length(v)))
_toSVector(v::AbstractVector) = SVector(ntuple(i -> v[i], length(v)))
_toSVector(v) = SVector(v)

toSVectors() = toSVectors(Float64)
toSVectors(::Type{T}) where {T} = SVector{0,T}[]
toSVectors(::Type{T}, vs::Vararg{<:Any,N}) where {T,N} = [toSVector.(T, vs)...]
toSVectors(vs...) = [promote(toSVector.(vs)...)...]

@inline padright(sv::SVector{E,T}, x::T, ::Val{E}) where {E,T} = sv
@inline padright(sv::SVector{E,T}, x::T2, ::Val{E2}) where {E,T,E2,T2} =
    SVector{E2, T2}(ntuple(i -> i > E ? x : T2(sv[i]), Val(E2)))

@inline padrightbottom(s::SMatrix{E,L}, st::Type{SMatrix{E2,L2,T2,EL2}}) where {E,L,E2,L2,T2,EL2} =
    SMatrix{E2,L2,T2,EL2}(ntuple(k -> _padrightbottom((k - 1) % E2 + 1, (k - 1) ÷ E2 + 1, zero(T2), s), Val(EL2)))
@inline _padrightbottom(i, j, zero, s::SMatrix{E,L}) where {E,L} = i > E || j > L ? zero : s[i,j]
function padrightbottom(m::Matrix{T}, im, jm) where T
    i0, j0 = size(m)
    [i <= i0 && j<= j0 ? m[i,j] : zero(T) for i in 1:im, j in 1:jm]
end

@inline tuplejoin(x) = x
@inline tuplejoin(x, y) = (x..., y...)
@inline tuplejoin(x, y, z...) = (x..., tuplejoin(y, z...)...)
tuplesort((a,b)::Tuple{<:Number,<:Number}) = a > b ? (b, a) : (a, b)
tuplesort(t::Tuple) = t
tuplesort(::Missing) = missing

to_tuples_or_missing(::Missing) = missing
to_tuples_or_missing(::Tuple{}) = missing
to_tuples_or_missing(l::NTuple{N,Any}) where N = ntuple(n -> _to_tuples_or_missing(l[n]), Val(N))
_to_tuples_or_missing(l::Tuple{T1,T2}) where {T1, T2} = l
_to_tuples_or_missing(l) = (l, l)
to_ints_or_missing(::Missing) = missing
to_ints_or_missing(::Tuple{}) = missing
to_ints_or_missing(l::NTuple{N,Int}) where N = l
function tuplemaximum(ts::NTuple{N, Tuple{Int,Int}}) where {N}
    m = ts[1][1]
    for (x, y) in ts
        m = max(m, x, y)
    end
    return m
end

allsame(x) = all(isequal(first(x)), x)

function matrixnonzeros(m::Matrix)
    ids = Tuple{Int,Int}[]
    @inbounds for j in 1:size(m, 2), i in j:size(m,1)
        (iszero(m[i,j]) && iszero(m[j,i])) || push!(ids, (j,i))
    end
    return ids
end

function vectornonzeros(v::Vector)
    ids = Int[]
    @inbounds for (i,e) in enumerate(v)
        iszero(e) || push!(ids, i)
    end
    return ids
end

function filldiag!(matrix::AbstractMatrix, matrices)
    sizes = map(size, matrices)
    all(map(t->t[1] == t[2], sizes)) || throw(DimensionMismatch("All diagonal blocks should be square matrices"))
    dims = map(first, sizes)
    totaldim = sum(dims)
    sizem = size(matrix)
    sizem[1] == sizem[2] || throw(DimensionMismatch("Cannot fill diagonal of non-square matrices"))
    totaldim == sizem[1] || throw(DimensionMismatch("Diagonal blocks do not fit in matrix"))

    offset = 1
    for (m, d) in zip(matrices, dims)
        matrix[offset:(offset + d - 1), offset:(offset + d - 1)] .= m
        offset += d
    end
    return matrix
end