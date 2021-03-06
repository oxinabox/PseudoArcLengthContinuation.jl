# Brusselator 1d

!!! unknown "References"
    This example is taken from **Numerical Bifurcation Analysis of Periodic Solutions of Partial Differential Equations,** Lust, 1997.

We look at the Brusselator in 1d. The equations are as follows

$$\begin{aligned} \frac { \partial X } { \partial t } & = \frac { D _ { 1 } } { l ^ { 2 } } \frac { \partial ^ { 2 } X } { \partial z ^ { 2 } } + X ^ { 2 } Y - ( β + 1 ) X + α \\ \frac { \partial Y } { \partial t } & = \frac { D _ { 2 } } { l ^ { 2 } } \frac { \partial ^ { 2 } Y } { \partial z ^ { 2 } } + β X - X ^ { 2 } Y \end{aligned}$$

with Dirichlet boundary conditions

$$\begin{array} { l } { X ( t , z = 0 ) = X ( t , z = 1 ) = α } \\ { Y ( t , z = 0 ) = Y ( t , z = 1 ) = β / α } \end{array}$$

These equations have been introduced to reproduce an oscillating chemical reaction. There is an obvious equilibrium $(α, β / α)$. Here, we consider bifurcation with respect to the parameter $l$.

We start by writing the PDE

```julia
using Revise
using PseudoArcLengthContinuation, LinearAlgebra, Plots, SparseArrays, Setfield, Parameters
const PALC = PseudoArcLengthContinuation

f1(u, v) = u * u * v
norminf = x -> norm(x, Inf)

function Fbru(x, p)
	@unpack α, β, D1, D2, l = p
	f = similar(x)
	n = div(length(x), 2)
	h = 1.0 / n; h2 = h*h
	c1 = D1 / l^2 / h2
	c2 = D2 / l^2 / h2

	u = @view x[1:n]
	v = @view x[n+1:2n]

	# Dirichlet boundary conditions
	f[1]   = c1 * (α      - 2u[1] + u[2] ) + α - (β + 1) * u[1] + f1(u[1], v[1])
	f[end] = c2 * (v[n-1] - 2v[n] + β / α)			 + β * u[n] - f1(u[n], v[n])

	f[n]   = c1 * (u[n-1] - 2u[n] +  α  )  + α - (β + 1) * u[n] + f1(u[n], v[n])
	f[n+1] = c2 * (β / α  - 2v[1] + v[2])			 + β * u[1] - f1(u[1], v[1])

	for i=2:n-1
		  f[i] = c1 * (u[i-1] - 2u[i] + u[i+1]) + α - (β + 1) * u[i] + f1(u[i], v[i])
		f[n+i] = c2 * (v[i-1] - 2v[i] + v[i+1])			  + β * u[i] - f1(u[i], v[i])
	end
	return f
end
```

For computing periodic orbits, we will need a Sparse representation of the Jacobian:

```julia
function Jbru_sp(x, p)
	@unpack α, β, D1, D2, l = p
	# compute the Jacobian using a sparse representation
	n = div(length(x), 2)
	h = 1.0 / n; h2 = h*h

	c1 = D1 / p.l^2 / h2
	c2 = D2 / p.l^2 / h2

	u = @view x[1:n]
	v = @view x[n+1:2n]

	diag   = zeros(eltype(x), 2n)
	diagp1 = zeros(eltype(x), 2n-1)
	diagm1 = zeros(eltype(x), 2n-1)

	diagpn = zeros(eltype(x), n)
	diagmn = zeros(eltype(x), n)

	@. diagmn = β - 2 * u * v
	@. diagm1[1:n-1] = c1
	@. diagm1[n+1:end] = c2

	@. diag[1:n]    = -2c1 - (β + 1) + 2 * u * v
	@. diag[n+1:2n] = -2c2 - u * u

	@. diagp1[1:n-1] = c1
	@. diagp1[n+1:end] = c2

	@. diagpn = u * u
	return spdiagm(0 => diag, 1 => diagp1, -1 => diagm1, n => diagpn, -n => diagmn)
end
```

