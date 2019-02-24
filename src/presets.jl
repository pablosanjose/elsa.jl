# struct Preset{S<:NamedTuple}
#     name::NameType
#     kwargs::S
# end

# Preset(name; kwargs...) = Preset(name, kwargs.data)

#######################################################################
# System presets
#######################################################################

systempresets = Dict(
    :linear => (; kw...) ->
        System(Sublat((0.,); kw...), Bravais((1.,)); kw...),
    :square => (; kw...) ->
        System(Sublat((0., 0.); kw...), Bravais((1., 0.),(0., 1.)); kw...),
    :triangular => (; kw...) ->
        System(Sublat((0.,0.); kw...), Bravais((cos(pi/3), sin(pi/3)),(-cos(pi/3), sin(pi/3))); kw...),
    :honeycomb => (; kw...) ->
        System(Sublat((0.0, -0.5/sqrt(3.0)); name = :A, kw...),
        Sublat((0.0, 0.5/sqrt(3.0)); name = :B, kw...), Bravais((cos(pi/3), sin(pi/3)), (-cos(pi/3), sin(pi/3))); kw...),
    :cubic => (; kw...) ->
        System(Sublat((0., 0., 0.); kw...), Bravais((1., 0., 0.), (0., 1., 0.), (0., 0., 1.)); kw...),
    :bcc => (; kw...) ->
        System(Sublat((0., 0., 0.); kw...), Bravais(@SMatrix([-1. -1. 0.; 1. -1. 0.; 0. 1. -1.])'/sqrt(2.)); kw...),
    :bcc => (; kw...) ->
        System(Sublat((0., 0., 0.); kw...), Bravais((1., 0., 0.), (0., 1., 0.), (0.5, 0.5, 0.5)); kw...),
    :graphene_bilayer =>
        function (;twistindex = 1, twistindices = (twistindex, 1), a0 = 0.246, interlayerdistance = 1.36a0, rangeintralayer = a0/sqrt(3), rangeinterlayer = 4a0/sqrt(3), hopintra = 2.70, hopinter = 0.48, kw...)
            (m, r) = twistindices
            θ = acos((3m^2 + 3m*r +r^2/2)/(3m^2 + 3m*r + r^2))
            sAbot = Sublat((0.0, -0.5a0/sqrt(3.0), - interlayerdistance / 2); name = :Ab)
            sBbot = Sublat((0.0,  0.5a0/sqrt(3.0), - interlayerdistance / 2); name = :Bb)
            sAtop = Sublat((0.0, -0.5a0/sqrt(3.0),   interlayerdistance / 2); name = :At)
            sBtop = Sublat((0.0,  0.5a0/sqrt(3.0),   interlayerdistance / 2); name = :Bt)
            bravais = Bravais((cos(pi/3)*a0, sin(pi/3)*a0, 0), (-cos(pi/3)*a0, sin(pi/3)*a0, 0))
            if gcd(r, 3) == 1
                scbot, sctop = @SMatrix[m -(m+r); (m+r) 2m+r], @SMatrix[m+r -m; m 2m+r]
            else
                scbot, sctop = @SMatrix[m+r÷3 -r÷3; r÷3 m+2r÷3], @SMatrix[m+2r÷3 r÷3; -r÷3 m+r÷3]
            end
            modelintra = Model(hopping(hopintra, range = rangeintralayer))
            top = grow(System(sAtop, sBtop, bravais, modelintra; dim = Val(3), kw...), supercell = sctop)
            bot = grow(System(sAbot, sBbot, bravais, modelintra; dim = Val(3), kw...), supercell = scbot)
            topR = let R = @SMatrix[cos(θ/2) -sin(θ/2) 0; sin(θ/2) cos(θ/2) 0; 0 0 1]
                transform(top, r -> @SMatrix[cos(θ/2) -sin(θ/2) 0; sin(θ/2) cos(θ/2) 0; 0 0 1] * r)
            end
            botR = let R = @SMatrix[cos(θ/2) sin(θ/2) 0; -sin(θ/2) cos(θ/2) 0; 0 0 1]
                transform(bot, r -> R * r)
            end
            modelinter = Model(hopping((r,dr) -> hopinter * exp(-3*(norm(dr)/interlayerdistance - 1)) * dr[3]^2/sum(abs2,dr), 
                              range = rangeinterlayer, sublats = ((:Ab,:At), (:Ab,:Bt), (:Bb,:At), (:Bb,:Bt))))
            return combine(botR, topR, modelinter)
        end
    )


struct Region{E,F} <: Function
    f::F
end
Region{E}(f::F) where {E,F<:Function} = Region{E,F}(f)
Region(name::NameType, args...) = regionpresets[name](args...)
(region::Region{E})(r::SVector{E}) where {E} = region.f(r)
(region::Region{E})(r::SVector{E2}) where {E,E2} = throw(DimensionMismatch("Region of dimension $E used in an $E2-dimensional space"))

regionpresets = Dict(
    :circle => (radius = 10.0) -> Region{2}(_region_ellipse((radius, radius))),
    :ellipse => (radii = (10.0, 15.0)) -> Region{2}(_region_ellipse(radii)),
    :square => (side = s) -> Region{2}(_region_rectangle((side, side))),
    :rectangle => (sides = (10.0, 15.0)) -> Region{2}(_region_ellipsoid((radius, radius, radius))),
    :sphere => (radius = 10.0) -> Region{3}(_region_ellipsoid((radius, radius, radius))),
    :spheroid => (radii = (10.0, 15.0, 20.0)) -> Region{3}(_region_ellipsoid(radii)),
    :cube => (side = 10.0) -> Region{3}(_region_cuboid((side, side, side))),
    :cuboid => (sides = (10.0, 15.0, 20.0)) -> Region{3}(_region_cuboid(sides))
    )

function _region_ellipse(radii)
    return r -> (r[1]/radii[1])^2 + (r[2]/radii[2])^2 <= 1 + extended_eps()
end

function _region_rectangle(sides)
    return r -> abs(2*r[1])<= sides[1] * (1 + extended_eps()) &&
                abs(2*r[2])<= sides[2] * (1 + extended_eps())
end

function _region_ellipsoid(radii)
    return r -> (r[1]/radii[1])^2 + (r[2]/radii[2])^2 + (r[3]/radii[3])^2 <= 1 + eps()
end

function _region_cuboid(sides)
    return r -> abs(2*r[1])<=sides[1] * (1 + extended_eps()) &&
                abs(2*r[2])<=sides[2] * (1 + extended_eps()) &&
                abs(2*r[3])<=sides[3] * (1 + extended_eps())
end

# #######################################################################
# # System and Model presets
# #######################################################################

# systempresets = Dict()

# modelpresets = Dict(
#     :kinetic2D => ((; mass = 1, a0 = 1) -> Model(
#             Onsite(r-> (2.0 ./ (mass.*a0^2)) .* eye(SMatrix{2,2, Float64})),
#             Hopping((r,dr)-> (-1.0 ./ (mass.*a0^2)) .* eye(SMatrix{2,2, Float64}))))
#     )
