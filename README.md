# PiGPIO

#### Control GPIO pins on the Raspberry Pi from Julia

[![][docs-stable-img]][docs-stable-url]

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://pkg.julialang.org/docs/PiGPIO/

[![PiGPIO](https://img.youtube.com/vi/UmSQjkaATk8/0.jpg)](https://www.youtube.com/watch?v=UmSQjkaATk8)

PiGPIO.jl is a Julia package for the Raspberry which communicates with the pigpio
daemon to allow control of the general purpose
input outputs (GPIO).

This package is an effective translation of the python package for the same.
Which can be found [here](http://abyz.me.uk/rpi/pigpio/python.html)

### Features

* OS independent. Only Julia 1.0+ required.
* Controls one or more Pi's.
* Hardware timed pulse width modulation.
* Hardware timed servo pulse.
* Callbacks when any of GPIO change state.
* Create and transmit precise waveforms.
* Read/Write GPIO and set their modes.
* Wrappers for I2C, SPI, and serial links.

Once a pigpio daemon is launched on the pi this package can connect to
it and communicate with it to manipulate the GPIO pins of the pi. The actual
work is done by the daemon. One benefit of working this way is that you can
remotely access the pi over a network and multiple instances can be connected
to the daemon simultaneously.

Launching the daemon requires sudo privileges. Launch by typing `sudo pigpiod`
in the terminal.

## Installation and Usage

```julia
using Pkg
Pkg.add("https://github.com/JuliaBerry/PiGPIO.jl")

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
