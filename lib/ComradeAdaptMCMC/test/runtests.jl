using Comrade, ComradeAdaptMCMC, Distributions
using Test

load_ehtim()
include(joinpath(@__DIR__, "../../../test/test_util.jl"))

@testset "ComradeAdaptMCMC.jl" begin

    m, vis, amp, lcamp, cphase = load_data()
    prior = test_prior()
    lklhd = RadioLikelihood(lcamp, cphase)
    post = Posterior(lklhd, prior, test_model)
    a1 = AdaptMCMC(ntemp=5)
    a2 = AdaptMCMC(ntemp=5, all_levels=true)

    x0 = prior_sample(post)

    chain, stats = sample(post, a1, 100_000; thin=5)
    chain, stats = sample(post, a2, 100_000; thin=5)
    chain, stats = sample(post, a1, 100_000; thin=5, init_params=x0)

    cpost = ascube(post)
    l0 = logdensityof(cpost, Comrade.HypercubeTransform.inverse(cpost, x0))
    @test l0 < mean(stats.logl[1])
end