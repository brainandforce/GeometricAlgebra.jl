"""
	use_symbolic_optim(sig) -> Bool

Whether to use symbolic optimization in algebras of metric signature `sig`.

By default, this is enabled if `dimension(sig) ≤ 8`
(in many dimensions, algebraic expressions may become too unwieldy).
"""
use_symbolic_optim(sig) = dimension(sig) <= 8
use_symbolic_optim(::Function, ::Union{Scalar,Function,AbstractMultivector{Sig}}...) where {Sig} = use_symbolic_optim(Sig)

"""
	symbolic_components(label::Symbol, dims::Integer...)

Create an array of symbolic values of the specified shape.

# Example
```jldoctest
julia> GeometricAlgebra.symbolic_components(:a, 2, 3)
2×3 Matrix{Any}:
 a[1, 1]  a[1, 2]  a[1, 3]
 a[2, 1]  a[2, 2]  a[2, 3]

julia> prod(ans)
a[1, 1]*a[1, 2]*a[1, 3]*a[2, 1]*a[2, 2]*a[2, 3]
```
"""
function symbolic_components(label::Symbol, dims::Integer...)
	var = SymbolicUtils.Sym{Array{length(dims),Real}}(label)
	indices = Iterators.product(Base.OneTo.(dims)...)
	Any[SymbolicUtils.Term{Real}(getindex, [var, I...]) for I in indices]
end

symbolic_argument(::OrType{<:BasisBlade{Sig,K}}, label) where {Sig,K} = symbolic_argument(Multivector{Sig,K}, label)
symbolic_argument(A::OrType{<:Multivector{Sig,K}}, label) where {Sig,K} = Multivector{Sig,K}(symbolic_components(label, ncomponents(A)))
symbolic_argument(::OrType{F}, label) where {F<:Function} = F.instance
symbolic_argument(::OrType{Val{V}}, label) where {V} = Val(V)

function toexpr(a::AbstractMultivector, compstype, T)
	comps = SymbolicUtils.expand.(a.comps)
	comps_expr = SymbolicUtils.Code.toexpr(SymbolicUtils.Code.MakeArray(comps, compstype, T))
	:( $(constructor(a))($comps_expr) )
end
toexpr(a, compstype, T) = SymbolicUtils.Code.toexpr(a)


"""
	symbolic_multivector_eval(compstype, f, x::AbstractMultivector...)

Evaluate `f(x...)` using symbolically generated code, returning a `Multivector`
with components array of type `compstype`.

This is a generated function which first evaluates `f` on symbolic versions of
the multivector arguments `x` and then converts the symbolic result into unrolled code.

Calling `symbolic_multivector_eval(Expr, compstype, f, x...)` with `Expr` as the first argument
returns the expression to be compiled.

See also [`@symbolic_optim`](@ref).

# Example
```julia
julia> A, B = Multivector{2,1}([1, 2]), Multivector{2,1}([3, 4]);

julia> symbolic_multivector_eval(Expr, MVector, geometric_prod, A, B)
quote # prettified for readability
    let a = components(args[1]), b = components(args[2])
        comps = SymbolicUtils.Code.create_array(
            MVector, Int64, Val(1), Val((2,)),
            a[1]*b[1] + a[2]*b[2],
            a[1]*b[2] - a[2]*b[1],
        )
        Multivector{2, 0:2:2}(comps)
    end
end

julia> @btime symbolic_multivector_eval(MVector, geometric_prod, A, B);
  86.928 ns (3 allocations: 192 bytes)

julia> @btime geometric_prod(Val(:nosym), A, B); # opt-out of symbolic optim
  4.879 μs (30 allocations: 1.22 KiB)
```
"""
function symbolic_multivector_eval(::Type{Expr}, compstype::Type, f::Function, args...)
	abc = Symbol.('a' .+ (0:length(args) - 1))

	sym_args = symbolic_argument.(args, abc)
	sym_result = f(sym_args...)


	I = findall(T -> T isa Multivector, sym_args)
	assignments = [:( $(abc[i]) = components(args[$i]) ) for i in I]
	T = numberorany(promote_type(eltype.(args[I])...))

	quote
		let $(assignments...)
			$(toexpr(sym_result, compstype, T))
		end
	end
end

@generated function symbolic_multivector_eval(compstype::Type{S}, f::Function, args...) where S
	symbolic_multivector_eval(Expr, S, f.instance, args...)
end

