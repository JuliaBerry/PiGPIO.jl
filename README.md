# PiGPIO

#### Control GPIO pins on the Raspberry Pi from Julia

[![PiGPIO](https://img.youtube.com/vi/UmSQjkaATk8/0.jpg)](https://www.youtube.com/watch?v=UmSQjkaATk8)

## Installation and Usage

This package depends on the native [pigpio](http://abyz.co.uk/rpi/pigpio/index.html) control library, which is usually present in recent versions of raspbian. The `pigpiod` daemon must be started on the pi before using this package. 

```julia
Pkg.clone("https://github.com/JuliaBerry/PiGPIO.jl")

using PiGPIO

pi=Pi() #connect to pigpiod daemon on localhost
```

## Reference

```julia
set_mode(p::Pi, pin::Int, mode)
get_mode(p::Pi, pin::Int)
# mode can be INPUT or OUTPUT

read(p, pin)
write(p, pin, state)
#state can be HIGH, LOW, ON, OFF

set_PWM_dutycycle(p, pin, dutycyle)
#dutycyle defaults to a range 0-255

```


