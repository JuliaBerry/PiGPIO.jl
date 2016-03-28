
using PiGPIO

red_pin1 = 18
red_pin2 = 23

pinMode(red_pin1, OUTPUT)
pinMode(red_pin2, OUTPUT)

try 
	for i in 1:10
		digitalWrite(red_pin1, HIGH)
        digitalWrite(red_pin2, LOW)
		sleep(0.5)
        digitalWrite(red_pin1, LOW)
		digitalWrite(red_pin2, HIGH)
		sleep(0.5)
	end
finally
    println("Cleaning up!")
	pinMode(red_pin1, INPUT)
    pinMode(red_pin2, INPUT)
end
