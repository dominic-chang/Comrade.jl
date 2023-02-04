# # Stokes I simultaneous Image and Instrument Modeling

# In this tutorial we will create a preliminary reconstruction of the 2017 M87 data on April 6
# by simultaneously creating and image and model for the instrument. By instrument model we
# mean something akin to self-calibration in traditional VLBI imaging terminology. However,
# unlike traditional self-cal we will at each point in our parameter space effectively explore
# the possible self-cal solutions. This will allow us to constrain and marginalize over the
# instrument effects such as time variable gains.

# ## Introduction to Complex Visibility Fitting


using Pkg; Pkg.activate(@__DIR__)

# To get started we will load Comrade
using Comrade

# ## Load the Data
# To download the data visit https://doi.org/10.25739/g85n-f134
# To load the eht-imaging obsdata object we do:
obs = load_ehtim_uvfits(joinpath(@__DIR__, "SR1_M87_2017_096_hi_hops_netcal_StokesI.uvfits"))

# Now we do some minor preprocessing:
#   - Scan average the data since the data have been preprocessed so that the gain phases
#      coherent.
#   - Add 1% systematic noise to deal with calibration issues that cause 1% non-closing errors.
obs = scan_average(obs).add_fractional_noise(0.015).flag_uvdist(uv_min=0.1e9)

# Now we extract our complex visibilities.
dvis = extract_vis(obs)

# ##Building the Model/Posterior

# Now we must build our intensity/visibility model. That is, the model that takes in a
# named tuple of parameters and perhaps some metadata required to construct the model.
# For our model we will be using a raster or `ContinuousImage` for our image model.
# Unlike other imaging examples
# (e.g., [Imaging a Black Hole using only Closure Quantities](@ref)) we also need to include
# a model for the intrument, i.e., gains as well. The gains will be broken into two components
#   - Gain amplitudes which are typically known to 10-20% except for LMT which has large issues
#   - Gain phases which are more difficult to constrain and can shift rapidly.
# The model is given below:

function model(θ, metadata)
    (;c, lgamp, gphase) = θ
    (; grid, cache) = metadata
    # Construct the image model we fix the flux to 0.6 Jy in this case
    img = IntensityMap(0.6*c, grid)
    cimg = ContinuousImage(img,cache)
    # Now form our instrument model
    j = @fastmath jonesStokes(exp.(lgamp).*cis.(gphase), gcache)
    # Now return the total model
    return JonesModel(j, cimg)
end

# The model construction is very similar to [`Imaging a Black Hole using only Closure Quantities`](@ref),
# except we fix the compact flux to 0.6 Jy for simplicity in this run. For more information about the image model
# please read the closure only example. Let's discuss the instrument model `j`.
# Thanks the the EHT pre-calibration the gains are stable over scans to we just need to
# model the gains on a scan-by-scan basis. To form the instrument model we need our
#   1. Our (log) gain amplitudes and phases given below by `lgamp` and `gphase`
#   2. Our function or cache that maps the gains from a list to the stations they impact `gcache`
#   3. The set of `JonesPairs` produced by `jonesStokes`
# These three ingredients then specify our instrument model `j`. The instrument model can then be
# combined with our image model `cimg` to form the total `JonesModel`.




# Now 'et's set up our image model. The EHT's nominal resolution is 20-25 μas. Additionally,
# the EHT is not very sensitive to larger field of views, typically 60-80 μas is enough to
# describe the compact flux of M87. Given this we only need to use a small number of pixels
# to describe our image.
npix = 24
fovxy = μas2rad(67.5)

# Now let's form our cache's. First, we have our usual image cache which is needed to numerically
# compute the visibilities.
grid = imagepixels(fovxy, fovxy, npix, npix)
buffer = IntensityMap(zeros(size(grid)), grid)
cache = create_cache(DFTAlg(dvis), buffer, BSplinePulse{3}())
# Second, we now construct our instrument model cache. This tells us how to map from the gains
# to the model visibilities. However, to construct this map we also need to specify the observation
# segmentation over which we expect the gains to change. This is specified in the second argument
# to `JonesCache`, and currently there are two options
#   - `ScanSeg()`: which forces the corruptions to only change from scan-to-scan
#   - `TrackSeg()`: which forces the corruptions to be constant over a night's observation
# For this work we use the scan segmentation since that is roughly the timescale we expect the
# complex gains to vary.
gcache = JonesCache(dvis, ScanSeg())

