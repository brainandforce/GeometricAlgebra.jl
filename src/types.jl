const OrType{T} = Union{T,Type{T}}

"""
	AbstractMultivector{Sig}

Supertype of all elements in the geometric algebra defined by the
metric signature `Sig` (retrieved with the `signature` method).

Subtypes
--------

```
          AbstractMultivector
           /               \\
HomogeneousMultivector   MixedMultivector
   /       \\                         │
Blade   Multivector                  │
            │                        │
            ╰─ CompositeMultivector ─╯
```

- `Blade`: a scalar multiple of a wedge product of orthogonal basis vectors.
   Note that the mathematical definition of a ``k``-blade is the wedge product
   of ``k`` different _vectors_, not necessarily basis vectors. Thus, not all
   ``k``-blades are representable as a `Blade` (but always as a `Multivector`).
- `Multivector`: a homogeneous multivector; a sum of same-grade blades.
- `MixedMultivector`: an inhomogeneous multivector. All elements in a geometric
   algebra can be represented as this type.

"""
abstract type AbstractMultivector{Sig} end

Base.broadcastable(a::AbstractMultivector) = Ref(a)
Base.length(::AbstractMultivector) = error(
	"$length is not defined for multivectors. Do you mean $(repr(ncomponents))()?")


"""
	signature(::AbstractMultivector{Sig}) -> Sig

The metric signature type parameter of the multivector object or type.
"""
signature(::OrType{<:AbstractMultivector{Sig}}) where {Sig} = Sig


"""
	HomogeneousMultivector{Sig,K} <: AbstractMultivector{Sig}

Supertype of grade `K ∈ ℕ` elements in the geometric algebra with metric signature `Sig`.
"""
abstract type HomogeneousMultivector{Sig,K} <: AbstractMultivector{Sig} end

"""
	grade(::HomogeneousMultivector{Sig,K}) -> K

The grade of a homogeneous multivector (`Blade` or `Multivector`) object or type.
"""
grade(::OrType{<:HomogeneousMultivector{Sig,K}}) where {Sig,K} = K

"""
	Blade{Sig,K,T} <: HomogeneousMultivector{Sig,K}

A blade of grade `K ∈ ℕ` with basis blade `bits` and scalar coefficient of type `T`.

Parameters
----------
- `Sig`: metric signature defining the parent geometric algebra
- `K`: grade of the blade, equal to `count_ones(bits)`
- `T`: type of the scalar coefficient
"""
struct Blade{Sig,K,T} <: HomogeneousMultivector{Sig,K}
	bits::UInt
	coeff::T
end
Blade{Sig}(bits, coeff::T) where {Sig,T} = Blade{Sig,count_ones(bits),T}(bits, coeff)
Blade{Sig}(pair::Pair) where {Sig} = Blade{Sig}(pair...)

bitsof(a::Blade) = a.bits

"""
	Multivector{Sig,K,S} <: HomogeneousMultivector{Sig,K}

A homogeneous multivector of grade `K ∈ ℕ` with storage type `S`.

Parameters
----------
- `Sig`: metric signature defining the parent geometric algebra
- `K`: grade of the multivector
- `S`: type in which the multivector components are stored; usually a vector-like or dictionary-like type
"""
struct Multivector{Sig,K,S} <: HomogeneousMultivector{Sig,K}
	components::S
end
Multivector{Sig,K}(comps::S) where {Sig,K,S} = Multivector{Sig,K,S}(comps)


"""
	MixedMultivector{Sig,S} <: AbstractMultivector{Sig}

A (possibly inhomogeneous) multivector.

All elements of a geometric algebra are representable as a `MixedMultivector`.

Parameters
----------
- `Sig`: metric signature defining the parent geometric algebra
- `S`: type in which the multivector components are stored; usually a vector-like or dictionary-like type
"""
struct MixedMultivector{Sig,S} <: AbstractMultivector{Sig}
	components::S
end
MixedMultivector{Sig}(comps::S) where {Sig,S} = MixedMultivector{Sig,S}(comps)


