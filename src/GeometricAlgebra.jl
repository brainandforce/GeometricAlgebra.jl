"""
# GeometricAlgebra

Implements multivector (or ``k``-vector) types from geometric algebra (a.k.a. Clifford algebra).

## Exported Types

```
                   AbstractMultivector{Sig}
                     /                  \\
   HomogeneousMultivector{Sig,K}    MixedMultivector{Sig,S}
       /                \\                             
Blade{Sig,K,T}    Multivector{Sig,K,S}                
                                                   
                  ╰───── CompositeMultivector{Sig,S} ─────╯
```

See [`basis`](@ref) and [`@basis`](@ref) to get started.

"""
module GeometricAlgebra

using StaticArrays, SparseArrays
using Combinatorics: permutations, powerset
using SymbolicUtils
using PrettyTables: pretty_table

export AbstractMultivector, HomogeneousMultivector, Blade, Multivector, MixedMultivector
export basis, @basis, @basisall, cayleytable
export signature, dimension, grade, ncomponents, blades
export geometric_prod, scalar_prod, ⊙, wedge, ∧, inner, ⋅, lcontract, ⨼, rcontract, ⨽
export reversion, involution
export vector_repr, matrix_repr
export Cl

include("bits.jl")
include("types.jl")
include("utils.jl")
include("signatures.jl")
include("algebra.jl")
include("special.jl")
include("generated.jl")
include("show.jl")


end # module GeometricAlgebra
