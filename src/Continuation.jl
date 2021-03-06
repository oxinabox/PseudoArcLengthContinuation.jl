using RecursiveArrayTools # for bifurcation point handling in ContRes
import Base: show		# simplified display method for ContRes

"""
	options = ContinuationPar(dsmin = 1e-4,...)

Returns a variable containing parameters to affect the `continuation` algorithm when solving `F(x,p) = 0`.

# Arguments
- `dsmin, dsmax` are the minimum, maximum arclength allowed value. It controls the density of points in the computed branch of solutions.
- `ds` is the initial arclength.
- `theta` is a parameter in the arclength constraint. It is very **important** to tune it. See the docs of [`continuation`](@ref).
- `pMin, pMax` allowed parameter range for `p`
- `maxSteps` maximum number of continuation steps
- `newtonOptions::NewtonPar`: options for the Newton algorithm
- `saveToFile = false`: save to file. A name is automatically generated.
- `saveSolEveryNsteps::Int64 = 0` at which continuation steps do we save the current solution`
- `plotEveryNsteps = 3`

Handling eigen elements
- `computeEigenValues = false` compute eigenvalues / eigenvectors
- `nev = 3` number of eigenvalues to be computed. It is automatically increased to have at least `nev` unstable eigenvalues. To be set for proper  bifurcation detection. See [Detection of bifurcation points](@ref) for more informations.
- `saveEigEveryNsteps = 1`	record eigen vectors every specified steps. **Important** for memory limited ressource, *e.g.* GPU.
- `saveEigenvectors	= true`	**Important** for memory limited ressource, *e.g.* GPU.

Handling bifurcation detection
- `precisionStability = 1e-10` lower bound on the real part of the eigenvalues to test for stability of equilibria and periodic orbits
- `detectFold = true` detect Fold bifurcations? It is a useful option although the detection of Fold is cheap. Indeed, it may happen that there is a lot of Fold points and this can saturate the memory in memory limited devices (e.g. on GPU)
- `detectBifurcation::Int` ∈ {0, 1, 2} detect bifurcations? If set to 0, bifurcation are not detected. If set to 1, bifurcation are detected along the continuation run, but not located precisely. If set to 2, a bisection algorithm is used to locate the bifurcations (slower). The possibility to switch off detection is a useful option. Indeed, it may happen that there are a lot of bifurcation points and this can saturate the memory in memory limited devices (e.g. on GPU)
- `dsminBisection` dsmin for the bisection algorithm when locating bifurcation points
- `nInversion` number of sign inversions in bisection algorithm
- `maxBisectionSteps` maximum number of bisection steps

Handling `ds` adaptation (see [`continuation`](@ref) for more information)
- `a  = 0.5` aggressiveness factor. It is used to adapt `ds` in order to have a number of newton iteration per continuation step roughly the same. The higher `a` is, the larger the step size `ds` is changed at each continuation step.
- `thetaMin = 1.0e-3` minimum value of `theta`
- `doArcLengthScaling` trigger further adaptation of `theta`

 Misc
- `finDiffEps::T  = 1e-9` ε used in finite differences computations

!!! tip "Mutating"
    For performance reasons, we decided to use an immutable structure to hold the parameters. One can use the package `Setfield.jl` to drastically simplify the mutation of different fields. See tutorials for more examples.
"""
@with_kw struct ContinuationPar{T, S <: AbstractLinearSolver, E <: AbstractEigenSolver}
	# parameters for arclength continuation
	dsmin::T	= 1e-3
	dsmax::T	= 2e-2;		@assert dsmax >= dsmin
	ds::T		= 1e-3;		@assert dsmax >= abs(ds);	@assert abs(ds) >= dsmin
	@assert dsmin > 0
	@assert dsmax > 0

	# parameters for scaling arclength step size
	theta::T			  		= 0.5 	# parameter in the dot product used for the extended system
	doArcLengthScaling::Bool  	= false
	gGoal::T			  		= 0.5
	gMax::T			   			= 0.8
	thetaMin::T		   			= 1.0e-3
	# isFirstRescale::Bool  		= true
	a::T				  		= 0.5  	# aggressiveness factor
	tangentFactorExponent::T 	= 1.5

	# parameters bound
	pMin::T	= -1.0
	pMax::T	=  1.0;		@assert pMax >= pMin

	# maximum number of continuation steps
	maxSteps::Int64  = 100

	# Newton solver parameters
	finDiffEps::T  = 1e-9 				#constant for finite differences
	newtonOptions::NewtonPar{T, S, E} = NewtonPar()

	saveToFile::Bool = false 			# save to file?
	saveSolEveryNsteps::Int64 = 0		# what steps do we save the current solution

	# parameters for eigenvalues
 	computeEigenValues::Bool = false
	nev::Int64 = 3 						# number of eigenvalues
	saveEigEveryNsteps::Int64 = 1		# what steps do we keep the eigenvectors
	saveEigenvectors::Bool	= true		# useful options because if puts a high memory pressure

	plotEveryNsteps::Int64 = 10

	# handling bifucation points
	precisionStability::T = 1e-10		# lower bound for stability of equilibria and periodic orbits
	detectFold::Bool = true				# detect fold points?
	detectBifurcation::Int64 = 0		# detect bifurcation points?
	dsminBisection::T = 1e-5			# dsmin for the bisection algorithm when locating bifurcation points
	nInversion::Int64 = 2				# number of sign inversions in bisection algorithm
	maxBisectionSteps::Int64 = 15		# maximum number of bisection steps
	@assert iseven(nInversion) "This number must be even"
