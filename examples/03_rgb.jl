
using PiGPIO

red_pin = 23
green_pin = 24
blue_pin = 25
p=Pi()



using Colors

dc = distinguishable_colors(10)

for r in dc
    set_PWM_dutycycle(p, red_pin, round(Int, r.r*255))
    set_PWM_dutycycle(p, green_pin, round(Int,r.g*255))
    set_PWM_dutycycle(p, blue_pin, round(Int,r.b*255))
    sleep(0.5)
end

set_PWM_dutycycle(p, red_pin, 0)
set_PWM_dutycycle(p, green_pin, 0)
set_PWM_dutycycle(p, blue_pin, 0)
    
using SIUnits
using SIUnits.ShortUnits

function normalize0(c::XYZ)
    d=convert(xyY, c)
    xyY(d.x, d.y, 1.0)
end

const hc_k  = 0.0143877696*K*m
const twohc²= 1.19104287e-16*Watt*m^2
planck{S1<:Real, S2<:Real}(λ::quantity(S1,Meter); T::quantity(S2,Kelvin)=5778.0K) =
    λ≤0m ? zero(λ)*Watt*m^-4 : twohc²*λ^-5.0/(exp(hc_k/(λ*T))-1)

Base.convert{S<:Real}(::Type{xyY}, T::quantity(S, K)) = 
  mapreduce(λ->planck(λ*nm,T=T)*m^3/Watt*colormatch(λ), +, 380:780) |>
  normalize0

blackbodies = xyY[convert(xyY, T) for T in 100K:200K:10000K]

for b in blackbodies
     r=convert(RGB, b)
     set_PWM_dutycycle(p, red_pin, round(Int, r.r*255))
     set_PWM_dutycycle(p, green_pin, round(Int,r.g*255))
     set_PWM_dutycycle(p, blue_pin, round(Int,r.b*255))
     sleep(0.5)
end
     
    
