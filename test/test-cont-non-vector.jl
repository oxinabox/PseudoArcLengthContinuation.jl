# this test is designed to test the ability of the package to use a state space that is not an AbstractArray.
# using Revise
using Test, Random, Setfield
using PseudoArcLengthContinuation
const PALC = PseudoArcLengthContinuation
####################################################################################################
# We start with a simple Fold problem
using LinearAlgebra
function F0(x::Vector, r)
	out = r .+  x .- x.^3
end

opt_newton0 = PALC.NewtonPar(tol = 1e-11, verbose = true)
	out0, hist, flag = @time PALC.newton(
		x -> F0(x, 1.),
		[0.8],
		opt_newton0)

opts_br0 = PALC.ContinuationPar(dsmin = 0.001, dsmax = 0.021, ds= -0.01, pMax = 4.1, pMin = -1., newtonOptions = setproperties(opt_newton0; maxIter = 70, tol = 1e-8), detectBifurcation = 0, maxSteps = 150, detectFold = true)

	br0, u1 = @time PALC.continuation(
		F0,
		out0, 1.0,
		opts_br0, printSolution = (x,p) -> x[1])

# plotBranch(br0);title!("a")

outfold, hist, flag = @time PALC.newtonFold(
	F0,
	(x, r) -> diagm(0 => 1 .- 3 .* x.^2),
	(x, r) -> diagm(0 => 1 .- 3 .* x.^2),
	(x, r, v1, v2) -> -6 .* x .* v1 .* v2,
	br0, 2, #index of the fold point
	opts_br0.newtonOptions)
		flag && printstyled(color=:red, "--> We found a Fold Point at α = ",outfold.p, ", from ", br0.foldpoint[1][3], "\n")

####################################################################################################
# Here is a more involved example

function Fb(x::BorderedArray, r, s = 1.0)
	BorderedArray(r .+  s .* x.u .- (x.u).^3, x.p - 0.0)
end

# there is no finite differences defined, so we need to provide a linearsolve
# we could also have used GMRES. We define a custom Jacobian which will be used for evaluation and jacobian inverse
struct Jacobian
	x
	r
	s
end

# We express the jacobian operator
function (J::Jacobian)(dx)
	BorderedArray( (J.s .- 3 .* ((J.x).u).^2) .* dx.u, dx.p)
end

struct linsolveBd <: PALC.AbstractBorderedLinearSolver end

function (l::linsolveBd)(J, dx)
	x = J.x
	r = J.r
	out = BorderedArray(dx.u ./ (J.s .- 3 .* (x.u).^2), dx.p)
	out, true, 1
end

sol = BorderedArray([0.8], 0.0)

opt_newton = PALC.NewtonPar(tol = 1e-11, verbose = true, linsolver = linsolveBd())
out, hist, flag = @time PALC.newton(
		x -> Fb(x, 1., 1.),
		x -> Jacobian(x, 1., 1.),
		sol,
		opt_newton)

opts_br = PALC.ContinuationPar(dsmin = 0.001, dsmax = 0.05, ds= -0.01, pMax = 4.1, pMin = -1., newtonOptions = setproperties(opt_newton; maxIter = 70, tol = 1e-8), detectBifurcation = 0, maxSteps = 150)

	br, u1 = @time PALC.continuation(
		(x, r) -> Fb(x, r, 1.),
		(x, r) -> Jacobian(x, r, 1.),
		out, 1.,
		opts_br; printSolution = (x,p) -> x.u[1])


# plotBranch(br);title!("")

outfold, hist, flag = @time PALC.newtonFold(
	(x, r) -> Fb(x, r),
	(x, r) -> Jacobian(x, r, 1.),
	(x, r) -> Jacobian(x, r, 1.),
	(x, r, v1, v2) -> BorderedArray(-6 .* x.u .* v1.u .* v2.u, 0.),
	br, 1, #index of the fold point
	opts_br.newtonOptions)
		flag && printstyled(color=:red, "--> We found a Fold Point at α = ", outfold.p, ", from ", br.foldpoint[1][3],"\n")

outfoldco, hist, flag = @time PALC.continuationFold(
	(x, r, s) -> Fb(x, r, s),
	(x, r, s) -> Jacobian(x, r, s),
	(x, r, s) -> Jacobian(x, r, s),
	s -> ((x, r, v1, v2) -> BorderedArray(-6 .* x.u .* v1.u .* v2.u, 0.)),
	br, 1,
	1.0, plot = false, opts_br)

# try with newtonDeflation
printstyled(color=:green, "--> test with Newton deflation 1")
deflationOp = DeflationOperator(2.0, (x, y) -> dot(x, y), 1.0, [zero(sol)])
soldef0 = BorderedArray([0.1], 0.0)
soldef1, _, _ = @time PALC.newton(
	x -> Fb(x, 0., 1.),
	x -> Jacobian(x, 0., 1.),
	soldef0,
	opt_newton, deflationOp)

