#######################################################################
# Bandstructure
#######################################################################
struct Band{M,A<:AbstractVector{M},MD<:Mesh,S<:AbstractArray}
    mesh::MD        # Mesh with missing vertices removed
    simplices::S    # Tuples of indices of mesh vertices that define mesh simplices
    states::A       # Must be resizeable container to build & refine band
    dimstates::Int  # Needed to extract the state at a given vertex from vector `states`
end

function Band{M}(mesh::Mesh{D}, dimstates::Int) where {M,D}
    nk = nvertices(mesh)
    states = M[]
    simps = simplices(mesh, Val(D))
    return Band(mesh, simps, states, dimstates)
end

struct Bandstructure{D,M,B<:Band{M},MD<:Mesh{D}}   # D is dimension of parameter space
    bands::Vector{B}
    kmesh::MD
end

function Base.show(io::IO, b::Bandstructure{D,M}) where {D,M}
    ioindent = IOContext(io, :indent => string("  "))
    print(io,
"Bandstructure: bands for a $(D)D hamiltonian
  Bands        : $(length(b.bands))
  Element type : $(displayelements(M))")
    print(ioindent, "\n", b.kmesh)
end

#######################################################################
# bandstructure
#######################################################################
"""
    bandstructure(h::Hamiltonian, mesh::Mesh; minprojection = 0.5, method = defaultmethod(h))

Compute the bandstructure of Bloch Hamiltonian `bloch(h, ϕs...)` with `ϕs` evaluated on the
vertices of `mesh`.

The option `minprojection` determines the minimum projection between eigenstates to connect
them into a common subband. The option `method` is chosen automatically if unspecified, and
can be one of the following

    method                    diagonalization function
    --------------------------------------------------------------
    LinearAlgebraPackage()     LinearAlgebra.eigen!
    ArpackPackage()            Arpack.eigs (must be `using Arpack`)

Options passed to the `method` will be forwarded to the diagonalization function. For example,
`method = ArpackPackage(nev = 8, sigma = 1im)` will use `Arpack.eigs(matrix; nev = 8,
sigma = 1im)` to compute the bandstructure.

    bandstructure(h::Hamiltonian; resolution = 13, shift = missing, kw...)

Same as above with a  uniform `mesh = marchingmesh(h; npoints = resolution, shift = shift)`
of marching tetrahedra (generalized to the lattice dimensions of the Hamiltonian). Note that
`resolution` denotes the number of points along each Bloch axis, including endpoints (can be
a tuple for axis-dependent points).

# Example
```
julia> h = LatticePresets.honeycomb() |> unitcell(3) |> hamiltonian(hopping(-1, range = 1/√3));

julia> bandstructure(h; resolution = 25, method = LinearAlgebraPackage())
Bandstructure: bands for a 2D hamiltonian
  Bands        : 8
  Element type : scalar (Complex{Float64})
  Mesh{2}: mesh of a 2-dimensional manifold
    Vertices   : 625
    Edges      : 3552
```

# See also
    marchingmesh
"""
function bandstructure(h::Hamiltonian{<:Any,L,M}; resolution = 13, shift = missing, kw...) where {L,M}
    mesh = marchingmesh(h; npoints = resolution, shift = shift)
    return bandstructure(h,  mesh; kw...)
end

function bandstructure(h::Hamiltonian, mesh::Mesh; method = defaultmethod(h), minprojection = 0.5)
    d = diagonalizer(h, mesh, method, minprojection)
    matrix = similarmatrix(h)
    return bandstructure!(matrix, h, mesh, d)
end

function bandstructure!(matrix::AbstractMatrix, h::Hamiltonian{<:Lattice,<:Any,M}, mesh::MD, d::Diagonalizer) where {M,D,T,MD<:Mesh{D,T}}
    nϵ = 0                           # Temporary, to be reassigned
    ϵks = Matrix{T}(undef, 0, 0)     # Temporary, to be reassigned
    ψks = Array{M,3}(undef, 0, 0, 0) # Temporary, to be reassigned

    dimh = size(h, 1)
    nk = nvertices(mesh)

    p = Progress(nk, "Step 1/2 - Diagonalising: ")
    for (n, ϕs) in enumerate(vertices(mesh))
        bloch!(matrix, h, ϕs)
        (ϵk, ψk) = diagonalize(matrix, d)
        resolve_degeneracies!(ϵk, ψk, ϕs, matrix, d.codiag)
        if n == 1  # With first vertex can now know the number of eigenvalues... Reassign
            nϵ = size(ϵk, 1)
            ϵks = Matrix{T}(undef, nϵ, nk)
            ψks = Array{M,3}(undef, dimh, nϵ, nk)
        end
        copyslice!(ϵks, CartesianIndices((1:nϵ, n:n)),
                   ϵk,  CartesianIndices((1:nϵ,)))
        copyslice!(ψks, CartesianIndices((1:dimh, 1:nϵ, n:n)),
                   ψk,  CartesianIndices((1:dimh, 1:nϵ)))
        ProgressMeter.next!(p; showvalues = ())
    end

    p = Progress(nϵ * nk, "Step 2/2 - Connecting bands: ")
    pcounter = 0
    bands = Band{M,Vector{M},Mesh{D+1,T,Vector{SVector{D+1,T}}},Vector{NTuple{D+1,Int}}}[]
    vertindices = zeros(Int, nϵ, nk) # 0 == unclassified, -1 == different band, > 0 vertex index
    pending = CartesianIndex{2}[]
    sizehint!(pending, nk)
    while true
        src = findfirst(iszero, vertindices)
        src === nothing && break
        resize!(pending, 1)
        pending[1] = src # source for band search
        band = extractband(mesh, pending, ϵks, ψks, vertindices, d.minprojection)
        nverts = nvertices(band.mesh)
        nverts > D && push!(bands, band) # avoid bands with no simplices
        pcounter += nverts
        ProgressMeter.update!(p, pcounter; showvalues = ())
    end
    return Bandstructure(bands, mesh)
end

function extractband(kmesh::Mesh{D,T}, pending, ϵks::AbstractArray{T}, ψks::AbstractArray{M}, vertindices, minprojection) where {D,T,M}
    dimh, nϵ, nk = size(ψks)
    kverts = vertices(kmesh)
    states = eltype(ψks)[]
    sizehint!(states, nk * dimh)
    verts = SVector{D+1,T}[]
    sizehint!(verts, nk)
    adjmat = SparseMatrixBuilder{Bool}()
    vertindices[first(pending)] = 1
    for c in pending
        ϵ, k = Tuple(c) # c == CartesianIndex(ϵ, k)
        vertex = vcat(kverts[k], SVector(ϵks[c]))
        push!(verts, vertex)
        appendslice!(states, ψks, CartesianIndices((1:dimh, ϵ:ϵ, k:k)))
        for edgek in edges(kmesh, k)
            k´ = edgedest(kmesh, edgek)
            proj, ϵ´ = findmostparallel(ψks, k´, ϵ, k)
            if proj >= minprojection
                if iszero(vertindices[ϵ´, k´]) # unclassified
                    push!(pending, CartesianIndex(ϵ´, k´))
                    vertindices[ϵ´, k´] = length(pending)
                end
                indexk´ = vertindices[ϵ´, k´]
                indexk´ > 0 && pushtocolumn!(adjmat, indexk´, true)
            end
        end
        finalizecolumn!(adjmat)
    end
    for (i, vi) in enumerate(vertindices)
        @inbounds vi > 0 && (vertindices[i] = -1) # mark as classified in a different band
    end
    mesh = Mesh(verts, sparse(adjmat))
    return Band{M}(mesh, dimh)
end

function findmostparallel(ψks::Array{M,3}, destk, srcb, srck) where {M}
    T = real(eltype(M))
    dimh, nϵ, nk = size(ψks)
    maxproj = zero(T)
    destb = 0
    @inbounds for nb in 1:nϵ
        proj = zero(M)
        for i in 1:dimh
            proj += ψks[i, nb, destk]' * ψks[i, srcb, srck]
        end
        absproj = T(abs(tr(proj)))
        if maxproj < absproj
            destb = nb
            maxproj = absproj
        end
    end
    return maxproj, destb
end

function extractband!(vertexindices, bandindices, nb, ϵks, ψks, mesh::Mesh{D,T}) where {D,T}
    dimh, nϵ, nk = size(ψks)
    states = similar(ψks, dimh * nk)
    vertices = Vector{SVector{D+1,T}}(undef, nk)
    fill!(vertexindices, 0)
    k´ = 0
    for (k, ind) in enumerate(bandindices)
        if !iszero(ind)
            k´ += 1
            vertices[k´] = SVector(Tuple(mesh.vertices[k])..., ϵks[ind, k])
            copyto!(states, 1 + dimh * (k´ - 1), ψks, 1 + dimh * (k - 1), dimh)
            vertexindices[k] = k´ # Reuse to store new vertex indices
        end
    end
    if k´ < nk
        resize!(vertices, k´)
        resize!(states, k´ * dimh)
        simplices = extractsimplices(mesh.simplices, vertexindices)
        adjmat = extractsadjacencies(mesh.adjmat, vertexindices)
    else
        simplices = copy(vec(mesh.simplices))
        adjmat = copy(mesh.adjmat)
    end
    mesh´ = Mesh(vertices, adjmat, simplices)
    band = Band(mesh´, states, dimh)
    return band
end

function extractsimplices(simplices::AbstractArray{NTuple{N,Int}}, vertexindices) where {N}
    simplices´ = similar(vec(simplices))
    n = 0
    for simp in simplices
        simp´ = ntuple(i -> vertexindices[simp[i]], Val(N))
        if all(!iszero, simp´)
            n += 1
            simplices´[n] = simp´
        end
    end
    resize!(simplices´, n)
    return simplices´
end

## This is simpler, but allocates more, and is slower
# extractsadjacencies(adjmat, bandindices) =
#     adjmat[(!iszero).(bandindices), (!iszero).(bandindices)]

function extractsadjacencies(adjmat::AbstractSparseMatrix{Tv}, vertexindices) where {Tv}
    n = count(!iszero, vertexindices)
    b = SparseMatrixBuilder{Tv}(n, n)
    for col in 1:size(adjmat, 2)
        iszero(vertexindices[col]) && continue
        for ptr in nzrange(adjmat, col)
            row = rowvals(adjmat)[ptr]
            iszero(vertexindices[row]) || pushtocolumn!(b, row, nonzeros(adjmat)[ptr])
        end
        finalizecolumn!(b)
    end
    adjmat´ = sparse(b)
    return adjmat´
end