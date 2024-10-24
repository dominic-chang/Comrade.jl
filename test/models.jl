
function testmodel(m::Comrade.AbstractModel, atol=1e-4)
    img = intensitymap(m, 2*Comrade.radialextent(m), 2*Comrade.radialextent(m), 1024, 1024)
    img2 = similar(img)
    intensitymap!(img2, m)
    @test isapprox(flux(m), flux(img), atol=atol)
    @test isapprox(mean(img .- img2), 0, atol=1e-8)
    cache = Comrade.create_cache(Comrade.FFT(padfac=3), img)
    u = fftshift(fftfreq(size(img,1), 1/img.psizex))./10
    @test isapprox(mean(abs.(visibility.(Ref(m), u', u) .- cache.sitp.(u', u))), 0.0, atol=1e-3)
end

@testset "Primitive models" begin

    @testset "Gaussian" begin
        m = Gaussian()
        testmodel(m, 1e-5)
    end

    @testset "Disk" begin
        m = smoothed(Disk(), 0.25)
        ComradeBase.intensity_point(Disk(), 0.0, 0.0)
        testmodel(m)
    end


    @testset "MRing1" begin
        α = (0.25,)
        β = (0.1,)

        # We convolve it to remove some pixel effects
        m = convolved(MRing(α, β), stretched(Gaussian(), 0.1, 0.1))
        m2 = convolved(MRing{1}(collect(α), collect(β)), stretched(Gaussian(), 0.1, 0.1))
        @test m == m2
        testmodel(m)
    end

    @testset "MRing2" begin
        α = (0.25, -0.1)
        β = (0.1, 0.2)

        # We convolve it to remove some pixel effects
        m = convolved(MRing(α, β), stretched(Gaussian(), 0.1, 0.1))
        testmodel(m)
    end


    @testset "ConcordanceCrescent" begin
        m = ConcordanceCrescent(20.0, 10.0, 5.0, 0.5)
        testmodel(m)
    end


    @testset "Crescent" begin
        m = smoothed(Crescent(5.0, 2.0, 1.0, 0.5), 1.0)
        testmodel(m,1e-3)
    end

    @testset "ExtendedRing" begin
        mr = ExtendedRing(10.0, 0.5)
        rad = Comrade.radialextent(mr)
        m = modelimage(mr, IntensityMap(zeros(1024,1024), rad, rad))
        testmodel(m)
    end
end

@testset "ModelImage" begin
    m1 = Gaussian()
    m2 = ExtendedRing(2.0, 10.0)
    mimg1 = modelimage(m1)
    mimg2 = modelimage(m2)

    show(mimg1)

    img = similar(mimg2.image)
    intensitymap!(img, m2)
    @test m1 == mimg1
    @test isapprox(mean(img .- mimg2.image), 0.0, atol=1e-8)
end



@testset "Modifiers" begin
    ma = Gaussian()
    mb = ExtendedRing(2.0, 10.0)
    @testset "Shifted" begin
        mas = shifted(ma, 0.5, 0.5)
        mbs = shifted(mb, 0.5, 0.5)
        testmodel(mas)
        testmodel(modelimage(mbs, IntensityMap(zeros(1024, 1024),
                                               2*Comrade.radialextent(mbs),
                                               2*Comrade.radialextent(mbs))))
    end

    @testset "Renormed" begin
        m1 = 3.0*ma
        m2 = ma*3.0
        m2inv = ma/(1/3)
        @test visibility(m1, 4.0, 0.0) == visibility(m2, 4.0, 0.0)
        @test visibility(m2, 4.0, 0.0) == visibility(m2inv, 4.0, 0.0)
        mbs = 3.0*mb
        testmodel(m1)
        testmodel(modelimage(mbs, IntensityMap(zeros(1024, 1024),
                                               2*Comrade.radialextent(mbs),
                                               2*Comrade.radialextent(mbs))))
    end

    @testset "Stretched" begin
        mas = stretched(ma, 5.0, 4.0)
        mbs = stretched(mb, 5.0, 4.0)
        testmodel(mas)
        testmodel(modelimage(mbs, IntensityMap(zeros(1024, 1024),
                                               2*Comrade.radialextent(mbs),
                                               2*Comrade.radialextent(mbs))))
    end

    @testset "Rotated" begin
        mas = rotated(ma, π/3)
        mbs = rotated(mb, π/3)
        testmodel(mas)
        testmodel(modelimage(mbs, IntensityMap(zeros(1024, 1024),
                                               2*Comrade.radialextent(mbs),
                                               2*Comrade.radialextent(mbs))))
    end

    @testset "AllMods" begin
        mas = rotated(stretched(shifted(ma, 0.5, 0.5), 5.0, 4.0), π/3)
        mbs = rotated(stretched(shifted(mb, 0.5, 0.5), 5.0, 4.0), π/3)
        testmodel(mas)
        testmodel(modelimage(mbs, IntensityMap(zeros(1024, 1024),
                                               2*Comrade.radialextent(mbs),
                                               2*Comrade.radialextent(mbs))))
    end
