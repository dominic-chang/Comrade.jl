using .AdvancedHMC
using Random
export  HMC

Base.@kwdef struct HMC{S,I,P,T,A,D}
    metric::S
    integrator::I = Leapfrog
    trajectory::P = MultinomialTS
    termination::T = StrictGeneralisedNoUTurn(10, 1000.0)
    adaptor::A = StanHMCAdaptor
    targetacc::Float64 = 0.8
    autodiff::D = AD.ForwardDiffBackend()
end

samplertype(::Type{<:HMC}) = IsFlat()

function make_pullback(ℓ, autodiff::AD.AbstractBackend)
    function ∇ℓ(x)
        res = AD.value_and_gradient(autodiff, ℓ, x)
        return (first(res), first(last(res)))
    end
end

# This is custom since Zygote and AD have some weird performanc regression currently
function make_pullback(ℓ, ::AD.ReverseRuleConfigBackend)
    function ∇ℓ(x)
        f, b = AD.Zygote.pullback(ℓ, x)
        return (f, first(b(1.0)))
    end
end

function make_pullback(ℓ, autodiff::Function)
    function ∇ℓ(x)
        return (ℓ(x), autodiff(x))
    end
end


function _initialize_hmc(tpost::TransformedPosterior, init_params, nchains)
    isnothing(init_params) && return inverse.(Ref(tpost.transform), rand(tpost.lpost.prior, nchains))
    @argcheck length(init_params) == nchains
    return inverse.(Ref(tpost), init_params)
end



function AbstractMCMC.sample(tpost::TransformedPosterior,
                             sampler::HMC, parallel::AbstractMCMC.AbstractMCMCEnsemble,
                             nsamples, nchains, args...;
                             init_params=nothing, kwargs...
                             )

    ℓ(x) = logdensityof(tpost, x)

    ∇ℓ = make_pullback(ℓ, sampler.autodiff)
    θ0 = _initialize_hmc(tpost, init_params, nchains)


    model = AdvancedHMC.DifferentiableDensityModel(ℓ, ∇ℓ)
    metric = sampler.metric
    # This is a hack to get a good initial step size
    hamiltonian = Hamiltonian(metric, ℓ, ∇ℓ)
    ϵ0 = find_good_stepsize(hamiltonian, first(θ0))
    integrator = sampler.integrator(ϵ0)

    # form the HMCKernel
    kernel = HMCKernel(Trajectory{sampler.trajectory}(integrator, sampler.termination))
    adaptor = sampler.adaptor(MassMatrixAdaptor(metric), StepSizeAdaptor(sampler.targetacc, integrator))

    res = AbstractMCMC.sample(Random.GLOBAL_RNG, model, kernel, metric, adaptor, parallel, nsamples, nchains, args...; init_params=θ0, chain_type=Array, kwargs...)

    stats = [TupleVector(getproperty.(r, :stat)) for r in res]
    samples = [getproperty.(getproperty.(r, :z), :θ) for r in res]
    chains = [TupleVector(transform.(Ref(tpost), s)) for s in samples]
    return chains, stats

end

function AbstractMCMC.sample(tpost::TransformedPosterior, sampler::HMC, nsamples, args...;
                             init_params=nothing,
                             kwargs...)
    ℓ(x) = logdensityof(tpost, x)

    ∇ℓ = make_pullback(ℓ, sampler.autodiff)

    p0 = init_params
    if isnothing(init_params)
        @warn "No starting location chosen, picking start from random"
        p0 = transform(tpost.transform, rand(tpost.prior))
    end
    θ0 = HypercubeTransform.inverse(tpost, p0)
    model = AdvancedHMC.DifferentiableDensityModel(ℓ, ∇ℓ)
    metric = sampler.metric
    # This is a hack to get a good initial step size
    hamiltonian = Hamiltonian(metric, ℓ, ∇ℓ)
    ϵ0 = find_good_stepsize(hamiltonian, θ0)
    integrator = sampler.integrator(ϵ0)

    # form the HMCKernel
    kernel = HMCKernel(Trajectory{sampler.trajectory}(integrator, sampler.termination))
    adaptor = sampler.adaptor(MassMatrixAdaptor(metric), StepSizeAdaptor(sampler.targetacc, integrator))

    res = AbstractMCMC.sample(model, kernel, metric, adaptor, nsamples, args...; init_params=θ0, chain_type=Array, kwargs...)

    stats = TupleVector(getproperty.(res, :stat))
    samples = getproperty.(getproperty.(res, :z), :θ)
    chain = transform.(Ref(tpost), samples)
    return TupleVector(chain), stats, res
    #return TupleVector(transform.(Ref(tpost), chain)), TupleVector(stats)
end
