# https://github.com/joan2937/pigpio/blob/master/pigpio.py
module PiGPIO

export Pi

using Sockets

include("pi.jl")
include("basic.jl")
include("wave.jl")
include("i2c.jl")
include("spiSerial.jl")

end
