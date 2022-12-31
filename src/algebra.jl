#= Equality =#

Base.:(==)(a::BasisBlade{Sig}, b::BasisBlade{Sig}) where Sig = bitsof(a) == bitsof(b) ? a.coeff == b.coeff : iszero(a) && iszero(b)
function Base.:(==)(a::AbstractMultivector{Sig}, b::AbstractMultivector{Sig}) where {Sig}
	all(grade(a, k).comps == grade(b, k).comps for k in promote_grades(a, b))
end

Base.:(==)(a::AbstractMultivector, b::Number) = iszero(b) ? iszero(a) : isscalar(a) && scalar(a) == b
Base.:(==)(a::Number, b::AbstractMultivector) = iszero(a) ? iszero(b) : isscalar(b) && a == scalar(b)



#= Approximate Equality =#

isapproxzero(a; kwargs...) = isapprox(a, zero(a); kwargs...)
isapproxzero(a::BasisBlade; kwargs...) = isapproxzero(a.coeff; kwargs...)
isapproxzero(a::Multivector; kwargs...) = isapproxzero(a.comps; kwargs...)

Base.isapprox(a::BasisBlade{Sig}, b::BasisBlade{Sig}; kwargs...) where Sig = bitsof(a) == bitsof(b) ? isapprox(a.coeff, b.coeff; kwargs...) : isapproxzero(a) && isapproxzero(b)
function Base.isapprox(a::AbstractMultivector{Sig}, b::AbstractMultivector{Sig}; kwargs...) where {Sig}
	k = promote_grades(a, b)
	isapprox(grade(a, k).comps, grade(b, k).comps; kwargs...)
end

Base.:isapprox(a::AbstractMultivector, b::Number; kwargs...) = isapprox(a, zero(a) + b; kwargs...)
Base.:isapprox(a::Number, b::AbstractMultivector; kwargs...) = isapprox(zero(b) + a, b; kwargs...)



#= Scalar Multiplication =#

scalar_multiply(a::BasisBlade{Sig,K}, b) where {Sig,K} = BasisBlade{Sig,K}(bitsof(a) => a.coeff*b)
scalar_multiply(a, b::BasisBlade{Sig,K}) where {Sig,K} = BasisBlade{Sig,K}(bitsof(b) => a*b.coeff)

scalar_multiply(a::Multivector, b) = constructor(a)(a.comps*b)
scalar_multiply(a, b::Multivector) = constructor(b)(a*b.comps)

Base.:*(a::AbstractMultivector, b::Scalar) = scalar_multiply(a, b)
Base.:*(a::Scalar, b::AbstractMultivector) = scalar_multiply(a, b)
Base.:-(a::AbstractMultivector) = -numberone(eltype(a))*a

promote_to(T, x) = convert(promote_type(T, typeof(x)), x)
Base.:/(a::AbstractMultivector, b::Scalar) = a*inv(promote_to(eltype(a), b))
Base.:\(a::Scalar, b::AbstractMultivector) = inv(promote_to(eltype(b), a))*b

Base.://(a::AbstractMultivector, b::Scalar) = a*(one(b)//b)
Base.://(a::Scalar, b::AbstractMultivector) = inv(b//a)
Base.://(a::AbstractMultivector, b::AbstractMultivector) = a*(numberone(eltype(b))//b)



#= Addition =#

function add!(a::Multivector, bits::Unsigned, coeff)
	i = componentindex(a, bits)
	isnothing(i) || (a.comps[i] += coeff)
	a
end

add!(a::Multivector, b::BasisBlade) = add!(a, bitsof(b), b.coeff)

function add!(a::Multivector, b::Multivector)
	a.comps .+= grade(b, grade(a)).comps
end


resulting_grades(::typeof(+), dim, pq...) = promote_grades(dim, pq...)

function Base.:+(abc::AbstractMultivector{Sig}...) where {Sig}
	Σ = zero(resulting_multivector_type(+, abc...))
	for a in abc
		add!(Σ, a)
	end
	Σ
end
Base.:-(a::AbstractMultivector, b::AbstractMultivector) = a + (-b)



#= Scalar Addition =#

add_scalar(a::AbstractMultivector{Sig}, b) where {Sig} = a + BasisBlade{Sig,0}(0 => b)

