# PiGPIO.jl

#### Control GPIO pins on the Raspberry Pi from Julia

[![][docs-stable-img]][docs-stable-url]
[![documentation dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliaberry.github.io/PiGPIO.jl/dev/)

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://juliahub.com/docs/PiGPIO/

[![PiGPIO](https://img.youtube.com/vi/UmSQjkaATk8/0.jpg)](https://www.youtube.com/watch?v=UmSQjkaATk8)

PiGPIO.jl is a Julia package for the Raspberry which communicates with the pigpio
daemon to allow control of the general purpose
input outputs (GPIO).

This package is an effective translation of the python package for the same.
Which can be found [here](http://abyz.me.uk/rpi/pigpio/python.html)

Click [here](https://medium.com/@imkimfung/using-julia-to-control-leds-on-a-raspberry-pi-b320be83e503) for an **in-depth tutorial** on how you can control GPIO pins such as LEDs from Julia on the Raspberry Pi.

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

## The daemon process `pigpiod`

On Raspberry Pi OS, the daemon `pigpiod` can be installed and launched by using the following shell commands:

```bash
# install pigpiod
sudo apt-get install pigpiod
# enable pigpiod via system D
sudo systemctl enable pigpiod
```

The daemon can also be launched manually with `sudo pigpiod` in the terminal.

## Installation and Usage

```julia
using Pkg
Pkg.add("PiGPIO")

using PiGPIO

pi=Pi() # connect to the pigpiod daemon on localhost
```

## Example Usage

The `pin` number corresponds to the GPIO pins
(General Purpose Input/Output, aka "BCM" or "Broadcom") and not 
to the physical pin numbers.

```julia
set_mode(pi::Pi, pin::Int, mode)
get_mode(pi::Pi, pin::Int)
# mode can be PiGPIO.INPUT or PiGPIO.OUTPUT

PiGPIO.read(pi, pin)
PiGPIO.write(pi, pin, state)
# state can be PiGPIO.HIGH, PiGPIO.LOW, PiGPIO.ON, PiGPIO.OFF

PiGPIO.set_PWM_dutycycle(pi, pin, dutycyle)
# dutycyle defaults to a range 0-255
```
