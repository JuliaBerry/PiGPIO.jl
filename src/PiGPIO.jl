# https://github.com/joan2937/pigpio/blob/master/pigpio.py
module PiGPIO

export Pi

import Base: run, write
using Sockets

include("constants.jl")
include("pi.jl")
include("wave.jl")
include("i2c.jl")
include("spiSerial.jl")

end