end

# check the logic of the parameters
function check(contParams::ContinuationPar)
	if contParams.detectBifurcation > 0
		@set contParams.computeEigenValues = true
	else
		contParams
	end
end
####################################################################################################
# Structure to hold result
"""
	ContResult{T, Eigentype, Vectype, Biftype}

Structure which holds the results after a call to [`continuation`](@ref).

# Arguments
- `branch::VectorOfArray` holds the low-dimensional information about the branch. More precisely, `branch[:,i]` contains the following information `(param, printSolution(u, param), Newton iterations, ds, i)` for each continuation step `i`.
- `n_unstable::Vector{Int64}` a vector holding the number of eigenvalues with positive real part for each continuation step	(to detect stationary bifurcation)
- `n_imag::Vector{Int64}` a vector holding the number of eigenvalues with positive real part and non zero imaginary part for each continuation step (to detect Hopf bifurcation)
- `stability::Vector{Bool}` a vector holding the stability of the computed solution for each continuation step
- `bifpoint::Vector{Biftype}` a vector holding the set of bifurcation points detected during the computation of the branch. Each entry of the vector contains a tuple `(type, idx, param = T(0.), norm, printsol, u, tau, ind_bif, step, status)` where `step` is the continuation step at which the bifurcation occurs, `ind_bif` is the eigenvalue index responsible for the bifurcation (if applicable) and `idx` is the index in `eig` (see above) for which the bifurcation occurs.
- `foldpoint::Vector{Biftype}` a vector holding the set of fold points detected during the computation of the branch.
- `eig::Vector` contains for each continuation step the eigen elements.
"""
@with_kw struct ContResult{T, Teigvals, Teigvec, Biftype, Ts}
	# this vector is used to hold (param, printSolution(u, param), Newton iterations, ds)
	branch::VectorOfArray{T, 2, Array{Vector{T}, 1}}

	# the following variable holds the eigen elements at the index of the point along the curve. This index is the last element of eig[1] (for example). Recording this index is useful for storing only some eigenelements and not all of them along the curve
	eig::Vector{NamedTuple{(:eigenvals, :eigenvec, :step), Tuple{Teigvals, Teigvec ,Int64}}}

	# the following variable holds information about the detected bifurcation points like
	# [(:none, idx, normC(u), u, tau, eigenvalue_index, step)] where `tau` is the tangent along the curve and `eigenvalue_index` is the index of the eigenvalue in eig (see above) which changes stability
	bifpoint::Vector{Biftype}

	# vector holding the set of fold points detected during the computation of the branch.
	foldpoint::Vector{Biftype}

	# whether the associated point is linearly stable
	stability::Vector{Bool}

	# number of eigenvalues with positive real part and non zero imaginary part
	n_imag::Vector{Int64}

	# number of eigenvalues with positive real part
	n_unstable::Vector{Int64}

	# vector of solutions
	sol::Ts
end

length(br::ContResult) = length(br.branch[1, :])

_show(io, bp, ii) = @printf(io, "- %3i, %7s point around p ≈ %4.8f, step = %3i, idx = %3i, ind_bif = %3i [%9s], δ = (%2i, %2i)\n", ii, bp.type, bp.param, bp.step, bp.idx, bp.ind_bif, bp.status, bp.δ[1], bp.δ[2])

function show(io::IO, br::ContResult)
	println(io, "Branch number of points: ", length(br.branch))
	if length(br.bifpoint) > 0
		println(io, "Bifurcation points:")
		for ii in eachindex(br.bifpoint)
			_show(io, br.bifpoint[ii], ii)
		end
	end
	if length(br.foldpoint) > 0
		println(io, "Fold points:")
		for ii in eachindex(br.foldpoint)
			_show(io, br.foldpoint[ii], ii)
		end
	end
end