!!! tip "Tip"
    We could have used `DiffEqOperators.jl` like for the Swift-Hohenberg tutorial.

We shall now compute the equilibria and their stability.

```julia
n = 500

# parameters of the Brusselator model and guess for the stationary solution
par_bru = (α = 2., β = 5.45, D1 = 0.008, D2 = 0.004, l = 0.3)
sol0 = vcat(par_bru.α * ones(n), par_bru.β/par_bru.α * ones(n))
```

For the eigensolver, we use a Shift-Invert algorithm (see [Eigen solvers](@ref))

```julia
eigls = EigArpack(1.1, :LM)
```

We continue the trivial equilibrium to find the Hopf points

```julia
opt_newton = NewtonPar(eigsolver = eigls, verbose = false)
opts_br_eq = ContinuationPar(dsmin = 0.001, dsmax = 0.01, ds = 0.001, pMax = 1.9, detectBifurcation = 2, nev = 21, plotEveryNsteps = 50, newtonOptions = NewtonPar(eigsolver = eigls, tol = 1e-9), maxSteps = 1060)

	br, _ = @time continuation(
		(x, p) ->    Fbru(x, @set par_bru.l = p),
		(x, p) -> Jbru_sp(x, @set par_bru.l = p),
		sol0, par_bru.l,
		opts_br_eq, verbosity = 0,
		plot = true,
		printSolution = (x,p) -> x[div(n,2)], normC = norminf)
```

We obtain the following bifurcation diagram with 3 Hopf bifurcation points

![](bru-sol-hopf.png)

## Continuation of Hopf points

We use the bifurcation points guesses located in `br.bifpoint` to turn them into precise bifurcation points. For the second one, we have

```julia
# index of the Hopf point in br.bifpoint
ind_hopf = 2
hopfpoint, _, flag = @time newtonHopf(
	(x, p) ->    Fbru(x, @set par_bru.l = p),
	(x, p) -> Jbru_sp(x, @set par_bru.l = p),
	br, ind_hopf,
	opts_br_eq.newtonOptions, normN = norminf)
flag && printstyled(color=:red, "--> We found a Hopf Point at l = ", hopfpoint.p[1], ", ω = ", hopfpoint.p[2], ", from l = ", br.bifpoint[ind_hopf].param, "\n")
```

which produces

```julia
--> We found a Hopf Point at l = 1.0239851696548035, ω = 2.1395092895339842, from l = 1.0353910524340078
```

We now perform a Hopf continuation with respect to the parameters `l, β`

!!! tip "Tip"
    You don't need to call `newtonHopf` first in order to use `continuationHopf`.

```julia
br_hopf, _ = @time continuationHopf(
	(x, l, β) ->  Fbru(x, setproperties(par_bru, (l=l, β=β))),
	(x, l, β) -> Jbru_sp(x, setproperties(par_bru, (l=l, β=β))),
	br, ind_hopf, par_bru.β,
	ContinuationPar(dsmin = 0.001, dsmax = 0.05, ds= 0.01, pMax = 6.5, pMin = 0.0, newtonOptions = opt_newton), verbosity = 2, normC = norminf)
```

which gives using `plotBranch(br_hopf, xlabel="beta", ylabel = "l")`

![](bru-hopf-cont.png)


## Continuation of periodic orbits (Finite differences)

Here, we perform continuation of periodic orbits branching from the Hopf bifurcation points. Note that the Hopf normal form is not included in the current version of the package, so we need an educated guess for the periodic orbit which is given by `guessFromHopf`:

```julia
# number of time slices
M = 51

l_hopf, Th, orbitguess2, hopfpt, vec_hopf = guessFromHopf(br, ind_hopf,
	opts_br_eq.newtonOptions.eigsolver,
	M, 2.7; phase = 0.25)
```
We wish to make two remarks at this point. The first is that an initial guess is composed of a space time solution and of the guess for the period `Th` of the solution. Note that the argument `2.7` is a guess for the amplitude of the orbit.

