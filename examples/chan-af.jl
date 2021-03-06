using Revise
using ApproxFun, LinearAlgebra, Parameters, Setfield

using PseudoArcLengthContinuation, Plots
const PALC = PseudoArcLengthContinuation

####################################################################################################
# specific methods for ApproxFun
import Base: eltype, similar, copyto!, length
import LinearAlgebra: mul!, rmul!, axpy!, axpby!, dot, norm

similar(x::ApproxFun.Fun, T) = (copy(x))
similar(x::ApproxFun.Fun) = copy(x)
mul!(w::ApproxFun.Fun, v::ApproxFun.Fun, α) = (w .= α * v)

eltype(x::ApproxFun.Fun) = eltype(x.coefficients)
length(x::ApproxFun.Fun) = length(x.coefficients)

dot(x::ApproxFun.Fun, y::ApproxFun.Fun) = sum(x * y)

# do not put y .= a .* x .+ y, this puts a lot of coefficients!
axpy!(a::Float64, x::ApproxFun.Fun, y::ApproxFun.Fun) = (y .= a * x + y)
axpby!(a::Float64, x::ApproxFun.Fun, b::Float64, y::ApproxFun.Fun) = (y .= a * x + b * y)
rmul!(y::ApproxFun.Fun, b::Float64) = (y.coefficients .*= b; y)
rmul!(y::ApproxFun.Fun, b::Bool) = b == true ? y : (y.coefficients .*= 0; y)

# copyto!(x::ApproxFun.Fun, y::ApproxFun.Fun) = ( copyto!(x.coefficients, y.coefficients);x)
copyto!(x::ApproxFun.Fun, y::ApproxFun.Fun) = ( (x.coefficients = copy(y.coefficients);x))

####################################################################################################

N(x; a = 0.5, b = 0.01) = 1 + (x + a * x^2) / (1 + b * x^2)
dN(x; a = 0.5, b = 0.01) = (1 - b * x^2 + 2 * a * x)/(1 + b * x^2)^2

function F_chan(u, alpha, beta = 0.01)
	return [Fun(u(0.), domain(u)) - beta,
			Fun(u(1.), domain(u)) - beta,
			Δ * u + alpha * N(u, b = beta)]
end

function dF_chan(u, v, alpha, beta = 0.01)
	return [Fun(v(0.), domain(u)),
			Fun(v(1.), domain(u)),
			Δ * v + alpha * dN(u, b = beta) * v]
end

function Jac_chan(u, alpha, beta = 0.01)
	return [Evaluation(u.space, 0.),
			Evaluation(u.space, 1.),
			Δ + alpha * dN(u, b = beta)]
end

function finalise_solution(z, tau, step, contResult)
	printstyled(color=:red,"--> AF length = ", (z, tau) .|> length ,"\n")
	chop!(z.u, 1e-14);chop!(tau.u, 1e-14)
	true
end

sol = Fun( x -> x * (1-x), Interval(0.0, 1.0))
const Δ = Derivative(sol.space, 2);

optnew = NewtonPar(tol = 1e-12, verbose = true)
	out, _, flag = @time PALC.newton(
		u -> F_chan(u, 3.0),
		u -> Jac_chan(u, 3.0),
		sol, optnew, normN = x -> norm(x, Inf64))
	# Plots.plot(out, label="Solution")


optcont = ContinuationPar(dsmin = 0.001, dsmax = 0.05, ds= 0.01, pMax = 4.1, plotEveryNsteps = 10, newtonOptions = NewtonPar(tol = 1e-8, maxIter = 20, verbose = true), maxSteps = 300)

	br, _ = @time continuation(
		(x, p) ->   F_chan(x, p),
		(x, p) -> Jac_chan(x, p),
		out, 3.0, optcont,
		plot = true,
		plotSolution = (x; kwargs...) -> plot!(x; label = "l = $(length(x))", kwargs...),
		verbosity = 2,
		# printsolution = x -> norm(x, Inf64),
		normC = x -> norm(x, Inf64))
####################################################################################################
# other dot product
# dot(x::ApproxFun.Fun, y::ApproxFun.Fun) = sum(x * y) * length(x) # gives 0.1

optcont = ContinuationPar(dsmin = 0.001, dsmax = 0.05, ds= 0.01, pMax = 4.1, plotEveryNsteps = 10, newtonOptions = NewtonPar(tol = 1e-8, maxIter = 20, verbose = true), maxSteps = 300, theta = 0.2)

	br, _ = @time continuation(
		(x, p) ->   F_chan(x, p),
		(x, p) -> Jac_chan(x, p),
		out, 3.0, optcont;
		dotPALC = (x, y) -> dot(x, y),
		plot = true,
		# finaliseSolution = finalise_solution,
		plotSolution = (x; kwargs...) -> plot!(x; label = "l = $(length(x))", kwargs...),
		verbosity = 2,
		# printsolution = x -> norm(x, Inf64),
		normC = x -> norm(x, Inf64))
####################################################################################################
# tangent predictor with Bordered system
br, _ = @time continuation(
	(x, p) ->   F_chan(x, p),
	(x, p) -> Jac_chan(x, p),
	out, 3.0, optcont,
	tangentAlgo = BorderedPred(),
	plot = true,
	finaliseSolution = finalise_solution,
	plotSolution = (x;kwargs...)-> plot!(x; label = "l = $(length(x))", kwargs...))
####################################################################################################
# tangent predictor with Bordered system
# optcont = @set optcont.newtonOptions.verbose = true
indfold = 2
outfold, _, flag = @time newtonFold(
		(x, α) -> F_chan(x, α),
		(x, p) -> Jac_chan(x, p),
		br, indfold, #index of the fold point
		optcont.newtonOptions)
	flag && printstyled(color=:red, "--> We found a Fold Point at α = ", outfold[end], ", β = 0.01, from ", br.bifpoint[indfold][3],"\n")
#################################################################################################### Continuation of the Fold Point using minimally augmented
indfold = 2

outfold, _, flag = @time newtonFold(
	(x, p) -> F_chan(x, p),
	(x, p) -> Jac_chan(x, p),
	(x, p) -> Jac_chan(x, p),
	br, indfold, #index of the fold point
	optcont.newtonOptions)

br.bifpoint[2].
