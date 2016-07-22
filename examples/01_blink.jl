
using PiGPIO

red_pin = 18
p=Pi()
set_mode(p, red_pin, OUTPUT)
try 
	for i in 1:10
		write(p, red_pin, HIGH)
		sleep(0.5)
		write(p, red_pin, LOW)
		sleep(0.5)
	end
finally
	println("Cleaning up!")
	set_mode(p, red_pin, INPUT)
end
	