# Now we can form our metadata we need to fully define our model.
metadata = (;grid, cache, gcache)

# Moving onto our prior we first focus on the instrument model priors.
# Each station requires its own prior on both the amplitudes and phases.
# For the amplitudes
# we assume that the gains are aprior well calibrated around unit gains (or 0 log gain amplitudes)
# which corresponds to no instrument corruption. The gain dispersion is then set to 10% for
# all stations except LMT representing that from scan-to-scan we expect 10% deviations. For LMT
# we let the prior expand to 100% due to the known pointing issues LMT had in 2017.
using Distributions
using DistributionsAD
distamp = (AA = Normal(0.0, 0.1),
           AP = Normal(0.0, 0.1),
           LM = Normal(0.0, 1.0),
           AZ = Normal(0.0, 0.1),
           JC = Normal(0.0, 0.1),
           PV = Normal(0.0, 0.1),
           SM = Normal(0.0, 0.1),
           )

# For the phases we assume that the gains are effectively scrambled by the atmosphere.
# Since the gain phases are periodic we also use a von Mises priors for all stations with
# essentially a flat distribution.
using VLBIImagePriors
distphase = (AA = DiagonalVonMises(0.0, inv(π^2)),
             AP = DiagonalVonMises(0.0, inv(π^2)),
             LM = DiagonalVonMises(0.0, inv(π^2)),
             AZ = DiagonalVonMises(0.0, inv(π^2)),
             JC = DiagonalVonMises(0.0, inv(π^2)),
             PV = DiagonalVonMises(0.0, inv(π^2)),
             SM = DiagonalVonMises(0.0, inv(π^2)),
           )

# We can now form our model parameter priors. Like our other imaging examples we use a
# Dirichlet prior for our image pixels. For the log gain amplitudes we use the `CalPrior`
# which automatically constructs the prior for the given jones cache `gcache`.
# For the gain phases we also use `CalPrior` but we include a third argument which specifies
# the prior to be used for the reference station for each scan. This is typically a very tight
# prior that forces the phase to zero. This is required to remove a trivial degeneracy, where the total gain phase
# for all visibilities in a scan are invariant to a constant phase being added to all station gains.
(;X, Y) = grid
prior = (
        # c = CenteredImage(X, Y, μas2rad(5.0), ImageDirichlet(1.0, npix, npix)),
        c = ImageDirichlet(1.0, npix, npix),
        lgamp = CalPrior(distamp, gcache),
        gphase = CalPrior(distphase, gcache, DiagonalVonMises(0.0, 1e8))
        )



lklhd = RadioLikelihood(model, metadata, dvis)
post = Posterior(lklhd, prior)

# ## Reconstructing the Image and Instrument Effects

# To sample from this posterior it is convienent to first move from our constrained paramter space
# to a unconstrained one (i.e., the support of the transformed posterior is (-∞, ∞)). This is
# done using the `asflat` function.
tpost = asflat(post)

# We can now also find the dimension of our posterior, or the number of parameters we are going to sample.
# !!! Warning
#    This can often be different from what you would expect. This is especially true when using
#    angular variables where to make sampling easier we often artifically increase the dimension
#    of the parameter space.
ndim = dimension(tpost)

# Now we optimize. Unlike other imaging examples here we move straight to gradient optimizers
# due to the higher dimension of the space.
using ComradeOptimization
using OptimizationOptimJL
using Zygote
f = OptimizationFunction(tpost, Optimization.AutoZygote())
prob = OptimizationProblem(f, rand(ndim) .- 0.5, nothing)
ℓ = logdensityof(tpost)
sol = solve(prob, LBFGS(), maxiters=10_000, callback=((x,p)->(@info ℓ(x);false)), g_tol=1e-1)