push!(deflationOp, soldef1)

Random.seed!(1231)
printstyled(color=:green, "--> test with Newton deflation 2")
soldef2, _, _ = @time PALC.newton(
	x -> Fb(x, 0., 1.),
	x -> Jacobian(x, 0., 1.),
	rmul!(soldef0,rand()),
	opt_newton, deflationOp)

# test indexing
deflationOp[1]

# test length
length(deflationOp)

# test pop!
pop!(deflationOp)

####################################################################################################
using KrylovKit

function Fr(x::RecursiveVec, r, s = 1.0)
	out = similar(x)
	for ii=1:length(x)
		out[ii] .= r .+  s .* x[ii] .- x[ii].^3
	end
	out
end

# there is no finite differences defined, so we need to provide a linearsolve
# we could also have used GMRES. We define a custom Jacobian which will be used for evaluation and jacobian inverse
struct JacobianR
	x
	s
end

# We express the jacobian operator
function (J::JacobianR)(dx)
	out = similar(dx)
	for ii=1:length(out)
		out[ii] .= (J.s .- 3 .* (J.x[ii]).^2) .* dx[ii]
	end
	return out
end

struct linsolveBd_r <: PALC.AbstractBorderedLinearSolver end

function (l::linsolveBd_r)(J, dx)
	x = J.x
	out = similar(dx)
	for ii=1:length(out)
		out[ii] .= dx[ii] ./ (J.s .- 3 .* (x[ii]).^2)
	end
	out, true, 1
end

opt_newton0 = PALC.NewtonPar(tol = 1e-11, verbose = false, linsolver = linsolveBd_r())
	out0, hist, flag = @time PALC.newton(
		x -> Fr(x, 1.),
		x -> JacobianR(x, 1),
		RecursiveVec([1 .+ 0.1*rand(10) for _=1:2]),
		opt_newton0)

opts_br0 = PALC.ContinuationPar(dsmin = 0.001, dsmax = 0.2, ds= -0.01, pMin = -1.1, pMax = 1.1, newtonOptions = opt_newton0)

br0, u1 = @time PALC.continuation(
	(x, r) -> Fr(x, r),
	(x, r) -> JacobianR(x, 1),
	out0, 0.9, opts_br0;
	plot = false,
	printSolution = (x,p) -> x[1][1])

br0, u1 = @time PALC.continuation(
	(x, r) -> Fr(x, r),
	(x, r) -> JacobianR(x, 1),
	out0, 0.9, opts_br0;
	tangentAlgo = BorderedPred(),
	plot = false,
	printSolution = (x,p) -> x[1][1])

outfold, hist, flag = @time PALC.newtonFold(
	(x, r) -> Fr(x, r),
	(x, r) -> JacobianR(x, 1),
	(x, r) -> JacobianR(x, 1),
	(x, r, v1, v2) -> RecursiveVec([-6 .* x[ii] .* v1[ii] .* v2[ii] for ii=1:length(x)]),
	br0, 1, #index of the fold point
	opt_newton0)
		flag && printstyled(color=:red, "--> We found a Fold Point at α = ", outfold.p, ", from ", br0.foldpoint[1][3],"\n")

outfoldco, hist, flag = @time PALC.continuationFold(
	(x, r, s) -> Fr(x, r, s),
	(x, r, s) -> JacobianR(x, s),
	(x, r, s) -> JacobianR(x, s),
	s -> ((x, r, v1, v2) -> RecursiveVec([-6 .* x[ii] .* v1[ii] .* v2[ii] for ii=1:length(x)])),
	br0, 1,	1.0, opts_br0;
	tangentAlgo = SecantPred(), plot = false)

outfoldco, hist, flag = @time PALC.continuationFold(
	(x, r, s) -> Fr(x, r, s),
	(x, r, s) -> JacobianR(x, s),
	(x, r, s) -> JacobianR(x, s),
	s -> ((x, r, v1, v2) -> RecursiveVec([-6 .* x[ii] .* v1[ii] .* v2[ii] for ii=1:length(x)])),
	br0, 1,	1.0, opts_br0;
	tangentAlgo = BorderedPred(), plot = false)

# try with newtonDeflation
printstyled(color=:green, "--> test with Newton deflation 1")
deflationOp = DeflationOperator(2.0, (x, y) -> dot(x, y), 1.0, [(out0)])
soldef1, _, _ = @time PALC.newton(
	x -> Fr(x, 0.),
	x -> JacobianR(x, 0.),
	out0,
	opt_newton0, deflationOp)

push!(deflationOp, soldef1)
