using Pkg; Pkg.activate(@__DIR__)
using Comrade
using Distributions
using Pathfinder
using AdvancedHMC
using Plots
using TupleVectors
using StatsBase

# load eht-imaging we use this to load eht data
load_ehtim()
# To download the data visit https://doi.org/10.25739/g85n-f134
obs = ehtim.obsdata.load_uvfits(joinpath(@__DIR__, "SR1_M87_2017_096_lo_hops_netcal_StokesI.uvfits"))
obs.add_scans()
# kill 0-baselines since we don't care about
# large scale flux and make scan-average data
obs = obs.flag_uvdist(uv_min=0.1e9).avg_coherent(0.0, scan_avg=true)
# extract log closure amplitudes and closure phases
dlcamp = extract_lcamp(obs)
dcphase = extract_cphase(obs; cutmin)
# form the likelihood
lklhd = RadioLikelihood(dlcamp, dcphase)
# build the model here we fit a ring with a azimuthal
#brightness variation and a Gaussian
function model(θ)
  (;rad, wid, a, b, f, sig, asy, pa, x, y) = θ
  ring = f*smoothed(stretched(MRing((a,), (b,)), rad, rad), wid)
  g = (1-f)*shifted(rotated(stretched(Gaussian(), sig*asy, sig), pa), x, y)
  return ring + g
end
# define the priors
prior = (
          rad = Uniform(μas2rad(10.0), μas2rad(30.0)),
          wid = Uniform(μas2rad(1.0), μas2rad(10.0)),
          a = Uniform(-0.5, 0.5), b = Uniform(-0.5, 0.5),
          f = Uniform(0.0, 1.0),
          sig = Uniform(μas2rad(1.0), μas2rad(40.0)),
          asy = Uniform(0.0, 0.75),
          pa = Uniform(0.0, 1π),
          x = Uniform(-μas2rad(80.0), μas2rad(80.0)),
          y = Uniform(-μas2rad(80.0), μas2rad(80.0))
        )
# Now form the posterior
post = Posterior(lklhd, prior, model)
# We will use HMC to sample the posterior.
# First to reduce burn in we use pathfinder
using Dynesty
chain, stats = sample(post, NestedSampler(dimension(post)))
echain = sample(chain, Weights(stats.weights), 10_000)|> TupleVector

residual(model(chain[end]), dlcamp)
plot(model(echain[rand(eachindex(echain))]), xlims=(-50.0,50.0), ylims=(-50.0,50.0))

q, phi, _ = multipathfinder(post, 100)
# now we sample using hmc
metric = DiagEuclideanMetric(dimension(post))
chain, stats = sample(post, HMC(;metric), 2000; nadapts=1000, init_params=chain[end])
# plot a draw from the posterior
plot(model(chain[rand(1:length(chain))]), xlims=(-80.0, 80.0), ylims=(-80.0,80.0), colorbar=nothing)
