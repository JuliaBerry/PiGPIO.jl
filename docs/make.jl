using Documenter
using PiGPIO
using Literate

Literate.markdown(joinpath(@__DIR__, "..", "examples", "01_blink.jl"), joinpath(@__DIR__, "src", "examples"))
Literate.markdown(joinpath(@__DIR__, "..", "examples", "02_blink_twice.jl"),joinpath(@__DIR__, "src", "examples"))
Literate.markdown(joinpath(@__DIR__, "..", "examples", "03_rgb.jl"), joinpath(@__DIR__, "src", "examples"))

makedocs(
    sitename = "PiGPIO",
    format = Documenter.HTML(),
    modules = [PiGPIO],
    # examples need to be run on a Raspberry Pi
    doctest = false,
    draft = true,
    pages = [
        "index.md",
        "Tutorial" => "tutorial.md",
        "API Docs" => "api.md",
        "Examples" => [
            "Blink Once" => "examples/01_blink.md",
            "Blink Twice" => "examples/02_blink_twice.md",
            "Red-Green-Blue" => "examples/03_rgb.md"
        ]
    ]
)

deploydocs(;
    repo="github.com/JuliaBerry/PiGPIO.jl",
)
