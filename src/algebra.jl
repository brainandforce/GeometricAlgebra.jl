#= Equality =#

Base.:(==)(a::Blade{Sig}, b::Blade{Sig}) where Sig = bitsof(a) == bitsof(b) ? a.coeff == b.coeff : iszero(a) && iszero(b)
Base.:(==)(a::Multivector{Sig}, b::Multivector{Sig}) where {Sig} = grade(a) == grade(b) ? a.components == b.components : iszero(a) && iszero(b)
Base.:(==)(a::MixedMultivector{Sig}, b::MixedMultivector{Sig}) where {Sig} = a.components == b.components

Base.:(==)(a::AbstractMultivector, b::Number) = isscalar(a) && scalarpart(a) == b
Base.:(==)(a::Number, b::AbstractMultivector) = isscalar(b) && a == scalarpart(b)

# equality between different multivector types
# TODO: implement without conversions?
Base.:(==)(a::AbstractMultivector{Sig}, b::AbstractMultivector{Sig}) where {Sig} = let T = largest_type(a, b)
	T(a) == T(b)
end

#= Approximate Equality =#

isapproxzero(a; kwargs...) = isapprox(a, zero(a); kwargs...)
isapproxzero(a::Blade; kwargs...) = isapproxzero(a.coeff; kwargs...)
isapproxzero(a::CompositeMultivector; kwargs...) = isapproxzero(a.components; kwargs...)

Base.isapprox(a::Blade{Sig}, b::Blade{Sig}; kwargs...) where Sig = bitsof(a) == bitsof(b) ? isapprox(a.coeff, b.coeff; kwargs...) : isapproxzero(a) && isapproxzero(b)
Base.isapprox(a::Multivector{Sig}, b::Multivector{Sig}; kwargs...) where {Sig} = grade(a) == grade(b) ? isapprox(a.components, b.components; kwargs...) : isapproxzero(a) && isapproxzero(b)
Base.isapprox(a::MixedMultivector{Sig}, b::MixedMultivector{Sig}; kwargs...) where {Sig} = isapprox(a.components, b.components; kwargs...)

# promote scalar to target multivector type and compare component arrays
Base.:isapprox(a::Blade, b::Number; kwargs...) = isapprox(Multivector(a), b; kwargs...)
Base.:isapprox(a::CompositeMultivector, b::Number; kwargs...) = isapprox(a, zero(a) + b; kwargs...)
Base.:isapprox(a::Number, b::AbstractMultivector; kwargs...) = isapprox(b, a; kwargs...)

Base.isapprox(a::AbstractMultivector{Sig}, b::AbstractMultivector{Sig}; kwargs...) where {Sig} = let T = largest_type(a, b)
	isapprox(T(a), T(b); kwargs...)
end


#= Scalar Multiplication =#

scalar_multiply(a::Blade, b) = Blade{signature(a)}(bitsof(a) => a.coeff*b)
scalar_multiply(a, b::Blade) = Blade{signature(b)}(bitsof(b) => a*b.coeff)

scalar_multiply(a::CompositeMultivector, b) = constructor(a)(a.components*b)
scalar_multiply(a, b::CompositeMultivector) = constructor(b)(a*b.components)

Base.:*(a::AbstractMultivector, b::Number) = scalar_multiply(a, b)
Base.:*(a::Number, b::AbstractMultivector) = scalar_multiply(a, b)
Base.:-(a::AbstractMultivector) = -one(eltype(a))*a

Base.:/(a::AbstractMultivector, b::Number) = a*inv(promote_to(eltype(a), b))
Base.:\(a::Number, b::AbstractMultivector) = inv(promote_to(eltype(b), a))*b

Base.://(a::AbstractMultivector, b::Number) = a*(one(b)//b)



#= Addition =#

add!(a::Multivector, b::Blade) = (a.components[mv_index(b)] += b.coeff; a)
add!(a::MixedMultivector, b::Blade) = (a.components[mmv_index(b)] += b.coeff; a)

add!(a::Multivector, b::Multivector) = (a.components[:] += b.components; a)
add!(a::MixedMultivector, b::MixedMultivector) = (a.components[:] += b.components; a)

function add!(a::MixedMultivector, b::Multivector)
	offset = multivector_index_offset(grade(b), dimension(b))
	a.components[mmv_slice(b)] = b.components
	a
end

