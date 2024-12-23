using PiGPIO
using Test

using PiGPIO: u2i


@testset "utility functions" begin
    # https://github.com/joan2937/pigpio/blob/c33738a320a3e28824af7807edafda440952c05d/pigpio.py#L989

    @test u2i(UInt32(4294967272)) == -24
    @test u2i(UInt32(37)) == 37
end

@testset "aqua checks" begin
    include("test_aqua.jl")
end
