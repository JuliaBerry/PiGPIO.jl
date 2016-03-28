
using PiGPIO

red_pin = 18
green_pin = 23
blue_pin = 24

softPwmCreate(red_pin, 0, 100)
softPwmCreate(green_pin, 0, 100)
softPwmCreate(blue_pin, 0, 100)

try 
	for i in 1:100
        for j=1:100
            for k=1:100
                softPwmWrite(red_pin, k)
                softPwmWrite(green_pin, j)
                softPwmWrite(blue_pin, i)
                sleep(0.01)
            end
        end
	end
finally
    println("Cleaning up!")
	pinMode(red_pin, INPUT)
    pinMode(green_pin, INPUT)
    pinMode(blue_pin, INPUT)
end
