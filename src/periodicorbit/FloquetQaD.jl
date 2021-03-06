# This function is very important for the computation of Floquet multipliers and checks that the eigensolvers compute the eigenvalues with largest modulus instead of their default behaviour which is with largest real part. If this option is not properly set, bifurcations of periodic orbits will be missed.
function checkFloquetOptions(eigls::AbstractEigenSolver)
	if eigls isa DefaultEig
		return @set eigls.which = abs
	end

	if eigls isa EigArpack
		return setproperties(eigls; which = :LM, by = abs)
	end

	if eigls isa EigKrylovKit
		return @set eigls.which = :LM
	end
end
####################################################################################################
# Computation of Floquet Coefficients for periodic orbits problems based on Finite Differences

"""
	floquet = FloquetQaDTrap(eigsolver::AbstractEigenSolver)

This composite type implements the computation of the eigenvalues of the monodromy matrix in the case of periodic orbits problems based on Finite Differences (Trapeze method), also called the Floquet multipliers. The method, dubbed Quick and Dirty (QaD), is not numerically very precise for large / small Floquet exponents. It allows, nevertheless, to detect bifurcations. The arguments are as follows:
- `eigsolver::AbstractEigenSolver` solver used to compute the eigenvalues.

If `eigsolver == DefaultEig()`, then the monodromy matrix is formed and its eigenvalues are computed. Otherwise, a Matrix-Free version of the monodromy is used.

!!! danger "Floquet multipliers computation"
    The computation of Floquet multipliers is necessary for the detection of bifurcations of periodic orbits (which is done by analyzing the Floquet exponents obtained from the Floquet multipliers). Hence, the eigensolver `eigsolver` needs to compute the eigenvalues with largest modulus (and not with largest real part which is their default behavior). This can be done by changing the option `which = :LM` of `eigsolver`. Nevertheless, note that for most implemented eigensolvers in the current Package, the proper option is set.
"""
struct FloquetQaDTrap{E <: AbstractEigenSolver } <: AbstractFloquetSolver
	eigsolver::E
	function FloquetQaDTrap(eigls::AbstractEigenSolver)
		eigls2 = checkFloquetOptions(eigls)
		return new{typeof(eigls2)}(eigls2)
	end
end

"""
Matrix-Free expression expression of the Monodromy matrix for the periodic problem computed at the space-time guess: `u0`
"""
function MonodromyQaDFD(poPb::PeriodicOrbitTrapProblem, u0::AbstractVector, du::AbstractVector)
	# extraction of various constants
	M = poPb.M
	N = poPb.N

	# period of the cycle
	T = extractPeriodFDTrap(u0)

	# time step
	h = T / M
	Typeh = typeof(h)

	out = copy(du)

	u0c = extractTimeSlice(u0, N, M)

	@views out .= out .+ h/2 .* apply(poPb.J(u0c[:, M-1]), out)
	# res = (I - h/2 * poPb.J(u0c[:, 1])) \ out
	@views res, _ = poPb.linsolver(poPb.J(u0c[:, 1]), out; a₀ = convert(Typeh, 1), a₁ = -h/2)
	out .= res

	for ii = 2:M-1
		@views out .= out .+ h/2 .* apply(poPb.J(u0c[:, ii-1]), out)
		# res = (I - h/2 * poPb.J(u0c[:, ii])) \ out
		@views res, _ = poPb.linsolver(poPb.J(u0c[:, ii]), out; a₀ = convert(Typeh, 1), a₁ = -h/2)
		out .= res
	end

	return out
end

# Compute the monodromy matrix at `u0` explicitely, not suitable for large systems
function MonodromyQaDFD(poPb::PeriodicOrbitTrapProblem, u0::vectype) where {vectype <: AbstractVector}
	# extraction of various constants
	M = poPb.M
	N = poPb.N

	# period of the cycle
	T = extractPeriodFDTrap(u0)

	# time step
	h = T / M

	u0c = extractTimeSlice(u0, N, M)

	@views mono = Array(I - h/2 * (poPb.J(u0c[:, 1]))) \ Array(I + h/2 * poPb.J(u0c[:, M-1]))
	temp = similar(mono)

	for ii = 2:M-1
		# for some reason, the next line is faster than doing (I - h/2 * (poPb.J(u0c[:, ii]))) \ ...
		# also I - h/2 .* J seems to hurt (a little) performances
		@views temp = Array(I - h/2 * (poPb.J(u0c[:, ii]))) \ Array(I + h/2 * poPb.J(u0c[:, ii-1]))
		mono .= temp * mono
	end
	return mono
end

function (fl::FloquetQaDTrap)(J, nev)
	if fl.eigsolver isa DefaultEig
		# we build the monodromy matrix and compute the spectrum
		monodromy = MonodromyQaDFD(J.pb, J.orbitguess0)
	else
		# we use a Matrix Free version
		monodromy = x -> MonodromyQaDFD(J.pb, J.orbitguess0, x)
	end
	vals, vecs, cv, info = fl.eigsolver(monodromy, nev)
	# the `vals` should be sorted by largest modulus, but we need the log of them sorted this way
	logvals = log.(complex.(vals))
	I = sortperm(logvals, by = x-> real(x), rev = true)
	# Base.display(logvals)
	return logvals[I], geteigenvector(fl.eigsolver, vecs, I), cv, info
