```@meta
CurrentModule = Comrade
```

# Comrade

Comrade is a **differentiable** modular modeling framework for use with very long baseline interferometry.
The goal is to allow the user to easily combine and modify a set of *primitive* models
to construct complicated source structures. These primitives themselves do not have to 
be simple. Comrade itself does not Bayesian inference or optimization itself. Instead it
creates all the components needed, i.e. a image/visibility model, some simple likelihoods, and telescope corruption effects (still to be implemented).

To use perform inferences on data you can then hook into the vast array of different 
modeling and optimization packages in Julia. There are some small examples packages
defining these interface such as [ComradeSoss.jl](https://github.com/ptiede/ComradeSoss.jl) 
which combines Comrade with `Soss` a probabilistic programming language. Other interfaces
to e.g. [Turing](https://turing.ml/stable/), [BAT](https://github.com/bat/BAT.jl) are 
planned.

## Requirements

The minimum Julia version we require is 1.6, which is the current LTS release. In the 
future we may increase this as Julia advances.

```@contents
Pages = [
    "index.md",
    "getting_started.md",
    "model_interface.md",
    "api.md"
]
```