```julia
# orbit initial guess from guessFromHopf, is not a vector, so we reshape it
orbitguess_f2 = reduce(vcat, orbitguess2)
orbitguess_f = vcat(vec(orbitguess_f2), Th) |> vec
```

The second remark concerns the phase `0.25` written above. To account for the additional unknown (*i.e.* the period), periodic orbit localisation using Finite Differences requires an additional constraint (see [Periodic orbits based on finite differences](@ref) for more details). In the present case, this constraint is

$$< u(0) - u_{hopf}, \phi> = 0$$

where `u_{hopf}` is the equilibrium at the Hopf bifurcation and $\phi$ is `real.(vec_hopf)` where `vec_hopf` is the eigenvector. This is akin to a Poincaré section.

The phase of the periodic orbit is set so that the above constraint is satisfied. We shall now use Newton iterations to find a periodic orbit.

Given our initial guess, we create a (family of) problem which encodes the functional associated to finding periodic orbits based on finite differences (see [Periodic orbits based on finite differences](@ref) for more information):

```julia
poTrap = p -> PeriodicOrbitTrapProblem(
	x ->    Fbru(x, @set par_bru.l = p),    # pass the vector field
	x -> Jbru_sp(x, @set par_bru.l = p),    # pass the jacobian of the vector field
	real.(vec_hopf),                        # used to set ϕ, see the phase constraint
	hopfpt.u,                               # used to set uhopf, see the phase constraint
	M)			                # number of time slices
```

To evaluate the functional at `x`, you call it like a function: `poTrap(l_hopf + 0.01)(x)` for the parameter `l_hopf + 0.01`. 

!!! note "Using the functional for deflation, Fold of limit cycles..."
    The functional `poTrap` gives you access to the underlying methods to call a regular `newton`. For example the functional is `x -> poTrap(l_hopf + 0.01)(x)` at parameter `l_hopf + 0.01`. The (sparse) Jacobian at `(x,p)` is computed like this `poTrap(p)(Val(:JacFullSparse), x)` while the Matrix Free version is `dx -> poTrap(p)(x, dx)`. This also allows you to call the newton deflated method (see [Newton with deflation](@ref)) or [Newton for Fold / Hopf](@ref) to locate Fold point of limit cycles see [`PeriodicOrbitTrapProblem`](@ref). You can also use preconditioners. In the case of more computationally intense problems (like the 2d Brusselator), this might be mandatory as using LU decomposition for the linear solve will use too much memory. See [Newton for Periodic Orbits](@ref) for more information and the example `cGL2.jl`
 

For convenience, we provide a simplified newton / continuation methods for periodic orbits. One has just to pass a [`PeriodicOrbitTrapProblem`](@ref).

```julia
opt_po = NewtonPar(tol = 1e-10, verbose = true, maxIter = 20)
	outpo_f, _, flag = @time newton(poTrap(l_hopf + 0.01),
			orbitguess_f, opt_po, normN = norminf,
			callback = (x, f, J, res, iteration, options; kwargs...) -> (println("--> amplitude = ", PALC.amplitude(x, n, M; ratio = 2));true))
flag && printstyled(color=:red, "--> T = ", outpo_f[end], ", amplitude = ", PALC.amplitude(outpo_f, n, M; ratio = 2),"\n")
# plot of the periodic orbit
PALC.plotPeriodicPOTrap(outpo_f, n, M; ratio = 2)
```

and obtain

```julia
 Newton Iterations 
   Iterations      Func-count      f(x)      Linear-Iterations

        0                1     1.5492e-03         0
--> amplitude = 0.48837364060021904
        1                2     1.4482e-02         2
--> amplitude = 0.5444815902638647
        2                3     1.6588e-03         2
--> amplitude = 0.5114497102285744
        3                4     3.6207e-05         2
--> amplitude = 0.5153024440971214
        4                5     5.8333e-07         2
--> amplitude = 0.5152672386060477
        5                6     4.8436e-11         2
  6.710838 seconds (742.76 k allocations: 7.356 GiB, 20.12% gc time)
--> T = 3.0206156984967505, amplitude = 0.5152672386060477
```