# add alike types
Base.:+(As::Multivector{Sig,K}...) where {Sig,K} = Multivector{Sig,K}(sum(a.components for a ∈ As))
Base.:+(As::MixedMultivector{Sig}...) where {Sig} = MixedMultivector{Sig}(sum(a.components for a ∈ As))

# convert unalike to alike
Base.:+(As::HomogeneousMultivector{Sig,K}...) where {Sig,K} = +(Multivector.(As)...)
Base.:+(As::AbstractMultivector{Sig}...) where {Sig} = +(MixedMultivector.(As)...)

Base.:-(a::AbstractMultivector, b::AbstractMultivector) = a + (-b)


#= Scalar Addition =#

add_scalar!(a::Multivector{Sig,0}, b::Number) where {Sig} = (a.components[] += b; a)
add_scalar!(a::MixedMultivector, b::Number) = (a.components[1] += b; a)

add_scalar(a::Blade{Sig,0}, b::Number) where {Sig} = Blade{Sig}(0 => a.coeff + b)

add_scalar(a::Multivector{Sig,0}, b::Number) where {Sig} = let T = promote_type(eltype(a), typeof(b))
	add_scalar!(Multivector(a, T), b)
end

add_scalar(a::HomogeneousMultivector, b::Number) = let T = promote_type(eltype(a), typeof(b))
	add_scalar!(MixedMultivector(a, T), b)
end

function add_scalar(a::MixedMultivector, b::Number)
	# must be careful to preserve the type (but not the eltype) of the components array
	T = promote_type(eltype(a), eltype(b))
	comps = convert(with_eltype(typeof(a.components), T), a.components)
	comps[1] += b
	MixedMultivector{signature(a)}(comps)
end

Base.:+(a::AbstractMultivector, b::Number) = add_scalar(a, b)
Base.:+(a::Number, b::AbstractMultivector) = add_scalar(b, a)

Base.:-(a::AbstractMultivector, b::Number) = add_scalar(a, -b)
Base.:-(a::Number, b::AbstractMultivector) = add_scalar(-b, a)


#= Geometric Multiplication =#

function geometric_prod(a::Blade{Sig}, b::Blade{Sig}) where {Sig}
	factor, bits = geometric_prod_bits(Sig, bitsof(a), bitsof(b))
	Blade{Sig}(bits => factor*(a.coeff*b.coeff))
end

# function geometric_prod(a::AbstractMultivector{Sig}, b::AbstractMultivector{Sig}) where {Sig}
# 	T = promote_type(eltype(a), eltype(b))
# 	S = componentstype(Sig, ncomponents(Sig), T)
# 	ab = zero(MixedMultivector{Sig,S})
# 	for (abits, acoeff) ∈ nonzero_components(a), (bbits, bcoeff) ∈ nonzero_components(b)
# 		factor, bits = geometric_prod_bits(Sig, abits, bbits)
# 		i = bits_to_mmv_index(bits, dimension(Sig))
# 		ab.components[i] += factor*(acoeff*bcoeff)
# 	end
# 	ab
# end
geometric_prod(a::AbstractMultivector{Sig}, b::AbstractMultivector{Sig}) where {Sig} = _generated_geometric_prod(a, b)

geometric_prod(a::AbstractMultivector, b::Number) = scalar_multiply(a, b)
geometric_prod(a::Number, b::AbstractMultivector) = scalar_multiply(a, b)

Base.:*(a::AbstractMultivector, b::AbstractMultivector) = geometric_prod(a, b)



#= Derived Products =#

function homogeneous_prod(a::AbstractMultivector{Sig}, b::AbstractMultivector{Sig}, k::Int) where {Sig}
	T = promote_type(eltype(a), eltype(b))
	S = with_eltype(componentstype(Sig), T)
	ab = zero(MixedMultivector{Sig,S})
	for (abits, acoeff) ∈ nonzero_components(a), (bbits, bcoeff) ∈ nonzero_components(b)
		bits = abits ⊻ bbits
		if count_ones(bits) == k
			factor = sign_from_swaps(abits, bbits)*factor_from_squares(Sig, abits & bbits)
			i = bits_to_mmv_index(bits, dimension(Sig))
			ab.components[i] += factor*(acoeff*bcoeff)
		end
	end
	ab
end