Base.:+(a::AbstractMultivector, b::Scalar) = add_scalar(a, b)
Base.:+(a::Scalar, b::AbstractMultivector) = add_scalar(b, a)

Base.:-(a::AbstractMultivector, b::Scalar) = add_scalar(a, -b)
Base.:-(a::Scalar, b::AbstractMultivector) = add_scalar(-b, a)




#= Geometric Multiplication =#

"""
	a * b
	geometric_prod(a, b)

Geometric product of multivectors.
"""
geometric_prod(a::Scalar, b::Scalar) = a*b
geometric_prod(a::AbstractMultivector, b::Scalar) = scalar_multiply(a, b)
geometric_prod(a::Scalar, b::AbstractMultivector) = scalar_multiply(a, b)

function geometric_prod(a::BasisBlade{Sig}, b::BasisBlade{Sig}) where {Sig}
	factor, bits = geometric_prod_bits(Sig, bitsof(a), bitsof(b))
	BasisBlade{Sig}(bits => factor*(a.coeff*b.coeff))
end

function resulting_grades(::typeof(geometric_prod), dim, p::Integer, q::Integer)
	dim ∈ (p, q) && return dim - min(p, q)
	abs(p - q):2:min(p + q, dim)
end

@symbolic_optim function geometric_prod(a::AbstractMultivector{Sig}, b::AbstractMultivector{Sig}) where {Sig}
	c = zero(resulting_multivector_type(geometric_prod, a, b))
	for (abits::UInt, acoeff) ∈ nonzero_components(a), (bbits::UInt, bcoeff) ∈ nonzero_components(b)
		factor, bits = geometric_prod_bits(Sig, abits, bbits)
		add!(c, bits, factor*(acoeff*bcoeff))
	end
	c
end

Base.:*(a::AbstractMultivector, b::AbstractMultivector) = geometric_prod(a, b)



#= Scalar Product =#

"""
	a ⊙ b
	scalar_prod(a, b) -> Number

Scalar part of the multivector product `a*b`.
"""
scalar_prod(a::Scalar, b::Scalar) = a*b
scalar_prod(a::AbstractMultivector, b::Scalar) = scalar(a)*b
scalar_prod(a::Scalar, b::AbstractMultivector) = a*scalar(b)

scalar_prod(a::BasisBlade{Sig,K}, b::BasisBlade{Sig,K}) where {Sig,K} = bitsof(a) == bitsof(b) ? scalar(a*b) : numberzero(promote_type(eltype(a), eltype(b)))
scalar_prod(a::BasisBlade{Sig}, b::BasisBlade{Sig}) where {Sig} = numberzero(promote_type(eltype(a), eltype(b)))

function scalar_prod(a::Multivector{Sig,K}, b::Multivector{Sig,K}) where {Sig,K}
	s = numberzero(promote_type(eltype(a), eltype(b)))
	for (bits, a, b) in zip(componentbits(Multivector{Sig,K}), a.comps, b.comps)
		s += geometric_square_factor(Sig, bits)*(a*b)
	end
	s
end

@symbolic_optim function scalar_prod(a::AbstractMultivector{Sig}, b::AbstractMultivector{Sig}) where {Sig}
	s = numberzero(promote_type(eltype(a), eltype(b)))
	for k in grade(a) ∩ grade(b)
		s += scalar_prod(grade(a, k), grade(b, k))
	end
	s
end


@doc (@doc scalar_prod)
a ⊙ b = scalar_prod(a, b)



#= Graded Products =#

"""
	graded_prod(grade_selector::Function, a, b)

A "graded" product of multivectors, generalising the wedge ``∧``, inner ``⋅`` and contraction products.
For example, the wedge product is defined as:
```julia
wedge(a, b) = graded_prod(+, a, b)
```

If `grade(a) == p` and `grade(b) == q`, then `graded_prod(f, a, b)` is the grade `f(p, q)` part of `a*b`.
The definition extends linearly to general multivectors ``A`` and ``B`` as
```math
	(A, B) ↦ \\sum_{p,q} ⟨⟨A⟩_p ⟨B⟩_q⟩_{f(p, q)}
```
where ``⟨⋅⟩_k`` denotes the grade ``k`` part.
"""
graded_prod(grade_selector, a::Scalar, b::Scalar) = iszero(grade_selector(0, 0)) ? a*b : zero(promote_type(a, b))
graded_prod(grade_selector, a::AbstractMultivector, b::Scalar) = grade(a) == (grade_selector(grade(a), 0)) ? scalar_multiply(a, b) : zero(a)
graded_prod(grade_selector, a::Scalar, b::AbstractMultivector) = grade(b) == (grade_selector(0, grade(b))) ? scalar_multiply(a, b) : zero(a)