and

![](PO-newton.png)

Finally, we can perform continuation of this periodic orbit using the specialized call `continuationPOTrap`

```julia
opt_po = @set opt_po.eigsolver = EigArpack(; tol = 1e-5, v0 = rand(2n))
opts_po_cont = ContinuationPar(dsmin = 0.001, dsmax = 0.03, ds= 0.01, pMax = 3.0, maxSteps = 30, newtonOptions = opt_po, nev = 5, precisionStability = 1e-8, detectBifurcation = 0)
br_po, _ , _= @time continuationPOTrap(poTrap,
			outpo_f, l_hopf + 0.01,
			opts_po_cont;
			verbosity = 2,	plot = true,
			plotSolution = (x;kwargs...) -> heatmap!(reshape(x[1:end-1], 2*n, M)'; ylabel="time", color=:viridis, kwargs...), normC = norminf)
```

to obtain the period of the orbit as function of `l`

![](bru-po-cont.png)


## Deflation for periodic orbit problems
Looking for periodic orbits branching of bifurcation points, it is very useful to use `newton` algorithm with deflation. We thus define a deflation operator (see previous example)

```Julia
deflationOp = DeflationOperator(2.0, (x,y) -> dot(x[1:end-1], y[1:end-1]),1.0, [zero(orbitguess_f)])
```

which allows to find periodic orbits different from `orbitguess_f `. Note that the `dot` product remove the last component, *i.e.* the period of the cycle is not be considered during this particular deflation. We can now use 

```Julia
outpo_f, hist, flag = @time newton(poTrap(l_hopf + 0.01),
			orbitguess_f, opt_po, deflationOp, :BorderedLU; normN = norminf)
```

## Floquet coefficients

A basic method for computing Floquet cofficients based on the eigenvalues of the monodromy operator is available (see [`FloquetQaDTrap`](@ref)). It is precise enough to locate bifurcations. Their computation is triggered like in the case of a regular call to `continuation`:

```Julia
opt_po = @set opt_po.eigsolver = DefaultEig()
opts_po_cont = ContinuationPar(dsmin = 0.001, dsmax = 0.04, ds= -0.01, pMax = 3.0, maxSteps = 200, saveSolEveryNsteps = 1, newtonOptions = opt_po, nev = 5, precisionStability = 1e-6, detectBifurcation = 2)
br_po, _ , _= @time continuationPOTrap(poTrap,
	outpo_f, l_hopf + 0.01,
	opts_po_cont;
	verbosity = 2,	plot = true,
	plotSolution = (x;kwargs...) -> heatmap!(reshape(x[1:end-1], 2*n, M)'; ylabel="time", color=:viridis, kwargs...), normC = norminf)
```

A more complete diagram can be obtained combining the methods (essentially deflation and Floquet) described above. It shows the period of the periodic orbits as function of `l`. See `example/brusselator.jl` for more information.

![](bru-po-cont-3br.png)

!!! danger "Floquet multipliers computation"
    The computation of Floquet multipliers is necessary for the detection of bifurcations of periodic orbits (which is done by analyzing the Floquet exponents obtained from the Floquet multipliers). Hence, the eigensolver needs to compute the eigenvalues with largest modulus (and not with largest real part which is their default behavior). This can be done by changing the option `which = :LM` of the eigensolver. Nevertheless, note that for most implemented eigensolvers in the current Package, the proper option is set when the computation of Floquet multipliers is requested.

!!! tip "Performances"
    This example is clearly not optimized because we wanted to keep it simple. We can use a Matrix-Free version of the functional and preconditioners to speed this up. Floquet multipliers could also be computed in a Matrix-Free manner. See `examples/brusselator.jl` for more efficient methods. See also [Complex Ginzburg-Landau 2d](@ref) for a more advanced example where we introduce those methods.

