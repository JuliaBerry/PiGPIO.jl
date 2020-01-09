
using PiGPIO

red_pin = 18 #change this accordingly with your GPIO pin number
p=Pi()
set_mode(p, red_pin, PiGPIO.OUTPUT)
try 
    for i in 1:10
        PiGPIO.write(p, red_pin, PiGPIO.HIGH)
        sleep(0.5)
        PiGPIO.write(p, red_pin, PiGPIO.LOW)
        sleep(0.5)
    end
finally
    println("Cleaning up!")
    set_mode(p, red_pin, PiGPIO.INPUT)
end

	
