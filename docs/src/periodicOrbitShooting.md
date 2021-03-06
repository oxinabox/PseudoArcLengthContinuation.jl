# Periodic orbits based on the shooting method

A shooting algorithm is provided which is called either *Simple Shooting (SS)* if a single section is used and *Multiple Shooting (MS)* otherwise. 

!!! unknown "References"
    For the exposition, we follow the PhD thesis **Numerical Bifurcation Analysis of Periodic Solutions of Partial Differential Equations**, *Lust, Kurt*, 1997. 

We aim at finding periodic orbits for the Cauchy problem 

$$\tag{1} \frac{d x}{d t}=f(x)$$ 

and we write $\phi^t(x_0)$ the associated flow (or semigroup of solutions).

!!! tip "Tip about convenience functions"
    For convenience, we provide some functions `plotPeriodicShooting` for plotting, `getAmplitude` (resp. `getMaximum`) for getting the amplitude (resp. maximum) of the solution encoded by a shooting problem. See tutorials for example of use.

## Standard Shooting
### Simple shooting
A periodic orbit is found when we have a couple $(x, T)$ such that $\phi^T(x) = x$ and the trajectory is non constant. Therefore, we want to solve the equations $G(x,T)=0$ given by

$$\tag{SS}
\begin{array}{l}{\phi^T(x, T)-x=0} \\ {s(x,T)=0}\end{array}.$$

The section $s(x,T)=0$ is a phase condition to remove the indeterminacy of the point on the limit cycle.

### Multiple shooting
This case is similar to the previous one but more sections are used. To this end, we partition the unit interval with $M+1$ points
$$0=s_{0}<s_{1}<\cdots<s_{m-1}<s_{m}=1$$ and consider the equations $G(x_1,\cdots,x_M,T)=0$

$$\begin{aligned} 
\phi^{\delta s_1T}(x_{1})-x_{2} &=0 \\ 
\phi^{\delta s_2T}(x_{2})-x_{3} &=0 \\ & \vdots \\ 
\phi^{\delta s_{m-1}T}(x_{m-1})-x_{m} &=0 \\ 
\phi^{\delta s_mT}(x_{m})-x_{1} &=0 \\ s(x_{1}, x_{2}, \cdots, x_{m}, T) &=0. \end{aligned}$$

where $\delta s_i:=s_{i+1}-s_i$. The Jacobian of the system of equations *w.r.t.* $(x,T)$ is given by 

$$\mathcal{J}=\left(\begin{array}{cc}{\mathcal J_c} & {\partial_TG} \\ {\star} & {d}\end{array}\right)$$

where the cyclic matrix $\mathcal J_c$ is

$$\mathcal J_c := 
\left(\begin{array}{ccccc}
{M_{1}} & {-I} & {} & {} \\ 
{} & {M_{2}} & {-I} & {}\\ 
{} & {} & {\ddots} & {-I}\\ 
{-I} & {} & {} & {M_{m}}\\ 
\end{array}\right)$$

and $M_i=\partial_x\phi^{\delta s_i T}(x_i)$.

### Encoding of the functional

The functional is encoded in the composite type [`ShootingProblem`](@ref). In particular, the user can pass its own time stepper or he can use the different ODE solvers in  [DifferentialEquations.jl](https://github.com/JuliaDiffEq/DifferentialEquations.jl) which makes it very easy to choose a solver tailored for the a specific problem. See the link [`ShootingProblem`](@ref) for more information, in particular on how to access the underlying functional, its jacobian...

## Poincaré shooting
The idea is to look for periodic orbits solutions of (1) using hyperplanes $\Sigma_i$ for $i=1,\cdots,M$ which intersect transversally an initial periodic orbit guess. We write $\Pi_i$, the Poincaré return map on $\Sigma_i$ and look for solutions of the following problem:

$$\begin{aligned} 
\Pi_1(x_{1})-x_{2} &=0 \\ 
\Pi_{2}(x_{2})-x_{3} &=0 \\ & \vdots \\ 
\Pi_m(x_{m})-x_{1} &=0. 
\end{aligned}$$

> The algorithm is based on the one described in **Newton–Krylov Continuation of Periodic Orbits for Navier–Stokes Flows.**, Sánchez, J., M. Net, B. Garcı́a-Archilla, and C. Simó (2004) and **Matrix-Free Continuation of Limit Cycles for Bifurcation Analysis of Large Thermoacoustic Systems.** Waugh, Iain, Simon Illingworth, and Matthew Juniper (2013). The main idea of the algorithm is to use the fact that the problem is $(N-1)\cdot M$ dimensional if $x_i\in\mathbb R^N$ because each $x_i$ lives in $\Sigma_i$.


### Encoding of the functional

The functional is encoded in the composite type [`PoincareShootingProblem`](@ref). In particular, the user can pass its own time stepper or he can use the different ODE solvers in  [DifferentialEquations.jl](https://github.com/JuliaDiffEq/DifferentialEquations.jl) which makes it very easy to choose a tailored solver: the partial Poincaré return maps are implemented using **callbacks**. See the link [`PoincareShootingProblem`](@ref) for more information, in particular on how to access the underlying functional, its jacobian...

## Floquet multipliers computation

These are the eigenvalues of $M_m\cdots M_1$.

> Unlike the case with Finite differences, the matrices $M_i$ are not sparse.

A **not very precise** algorithm for computing the Floquet multipliers is provided. The method, dubbed Quick and Dirty (QaD), is not numerically very precise for large / small Floquet exponents. It allows, nevertheless, to detect bifurcations of periodic orbits. It seems to work reasonably well for the tutorials considered here. For more information, have a look at [`FloquetQaDShooting`](@ref).

!!! note "Algorithm"
    A more precise algorithm, based on the periodic Schur decomposition will be implemented in the future.

## Computation with `newton`

We provide a simplified call to `newton` to locate the periodic orbit. Have a look at the tutorial [Continuation of periodic orbits (Standard Shooting)](@ref) for a simple example on how to use the above methods. 

The docs for this specific `newton` are located at [Newton for Periodic Orbits](@ref).

## Computation with `newton` and deflation

We also provide a simplified call to `newton` to locate the periodic orbit with a deflation operator:

```
newton(prob::T, orbitguess, options::NewtonPar; kwargs...) where {T <: AbstractShootingProblem}
```

and

```
newton(prob::Tpb, orbitguess, options::NewtonPar, defOp::DeflationOperator{T, Tf, vectype}; kwargs...) where {Tpb <: AbstractShootingProblem, T, Tf, vectype}
```

## Continuation

Have a look at the [Continuation of periodic orbits (Standard Shooting)](@ref) example for the Brusselator.

```@docs
continuationPOShooting
```