end

####################################################################################################
# Computation of Floquet Coefficients for periodic orbit problems based on Shooting

"""
	floquet = FloquetQaDShooting(eigsolver::AbstractEigenSolver)

This composite type implements the computation of the eigenvalues of the monodromy matrix in the case of periodic orbits problems based on the Shooting method, also called the Floquet multipliers. The method, dubbed Quick and Dirty (QaD), is not numerically very precise for large / small Floquet exponents. It allows, nevertheless, to detect bifurcations. The arguments are as follows:
- `eigsolver::AbstractEigenSolver` solver used to compute the eigenvalues.

If `eigsolver == DefaultEig()`, then the monodromy matrix is formed and its eigenvalues are computed. Otherwise, a Matrix-Free version of the monodromy is used.

!!! danger "Floquet multipliers computation"
    The computation of Floquet multipliers is necessary for the detection of bifurcations of periodic orbits (which is done by analyzing the Floquet exponents obtained from the Floquet multipliers). Hence, the eigensolver `eigsolver` needs to compute the eigenvalues with largest modulus (and not with largest real part which is their default behavior). This can be done by changing the option `which = :LM` of `eigsolver`. Nevertheless, note that for most implemented eigensolvers in the current Package, the proper option is set.
"""
struct FloquetQaDShooting{E <: AbstractEigenSolver } <: AbstractFloquetSolver
	eigsolver::E
	function FloquetQaDShooting(eigls::AbstractEigenSolver)
		eigls2 = checkFloquetOptions(eigls)
		return new{typeof(eigls2)}(eigls2)
	end
end

function (fl::FloquetQaDShooting)(J, nev)
	if fl.eigsolver isa DefaultEig
		@warn "Not implemented yet in a fast way! Need to form the full monodromy matrix, not practical for large scale problems"
		# we build the monodromy matrix and compute the spectrum
		monodromy = MonodromyQaDShooting(J.pb, J.x)
	else
		# we use a Matrix Free version
		monodromy = x -> MonodromyQaDShooting(J.pb, J.x, x)
	end
	vals, vecs, cv, info = fl.eigsolver(monodromy, nev)

	# the `vals` should be sorted by largest modulus, but we need the log of them sorted this way
	logvals = log.(complex.(vals))
	# Base.display(logvals)
	I = sortperm(logvals, by = x-> real(x), rev = true)
	return logvals[I], geteigenvector(fl.eigsolver, vecs, I), cv, info
end

"""
Matrix-Free expression expression of the Monodromy matrix for the periodic problem based on Shooting computed at the space-time guess: `x`. The dimension of `u0` is N * M + 1 and the one of `du` is N.
"""
function MonodromyQaDShooting(sh::ShootingProblem, x, du::AbstractVector)
	# period of the cycle
	T = extractPeriodShooting(x)

	# extract parameters
	M = length(sh.ds)
	N = div(length(x) - 1, M)

	# extract the time slices
	xv = @view x[1:end-1]
	xc = reshape(xv, N, M)

	out = copy(du)

	for ii = 1:M
		# call jacobian of the flow
		@views out .= sh.flow(xc[:, ii], out, sh.ds[ii] * T)[2]
	end

	return out
end

# Compute the monodromy matrix at `x` explicitely, not suitable for large systems
function MonodromyQaDShooting(sh::ShootingProblem, x)
	# period of the cycle
	T = extractPeriodShooting(x)

	# extract parameters
	M = length(sh.ds)
	M > 1 && @error "This is not yet a practical approach for multiple shooting"

	N = div(length(x) - 1, M)

	Mono = zeros(N, N)

	# extract the time slices
	xv = @view x[1:end-1]
	xc = reshape(xv, N, M)

	du = zeros(N)

	for ii = 1:N
		du[ii] = 1.0
		# call jacobian of the flow
		@views Mono[:, ii] .= sh.flow(xc[:, 1], du, T)[2]
		du[ii] = 0.0
	end

	return Mono
end

"""
Matrix-Free expression expression of the Monodromy matrix for the periodic problem based on Poicaré Shooting computed at the space-time guess: `x`. The dimension of `x` is N * M and the one of `du` is N.
"""
function MonodromyQaDShooting(sh::PoincareShootingProblem, x, du::AbstractVector)
	# extract parameters
	M = sh.M
	N = div(length(x), M)

	# extract the time slices
	xc = reshape(x, N, M)

	out = copy(du)

	for ii = 1:M
		# call jacobian of the flow
		@views out .= sh.flow(xc[:, ii], out, Inf64)[2]
	end

	return out
end


# Compute the monodromy matrix at `u0` explicitely, not suitable for large systems
function MonodromyQaDShooting(sh::PoincareShootingProblem, x)
	# extract parameters
	M = sh.M
	@assert M == 1 "This is not yet a practical approach for multiple shooting"

	N = div(length(x) , M)

	Mono = zeros(N, N)

	# extract the time slices
	xc = reshape(x, N, M)

	du = zeros(N)

	for ii = 1:N
		du[ii] = 1.0
		# call jacobian of the flow
		@views Mono[:, ii] .= sh.flow(xc[:, 1], du, Inf64)[2]
		du[ii] = 0.0
	end

	return Mono
end
