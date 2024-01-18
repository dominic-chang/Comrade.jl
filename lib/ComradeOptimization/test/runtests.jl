using Comrade, ComradeOptimization
using Pyehtim, OptimizationOptimJL, Distributions, VLBIImagePriors
using Zygote
using Test

include(joinpath(@__DIR__, "../../../test/test_util.jl"))

@testset "ComradeOptimization.jl" begin
    m, vis, amp, lcamp, cphase = load_data()
    prior = test_prior()
    lklhd = RadioLikelihood(test_model, lcamp, cphase)
    post = Posterior(lklhd, prior)

    tpost = asflat(post)
    f = OptimizationFunction(tpost, Optimization.AutoZygote())
    x0 = [  0.21073019358414513,
            0.13780160840617572,
            0.39730883437243103,
           -0.0376931744475234,
            0.3662436692551876,
           -0.03851423918413366,
           -0.28915094775302785,
           -0.24972299832315636,
           -0.34200263379293494,
            0.19287666836584216,]
    prob = OptimizationProblem(f, x0, nothing)
    sol = solve(prob, LBFGS(); maxiters=10_000)

    xopt = transform(tpost, sol)
    @test isapprox(xopt.f1/xopt.f2, 2.0, atol=1e-3)
    @test isapprox(xopt.σ1*2*sqrt(2*log(2)), μas2rad(40.0), rtol=1e-3)
    @test isapprox(xopt.σ1*xopt.τ1*2*sqrt(2*log(2)), μas2rad(20.0), rtol=1e-3)
    @test isapprox(xopt.ξ1, π/3, atol=1e-3)
    @test isapprox(xopt.σ2*2*sqrt(2*log(2)), μas2rad(20.0), atol=1e-3)
    @test isapprox(xopt.σ2*xopt.τ2*2*sqrt(2*log(2)), μas2rad(10.0), rtol=1e-3)
    @test isapprox(xopt.ξ2, π/6, atol=1e-3)
    @test isapprox(xopt.x, μas2rad(30.0), rtol=1e-3)
    @test isapprox(xopt.y, μas2rad(30.0), rtol=1e-3)
    @test chi2(skymodel(post, xopt), lcamp, cphase) < 0.1

end
