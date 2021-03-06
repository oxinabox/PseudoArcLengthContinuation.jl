# Detection of bifurcation points

The bifurcations are detected during a call to `br, _ = continuation(F, J, u0, p0::Real, contParams::ContinuationPar;kwargs...)` by turning on the following flags:

- `contParams.detectBifurcation = 1` which also turns on `contParams.computeEigenValues = true`

The located bifurcation points are then returned in `br.bifpoint`. 

!!! danger 
    Note that these points are only approximate **bifurcation** points when `detectBifurcation = 1`. If `detectBifurcation = 2`, a bisection algorithm is used to locate them more precisely. They can also be refined using the methods described here after.

!!! warning "Large scale computations"
    The user must specify the number of eigenvalues to be computed (like `nev = 10`) in the parameters `::ContinuationPar` passed to `continuation`. Note that `nev` is automatically incremented whenever a bifurcation point is detected [^1]. Also, there is an option in `::ContinuationPar` to save (or not) the eigenvectors. This can be useful in memory limited environments (like on GPUs).
    
[^1] In this case, the Krylov dimension is not increased because the eigensolver could be a direct solver. You might want to increase this dimension using the callbacks in [`continuation`](@ref). 

## List of detected bifurcation points
|Bifurcation|index used|
|---|---|
| Fold | fold |
| Hopf | hopf |
| Branch point (single eigenvalue stability change) | bp |
| Neimark-Sacker | ns |
| Period doubling | pd |
| Not documented | nd |

## Eigensolver

The user must provide an eigensolver by setting `NewtonOptions.eigsolver` where `NewtonOptions` is located in the parameter `::ContinuationPar` passed to continuation. See [`NewtonPar`](@ref) and [`ContinuationPar`](@ref) for more information on the composite type of the options passed to `newton` and `continuation`.

The eigensolver is highly problem dependent and this is why the user should implement / parametrize its own eigensolver through the abstract type `AbstractEigenSolver` or select one among [List of implemented eigen solvers](@ref).

## Fold bifurcation
The detection of **Fold** point is done by monitoring  the monotonicity of the parameter.

The detection is triggered by setting `detectFold = true` in the parameter `::ContinuationPar` passed to `continuation`. When a **Fold** is detected on a branch `br`, a point is added to `br.bifpoint` allowing for later refinement using the function `newtonFold`.

## Generic bifurcation

By this we mean a change in the dimension of the Jacobian kernel. The detection of Branch point is done by analysis of the spectrum of the Jacobian.

The detection is triggered by setting `detectBifurcation = true` in the parameter `::ContinuationPar` passed to `continuation`. 

## Hopf bifurcation

The detection of Branch point is done by analysis of the spectrum of the Jacobian.

The detection is triggered by setting `detectBifurcation = true` in the parameter `::ContinuationPar` passed to `continuation`. When a **Hopf point** is detected, a point is added to `br.bifpoint` allowing for later refinement using the function `newtonHopf`.

```@docs
guessFromHopf(br, ind_hopf, eigsolver::AbstractEigenSolver, M, amplitude; phase = 0)
```

## Bifurcations of periodic orbits
The detection is triggered by setting `detectBifurcation = true` in the parameter `::ContinuationPar` passed to `continuation`. The detection of bifurcation points is done by analysis of the spectrum of the Monodromy matrix composed of the Floquet multipliers. The following bifurcations are currently detected:

- Fold of periodic orbit
- Neimark-Sacker 
- Period doubling

!!! danger "Floquet multipliers computation"
    The computation of Floquet multipliers is necessary for the detection of bifurcations of periodic orbits (which is done by analyzing the Floquet exponents obtained from the Floquet multipliers). Hence, the eigensolver needs to compute the eigenvalues with largest modulus (and not with largest real part which is their default behavior). This can be done by changing the option `which = :LM` of the eigensolver. Nevertheless, note that for most implemented eigensolvers in the current Package, the proper option is set.   