end

@testset "CompositeModels" begin
    m1 = Gaussian()
    m2 = ExtendedRing(2.0, 10.0)

    @testset "Add models" begin
        img = IntensityMap(zeros(1024, 1024),
                                        20.0,
                                        20.0)
        mt1 = m1 + m2
        mt2 = shifted(m1, 1.0, 1.0) + m2
        mt3 = shifted(m1, 1.0, 1.0) + 0.5*stretched(m2, 0.9, 0.8)
        mc = Comrade.components(mt1)
        @test mc[1] === m1
        @test mc[2] === m2
        @test flux(mt1) ≈ flux(m1) + flux(m2)

        testmodel(modelimage(mt1, img))
        testmodel(modelimage(mt2, img))
        testmodel(modelimage(mt3, img))
    end

    @testset "Convolved models" begin
        img = IntensityMap(zeros(1024, 1024),
                                        20.0,
                                        20.0)
        mt1 = convolved(m1, m2)
        mt2 = convolved(shifted(m1, 1.0, 1.0), m2)
        mt3 = convolved(shifted(m1, 1.0, 1.0), 0.5*stretched(m2, 0.9, 0.8))
        mc = Comrade.components(mt1)
        @test mc[1] === m1
        @test mc[2] === m2

        testmodel(modelimage(mt1, img))
        testmodel(modelimage(mt2, img))
        testmodel(modelimage(mt3, img))
    end

    @testset "All composite" begin
        img = IntensityMap(zeros(1024, 1024),
                                            20.0,
                                            20.0)

        mt = m1 + convolved(m1, m2)
        mc = Comrade.components(mt)
        @test mc[1] === m1
        @test mc[2] === m1
        @test mc[3] === m2

        testmodel(modelimage(mt, img))

    end
end

@testset "PolarizedModel" begin
    mI = stretched(MRing((0.2,), (0.1,)), 20.0, 20.0)
    mQ = 0.2*stretched(MRing((0.0,), (0.6,)), 20.0, 20.0)
    mU = 0.2*stretched(MRing((0.1,), (-0.6,)), 20.0, 20.0)
    mV = 0.0*stretched(MRing((0.0,), (-0.6,)), 20.0, 20.0)
    m = PolarizedModel(mI, mQ, mU, mV)

    v = coherencymatrix(m, 0.005, 0.01)
    @test evpa(v) == evpa(m, 0.005, 0.01)
    @test m̆(v) == m̆(m, 0.005, 0.01)

    I = IntensityMap(zeros(1024,1024), 100.0, 100.0)
    Q = similar(I)
    U = similar(I)
    V = similar(I)
    pimg1 = IntensityMap(I,Q,U,V)
    intensitymap!(pimg1, m)
    pimg2 = intensitymap(m, 100.0, 100.0, 1024, 1024)
    @test isapprox(sum(abs, (stokes(pimg1, :I) .- stokes(pimg2, :I))), 0.0, atol=1e-12)
    @test isapprox(sum(abs, (stokes(pimg1, :Q) .- stokes(pimg2, :Q))), 0.0, atol=1e-12)
    @test isapprox(sum(abs, (stokes(pimg1, :U) .- stokes(pimg2, :U))), 0.0, atol=1e-12)
    @test isapprox(sum(abs, (stokes(pimg1, :V) .- stokes(pimg2, :V))), 0.0, atol=1e-12)

end

@testset "RImage SqExp" begin
   mI = RImage(rand(8,8), SqExpPulse(5.0))
   testmodel(mI)
end
#@testset "RImage Bspline0" begin
#   mI = RImage(rand(8,8), BSplinePulse{0}())
#   testmodel(mI, 1e-2)
#end
@testset "RImage BSpline1" begin
   mI = RImage(rand(8,8), BSplinePulse{1}())
   testmodel(mI)
end
@testset "RImage BSpline3" begin
   mI = RImage(rand(8,8), BSplinePulse{3}())
   testmodel(mI)
end