"""
This function is used to initialize the composite type `ContResult` according to the options contained in `contParams`
"""
function initContRes(br, u0, evsol, contParams::ContinuationPar{T, S, E}) where {T, S, E}
	bif0 = (type = :none, idx = 1, param = T(0), norm  = T(0), printsol = T(0), u = u0, tau = u0, ind_bif = 0, step = 0, status = :guess, δ = (0,0))
	contParams.saveSolEveryNsteps > 0 ? sol = [(u = u0, p = br[1,1], step = 1)] : sol = nothing
	n_unstable = 0
	n_imag = 0
	stability = true

	if contParams.computeEigenValues
		evvectors = contParams.saveEigenvectors ? evsol[2] : nothing
		stability, n_unstable, n_imag = is_stable(contParams, evsol[1])
		_evvectors = (eigenvals = evsol[1], eigenvec = evvectors, step = 0)
	else
		_evvectors = (eigenvals = Complex{T}(1), eigenvec = nothing, step = 0)
	end

	return ContResult{T, typeof(_evvectors[1]), typeof(_evvectors[2]), typeof(bif0), typeof(sol)}(
		branch = br,
		bifpoint = [bif0],
		foldpoint = [bif0],
		n_imag = [n_imag],
		n_unstable = [n_unstable],
		stability = [stability],
		eig = [_evvectors],
		sol = sol )
end
####################################################################################################
# Iterator interface

@with_kw struct PALCIterable{TF, TJ, Tv, T, S, E, Ttangent, Tlinear, Tplotsolution, Tprintsolution, TnormC, Tdot, Tfinalisesolution, Tcallback, Tfilename}
	F::TF
	J::TJ

	x0::Tv							# initial guess
	p0::T

	contParams::ContinuationPar{T, S, E}

	tangentAlgo::Ttangent
	linearAlgo::Tlinear

	plot::Bool = false
	plotSolution::Tplotsolution
	printSolution::Tprintsolution

	normC::TnormC
	dottheta::Tdot
	finaliseSolution::Tfinalisesolution
	callbackN::Tcallback

	verbosity::Int64 = 2

	filename::Tfilename
end

import Base: eltype

eltype(it::PALCIterable{TF, TJ, Tv, T, S, E, Ttangent, Tlinear, Tplotsolution, Tprintsolution, TnormC, Tdot, Tfinalisesolution, Tcallback, Tfilename}) where {TF, TJ, Tv, T, S, E, Ttangent, Tlinear, Tplotsolution, Tprintsolution, TnormC, Tdot, Tfinalisesolution, Tcallback, Tfilename} = T

function PALCIterable(Fhandle, Jhandle,
					x0, p0::T,
					contParams::ContinuationPar{T, S, E},
					linearAlgo::AbstractBorderedLinearSolver = BorderingBLS()
					;
					filename = "branch-" * string(Dates.now()),
					tangentAlgo = SecantPred(),
					plot = false,
					plotSolution = (x; kwargs...) -> nothing,
					printSolution = (x, p) -> norm(x),
					normC = norm,
					dotPALC = (x,y) -> dot(x,y) / length(x),
					finaliseSolution = (z, tau, step, contResult) -> true,
					callbackN = (x, f, J, res, iteration, optionsN; kwargs...) -> true,
					verbosity = 0
					) where {T <: Real, S, E}

	return PALCIterable(F = Fhandle, J = Jhandle, x0 = x0, p0 = p0, contParams = check(contParams), tangentAlgo = tangentAlgo, linearAlgo = linearAlgo, plot = plot, plotSolution = plotSolution, printSolution = printSolution, normC = normC, dottheta = DotTheta(dotPALC), finaliseSolution = finaliseSolution, callbackN = callbackN, verbosity = verbosity, filename = filename)
end

"""
	state = PALCStateVariables(ds = 1e-4,...)

Returns a variable containing the state of the continuation procedure.

# Arguments
- `z_pred` current solution on the branch
- `tau_new` tangent predictor
- `z_old` previous solution
- `tau_old` previous tangent
- `isconverged` Boolean for newton correction
- `it_number` Number of newton iteration (in corrector)
- `step` current continuation step
- `ds` step size
- `theta` theta parameter for constraint equation in PALC
- `stopcontinuation` Boolean to stop continuation

# Useful functions
- `copy(state)` returns a copy of `state`
- `solution(state)` returns the current solution (u,p)
- `getu(state)` returns the u component of the current solution
- `getp(state)` returns the p component of the current solution
- `isstable(state)` whether the current solution is linearly stable
"""
@with_kw mutable struct PALCStateVariables{Tv, T, Teigvals, Teigvec}
	z_pred::Tv								# current solution
	tau_new::Tv								# tangent predictor

	z_old::Tv								# previous solution
	tau_old::Tv								# previous tangent

	isconverged::Bool						# Boolean for newton correction
	it_number::Int64						# Number of newton iteration (in corrector)

	step::Int64 = 0							# current continuation step
	ds::T									# step size
	theta::T								# theta parameter for constraint equation in PALC

	stopcontinuation::Bool = false			# Boolean to stop continuation
	stepsizecontrol::Bool = true			# Perform step size adaptation

	n_unstable::Tuple{Int64,Int64}  = (-1, -1)	# (current, previous)
	n_imag::Tuple{Int64,Int64} 		= (-1, -1)	# (current, previous)

	eigvals::Teigvals = nothing				# current eigenvalues
	eigvecs::Teigvec = nothing				# current eigenvectors
