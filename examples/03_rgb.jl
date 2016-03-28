
using PiGPIO

red_pin = 18
green_pin = 23
blue_pin = 24

PiGPIO.softPwmCreate(red_pin, 0, 100)
PiGPIO.softPwmCreate(green_pin, 0, 100)
PiGPIO.softPwmCreate(blue_pin, 0, 100)

try 
	for i in 1:100
        for j=1:100
            for k=1:100
                PiGPIO.softPwmWrite(red_pin, k)
                PiGPIO.softPwmWrite(green_pin, j)
                PiGPIO.softPwmWrite(blue_pin, i)
                sleep(0.1)
            end
        end
	end
finally
    println("Cleaning up!")
	PiGPIO.pinMode(red_pin, INPUT)
    PiGPIO.pinMode(green_pin, INPUT)
    PiGPIO.pinMode(blue_pin, INPUT)
end
