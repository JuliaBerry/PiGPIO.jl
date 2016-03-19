module PiGPIO

# package code goes here

function __init__()
	ENV["WIRINGPI_GPIOMEM"] = 1
	ccall( (:wiringPiSetupGPIO, "/usr/lib/libwiringPi.so"), Void, () )
end

pinMode(pin, mode) = ccall( (:pinMode, "/usr/lib/libwiringPi.so"), Void, (Cint, Cint), pin, mode)
digitalWrite(pin, value) = ccall( (:digitalWrite, "/usr/lib/libwiringPi.so"), Void, (Cint, Cint), pin, value)
analogWrite(pin, value) = ccall( (:analogWrite, "/usr/lib/libwiringPi.so"), Void, (Cint, Cint), pin, value)
digitalRead(pin) = ccall( (:digitalRead, "/usr/lib/libwiringPi.so"), Cint, (Cint,), pin)
analogRead(pin) = ccall( (:analogRead, "/usr/lib/libwiringPi.so"), Cint, (Cint,), pin)
pullUpDnControl(pin, pud) = ccall( (:pullUpDnControl, "/usr/lib/libwiringPi.so"), Void, (Cint, Cint), pin, pud)
softPwmCreate(pin, init, range) = ccall( (:softPwmCreate, "/usr/lib/libwiringPi.so"), Cint, (Cint, Cint, Cint), pin, init, range)
softPwmWrite(pin, value) = ccall( (:softPwmWrite, "/usr/lib/libwiringPi.so"), Void, (Cint, Cint), pin, value)

global const WPI_MODE_PINS = 0
global const WPI_MODE_GPIO = 1
global const WPI_MODE_GPIO_SYS = 2
global const WPI_MODE_PHYS = 3
global const WPI_MODE_PIFACE = 4
global const WPI_MODE_UNINITIALISED =  -1

# Pin modes

global const INPUT = 0
global const OUTPUT = 1
global const PWM_OUTPUT = 2
global const GPIO_CLOCK = 3
global const SOFT_PWM_OUTPUT = 4
global const SOFT_TONE_OUTPUT = 5
global const PWM_TONE_OUTPUT = 6

global const LOW = 0
global const HIGH = 1

# Pull up/down/none

global const PUD_OFF = 0
global const PUD_DOWN = 1
global const PUD_UP = 2

# PWM

global const PWM_MODE_MS = 0
global const PWM_MODE_BAL = 1

# Interrupt levels

global const INT_EDGE_SETUP = 0
global const INT_EDGE_FALLING = 1
global const INT_EDGE_RISING = 2
global const INT_EDGE_BOTH = 3

# Pi model types and version numbers
#      Intended for the GPIO program Use at your own risk.

global const PI_MODEL_A = 0
global const PI_MODEL_B = 1
global const PI_MODEL_AP = 2
global const PI_MODEL_BP = 3
global const PI_MODEL_2  = 4
global const PI_ALPHA = 5
global const PI_MODEL_CM = 6
global const PI_MODEL_07 = 7
global const PI_MODEL_3 = 8
global const PI_MODEL_ZERO = 9

global const PI_VERSION_1 = 0
global const PI_VERSION_1_1 = 1
global const PI_VERSION_1_2 = 2
global const PI_VERSION_2 = 3

global const PI_MAKER_SONY = 0
global const PI_MAKER_EGOMAN = 1
global const PI_MAKER_MBEST = 2
global const PI_MAKER_UNKNOWN = 3

end # module
