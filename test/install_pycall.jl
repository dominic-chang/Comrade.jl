# copied and modified from https://github.com/tkf/IPython.jl/blob/master/test/install_dependencies.jl
# and https://github.com/JuliaPy/SymPy.jl/blob/master/test/install_dependencies.jl

# Adding Pkg in test/REQUIRE would be an error in 0.6.  Using
# Project.toml still has some gotchas.  So:

# Let PyCall.jl use Python interpreter from Conda.jl
# See: https://github.com/JuliaPy/PyCall.jl
ENV["PYTHON"] = "/opt/hostedtoolcache/Python/3.10.1/x64/bin/python"
Pkg.build("PyCall")
