
using PiGPIO

red_pin1 = 18
red_pin2 = 23

PiGPIO.pinMode(red_pin1, OUTPUT)
PiGPIO.pinMode(red_pin2, OUTPUT)

try 
	for i in 1:20
		PiGPIO.digitalWrite(red_pin1, HIGH)
        PiGPIO.digitalWrite(red_pin2, LOW)
		sleep(0.5)
        PiGPIO.digitalWrite(red_pin1, LOW)
		PiGPIO.digitalWrite(red_pin2, HIGH)
		sleep(0.5)
	end
finally
    println("Cleaning up!")
	PiGPIO.pinMode(red_pin1, INPUT)
    PiGPIO.pinMode(red_pin2, INPUT)
end