## Continuation of periodic orbits (Standard Shooting)

> Note that what follows is not really optimized on the `DifferentialEquations.jl` side. Indeed, we do not use automatic differentiation, we do not pass the sparsity pattern,...

We now turn to a different method based on the flow of the Brusselator. To compute this flow (time stepper), we need to be able to solve the differential equation (actually a PDE) associated to the vector field `Fbru`. We will show how to do this with an implicit method `Rodas4P` from `DifferentialEquations.jl`. Note that the user can pass its own time stepper but for convenience, we use the ones in `DifferentialEquations.jl`. More information regarding the shooting method is contained in [Periodic orbits based on the shooting method](@ref). To define the flow, it is better to have an **inplace** version of the vector field:

```julia
function Fbru!(f, x, p)
	@unpack α, β, D1, D2, l = p
	n = div(length(x), 2)
	h = 1.0 / n; h2 = h*h
	c1 = D1 / l^2 / h2
	c2 = D2 / l^2 / h2
	
	u = @view x[1:n]
	v = @view x[n+1:2n]
	
	# Dirichlet boundary conditions
	f[1]   = c1 * (α	  - 2u[1] + u[2] ) + α - (β + 1) * u[1] + f1(u[1], v[1])
	f[end] = c2 * (v[n-1] - 2v[n] + β / α)			 + β * u[n] - f1(u[n], v[n])
	
	f[n]   = c1 * (u[n-1] - 2u[n] +  α   ) + α - (β + 1) * u[n] + f1(u[n], v[n])
	f[n+1] = c2 * (β / α  - 2v[1] + v[2])			 + β * u[1] - f1(u[1], v[1])
	
	for i=2:n-1
		  f[i] = c1 * (u[i-1] - 2u[i] + u[i+1]) + α - (β + 1) * u[i] + f1(u[i], v[i])
		f[n+i] = c2 * (v[i-1] - 2v[i] + v[i+1])			  + β * u[i] - f1(u[i], v[i])
	end
	return f
end

function Fbru(x, p)
	f = similar(x)
	Fbru!(f, x, p)
end
```

We then recompute the locus of the Hopf bifurcation points using the same method as above.


```julia
n = 100

# different parameters to define the Brusselator model and guess for the stationary solution
par_bru = (α = 2., β = 5.45, D1 = 0.008, D2 = 0.004, l = 0.3)
sol0 = vcat(par_bru.α * ones(n), par_bru.β/par_bru.α * ones(n))

eigls = EigArpack(1.1, :LM)
opts_br_eq = ContinuationPar(dsmin = 0.001, dsmax = 0.00615, ds = 0.0061, pMax = 1.9, 
	detectBifurcation = 1, nev = 21, plotEveryNsteps = 50, 
	newtonOptions = NewtonPar(eigsolver = eigls, tol = 1e-9), maxSteps = 1060)

br, _ = @time continuation(
	(x, p) ->    Fbru(x, @set par_bru.l = p),
	(x, p) -> Jbru_sp(x, @set par_bru.l = p),
	sol0, par_bru.l,
	opts_br_eq, verbosity = 0,
	plot = false,
	printSolution = (x, p)->x[div(n,2)], normC = norminf)
```

We need to create a guess for the periodic orbit. We proceed as previously:

```julia
# number of time slices
M = 10

# index of the Hopf point in the branch br
ind_hopf = 1

l_hopf, Th, orbitguess2, hopfpt, vec_hopf = guessFromHopf(br, ind_hopf, 
	opts_br_eq.newtonOptions.eigsolver, M, 22*0.05)

orbitguess_f2 = reduce(hcat, orbitguess2)
orbitguess_f = vcat(vec(orbitguess_f2), Th) |> vec
```