# !!! Warning
#    Fitting gains tends to be very difficult, meaning that optimization can take a lot longer.
#    The upside is that we usually get nicer images.

# Before we analyze our solution we first need to transform back to parameter space.
xopt = transform(tpost, sol)

# First we will evaluate our fit by plotting the residuals
using Plots
residual(model(xopt, metadata), dvis)

# These look reasonable, although maybe there is some minor overfitting. This could probably be
# improved in a few ways, but that is beyond the goal of this quick tutorial.
# Plotting the image we see that we a much clearner version of the closure only image from
# [`Imaging a Black Hole using only Closure Quantities`](@ref).
img = intensitymap(model(xopt, metadata), fovxy, fovxy, 128, 128)
plot(img, title="MAP Image")


# Now because we also fit the instrument model we can also inspect their parameters.
# To do this `Comrade` provides a `caltable` function that converts the flattened gain parameters
# to a tabular format based on the time and its segmentation.
gt = Comrade.caltable(gcache, xopt.gphase)
plot(gt, layout=(3,3), size=(600,500))
# The gain phases are pretty random, although much of this is due to us picking a random
# reference station for each scan.

# Moving onto the gain amplitudes we see that most of the gain variation is within 10% as expected
# except LMT which is having massive variations.
gt = Comrade.caltable(gcache, exp.(xopt.lgamp))
plot(gt, layout=(3,3), size=(600,500))


# To sample from the posterior we will use HMC and more specifically the NUTS algorithm. For information about NUTS
# see Michael Betancourt's [notes](https://arxiv.org/abs/1701.02434).
# !!! note
#    For our `metric` we use a diagonal matrix due to easier tuning.
# However, due to the need to sample a large number of gain parameters constructing the posterior
# is rather difficult here. Therefore, for this tutorial we will only do a very quick run, and any posterior
# inferences should be appropriately skeptical.
using ComradeAHMC
metric = DiagEuclideanMetric(ndim)
chain, stats = sample(post, AHMC(;metric, autodiff=AD.ZygoteBackend()), 30_000; nadapts=25_000, init_params=chain[end])

# Now plot the gain table with error bars
gphase  = hcat(chain.gphase...)
mgphase = mean(gphase, dims=2)
sgphase = std(gphase, dims=2)

gamp  = exp.(hcat(chain.lgamp...))
mgamp = mean(gamp, dims=2)
sgamp = std(gamp, dims=2)


using Measurements
gmeas_am = measurement.(mgamp, sgamp)
ctable_am = caltable(gcache, vec(gmeas_am))
plot(ctable_am, layout=(3,3), size=(600,500))

gmeas_ph = measurement.(mgphase, sgphase)
ctable_ph = caltable(gcache, vec(gmeas_ph))
plot(ctable_ph, layout=(3,3), size=(600,500))


# This takes about 1.75 hours on my laptop. Which isn't bad for a 575 dimensional model!

# Plot the mean image and standard deviation image
using StatsBase
samples = model.(sample(chain, 50), Ref(metadata))
imgs = intensitymap.(samples, fovxy, fovxy, 128,  128)

mimg, simg = mean_and_std(imgs)

p1 = plot(mimg, title="Mean", clims=(0.0, maximum(mimg)))
p2 = plot(simg,  title="Std. Dev.", clims=(0.0, maximum(mimg)))
p3 = plot(imgs[1],  title="Draw 1", clims = (0.0, maximum(mimg)))
p4 = plot(imgs[2],  title="Draw 2", clims = (0.0, maximum(mimg)))

plot(p1,p2,p3,p4, layout=(2,2), size=(800,800))

# Computing information
# ```
# Julia Version 1.7.3
# Commit 742b9abb4d (2022-05-06 12:58 UTC)
# Platform Info:
#   OS: Linux (x86_64-pc-linux-gnu)
#   CPU: 11th Gen Intel(R) Core(TM) i7-1185G7 @ 3.00GHz
#   WORD_SIZE: 64
#   LIBM: libopenlibm
#   LLVM: libLLVM-12.0.1 (ORCJIT, tigerlake)
# ```