end

import Base: copy

function copy(state::PALCStateVariables)
	return PALCStateVariables(
		z_pred 	= _copy(state.z_pred),
		tau_new = _copy(state.tau_new),
		z_old 	= _copy(state.z_old),
		tau_old = _copy(state.tau_old),
		isconverged = state.isconverged,
		it_number 	= state.it_number,
		step 		= state.step,
		ds 			= state.ds,
		theta 		= state.theta,
		stopcontinuation = state.stopcontinuation,
		stepsizecontrol  = state.stepsizecontrol,
		n_unstable 		 = state.n_unstable,
		n_imag 			 = state.n_imag
	)
end

solution(state::PALCStateVariables) = state.z_old
getu(state::PALCStateVariables) = state.z_old.u
getp(state::PALCStateVariables) = state.z_old.p
isstable(state::PALCStateVariables) = state.n_unstable[1] == 0

# condition for halting the continuation procedure
@inline done(it::PALCIterable, state::PALCStateVariables) =
			(state.step <= it.contParams.maxSteps) &&
			(it.contParams.pMin < state.z_old.p < it.contParams.pMax) &&
			(state.stopcontinuation == false)

function updatestability!(state::PALCStateVariables, n_unstable, n_imag)
	state.n_unstable = (n_unstable, state.n_unstable[1])
	state.n_imag = (n_imag, state.n_imag[1])
end

# we detect a bifurcation by a change in the number of unstable eigenvalues
function detectBifucation(state::PALCStateVariables)
	n1, n2 = state.n_unstable
	# deals with missing value encoded by n_unstable = -1
	if n1 == -1 || n2 == -1; return false; end
	return n1 !== n2
end

function save!(contres::ContResult, it::PALCIterable, state::PALCStateVariables)
	push!(contres.branch, getStateSummary(it, state, it.contParams))

	if state.n_unstable[1] >= 0 # if to deal with n_unstable = -1
		push!(contres.n_unstable, state.n_unstable[1])
		push!(contres.stability, isstable(state))
	end

	# if to deal with n_imag = -1
	if state.n_imag[1] >= 0; push!(contres.n_imag, state.n_imag[1]); end

	# save solution
	if it.contParams.saveSolEveryNsteps > 0 &&
		mod(state.step, it.contParams.saveSolEveryNsteps) == 0
		push!(contres.sol, (u = getu(state), p = getp(state), step = state.step))
	end
	# save eigen elements
	if it.contParams.computeEigenValues
		if mod(state.step, it.contParams.saveEigEveryNsteps) == 0
			if it.contParams.saveEigenvectors
				push!(contres.eig, (eigenvals = state.eigvals, eigenvec = state.eigvecs, step = state.step))
			else
				push!(contres.eig, (eigenvals = state.eigvals, eigenvec = state.eigvecs, step = state.step))
			end
		end
	end
end

function initContRes(it::PALCIterable, state::PALCStateVariables)
	u0 = getu(state)
	p0 = getp(state)
	contParams = it.contParams

	if contParams.computeEigenValues
		eiginfo = contParams.newtonOptions.eigsolver(it.J(u0, p0), contParams.nev)
		_, n_unstable, n_imag = is_stable(contParams, eiginfo[1])
		updatestability!(state, n_unstable, n_imag)
		return initContRes(VectorOfArray([getStateSummary(it, state, contParams)]), u0, eiginfo, contParams)
	else
		T = eltype(it)
		eiginfo = (Complex{T}(1), nothing, false, 0)
		return initContRes(VectorOfArray([getStateSummary(it, state, contParams)]), u0, nothing, contParams)
	end
end

import Base: iterate