scalar_prod(a::Blade{Sig,K}, b::Blade{Sig,K}) where {Sig,K} = bitsof(a) == bitsof(b) ? scalarpart(a*b) : zero(promote_type(eltype(a), eltype(b)))
scalar_prod(a::Blade{Sig}, b::Blade{Sig}) where {Sig} = zero(promote_type(eltype(a), eltype(b)))

function scalar_prod(a::Multivector{Sig,K}, b::Multivector{Sig,K}) where {Sig,K}
	Blade{Sig}(0 => sum(geometric_square_factor.(Ref(Sig), bits_of_grade(K, dimension(Sig))) .* (a.components .* b.components)))
end
scalar_prod(a::Multivector{Sig}, b::Multivector{Sig}) where {Sig} = zero(promote_type(eltype(a), eltype(b)))


function scalar_prod(a::MixedMultivector{Sig}, b::MixedMultivector{Sig}) where {Sig}
	Blade{Sig}(0 => sum(geometric_square_factor.(Ref(Sig), mmv_index_to_bits(dimension(Sig))) .* (a.components .* b.components)))
end
scalar_prod(a::AbstractMultivector, b::AbstractMultivector) = let T = largest_type(a, b)
	scalar_prod(T(a), T(b))
end

function graded_prod(a::AbstractMultivector{Sig}, b::AbstractMultivector{Sig}, grade_selector::Function) where {Sig}
	T = promote_type(eltype(a), eltype(b))
	S = componentstype(Sig, ncomponents(Sig), T)
	ab = zero(MixedMultivector{Sig,S})
	for (abits, acoeff) ∈ nonzero_components(a), (bbits, bcoeff) ∈ nonzero_components(b)
		bits = abits ⊻ bbits
		if count_ones(bits) == grade_selector(count_ones(abits), count_ones(bbits))
			factor = sign_from_swaps(abits, bbits)*factor_from_squares(Sig, abits & bbits)
			i = bits_to_mmv_index(bits, dimension(Sig))
			ab.components[i] += factor*(acoeff*bcoeff)
		end
	end
	ab
end

# this is correct assuming grade_selector(k, 0) == k == grade_selector(0, k)
graded_prod(a::AbstractMultivector, b::Number, grade_selector) = scalar_multiply(a, b)
graded_prod(a::Number, b::AbstractMultivector, grade_selector) = scalar_multiply(a, b)

wedge(a, b) = graded_prod(a, b, +)
∧(a, b) = wedge(a, b)


#= Exponentiation =#

# if a² is a scalar, then a²ⁿ = |a²|ⁿ, a²ⁿ⁺¹ = |a²|ⁿa
function power_with_scalar_square(a, a², p::Integer)
	# if p is even, p = 2n; if odd, p = 2n + 1
	aⁿ = a²^fld(p, 2)
	iseven(p) ? aⁿ*one(a) : aⁿ*a
end

function power_by_squaring(a::CompositeMultivector{Sig,S}, p::Integer) where {Sig,S}
	p < 0 && return power_by_squaring(inv(a), abs(p))
	Π = one(MixedMultivector{Sig,S})
	aⁿ = a
	while p > 0
		if isone(p & 1)
			Π *= aⁿ
		end
		aⁿ *= aⁿ
		p >>= 1
	end
	Π
end

Base.:^(a::Blade, p::Integer) = power_with_scalar_square(a, scalarpart(a*a), p)

function Base.:^(a::CompositeMultivector{Sig,S}, p::Integer) where {Sig,S}
	# TODO: type stability?
	p == 0 && return one(a)
	p == 1 && return a
	a² = a*a
	p == 2 && return a²
	if isscalar(a²)
		power_with_scalar_square(a, scalarpart(a²), p)
	else
		power_by_squaring(a, p)
	end
end



#= Reversion =#

graded_multiply(f, a::Number) = f(0)*a
graded_multiply(f, a::HomogeneousMultivector) = f(grade(a))*a
function graded_multiply(f, a::MixedMultivector{Sig}) where Sig
	comps = copy(a.components)
	dim = dimension(Sig)
	for k ∈ 0:dim
		comps[mmv_slice(k, dim)] *= f(k)
	end
	MixedMultivector{Sig}(comps)
end


reversion(a) = graded_multiply(reversion_sign, a)
Base.:~(a::AbstractMultivector) = reversion(a)


involution(a) = graded_multiply(k -> (-1)^k, a)

clifford_conj(a) = graded_multiply(a) do k
	(-1)^k*reversion_sign(k)
end