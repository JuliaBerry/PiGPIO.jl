## Overview
Via this tutorial, we shall be going over the entire process of installation and use of the Julia Programming language on a Raspberry Pi. We will be using the [PiGPIO.jl](https://github.com/JuliaBerry/PiGPIO.jl) library for controlling GPIO elements (namely LEDs). We shall be building a simple circuit of two alternately blinking LEDs.

## What you'll need
You will require a Raspberry Pi (I am using a Raspberry Pi 3 model B+), along with the standard peripherals(keyboard, mouse, display, power supply), 1 breadboard, 2 resistors, 2 LEDs and jumper wires. I am assuming that you have the Raspbian OS set up and running on the Raspberry Pi. If not, take a look at [this tutorial.](https://projects.raspberrypi.org/en/projects/raspberry-pi-setting-up)

## Setting up Julia

In your __Raspbian commmand line__, simply run:

```
sudo apt install julia
```
Next, we need to launch a __pigpio daemon__, which PiGPIO.jl can connect to and control the GPIO pins. To do this, run the following command.
```
sudo pigpiod
```
Then, run this to enter the __Julia REPL__
```
julia
```
now run the following commands to install the __PiGPIO__ library:

```
using Pkg
Pkg.add("PiGPIO")
```
You should now be ready to start with the circuit

## Building the Circuit

connect the __cathode__ of both the LEDs to the __ground rail__ of the breadboard. Connect the __anode__, via an appropriate resistor (I used 82 ohm) to __GPIO pins 2 and 3__ of the Raspberry Pi.

### circuit diagram for reference: 

![](https://github.com/NandVinchhi/JuliaGPIO/blob/master/circuit.png) 

You are now ready to launch Julia and start coding. PiGPIO.jl should be installed by now.

## The Code
You can run this code through an __external text editor__ or in the __Julia REPL__ itself.
First we need to import the package with the __using__ keyword. Next, we need to initialize the Raspberry Pi by creating an object variable and initialising it to __Pi()__

```Julia
using PiGPIO
pi = Pi()
```

Next, we need to intitialize the GPIO pins and their state (__INPUT/OUTPUT__ --> in this case __OUTPUT__).

```Julia
pin1 = 2 # GPIO pin 2
pin2 = 3 # GPIO pin 3

set_mode(pi, pin1, PiGPIO.OUTPUT) 
set_mode(pi, pin2, PiGPIO.OUTPUT)
# ^ initialization
``` 

Now we shall use a for loop to implement the blinking LEDs

```Julia
num_loops = 20 # The number of times you want the lights to blink. 
for i = 1:num_loops
    PiGPIO.write(pi, pin1, HIGH) # setting GPIO pin state
    PiGPIO.write(pi, pin2, LOW)
    sleep(1) # delay in seconds
    PiGPIO.write(pi, pin1, LOW)
    PiGPIO.write(pi, pin2, HIGH)
    sleep(1)
end
```

You should be getting blinking LEDs when you run this code. 

### pictures of the final working model: 
![](https://github.com/NandVinchhi/JuliaGPIO/blob/master/pic1.jpg)

![](https://github.com/NandVinchhi/JuliaGPIO/blob/master/pic2.jpg)

This project was made by Nand Vinchhi for the purpose of __GCI 2019__.

Circuit diagrams drawn with [circuit-diagram.org](https://www.circuit-diagram.org/)
