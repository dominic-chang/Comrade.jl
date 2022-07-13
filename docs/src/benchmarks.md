# Benchmarks

`Comrade` was partially designed with performance in mind. Solving imaging inverse problem is traditionally very computational expensive, especially when using Bayesian inference. However, `Comrade` also was designed to allow a user to easily modify the image model and refit the data with few changes to any script or notebook. 

To benchmark `Comrade` we will compare it to two of the most common modeling or imaging packages within the EHT:

- [eht-imaging](https://github.com/achael/eht-imaging/)
- [Themis](https://iopscience.iop.org/article/10.3847/1538-4357/ab91a4)

`eht-imaging`[^1] or `ehtim` is a Python package that is widely used within the EHT for its imaging and modeling interfaces. It is easy to use and is reasonably fast due, however, this comes with the caveat that the user must specify each model separately, and provide handwritten gradient definitions. Additionally, `ehtim`'s modeling interface is rather new, since it is mostly used to produce images using a method called *regularized maximum likelihood*, which is similar to `Comrade`'s approach except it only characterizes the images using the maximum likelihood estimate.

Themis is a C++ package that is focused on providing Bayesian estimates of the image structure. In fact, `Comrade` took some design queue's from `Themis`. However, `Themis` is quite challenging to use and requires a high level of knowledge from its users, requiring them to understand makefile, C++, and the MPI standard. Additionally, Themis was designed to solely work with distributed computing systems. Unfortunately, as of the writing of this document, Themis is still closed source software and it only available to members of the EHT.

## Benchmarking Problem

For our benchmarking problem we analyze a problem very similar to the problem explained in [Making an Image of a Black Hole](@ref). Namely we will consider fitting the 2017 M87 April 6 data using an m-ring and a single Gaussian component. To see the code we used for `Comrade` and `eht-imaging` please see the end of this page.


# Results

All tests were run using the following Julia system

```
Julia Version 1.7.3
Python Version 3.10.5
Commit 742b9abb4d (2022-05-06 12:58 UTC)
Platform Info:
  OS: Linux (x86_64-pc-linux-gnu)
  CPU: 11th Gen Intel(R) Core(TM) i7-1185G7 @ 3.00GHz
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-12.0.1 (ORCJIT, tigerlake)
```


Our benchmark results are the following:

| | Comrade (micro sec) | eht-imaging (micro sec) | Themis (micro sec)|
|---|---|---|---|
| posterior eval (min) | 31  | 445  | 55  |
| posterior eval (mean) | 36  | 476  | 60  |
| grad posterior eval (min) |  105 (ForwardDiff) | 1898  | 1809  |
| grad posterior eval (mean) |  119 (ForwardDiff) | 1971 |  1866  |

Therefore, for this test we found that `Comrade` was the fastest method in all tests. For the posterior evaluation we found that Comrade is > 10x faster than `eht-imaging`, and 2x faster then `Themis`. For gradient evaluations we have `Comrade` is > 15x faster than both `eht-imaging` and `Themis`.

[^1]: Chael A, et al. *Inteferometric Imaging Directly with Closure Phases* 2018 ApJ 857 1 arXiv:1803/07088

## Code

### Julia Code

```julia
using Comrade
using Distributions
using BenchmarkTools

load_ehtim()
# To download the data visit https://doi.org/10.25739/g85n-f134
obs = ehtim.obsdata.load_uvfits("SR1_M87_2017_096_lo_hops_netcal_StokesI.uvfits")
obs.add_scans()
obs = obs.avg_coherent(0.0, scan_avg=true)
amp = extract_amp(obs)
lklhd = RadioLikelihood(amp)

function model(θ)
    (;rad, wid, a, b, f, sig, asy, pa, x, y) = θ
    ring = f*smoothed(stretched(MRing((a,), (b,)), μas2rad(rad), μas2rad(rad)), μas2rad(wid))
    g = (1-f)*shifted(rotated(stretched(Gaussian(), μas2rad(sig)*asy, μas2rad(sig)), pa), μas2rad(x), μas2rad(y))
    return ring + g
end
prior = (
          rad = Uniform(10.0, 30.0),
          wid = Uniform(1.0, 10.0),
          a = Uniform(-0.5, 0.5), b = Uniform(-0.5, 0.5),
          f = Uniform(0.0, 1.0),
          sig = Uniform((1.0), (60.0)),
          asy = Uniform(0.0, 0.9),
          pa = Uniform(0.0, 1π),
          x = Uniform(-(80.0), (80.0)),
          y = Uniform(-(80.0), (80.0))
        )
# Now form the posterior
post = Posterior(lklhd, prior, model)

# transform to parameter space
tpost = asflat(post)

# We will use this random point in all tests
θ = (f=0.8, rad= 22.0, wid= 3.0, a = 0.0, b = 0.15, sig = 20.0, asy=0.2, pa=π/2, x=20.0, y=20.0)

# Transform to the unconstrained space
x0 = transform(tpost, θ)

# Lets benchmark the posterior evaluation
ℓ = logdensityof(tpost)
@benchmark ℓ($x0)

# Now we benchmark the gradient
gℓ = ForwardDiff.gradient(ℓ, x0)
@benchmark gℓ($x0)
```

### Python Code

```julia
using BenchmarkTools

load_ehtim()
# To download the data visit https://doi.org/10.25739/g85n-f134
obs = ehtim.obsdata.load_uvfits(joinpath(@__DIR__, "SR1_M87_2017_096_lo_hops_netcal_StokesI.uvfits"))
obs.add_scans()
obs = obs.avg_coherent(0.0, scan_avg=true)



meh = ehtim.model.Model()
meh = meh.add_thick_mring(F0=θ.f,
                    d=2*μas2rad(θ.rad),
                    alpha=2*sqrt(2*log(2))*μas2rad(θ.wid),
                    x0 = 0.0,
                    y0 = 0.0,
                    beta_list=[0.0+θ.b]
                    )
meh = meh.add_gauss(F0=1-θ.f,
                    FWHM_maj=2*sqrt(2*log(2))*μas2rad(θ.sig),
                    FWHM_min=2*sqrt(2*log(2))*μas2rad(θ.sig)*θ.asy,
                    PA = θ.pa,
                    x0 = μas2rad(20.0),
                    y0 = μas2rad(20.0)
                    )

preh = meh.default_prior()
preh[1]["F0"] = Dict("prior_type"=>"flat", "min"=>0.0, "max"=>1.0)
preh[1]["d"] = Dict("prior_type"=>"flat", "min"=>μas2rad(20.0), "max"=>μas2rad(60.0))
preh[1]["alpha"] = Dict("prior_type"=>"flat", "min"=>μas2rad(2.0), "max"=>μas2rad(25.0))
preh[1]["x0"] = Dict("prior_type"=>"fixed")
preh[1]["y0"] = Dict("prior_type"=>"fixed")

preh[2]["F0"] = Dict("prior_type"=>"flat", "min"=>0.0, "max"=>1.0)
preh[2]["FWHM_maj"] = Dict("prior_type"=>"flat", "min"=>μas2rad(2.0), "max"=>μas2rad(120.0))
preh[2]["FWHM_min"] = Dict("prior_type"=>"flat", "min"=>μas2rad(2.0), "max"=>μas2rad(120.0))
preh[2]["x0"] = Dict("prior_type"=>"flat", "min"=>-μas2rad(40.0), "max"=>μas2rad(40.0))
preh[2]["y0"] = Dict("prior_type"=>"flat", "min"=>-μas2rad(40.0), "max"=>μas2rad(40.0))
preh[2]["PA"] = Dict("prior_type"=>"flat", "min"=>-1π, "max"=>1π)

# Now get the posterior function
obj_func = 


# Lets benchmark the posterior evaluation
ℓ = logdensityof(tpost)
@benchmark ℓ($x0)

# Now we benchmark the gradient
gℓ = ForwardDiff.gradient(ℓ, x0)
@benchmark gℓ($x0)
```