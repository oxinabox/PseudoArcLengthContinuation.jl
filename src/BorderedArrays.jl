# composite type for Bordered arrays
import Base: copy, copyto!, eltype, zero
import LinearAlgebra: norm, dot, length, similar, axpy!, axpby!, rmul!, mul!

"""
	x = BorderedArray(vec1, vec2)

This defines an array (although not `<: AbstractArray`) to hold two arrays or an array and a scalar. This is useful when one wants to add constraints (phase, ...) to a functional for example. It is used throughout the package for the Pseudo Arc Length Continuation, for the continuation of Fold / Hopf points, for periodic orbits... It is also used to define periodic orbits as (orbit, period). As such, it is a convenient alternative to `cat`, `vcat` and friends. We chose not make it a subtype of AbstractArray as we wish to apply the current package to general "arrays", see [Requested methods for Custom State](@ref). Finally, it proves useful for the GPU where the operation `x[end]` can be slow.
"""
mutable struct BorderedArray{vectype1, vectype2}
	u::vectype1
	p::vectype2
end

eltype(b::BorderedArray{vectype, T}) where {T, vectype} = eltype(b.p)
similar(b::BorderedArray{vectype, T}, ::Type{S} = eltype(b)) where {S, T, vectype} = BorderedArray(similar(b.u, S), similar(b.p, S))
similar(b::BorderedArray{vectype, T}, ::Type{S} = eltype(b)) where {S, T <: Real, vectype} = BorderedArray(similar(b.u, S), S(0))

# a version of copy which cope with our requirements concerning the methods
# availabble for
_copy(b) = copyto!(similar(b), b)
copy(b::BorderedArray) = copyto!(similar(b), b)# BorderedArray(copy(b.u), copy(b.p))

copyto!(dest::BorderedArray{vectype, T}, src::BorderedArray{vectype, T}) where {vectype, T } = (copyto!(dest.u, src.u); copyto!(dest.p, src.p);dest)
copyto!(dest::BorderedArray{vectype, T}, src::BorderedArray{vectype, T}) where {vectype, T <: Number} = (copyto!(dest.u, src.u); dest.p = src.p;dest)

length(b::BorderedArray{vectype, T}) where {vectype, T} = length(b.u) + length(b.p)

dot(a::BorderedArray{vectype, T}, b::BorderedArray{vectype, T}) where {vectype, T} = dot(a.u, b.u) + dot(a.p, b.p)

norm(b::BorderedArray{vectype, T}, p::Real) where {vectype, T} = max(norm(b.u, p), norm(b.p, p))

zero(b::BorderedArray{vectype, T}) where {vectype, T } = BorderedArray(zero(b.u), zero(b.p))
################################################################################
function rmul!(A::BorderedArray{vectype, Tv}, a::T, b::T) where {vectype, T <: Number, Tv}
	# Scale an array A by a scalar b overwriting A in-place
	rmul!(A.u, a)
	rmul!(A.p, b)
	return A
end

function rmul!(A::BorderedArray{vectype, Tv}, a::T, b::T) where {vectype, Tv <: Number, T <: Number }
	# Scale an array A by a scalar b overwriting A in-place
	rmul!(A.u, a)
	A.p = A.p * b
	return A
end

rmul!(A::BorderedArray{vectype, Tv}, a::T) where {vectype, T <: Number, Tv} = rmul!(A, a, a)
################################################################################
function mul!(A::BorderedArray{vectype, Tv}, B::BorderedArray{vectype, Tv}, α::T) where {vectype, Tv, T <: Number}
	mul!(A.u, B.u, α)
	mul!(A.p, B.p, α)
	return A
end

function mul!(A::BorderedArray{vectype, Tv}, B::BorderedArray{vectype, Tv}, α::T) where {vectype, Tv <: Number, T <: Number}
	mul!(A.u, B.u, α)
	A.p = B.p * α
	return A
end

mul!(A::BorderedArray{vectype, Tv}, α::T, B::BorderedArray{vectype, Tv}) where {vectype, Tv, T} = mul!(A, B, α)
################################################################################
function axpy!(a::T, X::BorderedArray{vectype, Tv}, Y::BorderedArray{vectype, Tv}) where {vectype, T <:Real, Tv}
	# Overwrite Y with a*X + Y, where a is scalar
	axpy!(a, X.u, Y.u)
	axpy!(a, X.p, Y.p)
	return Y
end

function axpy!(a::T, X::BorderedArray{vectype, T}, Y::BorderedArray{vectype, T}) where {vectype, T <:Real}
	# Overwrite Y with a*X + Y, where a is scalar
	axpy!(a, X.u, Y.u)
	Y.p = a * X.p + Y.p
	return Y
end
################################################################################
function axpby!(a::T, X::BorderedArray{vectype, Tv}, b::T, Y::BorderedArray{vectype, Tv}) where {vectype, T <: Real, Tv}
	# Overwrite Y with a * X + b * Y, where a, b are scalar
	axpby!(a, X.u, b, Y.u)
	axpby!(a, X.p, b, Y.p)
	return Y
end

function axpby!(a::T, X::BorderedArray{vectype, T}, b::T, Y::BorderedArray{vectype, T}) where {vectype, T <:Real}
	# Overwrite Y with a * X + b * Y, where a is a scalar
	axpby!(a, X.u, b, Y.u)
	Y.p = a * X.p + b * Y.p
	return Y
end
################################################################################
# this function is actually axpy!(-1, y, x)
#
# 	`minus!(x, y)`
#
# computes x-y into x and returns x
minus!(x, y) = axpy!(convert(eltype(x), -1), y, x)
minus!(x::vec, y::vec) where {vec <: AbstractArray} = (x .= x .- y)
minus!(x::T, y::T) where {T <:Real} = (x = x - y)
minus!(x::BorderedArray{vectype, T}, y::BorderedArray{vectype, T}) where {vectype, T} = (minus!(x.u, y.u); minus!(x.p, y.p))
function minus!(x::BorderedArray{vectype, T}, y::BorderedArray{vectype, T}) where {vectype, T <: Real}
	minus!(x.u, y.u)
	# Carefull here. If I use the line below, then x.p will be left unaffected
	# minus_!(x.p, y.p)
	x.p = x.p - y.p
	return x
end
################################################################################
#
#	`minus(x,y)`
#
# returns x - y
minus(x, y) = (x1 = copyto!(similar(x), x); minus!(x1, y); return x1)
# minus(x, y) = (x - y)
minus(x::vec, y::vec) where {vec <: AbstractArray} = (return x .- y)
minus(x::T, y::T) where {T <:Real} = (return x - y)
minus(x::BorderedArray{vectype, T}, y::BorderedArray{vectype, T}) where {vectype, T} = (return BorderedArray(minus(x.u, y.u), minus(x.p, y.p)))
minus(x::BorderedArray{vectype, T}, y::BorderedArray{vectype, T}) where {vectype, T <: Real} = (return BorderedArray(minus(x.u, y.u), x.p - y.p))
