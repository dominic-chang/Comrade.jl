if lowercase(get(ENV, "CI", "false")) == "true"
    include("install_pycall.jl")
end

using ROSEx
using Statistics
using Test

include("test_util.jl")

@testset "ROSEx.jl" begin

    include("observation.jl")

end