const CompositeMultivector{S} = Union{Multivector{Sig,K,S},MixedMultivector{Sig,S}} where {Sig,K}


#= AbstractMultivector Interface =#

"""
	ncomponents(::CompositeMultivector)

Number of independent components of a multivector object or type.

In ``n`` dimensions, this is ``\binom{n}{k}`` for a `Multivector` and
``2^n`` for a `MixedMultivector`.
"""
ncomponents(::OrType{<:Multivector{Sig,K}}) where {Sig,K} = binomial(dimension(Sig), K)
ncomponents(::OrType{<:MixedMultivector{Sig}}) where {Sig} = 2^dimension(Sig)


"""
	eltype(::AbstractMultivector)

The numerical type of the components of a multivector object or type.
"""
Base.eltype(::OrType{<:Blade{sig,K,T} where {sig,K}}) where T = T
Base.eltype(::OrType{<:CompositeMultivector{S}}) where S = eltype(S)



#= Constructors =#

constructor(::Blade{Sig,K}) where {Sig,K} = Blade{Sig,K}
constructor(::Multivector{Sig,K}) where {Sig,K} = Multivector{Sig,K}
constructor(::MixedMultivector{Sig}) where {Sig} = MixedMultivector{Sig}

Base.zero(::OrType{<:Blade{Sig,K,T}}) where {Sig,K,T} = Blade{Sig}(0 => zero(T))
Base.zero(a::OrType{<:Multivector{Sig,K,S}}) where {Sig,K,S} = Multivector{Sig,K}(zeroslike(S, ncomponents(a)))
Base.zero(a::OrType{<:MixedMultivector{Sig,S}}) where {Sig,S} = MixedMultivector{Sig}(zeroslike(S, ncomponents(a)))

Base.iszero(a::Blade) = iszero(a.coeff)
Base.iszero(a::CompositeMultivector{<:AbstractVector}) = iszero(a.components)

Base.one(::OrType{<:Blade{Sig,K,T}}) where {Sig,K,T} = Blade{Sig}(0 => one(T))

Base.isone(a::Blade) = iszero(grade(a)) && isone(a.coeff)



#= Conversion =#

function Multivector(a::Blade{Sig,K,T}) where {Sig,K,T}
	N = ncomponents(Multivector{Sig,K})
	C = componentstype(Sig, T, N)
	mv = zero(Multivector{Sig,K,C})
	i = bits_to_mv_index(bitsof(a))
	mv.components[i] += a.coeff # TODO: implement this for static arrays
	mv
end

function MixedMultivector(a::Blade{Sig,K,T}) where {Sig,K,T}
	N = ncomponents(MixedMultivector{Sig})
	C = componentstype(Sig, T, N)
	mmv = zero(MixedMultivector{Sig,C})
	i = bits_to_mmv_index(bitsof(a), dimension(Sig))
	mmv.components[i] += a.coeff # TODO: implement this for static arrays
	mmv
end

function MixedMultivector(a::Multivector{Sig,K,C}) where {Sig,K,C}
	mmv = zero(MixedMultivector{Sig,C})
	offset = multivector_index_offset(K, dimension(Sig))
	mmv.components[offset .+ (1:ncomponents(a))] = a.components # TODO: implement this for static arrays
	mmv
end

#= Equality =#

Base.:(==)(a::Blade{Sig}, b::Blade{Sig}) where Sig = bitsof(a) == bitsof(b) ? a.coeff == b.coeff : iszero(a) && iszero(b)
Base.:(==)(a::(Multivector{Sig,K,S} where K), b::(Multivector{Sig,K,S} where K)) where {Sig,S} = grade(a) == grade(b) ? a.components == b.components : iszero(a) && iszero(b)
Base.:(==)(a::MixedMultivector{Sig,S}, b::MixedMultivector{Sig,S}) where {Sig,S} = a.components == b.components

Base.:(==)(a::AbstractMultivector, b::Number) = iszero(b) && iszero(a) || isscalar(a) && scalar(a) == b
Base.:(==)(a::Number, b::AbstractMultivector) = iszero(a) && iszero(b) || isscalar(b) && a == scalar(b)




