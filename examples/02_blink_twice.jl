
using PiGPIO

red_pin1 = 18 #change these numbers accordingly with your GPIO pins
red_pin2 = 23

p=Pi()

set_mode(p, red_pin1, PiGPIO.OUTPUT)
set_mode(p, red_pin2, PiGPIO.OUTPUT)

try 
    for i in 1:10
        PiGPIO.write(p, red_pin1, PiGPIO.HIGH)
        PiGPIO.write(p, red_pin2, PiGPIO.LOW)
        sleep(0.5)
        PiGPIO.write(p, red_pin1, PiGPIO.LOW)
        PiGPIO.write(p, red_pin2, PiGPIO.HIGH)
        sleep(0.5)
    end
finally
    println("Cleaning up!")
    set_mode(p, red_pin1, PiGPIO.INPUT)
    set_mode(p, red_pin2, PiGPIO.INPUT)
end