Let us now initiate the Standard Shooting method. To this aim, we need to provide a guess of the periodic orbit at times $T/M_{sh}$ where $T$ is the period of the cycle and $M_{sh}$ is the number of slices along the periodic orbits. If $M_{sh} = 1$, this the Standard Simple Shooting and the Standard Multiple one otherwise. See [`ShootingProblem`](@ref) for more information.

```julia
dM = 3
orbitsection = reduce(vcat, orbitguess2[1:dM:M])
# M_sh = size(orbitsection, 2)

# the last component is an estimate of the period of the cycle.
initpo = vcat(vec(orbitsection), 3.0)
```

Finally, we need to build a problem which encodes the Shooting functional. This done as follows where we first create the time stepper:

```julia
using DifferentialEquations, DiffEqOperators

FOde(f, x, p, t) = Fbru!(f, x, p)

u0 = sol0 .+ 0.01 .* rand(2n)

# parameter close to the Hopf bifurcation point
par_hopf = (@set par_bru.l = l_hopf + 0.01)

# this is the ODE time stepper when used with `solve`
probsundials = ODEProblem(FOde, u0, (0., 1000.), par_hopf)
```

We create the problem:

```julia
# this encodes the functional for the Shooting problem
probSh = p -> ShootingProblem(
	# pass the vector field and parameter (to be passed to the vector field)
	u -> Fbru(u, p), p, 
	
	# we pass the ODEProblem encoding the flow and the time stepper
	probsundials, Rodas4P(),
	
	# we pass M_{sh}
	length(1:dM:M),
	
	# this is the phase condition, you can pass your own function
	x -> PALC.sectionShooting(x, Array(orbitguess_f2[:,1:dM:M]), p, Fbru); 
	
	# these are options passed to the ODE time stepper
	atol = 1e-10, rtol = 1e-8)
```

We are now ready to call `newton` 

```julia
ls = GMRESIterativeSolvers(tol = 1e-7, N = length(initpo), maxiter = 100, verbose = false)
optn_po = NewtonPar(verbose = true, tol = 1e-9,  maxIter = 20, linsolver = ls)
outpo ,_ = @time newton(probSh(par_hopf),
	initpo, optn_po;
	normN = norminf)
plot(initpo[1:end-1], label = "Init guess")
plot!(outpo[1:end-1], label = "sol")
```

which gives (note that we did not have a really nice guess...)

```julia
 Newton Iterations 
   Iterations      Func-count      f(x)      Linear-Iterations

        0                1     1.2983e-01         0
        1                2     3.2046e-01        49
        2                3     5.4818e-02        49
        3                4     1.6409e-02        49
        4                5     8.1653e-03        49
        5                6     3.9391e-04        49
        6                7     2.2715e-07        49
        7                8     8.7713e-11        53
 26.499964 seconds (33.54 M allocations: 4.027 GiB, 3.38% gc time)
```

and

![](brus-sh-new.png)

Note that using Simple Shooting, the convergence is much faster. Indeed, running the code above with `dM = 10` gives:

```julia
Newton Iterations 
   Iterations      Func-count      f(x)      Linear-Iterations

        0                1     3.1251e-03         0
        1                2     4.7046e-03         6
        2                3     1.4468e-03         7
        3                4     2.7600e-03         8
        4                5     2.2756e-03         8
        5                6     7.0376e-03         8
        6                7     5.0430e-03         8
        7                8     1.7595e-02         8
        8                9     2.2254e-03         7
        9               10     2.6376e-04         7
       10               11     1.0260e-05         7
       11               12     1.0955e-06         8
       12               13     6.9387e-08         7
       13               14     4.7182e-09         7
       14               15     2.7187e-11         7
  3.398485 seconds (2.78 M allocations: 342.794 MiB, 1.40% gc time)
```

!!! info "Convergence and speedup"
    The convergence is much worse for the multiple shooting than for the simple one. This is reflected above in the number of linear iterations made during the newton solves. The reason for this is because of the cyclic structure of the jacobian which impedes GMRES from converging fast. This can only be resolved with an improved GMRES which we'll provide in the future.