function iterate(it::PALCIterable; _verbosity = it.verbosity)
	# this is to overwrite verbosity behaviour, like when locating bifurcations
	verbosity = min(it.verbosity, _verbosity)
	p0 = it.p0
	ds = it.contParams.ds
	T = eltype(p0)

	(verbosity > 0) && printstyled("#"^53*"\n*********** ArcLengthContinuationNewton *************\n\n", bold = true, color = :red)

	# Get parameters
	@unpack pMin, pMax, maxSteps, newtonOptions = it.contParams
	epsi = it.contParams.finDiffEps

	# Converge initial guess
	(verbosity > 0) && printstyled("*********** CONVERGE INITIAL GUESS *************", bold = true, color = :magenta)
	u0, fval, isconverged, it_number = newton(
			x -> it.F(x, p0),
			x -> it.J(x, p0),
			it.x0, newtonOptions; normN = it.normC, callback = it.callbackN, iterationC = 0, p = p0)
	@assert isconverged "Newton failed to converge initial guess"
	(verbosity > 0) && (print("\n--> convergence of initial guess = ");printstyled("OK\n", color=:green))
	(verbosity > 0) && println("--> p = $(p0), initial step")

	(verbosity > 0) && printstyled("\n******* COMPUTING INITIAL TANGENT *************", bold = true, color = :magenta)
	u_pred, fval, isconverged, it_number = newton(
			x -> it.F(x, p0 + ds / T(50)),
			x -> it.J(x, p0 + ds / T(50)),
			u0, newtonOptions; normN = it.normC, callback = it.callbackN, iterationC = 0, p = p0 + ds / T(50))
	@assert isconverged "Newton failed to converge for the computation of the initial tangent"
	(verbosity > 0) && (print("\n--> convergence of initial guess = ");printstyled("OK\n\n", color=:green))
	(verbosity > 0) && println("--> p = $(p0 + ds/50), initial step (bis)")

	# compute guess for initial tangent
	# duds = (u_pred - u0) / (contParams.ds / T(50));
	duds = copyto!(similar(u_pred), u_pred) #copy(u_pred)
	axpby!(-T(50) / ds, u0, T(50) / ds, duds)
	dpds = T(1)
	# compute the normtheta value
	α = it.dottheta(duds, dpds, it.contParams.theta)

	@assert typeof(α) == T "Error the type of α = $α, $(typeof(α)), does not match $T"
	@assert α > 0 "Error, α = 0, cannot scale first tangent vector"
	rmul!(duds, T(1) / α); dpds = dpds / α

	# number of iterations for newton correction
	# Variables to hold the predictor
	z_pred   = BorderedArray(copyto!(similar(u0), u0), p0)		# current solution
	tau_new  = BorderedArray(copyto!(similar(u0), u0), p0)		# tangent predictor

	z_old	 = BorderedArray(copyto!(similar(u_pred), u_pred), p0)	# variable for previous solution
	tau_old  = BorderedArray(copyto!(similar(duds), duds), dpds)

	# compute eigenvalues to get the type
	if it.contParams.computeEigenValues
		eigvals, eigvecs, _, _ = it.contParams.newtonOptions.eigsolver(it.J(u0, p0), it.contParams.nev)
		if it.contParams.saveEigenvectors == false
			eigvecs = nothing
		end
	else
		eigvals = nothing
		eigvecs = nothing
	end

	# return the state
	state = PALCStateVariables(z_pred = z_pred, tau_new  = tau_new, z_old = z_old, tau_old = tau_old, isconverged = true, stopcontinuation = false, step = 0, ds = it.contParams.ds, theta = it.contParams.theta, it_number = 0, stepsizecontrol = true, eigvals = eigvals, eigvecs = eigvecs)	# previous tangent
	return state, state
end

function iterate(it::PALCIterable, state::PALCStateVariables; _verbosity = it.verbosity)
	if !done(it, state) return nothing end
	# this is to overwrite verbosity behaviour, like when locating bifurcations
	verbosity = min(it.verbosity, _verbosity)

	step = state.step
	ds = state.ds
	theta = state.theta

	# Predictor: z_pred, following method only mutates z_pred
	getPredictor!(state.z_pred, state.z_old, state.tau_old, ds, it.tangentAlgo)
	(verbosity > 0) && println("#"^35)
	(verbosity > 0) && @printf("Start of Continuation Step %d:\nParameter = %2.4e ⟶  %2.4e\n", step, state.z_old.p, state.z_pred.p)

	(verbosity > 0) && @printf("Step size = %2.4e\n", ds)

	# Corrector, ie newton correction. This does not mutate the arguments
	z_new, fval, state.isconverged, state.it_number  = corrector(it.F, it.J,
			state.z_old, state.tau_old, state.z_pred,
			ds, theta,
			it.contParams, it.dottheta,
			it.tangentAlgo, it.linearAlgo, normC = it.normC, callback = it.callbackN, iterationC = step, p = state.z_old.p)

	# Successful step
	if state.isconverged
		(verbosity > 0) && printstyled("--> Step Converged in $(state.it_number) Nonlinear Iterations\n", color=:green)

		# Get predictor, it only mutates tau_old
		getTangent!(state.tau_old, z_new, state.z_old, state.tau_old, it.F, it.J,
					ds, theta, it.contParams, it.dottheta,
					it.tangentAlgo, verbosity, it.linearAlgo)

		# update current solution
		copyto!(state.z_old, z_new)
	else
		(verbosity > 0) && printstyled("Newton correction failed\n", color=:red)
		(verbosity > 0) && println("--> Newton Residuals history = ", fval)
	end

	if state.stopcontinuation == false && state.stepsizecontrol == true
		# we update the PALC paramters ds and theta, they are in the state variable
		state.ds, state.theta, state.stopcontinuation = stepSizeControl(ds, theta, it.contParams, state.isconverged, state.it_number, state.tau_old, verbosity)
	end

	state.step += 1
	return state, state
end

