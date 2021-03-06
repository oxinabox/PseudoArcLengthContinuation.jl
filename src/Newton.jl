"""
	options = NewtonPar(tol = 1e-4,...)

Returns a variable containing parameters to affect the `newton` algorithm when solving `F(x) = 0`.

# Arguments (with default values):
- `tol = 1e-10`: absolute tolerance for `F(x)`
- `maxIter = 50`: number of Newton iterations
- `verbose = false`: display Newton iterations?
- `linsolver = DefaultLS()`: linear solver, must be `<: AbstractLinearSolver`
- `eigsolver = DefaultEig()`: eigen solver, must be `<: AbstractEigenSolver`

# Arguments only used in `newtonPALC`
- `linesearch = false`: use line search algorithm
- `alpha = 1.0`: alpha (damping) parameter for line search algorithm
- `almin  = 0.001 `: minimal vslue of the damping `alpha`

!!! tip "Mutating"
    For performance reasons, we decided to use an immutable structure to hold the parameters. One can use the package `Setfield.jl` to drastically simplify the mutation of different fields. See tutorials for more examples.
"""
@with_kw struct NewtonPar{T, L <: AbstractLinearSolver, E <: AbstractEigenSolver}
	tol::T			 = 1e-10
	maxIter::Int64 	 = 50
	alpha::T         = 1.0        # damping
	almin::T         = 0.001      # minimal damping
	verbose::Bool    = false
	linesearch::Bool = false
	linsolver::L 	 = DefaultLS()
	eigsolver::E 	 = DefaultEig()
end

####################################################################################################
"""
		newton(F, J, x0, options::NewtonPar; normN = norm, callback = (x, f, J, res, iteration, optionsN; kwargs...) -> true, kwargs...)

This is the Newton Solver for `F(x) = 0` with Jacobian `J` and initial guess `x0`. The function `normN` allows to specify a norm for the convergence criteria. It is important to set the linear solver `options.linsolver` properly depending on your problem. This linear solver is used to solve ``J(x)u = -F(x)`` in the Newton step. You can for example use `linsolver = Default()` which is the operator backslash: it works well for Sparse / Dense matrices. See [Linear solvers](@ref) for more informations.

# Arguments:
- `x -> F(x)` functional whose zeros are looked for. In particular, it is not **inplace**,
- `dF(x) = x -> J(x)` compute the jacobian of `F` at `x`. It is then passed to `options.linsolver`. The Jacobian `J(x)` can be a matrix or an out-of-place function.
- `x0` initial guess
- `options` variable holding the internal parameters used by the `newton` method
- `callback` function passed by the user which is called at the end of each iteration. Can be used to update a preconditionner for example. The `optionsN` will be `options` passed in order to change the linear / eigen solvers
- `kwargs` arguments passed to the callback. Useful when `newton` is called from `continuation`

Simplified calls are provided, for example when `J` is not passed. It is then computed with finite differences.

# Output:
- solution:
- history of residuals
- flag of convergence
- number of iterations
"""
function newton(Fhandle, Jhandle, x0, options::NewtonPar{T}; normN = norm, callback = (x, f, J, res, iteration, optionsN; kwargs...) -> true, kwargs...) where T
	# Extract parameters
	@unpack tol, maxIter, verbose, linesearch = options

	# Initialise iterations
	x = similar(x0); copyto!(x, x0) # x = copy(x0)
	f = Fhandle(x)
	d = similar(f); copyto!(d, f)	# d = copy(f)

	neval = 1
	res = normN(f)
	resHist = [res]
	it = 0

	# Displaying results
	verbose && displayIteration(it, neval, res)

	# Main loop
	while (res > tol) & (it < maxIter)
		J = Jhandle(x)
		d, _, itlinear = options.linsolver(J, f)

		# Update solution: x .= x .- d
		minus!(x, d)

		copyto!(f, Fhandle(x))
		res = normN(f)

		neval += 1
		push!(resHist, res)
		it += 1

		callback(x, f, J, res, it, options; kwargs...) == false && (it = maxIter)
		verbose && displayIteration(it, neval, res, itlinear)
	end
	(resHist[end] > tol) && @error("\n--> Newton algorithm failed to converge, residual = $(res[end])")
	return x, resHist, resHist[end] < tol, it
end

# simplified call to newton when no Jacobian is passed in which case we estimate it using finiteDifferences
function newton(Fhandle, x0, options:: NewtonPar{T};kwargs...) where T
	Jhandle = u -> finiteDifferences(Fhandle, u)
	return newton(Fhandle, Jhandle, x0, options; kwargs...)
end