replace_signature(a::Multivector{Sig,K,S}, ::Val{Sig′}) where {Sig,Sig′,K,S} = Multivector{Sig′,K,S}(a.comps)
replace_signature(a ::BasisBlade{Sig,K,T}, ::Val{Sig′}) where {Sig,Sig′,K,T} =  BasisBlade{Sig′,K,T}(a.coeff, a.bits)
replace_signature(a, ::Val) = a

#=
	symbolic_optim()

Because of the rules of generated functions, we can’t call methods that may be later (re)defined
from within `symbolic_multivector_eval`. However, we still want the methods
- `dimension(sig)`
- `basis_vector_norm(sig, i)`
- `componentstype(sig)`
to work for user-defined signature types, as part of the “metric signature interface”.
Since these methods may be defined in a newer world-age than `symbolic_multivector_eval`,
we must move calls to such methods outside the generated function.

To do this, the metric signature is normalized to an equivalent tuple signature, and the result of `componentstype(sig)`
is passed as an argument to — rather than being called from — `symbolic_multivector_eval`.
(We assume that `dimension(::Tuple)`, etc, are core functionality that won’t be modified by the user.)

=#
function symbolic_optim(f::Function, args::Union{Val,Function,AbstractMultivector{Sig}}...) where {Sig}
	# we’re replacing objects’ type parameters, so type stability is a little delicate
	compstype = componentstype(Sig, 0, Any)
	# canonicalize signature to tuple
	Sig′ = ntuple(i -> basis_vector_norm(Sig, i), dimension(Sig))
	args′ = ntuple(i -> replace_signature(args[i], Val(Sig′)), length(args))
	result = symbolic_multivector_eval(compstype, f, args′...)
	# restore original signature
	replace_signature(result, Val(Sig))
end

"""
	@symbolic_optim <method definition>

Convert a single method definition `f(args...)` into two methods:
1. The original method `f(Val(:nosym), args...)`, called with `Val(:nosym)` as the first argument.
   Use this method to opt-out of symbolic optimization.
2. An optimized method `f(args...)` which uses [`symbolic_multivector_eval`](@ref).
   Code for this method is generated by calling `f(Val(:nosym), args...)` with symbolic versions of the `Multivector` arguments.

This is to reduce boilerplate when writing symbolically optimized versions of each method.
It only makes sense for methods with at least one `AbstractMultivector` argument for
which the exact return type is inferable.

# Example

```julia
# This macro call...
@symbolic_optim foo(a, b) = (a + b)^2
# ...is equivalent to the following two method definitions:

foo(::Val{:nosym}, a, b) = (a + b) ^ 2

function foo(a, b)
    if use_symbolic_optim(foo, a, b)
        symbolic_optim(foo, Val(:nosym), a, b)
    else
        foo(Val(:nosym), a, b)
    end
end
```
"""
macro symbolic_optim(fndef::Expr)
	fnhead, fnbody = fndef.args

	fnargs = fnhead::Expr
	while fnargs.head == :where
		fnargs = fnargs.args[1]::Expr
	end
	fnhead_orig = copy(fnhead)
	fnargs_orig = copy(fnargs)
	insert!(fnargs.args, 2, :(::Val{:nosym}))

	fnname, args... = fnargs_orig.args
	quote
		$(Expr(:function, fnhead, fnbody))

		Base.@__doc__ $(Expr(:function, fnhead_orig, quote
			if use_symbolic_optim($fnname, $(args...))
				symbolic_optim($fnname, Val(:nosym), $(args...))
			else
				$fnname(Val(:nosym), $(args...))
			end
		end))
	end |> esc
end


# way to convert a BasisBlade to a Multivector without allocating a full components array
# TODO: take this more seriously
function components(a::BasisBlade{Sig,K}) where {Sig,K}
	i = findfirst(==(a.bits), componentbits(Val(dimension(Sig)), Val(K)))
	SingletonVector(a.coeff, i, ncomponents(Sig, K))
end
components(a::Multivector) = a.comps

struct SingletonVector{T} <: AbstractVector{T}
	el::T
	index::Int
	length::Int
end
Base.length(a::SingletonVector) = a.length
Base.size(a::SingletonVector) = (length(a),)
Base.eltype(::SingletonVector{T}) where {T} = numberorany(T)
Base.getindex(a::SingletonVector{T}, i) where {T} = a.index == i ? a.el : numberzero(T)
function Base.iterate(a::SingletonVector, i = 1)
	i > a.length && return
	(a[i], i + 1)
end