function getStateSummary(it, state, contParams)
	u0 = getu(state)
	p0 = getp(state)
	vcat(p0, it.printSolution(u0, p0), state.it_number, contParams.ds, contParams.theta, state.step)
end

function continuation!(it::PALCIterable, state::PALCStateVariables, contRes::ContResult)
	contParams = it.contParams
	verbosity = it.verbosity

	next = (state, state)

	while next !== nothing
		# we get the current state
		(i, state) = next
		########################################################################################
		# the new solution has been successfully computed
		# we perform saving, plotting, computation of eigenvalues...
		# the case state.step = 0 was just done above
		if state.isconverged && (state.step <= it.contParams.maxSteps) && (state.step > 0)

			# Eigenvalues computation
			if contParams.computeEigenValues
				it_number = computeEigenvalues!(it, state)

				(verbosity > 0) && printstyled(color=:green,"--> Computed ", length(state.eigvals), " eigenvalues in ", it_number, " iterations, #unstable = ", state.n_unstable[1],"\n")
			end

			# Detection of fold points based on parameter monotony, mutates contRes.foldpoint
			if contParams.detectFold; locateFold!(contRes, it, state); end

			if contParams.detectBifurcation > 0 && detectBifucation(state)
				status::Symbol = :guess
				if contParams.detectBifurcation > 1
					(verbosity > 0) && printstyled(color=:red, "--> Bifurcation detected before p = ", getp(state), "\n")

					# locate bifurcations, mutates state so that it rests very close to the bifurcation point. It also update the eigenelements at the current state
					status = locateBifurcation!(it, state, verbosity > 2)
				end
				if contParams.detectBifurcation>0 && detectBifucation(state)
					_, bifpt = getBifurcationType(contParams, state, it.normC, it.printSolution, verbosity, status)
					if bifpt.type != :none; push!(contRes.bifpoint, bifpt); end
				end
			end

			# Plotting
			(it.plot && mod(state.step, contParams.plotEveryNsteps) == 0 ) && plotBranchCont(contRes, state.z_old, contParams, it.plotSolution)

			# Saving Solution to File
			if contParams.saveToFile
				(verbosity > 0) && printstyled("--> Solving solution in file\n", color=:green)
				saveToFile(it.filename, getu(state), getp(state), state.step, contRes, contParams)
			end

			# Call user saved finaliseSolution function. If returns false, stop continuation
			if it.finaliseSolution(state.z_old, state.tau_new, state.step, contRes) == false
				state.stopcontinuation = true
			end

			# Save solution
			save!(contRes, it, state)
		end
		########################################################################################
		# body
		next = iterate(it, state)
	end

	# We remove the initial guesses which are meaningless
	popfirst!(contRes.bifpoint)
	popfirst!(contRes.foldpoint)

	# we remove the first element of branch, it was just to initialize it
	# popfirst!(contRes.branch.u)

	it.plot && plotBranchCont(contRes, state.z_old, contParams, it.plotSolution)

	# return current solution in case the corrector did not converge
	return contRes, state.z_old, state.tau_old
end

function continuation(it::PALCIterable)
	## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	# contres is not known at compile time so we
	# need a function barrier to resolve its type
	#############################################

	# we compute the cache pour the continuation, i.e. state::PALCStateVariables
	state = iterate(it)[1]

	# variable to hold results from continuation
	contRes = initContRes(it, state)
	return continuation!(it, state, contRes)
end

function continuation(Fhandle, Jhandle,
					x0, p0::T,
					contParams::ContinuationPar{T, S, E},
					linearAlgo::AbstractBorderedLinearSolver;
					tangentAlgo = SecantPred(),
					plot = false,
					plotSolution = (x; kwargs...) -> nothing,
					printSolution = (x, p) -> norm(x),
					normC = norm,
					dotPALC = (x,y) -> dot(x,y) / length(x),
					finaliseSolution = (z, tau, step, contResult) -> true,
					callbackN = (x, f, J, res, iteration, optionsN; kwargs...) -> true,
					filename = "branch-" * string(Dates.now()),
					verbosity = 0) where {T <: Real, S, E}

	it = PALCIterable(Fhandle, Jhandle, x0, p0, contParams, linearAlgo;
						tangentAlgo = tangentAlgo, plot = plot, plotSolution = plotSolution, printSolution = printSolution, normC = normC, dotPALC = dotPALC, finaliseSolution = finaliseSolution, callbackN = callbackN, verbosity = verbosity, filename = filename)
	return continuation(it)
end

####################################################################################################

