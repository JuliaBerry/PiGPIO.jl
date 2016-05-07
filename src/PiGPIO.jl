module PiGPIO

export pinMode, digitalWrite, analogWrite, digitalRead, analogRead, pullUpDownControl, softPwmCreate, softPwmWrite,
      WPI_MODE_PINS,WPI_MODE_GPIO,WPI_MODE_SYS,WPI_MODE_PHYS,WPI_MODE_PIFACE,WPI_MODE_UNITIALISED,
      INPUT, OUTPUT, PWM_OUTPUT, GPIO_CLOCK, SOFT_PWM_OUTPUT, SOFT_TONE_OUTPUT, PWM_TONE_OUTPUT, HIGH, LOW,
      PUD_OFF,PUD_DOWN,PUD_UP,  PWM_MODE_MS,PWM_MODE_BAL,
      INT_EDGE_SETUP, INT_EDGE_FALLING, INT_EDGE_RISING, INT_EDGE_BOTH

const LIBWIRINGPI_PATH = "/usr/lib/libwiringPi.so"

@enum WPI_MODE WPI_MODE_PINS=0 WPI_MODE_GPIO=1 WPI_MODE_SYS=2 WPI_MODE_PHYS=3 WPI_MODE_PIFACE=4 WPI_MODE_UNITIALISED=-1

@enum PIN_MODE INPUT=0 OUTPUT=1 PWM_OUTPUT=2 GPIO_CLOCK=3 SOFT_PWM_OUTPUT=4 SOFT_TONE_OUTPUT=5 PWM_TONE_OUTPUT=6

@enum PIN_VALUE LOW=0 HIGH=1

@enum PUD PUD_OFF=0 PUD_DOWN=1 PUD_UP=2

@enum PWM_MODE PWM_MODE_MS=0 PWM_MODE_BAL=1

# Interrupt levels
@enum INT_EDGE INT_EDGE_SETUP=0 INT_EDGE_FALLING=1 INT_EDGE_RISING=2 INT_EDGE_BOTH=3

# Pi model types and version numbers
#      Intended for the GPIO program Use at your own risk.
@enum PI_MODEL PI_MODEL_A=0 PI_MODEL_B=1 PI_MODEL_AP=2 PI_MODEL_BP=3 PI_MODEL_2=4 PI_ALPHA=5 PI_MODEL_CM=6 PI_MODEL_07=7 PI_MODEL_3=8 PI_MODEL_ZERO=9

@enum PI_VERSION  PI_VERSION_1=0 PI_VERSION_1_1=1 PI_VERSION_1_2=2 PI_VERSION_2=3

@enum PI_MAKER  PI_MAKER_SONY=0 PI_MAKER_EGOMAN=1 PI_MAKER_MBEST=2 PI_MAKER_UNKNOWN=3

function __init__()
	ENV["WIRINGPI_GPIOMEM"] = 1
	ccall( (:wiringPiSetupGpio, LIBWIRINGPI_PATH), Void, () )
end

pinMode(pin, mode::PIN_MODE) = ccall( (:pinMode, LIBWIRINGPI_PATH), Void, (Cint, Cint), pin, mode)

digitalWrite(pin, value::PIN_VALUE) = ccall( (:digitalWrite, LIBWIRINGPI_PATH), Void, (Cint, Cint), pin, value)

analogWrite(pin, value) = ccall( (:analogWrite, LIBWIRINGPI_PATH), Void, (Cint, Cint), pin, value)

digitalRead(pin) = PIN_VALUE(ccall( (:digitalRead, LIBWIRINGPI_PATH), Cint, (Cint,), pin))

analogRead(pin) = ccall( (:analogRead, LIBWIRINGPI_PATH), Cint, (Cint,), pin)

pullUpDnControl(pin, pud::PUD) = ccall( (:pullUpDnControl, LIBWIRINGPI_PATH), Void, (Cint, Cint), pin, pud)

softPwmCreate(pin, init, range) = ccall( (:softPwmCreate, LIBWIRINGPI_PATH), Cint, (Cint, Cint, Cint), pin, init, range)

softPwmWrite(pin, value) = ccall( (:softPwmWrite, LIBWIRINGPI_PATH), Void, (Cint, Cint), pin, value)



end # module
