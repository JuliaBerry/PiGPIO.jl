
using PiGPIO

red_pin = 18

PiGPIO.pinMode(red_pin, OUTPUT)
try 
	for i in 1:10
		PiGPIO.digitalWrite(red_pin, HIGH)
		sleep(0.5)
		PiGPIO.digitalWrite(red_pin, LOW)
		sleep(0.5)
	end
finally
	println("Cleaning up!")
	PiGPIO.pinMode(red_pin, INPUT)
end
	