"""
	continuation(F, J, x0, p0::Real, contParams::ContinuationPar; plot = false, normC = norm, dotPALC = (x,y) -> dot(x,y) / length(x), printSolution = norm, plotSolution = (x; kwargs...)->nothing, finaliseSolution = (z, tau, step, contResult) -> true, callbackN = (x, f, J, res, iteration, options; kwargs...) -> true, linearAlgo = BorderingBLS(), tangentAlgo = SecantPred(), verbosity = 0)

Compute the continuation curve associated to the functional `F` and its jacobian `J`.

# Arguments:
- `F = (x, p) -> F(x, p)` where `p` is the parameter for the continuation
- `J = (x, p) -> d_xF(x, p)` its associated jacobian. It can be a matrix, a function or a callable struct.
- `u0` initial guess
- `p0` initial parameter, must be a real number
- `contParams` parameters for continuatio. See [`ContinuationPar`](@ref) for more information about the options
- `plot = false` whether to plot the solution while computing
- `printSolution = (x, p) -> norm(x)` function used to plot in the continuation curve. It is also used in the way results are saved. It could be `norm` or `x -> x[1]`. This is also useful when saving several huge vectors is not possible for memory reasons (for example on GPU...).
- `plotSolution = (x; kwargs...) -> nothing` function implementing the plot of the solution.
- `finaliseSolution = (z, tau, step, contResult) -> true` Function called at the end of each continuation step. Can be used to alter the continuation procedure (stop it by returning false), saving personal data, plotting... The notations are ``z=(x,p)``, `tau` is the tangent at `z` (see below), `step` is the index of the current continuation step and `ContResult` is the current branch. Note that you can have a better control over the continuation procedure by using an iterator, see [Iterator Interface](@ref).
- `callbackN` callback for newton iterations. see docs for `newton`. Can be used to change preconditioners
- `tangentAlgo = SecantPred()` controls the algorithm use to predict the tangent along the curve of solutions or the corrector. Can be `NaturalPred`, `SecantPred` or `BorderedPred`.
- `linearAlgo = BorderingBLS()`. Must belong to `[MatrixBLS(), BorderingBLS(), MatrixFreeBLS()]`. Used to control the way the extended linear system associated to the continuation problem is solved.
- `verbosity ∈ {0,1,2,3}` controls the amount of information printed during the continuation process.
- `normC = norm` norm used in the different Newton solves
- `dotPALC = (x,y) -> dot(x,y) / length(x)`, dot product used in the definition of the dot product (norm) ``\\|(u, p)\\|^2_\\theta`` in the constraint ``N(x,p)`` (see below). This option can be used to remove the factor `1/length(x)` for example in problems where the dimension of the state space changes (mesh adaptation, ...)
- `filename` name of a file to save the computed branch during continuation. The identifier .jld2 will be appended to this filename

# Outputs:
- `contres::ContResult` composite type which contains the computed branch. See [`ContResult`](@ref) for more information.
- `u::BorderedArray` the last solution computed on the branch

!!! tip "Controlling the parameter `linearAlgo`"
    In this simplified interface to `continuation`, the argument `linearAlgo` is internally overwritten to provide a valid argument to the algorithm. If you do not want this to happen, call directly `continuation(F, J, x0, p0, contParams, linearAlgo; kwrags...)`.

# Method

## Bordered system of equations

The pseudo-arclength continuation method solves the equation ``F(x, p) = 0`` (of dimension N) together with the pseudo-arclength constraint ``N(x, p) = \\frac{\\theta}{length(x)} \\langle x - x_0, \\tau_0\\rangle + (1 - \\theta)\\cdot(p - p_0)\\cdot dp_0 - ds = 0``. In practice, the curve ``\\gamma`` is parametrised by ``s`` so that ``\\gamma(s) = (x(s), p(s))`` is a curve of solutions to ``F(x, p)``. This formulation allows to pass turning points (where the implicit theorem fails). In the previous formula, ``(x_0, p_0)`` is a solution for a given ``s_0``, ``(\\tau_0, dp_0)`` is the tangent to the curve at ``s_0``. Hence, to compute the curve of solutions, we need solve an equation of dimension N+1 which is called a Bordered system.

!!! warning "Parameter `theta`"
    The parameter `theta` in the struct `ContinuationPar`is very important. It should be tuned for the continuation to work properly especially in the case of large problems where the ``\\langle x - x_0, \\tau_0\\rangle`` component in the constraint might be favoured too much.

The parameter ds is adjusted internally depending on the number of Newton iterations and other factors. See the function `stepSizeControl` for more information. An important parameter to adjust the magnitude of this adaptation is the parameter `a` in the struct `ContinuationPar`.

## Algorithm

The algorithm works as follows:
0. Start from a known solution ``(x_0, p_0,\\tau_0 ,dp_0)``
1. **Predictor** set ``(x_1, p_1) = (x_0, p_0) + ds\\cdot (\\tau_0, dp_0)``
2. **Corrector** solve ``F(x, p)=0,\\ N(x, p)=0`` with a (Bordered) Newton Solver with guess ``(x_1, p_1)``.
    - if Newton in 3. did not converge, put ds/2 ⟶ ds and go to 1.
3. **New tangent** Compute ``(\\tau_1, dp_1)``, set ``(x_0, p_0, \\tau_0, dp_0) = (x_1, p_1, \\tau_1, dp_1)`` and return to step 2

## Natural continuation

We speak of *natural* continuation when we do not consider the constraint ``N(x, p)=0``. Knowing ``(x_0, p_0)``, we use ``x_0`` as a guess for solving ``F(x, p_1)=0`` with ``p_1`` close to ``p_0``. Again, this fails at Turning points but it can be faster to compute than the constrained case. This is set by the option `tangentAlgo = NaturalPred()` in `continuation`.

## Tangent computation (step 4)
There are various ways to compute ``(\\tau_1, p_1)``. The first one is called secant and is parametrised by the option `tangentAlgo = SecantPred()`. It is computed by ``(\\tau_1, p_1) = (z_1, p_1) - (z_0, p_0)`` and normalised by the norm ``\\|(u, p)\\|^2_\\theta = \\frac{\\theta}{length(u)} \\langle u,u\\rangle + (1 - \\theta)\\cdot p^2``. Another method is to compute ``(\\tau_1, p_1)`` by solving solving the bordered linear system ``\\begin{bmatrix} F_x & F_p	; \\ \\frac{\\theta}{length(x)}\\tau_0 & (1-\\theta)p_0\\end{bmatrix}\\begin{bmatrix}\\tau_1 ;  p_1\\end{bmatrix} =\\begin{bmatrix}0 ; 1\\end{bmatrix}`` ; it is set by the option `tangentAlgo = BorderedPred()`.

## Bordered linear solver

When solving the Bordered system ``F(x, p) = 0,\\ N(x, p)=0``, one faces the issue of solving the Bordered linear system ``\\begin{bmatrix} J & a	; b^T & c\\end{bmatrix}\\begin{bmatrix}X ;  y\\end{bmatrix} =\\begin{bmatrix}R ; n\\end{bmatrix}``. This can be solved in many ways via bordering (which requires two Jacobian inverses), by forming the bordered matrix (which works well for sparse matrices) or by using a full Matrix Free formulation. The choice of method is set by the argument `linearAlgo`. Have a look at the struct `linearBorderedSolver` for more information.

## Linear Algebra

Let us discuss here more about the norm and dot product. First, the option `normC` gives a norm that is used to evaluate the residual in the following way: ``max(normC(F(x,p)), \\|N(x,p)\\|)<tol``. It is thus used as a stopping criterion for a Newton algorithm. The dot product (resp. norm) used in ``N`` and in the (iterative) linear solvers is `LinearAlgebra.dot` (resp. `LinearAlgebra.norm`). It can be changed by importing these functions and redefining it. Not that by default, the ``L^2`` norm is used. These details are important because of the constraint ``N`` which incorporates the factor `length`. For some custom composite type implementing a Vector space, the dot product could already incorporates the `length` factor in which case you should either redefine the dot product or change ``\\theta``.

## Step size control

As explained above, each time the corrector phased failed, the step size ``ds`` is halved. This has the disavantage of having lost Newton iterations (which costs time) and impose small steps (which can be slow as well). To prevent this, the step size is controlled internally with the idea of having a constant number of Newton iterations per point. This is in part controlled by the aggressiveness factor `a` in `ContinuationPar`. Further tuning is performed by using `doArcLengthScaling=true` in `ContinuationPar`. This adjusts internally ``\\theta`` so that the relative contributions of ``x`` and ``p`` are balanced in the constraint ``N``.
"""
function continuation(Fhandle, Jhandle,
					x0, p0::T,
					contParams::ContinuationPar{T, S, E};
					tangentAlgo = SecantPred(),
					linearAlgo  = BorderingBLS(),
					plot = false,
					printSolution = (x, p) -> norm(x),
					normC = norm,
					dotPALC = (x,y) -> dot(x,y) / length(x),
					plotSolution = (x; kwargs...) -> nothing,
					finaliseSolution = (z, tau, step, contResult) -> true,
					callbackN = (x, f, J, res, iteration, optionsN; kwargs...) -> true,
					filename = "branch-" * string(Dates.now()),
					verbosity = 0) where {T <: Real, S <: AbstractLinearSolver, E <: AbstractEigenSolver}

	# Create a bordered linear solver using newton linear solver
	_linearAlgo = @set linearAlgo.solver = contParams.newtonOptions.linsolver

	return continuation(Fhandle, Jhandle, x0, p0, contParams, _linearAlgo; tangentAlgo = tangentAlgo, plot = plot, printSolution = printSolution, normC = normC, dotPALC = dotPALC, plotSolution = plotSolution, finaliseSolution = finaliseSolution, callbackN = callbackN, filename = filename, verbosity = verbosity)

end

continuation(Fhandle, u0, p0::T, contParams::ContinuationPar{T, S, E}; kwargs...) where {T, S, E} = continuation(Fhandle, (u0, p) -> finiteDifferences(u -> Fhandle(u, p), u0), u0, p0, contParams; kwargs...)