function graded_prod(grade_selector::Function, a::BasisBlade{Sig}, b::BasisBlade{Sig}) where {Sig}
	if count_ones(bitsof(a) ⊻ bitsof(b)) == grade_selector(grade(a), grade(b))
		a*b
	else
		BasisBlade{Sig}(0 => zero(promote_type(eltype(a), eltype(b))))
	end
end

resulting_grades(::Tuple{typeof(graded_prod),GradeSelector}, dim, p::Integer, q::Integer) where {GradeSelector} = GradeSelector.instance(p, q)

@symbolic_optim function graded_prod(grade_selector::Function, a::AbstractMultivector{Sig}, b::AbstractMultivector{Sig}) where {Sig}
	c = zero(resulting_multivector_type((graded_prod, grade_selector), a, b))
	for (abits, acoeff) ∈ nonzero_components(a), (bbits, bcoeff) ∈ nonzero_components(b)
		bits = abits ⊻ bbits
		if count_ones(bits) == grade_selector(count_ones(abits), count_ones(bbits))
			factor = geometric_prod_factor(Sig, abits, bbits)
			i = componentindex(c, bits)
			c = setindex!!(c, c.comps[i] + factor*(acoeff*bcoeff), i)
		end
	end
	c
end


#= Derived Products =#

"""
	a ∧ b
	wedge(a, b)

Wedge product of multivectors (a.k.a. the _outer_, _exterior_, _progressive_ or _alternating_ product, or _join_).

This is a grade-raising operation, equivalent to [`graded_prod(+, a, b)`](@ref).
If `a` and `b` are of grades ``p`` and ``q`` respectively, then `a ∧ b` is defined as
the grade ``p + q`` part of `a*b`.
"""
wedge(a, b) = graded_prod(+, a, b)
@doc (@doc wedge)
a ∧ b = wedge(a, b)


"""
	a ⋅ b
	inner(a, b)

Inner product of multivectors.

This is a grade lowering operation, equivalent to [`graded_prod(abs∘-, a, b)`](@ref).
If `a` and `b` are of grades ``p`` and ``q`` respectively, then `a ⋅ b` is defined as
the grade ``|p - q|`` part of `a*b`.

Note that for scalars `a` and `b`, the inner product reduces to scalar multiplication,
in contrast to some authors (see [Dorst2002](@cite) for discussion).

See also [`lcontract`](@ref) and [`rcontract`](@ref).
"""
inner(a, b) = graded_prod(abs∘-, a, b)
@doc (@doc inner)
⋅(a, b) = inner(a, b)

"""
	a ⨼ b
	lcontract(a, b)

Left contraction of multivectors.

Equivalent to [`graded_prod((p, q) -> q - p, a, b)`](@ref).
If `a` and `b` are of grades ``p`` and ``q`` respectively, then `a ⨼ b` is defined as
the grade ``q - p`` part of `a*b`.

See also [`rcontract`](@ref) and [`inner`](@ref).
"""
lcontract(a, b) = graded_prod((-)∘-, a, b)
@doc (@doc lcontract)
⨼(a, b) = lcontract(a, b)

"""
	a ⨽ b
	rcontract(a, b)

Right contraction of multivectors.

Equivalent to [`graded_prod(-, a, b)`](@ref).
If `a` and `b` are of grades ``p`` and ``q`` respectively, then `a ⨽ b` is defined as
the grade ``p - q`` part of `a*b`.

See also [`lcontract`](@ref) and [`inner`](@ref).
"""
rcontract(a, b) = graded_prod(-, a, b)
@doc (@doc rcontract)
⨽(a, b) = rcontract(a, b)