Finally, we can perform continuation of this periodic orbit using a specialized version of `continuation`:

```julia
# note the eigensolver computes the eigenvalues of the monodromy matrix. Hence
# the dimension of the state space for the eigensolver is 2n
opts_po_cont = ContinuationPar(dsmin = 0.001, dsmax = 0.05, ds= 0.01, pMax = 1.5, 
	maxSteps = 500, newtonOptions = (@set optn_po.tol = 1e-7), nev = 25,
	precisionStability = 1e-8, detectBifurcation = 0)

br_po, _, _= @time continuationPOShooting(
	p -> probSh(@set par_hopf.l = p),
	outpo, par_hopf.l,
	opts_po_cont; verbosity = 2,
	plot = true,
	plotSolution = (x; kwargs...) -> PALC.plotPeriodicShooting!(x[1:end-1], length(1:dM:M); kwargs...),
	printSolution = (u, p) -> u[end], normC = norminf)
```

> We can observe that simple shooting is faster but the Floquet multipliers are less accurate than for multiple shooting. Also, when the solution is very unstable, simple shooting can have spurious branch switching.

![](brus-sh-cont.png)

## Continuation of periodic orbits (Poincaré Shooting)

!!! compat "Using DifferentialEquations.jl (Experimental)"
    This feature currently errors due to multiple events (via callbacks) being registered at the same time. This is being resolved.

We now turn to another Shooting method, namely the Poincaré one. We can provide this method thanks to the unique functionalities of `DifferentialEquations.jl`. More information is provided at [`PoincareShootingProblem`](@ref) and [Periodic orbits based on the shooting method](@ref) but basically, it is a shooting method between Poincaré sections $\Sigma_i$ (along the orbit) defined by hyperplanes. As a consequence, the dimension of the unknowns is $M_{sh}(N-1)$ where $N$ is the dimension of the phase space. Indeed, each time slice lives in an hyperplane $\Sigma_i$. Additionally, the period $T$ is not an unknown of the method but rather a by-product. However, the method requires the time stepper to find when the flow hits an hyperplane $\Sigma_i$, something called **event detection**.


We show how to use this method, the code is very similar to the case of the Standard Shooting. We first define the functional for Poincaré Shooting Problem

```julia
M = size(sol, 2)
dM = 15

# vectors to define the hyperplanes Sigma_i
normals = [Fbru(sol[:,ii], par_hopf) for ii = 1:dM:M]
centers = [sol[:,ii] for ii = 1:dM:M]

# functional to hold the Poincare Shooting Problem
probHPsh = p -> PoincareShootingProblem(
	# vector field and parameter
	u -> Fbru(u, p), p, 
	
	# ODEProblem, ODE solver used to compute the flow
	probsundials, Rodas4P(), 
	
	# parameters for the Poincaré sections
	normals, centers; 
	
	# Parameters passed to the ODE solver
	atol = 1e-10, rtol = 1e-9)
```

Let us now compute an initial guess for the periodic orbit which must live in the hyperplanes $\Sigma_i$. Fortunately, we provide projections on these hyperplanes.

```julia
# variable to hold the initial guess
initpo_bar = zeros(size(sol,1)-1, length(normals))

# projection of the initial guess on the hyperplanes. We assume that the centers[ii]
# form the periodic orbit initial guess.
for ii=1:length(normals)
	initpo_bar[:,ii] .= PALC.R(hyper, centers[ii], ii)
end
```

We can now call `newton` to refine the initial guess

```julia
ls = GMRES_IterativeSolvers(tol = 1e-5, N = length(vec(initpo_bar)), verbose = false)
optn = NewtonPar(verbose = true, tol = 1e-7,  maxIter = 140, linsolver = ls)
outpo_psh, _ = @time newton(x -> probHPsh(par_hopf)(x),
	x -> (dx -> probHPsh(par_hopf)(x, dx)),
	vec(initpo_bar), optn; normN = norminf)
```