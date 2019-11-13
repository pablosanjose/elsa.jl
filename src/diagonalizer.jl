#######################################################################
# Diagonalizer
#######################################################################
abstract type AbstractCodiagonalizer end
abstract type AbstractDiagonalizePackage end

struct Diagonalizer{M<:AbstractDiagonalizePackage,A<:AbstractArray,C<:Union{Missing,AbstractCodiagonalizer}}
    method::M
    matrix::A
    levels::Int
    origin::Float64
    minprojection::Float64
    codiag::C       # Matrices to resolve degeneracies, or missing
end

function Diagonalizer(method, matrix::AbstractMatrix{M};
             levels = missing,
             origin = 0.0,
             minprojection = 0.1,
             codiag = missing) where {M}
    _levels = levels === missing ? size(matrix, 1) : levels
    Diagonalizer(method, matrix, _levels, origin, minprojection, codiag)
end

# This is in general type unstable. A function barrier when using it is needed
diagonalizer(h::Hamiltonian{<:Lattice,<:Any,<:Any,<:Matrix}; kw...) =
    diagonalizer(LinearAlgebraPackage(values(kw)), similarmatrix(h))

function diagonalizer(h::Hamiltonian{<:Lattice,<:Any,M,<:SparseMatrixCSC};
                      levels = missing, origin = 0.0,
                      codiag = defaultcodiagonalizer(h), kw...) where {M}
    if size(h, 1) < 50 || levels === missing || levels / size(h, 1) > 0.1
        # @warn "Requesting significant number of sparse matrix eigenvalues. Converting to dense."
        matrix = Matrix(similarmatrix(h))
        _matrix = ishermitian(h) ? Hermitian(matrix) : matrix
        d = diagonalizer(LinearAlgebraPackage(; kw...), _matrix;
            levels = levels, origin = origin, codiag = codiag)
    elseif M isa Number
        matrix = similarmatrix(h)
        d = diagonalizer(ArpackPackage(; kw...), matrix;
            levels = levels, origin = origin, codiag = codiag)
    elseif M isa SMatrix
        matrix = similarmatrix(h)
        d = diagonalizer(ArnoldiPackagePackage(; kw...), matrix;
            levels = levels, origin = origin, codiag = codiag)
    else
        throw(ArgumentError("Could not establish diagonalizer method"))
    end
    return d
end

#######################################################################
# Diagonalize methods
#   (All but LinearAlgebraPackage `@require` some package to be loaded)
#######################################################################
struct LinearAlgebraPackage{O} <: AbstractDiagonalizePackage
    options::O
end

LinearAlgebraPackage(; kw...) = LinearAlgebraPackage(values(kw))

# Registers method as available
diagonalizer(method::LinearAlgebraPackage, matrix; kw...) = Diagonalizer(method, matrix; kw...)

function diagonalize(d::Diagonalizer{<:LinearAlgebraPackage})
    # ϵ, ψ = eigen!(d.matrix; sortby = λ -> abs(λ - d.origin), d.method.options...)
    ϵ, ψ = eigen!(d.matrix; d.method.options...)
    # ϵ´, ψ´ = view(ϵ, 1:d.levels), view(ψ, :, 1:d.levels)
    # return ϵ´, ψ´
end

# Fallback for unloaded packages

(m::AbstractDiagonalizePackage)(;kw...) =
    throw(ArgumentError("The package required for the requested diagonalize method $m is not loaded. Please do e.g. `using Arpack` to use the Arpack method. See `diagonalizer` for details."))

# Optionally loaded methods

struct ArpackPackage{O} <: AbstractDiagonalizePackage
    options::O
end

struct IterativeSolversPackage{O,L,E} <: AbstractDiagonalizePackage
    options::O
    point::Float64  # Shift point for shift and invert
    lmap::L         # LinearMap for shift and invert
    engine::E       # Optional support for lmap (e.g. Pardiso solver or factorization)
end

struct ArnoldiPackagePackage{O,L,E} <: AbstractDiagonalizePackage
    options::O
    point::Float64  # Shift point for shift and invert
    lmap::L         # LinearMap for shift and invert
    engine::E       # Optional support for lmap (e.g. Pardiso solver or factorization)
end

#######################################################################
# Codiagonalization
#######################################################################
# ϵ is assumed sorted
resolve_degeneracies!(ϵ, ψ, d::Diagonalizer{<:Any,<:Any,Missing}, ϕs) = (ϵ, ψ)