#= Exponentiation =#

# if a² is a scalar, then a²ⁿ = |a²|ⁿ and a²ⁿ⁺¹ = |a²|ⁿa
function power_with_scalar_square(a, a², p::Integer)
	# if p is even, p = 2n; if odd, p = 2n + 1
	aⁿ = a²^fld(p, 2)
	iseven(p) ? aⁿ*one(a) : aⁿ*a
end

Base.:^(a::BasisBlade, p::Integer) = power_with_scalar_square(a, scalar(a*a), p)
Base.literal_pow(::typeof(^), a::BasisBlade{Sig}, ::Val{2}) where {Sig} = BasisBlade{Sig,0}(0 => geometric_square_factor(Sig, bitsof(a))*a.coeff^2)

function Base.:^(a::Multivector{Sig,S}, p::Integer) where {Sig,S}
	# TODO: type stability?
	p < 0 && return inv(a)^abs(p)
	p == 0 && return one(a)
	p == 1 && return a
	a² = a*a
	p == 2 && return a²
	if isscalar(a²)
		power_with_scalar_square(a, scalar(a²), p)
	else
		Base.power_by_squaring(a, p)
	end
end



#= Reversion and Dualities =#

"""
	graded_multiply(f, a::AbstractMultivector)

Multiply the grade `k` part of `a` by `f(k)`.
"""
graded_multiply(f, a::Scalar) = f(0)*a
graded_multiply(f, a::BasisBlade) = f(grade(a))*a
function graded_multiply(f, a::Multivector{Sig}) where Sig
	comps = collect(a.comps)
	for k ∈ grade(a)
		comps[componentslice(a, k)] *= f(k) # TODO: what if this changes the eltype!?
	end
	constructor(a)(comps)
end

"""
	~a
	reversion(a::AbstractMultivector)

Reversion of a multivector.

Reversion is an anti-automorphism defined by reversing
the order of the geometric product: `~(a*b) == ~b * ~a`.
For a `k`-vector `a`, the reversion is `reversion_sign(k)*a`
where the sign is given by ``(-1)^{k(k - 1)/2}``.

See also [`involution`](@ref) and [`clifford_conj`](@ref).
"""
reversion(a) = graded_multiply(reversion_sign, a)
@doc (@doc reversion)
Base.:~(a::AbstractMultivector) = reversion(a)


"""
	involution(a)

Involute of a multivector.

Involution is an automorphism defined by reflecting through the origin:
for homogeneous multivectors, `involution(a) == (-1)^grade(a)*a`.

See also [`reversion`](@ref) and [`clifford_conj`](@ref).
"""
involution(a) = graded_multiply(k -> (-1)^k, a)

"""
	a'ᶜ
	clifford_conj(a)

Clifford conjugate of a multivector.

Equivalent to `reversion(involution(a))`.
"""
clifford_conj(a) = graded_multiply(a) do k
	(-1)^k*reversion_sign(k)
end
@doc (@doc clifford_conj)
var"'ᶜ"(a) = clifford_conj(a)


"""
	flipdual(a)

A dual of a multivector, for when the overall sign isn’t important.

For a unit `a::BasisBlade`, the flipdual satisfies
`a*flipdual(a) == ±I`
where `±I` is the unit pseudoscalar or its negative.

The `flipdual` is cheap to compute and is its own inverse.
It simply flips the bits of a `BasisBlade`, or reverses the components
vector of a `Multivector`.

The `flipdual` is _metric independent_ (but depends on a choice of _orientation_, or the order of basis vectors).

See also [`hodgedual`](@ref).
"""
function flipdual end


"""
	ldual(a)
	rdual(a)

Left and right multivector duals (a.k.a., _complements_).
The right dual is also called the _Poincaré dual_.

For a unit basis blade `a`, the duals satisfy `a*rdual(a) == I == ldual(a)*a` where `I` is the unit pseudoscalar.
If `dimension(a)` is odd, `rdual` and `ldual` are identical and self-inverse; in general, they are inverses of each other.

The left and right duals are _metric independent_ (but depend on a choice of _orientation_, or the order of basis vectors).
This makes them useful in degenerate algebras where `I^2 == 0`, since a non-zero multivector always
has a non-zero dual, even if its Hodge dual is zero.

See also [`hodgedual`](@ref).
"""
function ldual end