function resolve_degeneracies!(ϵ, ψ, d::Diagonalizer{<:Any,<:Any,<:AbstractCodiagonalizer}, ϕs)
    issorted(ϵ) || throw(ArgumentError("Unsorted eigenvalues"))
    if hasdegeneracies(ϵ)
        finddegeneracies!(d.codiag.degranges, ϵ)
        # if ϕs ./ 2π ≈ [0.5,0.5]
        #     @show d.codiag.degranges
        #     @show ϵ[41:60]
        # end
    else
        return ϵ, ψ
    end
    success = d.codiag.success
    resize!(success, length(d.codiag.degranges))
    fill!(success, false)
    # @show d.codiag.degranges, round.(ϕs/2π, digits=3)
    for n in 1:num_codiag_matrices(d)
        v = codiag_matrix(n, d, ϕs)
        for (i, r) in enumerate(d.codiag.degranges)
            success[i] || (success[i] = codiagonalize!(ϵ, ψ, v, r))
            @show success[i], n, length(r)
        end
        # all(isempty, d.codiag.degranges) && break
        all(success) && break
    end
    all(success) || @show "---------------------------FAILED---------------------------"
    return ϵ, ψ
end

function hasdegeneracies(sorted_ϵ::AbstractVector{T}, degtol = sqrt(eps(real(T)))) where {T}
    for i in 2:length(sorted_ϵ)
        # sorted_ϵ[i] ≈ sorted_ϵ[i-1] && return true
        abs(sorted_ϵ[i] - sorted_ϵ[i-1]) < degtol && return true
    end
    return false
end

finddegeneracies!(degranges, sorted_ϵ) = approxruns!(degranges, sorted_ϵ)

function codiagonalize!(ϵ, ψ, v, r)
    subspace = view(ψ, :, r)
    vsubspace = subspace' * v * subspace
    veigen = eigen!(vsubspace)
    success = !hasdegeneracies(veigen.values)
    success && (subspace .= subspace * veigen.vectors)
    # if !success
        @show success, r, round.(real.(veigen.values), digits = 3)
        # @show round.(Matrix(v), digits = 3)
    # end
    return success
end

#######################################################################
# Codiagonalizers
#######################################################################
defaultcodiagonalizer(h) = RandomCodiagonalizer(h)

## VelocityCodiagonalizer
## Uses velocity operators along different directions
struct VelocityCodiagonalizer{S,H<:Hamiltonian} <: AbstractCodiagonalizer
    h::H
    degranges::Vector{UnitRange{Int}}
    success::Vector{Bool}
    directions::Vector{S}
end

function VelocityCodiagonalizer(h::Hamiltonian{<:Any,L};
                                direlements = -5:5, onlypositive = true, kw...) where {L}
    directions = vec(SVector{L,Int}.(Iterators.product(ntuple(_ -> direlements, Val(L))...)))
    onlypositive && filter!(ispositive, directions)
    unique!(normalize, directions)
    sort!(directions, by = norm, rev = false) # to try diagonal directions first
    VelocityCodiagonalizer(h, UnitRange{Int}[], Bool[], directions)
end

num_codiag_matrices(d::Diagonalizer{<:Any,<:Any,<:VelocityCodiagonalizer}) =
    length(d.codiag.directions)
codiag_matrix(n, d::Diagonalizer{<:Any,<:Any,<:VelocityCodiagonalizer}, ϕs) =
    bloch!(d.matrix, d.codiag.h, ϕs, dn -> im * d.codiag.directions[n]' * dn)

## RandomCodiagonalizer
## Uses velocity operators along different directions
struct RandomCodiagonalizer{H<:Hamiltonian} <: AbstractCodiagonalizer
    h::H
    degranges::Vector{UnitRange{Int}}
    success::Vector{Bool}
    seed::Int
end

RandomCodiagonalizer(h::Hamiltonian) = RandomCodiagonalizer(h, UnitRange{Int}[], Bool[], 1)

num_codiag_matrices(d::Diagonalizer{<:Any,<:Any,<:RandomCodiagonalizer}) = 1
function codiag_matrix(n, d::Diagonalizer{<:Any,<:Any,<:RandomCodiagonalizer}, ϕs)
    bloch!(d.matrix, d.codiag.h, ϕs)
    data = _getdata(d.matrix)
    δ = sqrt(eps(realtype(d.codiag.h)))
    rng = MersenneTwister(d.codiag.seed) # To get reproducible perturbations for all ϕs
    for i in eachindex(data)
        @inbounds data[i] += δ * rand(rng)
    end
    return d.matrix
end
_getdata(m::AbstractSparseMatrix) = nonzeros(parent(m))
_getdata(m::AbstractMatrix) = parent(m)