@doc (@doc ldual)
function rdual end



"""
	hodgedual(a) = ~a*I

Hodge dual of a multivector.

The Hodge dual is defined by
```math
⋆a = ã I
```
where ``ã`` is the reversion of ``a`` and ``I`` is the unit pseudoscalar.
For ``k``-vectors ``a`` and ``b``, it is alternatively defined by
```math
a ∧ ⋆b = ⟨a, b⟩ I
```
where ``⟨a, b⟩ = a ⊙ b̃`` is the induced inner product on ``k``-vectors.

The Hodge dual is _metric dependent_, since it involves multiplication by `I`.

See also [`invhodgedual`](@ref) and [`ldual`](@ref), [`rdual`](@ref).

# Examples
```jldoctest
julia> u = Multivector{3,1}(1:3)
3-component Multivector{3, 1, UnitRange{Int64}}:
 1 v1
 2 v2
 3 v3

julia> hodgedual(u)
3-component Multivector{3, 2, MVector{3, Int64}}:
  3 v12
 -2 v13
  1 v23

julia> u ∧ hodgedual(u), u ⊙ ~u
(14v123, 14)

```
"""
function hodgedual end

"""
	invhodgedual(a)

Inverse of the multivector Hodge dual.

In degenerate algebras (for which ``I^2 = 0``), the Hodge dual is not invertible.
However, if `a` is a basis blade with a non-zero Hodge dual, then `invhodgedual(hodgedual(a)) == a` holds.

See also [`hodgedual`](@ref).
"""
function invhodgedual end

for (name, signrule) in [
		:flipdual => (sig, bits) -> 1,
		:rdual => (sig, bits) -> sign_from_swaps(bits, bits_dual(dimension(sig), bits)),
		:ldual => (sig, bits) -> sign_from_swaps(bits_dual(dimension(sig), bits), bits),
		:hodgedual => function(sig, bits)
			I = first(bits_of_grade(dimension(sig)))
			reversion_sign(count_ones(bits))geometric_prod_factor(sig, bits, I)
		end,
		:invhodgedual => function(sig, bits)
			I = first(bits_of_grade(dimension(sig)))
			reversion_sign(count_ones(I ⊻ bits))geometric_prod_factor(sig, I ⊻ bits, I)
		end,
	]
	@eval begin
		function $name(a::BasisBlade{Sig}) where {Sig}
			BasisBlade{signature(a)}(bits_dual(dimension(a), bitsof(a)) => $signrule(Sig, bitsof(a))*a.coeff)
		end

		@symbolic_optim function $name(a::Multivector{Sig,K}) where {Sig,K}
			K′ = promote_grades(dimension(Sig), dimension(Sig) .- K)
			Multivector{Sig,K′}(reverse($signrule.(Ref(Sig), componentbits(a)) .* a.comps))
		end
	end
end


"""
	a ∨ b
	antiwedge(a, b)

Anti-wedge product of multivectors (a.k.a. the _regressive_ product or _meet_).

The anti-wedge product satisfies
```math
⋆(a ∨ b) = (⋆a) ∧ (⋆b)
```
where ``⋆`` is a duality operation (`ldual` or `rdual` or if ``I^2 ≠ 0``, `hodgedual`).

The anti-wedge product is _metric independent_ like the wedge product,
but does depend on the choice of _orientation_ (the ordering of basis vectors).
"""
function antiwedge end

antiwedge(a, b) = rdual(ldual(a)∧ldual(b))

@doc (@doc antiwedge)
∨(a, b) = antiwedge(a, b)

#=

function outermorphism(mat::AbstractMatrix, a::AbstractMultivector{Sig}) where {Sig}
	resulttype = Multivector{Sig,grade(a)}
	a′ = zero(similar(resulttype, a))
	for (bits, coeff) ∈ nonzero_components(a)
		vs = Multivector{Sig,1}.(eachcol(coeff*mat[:,bits_to_indices(bits)]))
		v = reduce(∧, vs; init = one(a′))
		add!(a′, v)
	end
	a′
end

=#
