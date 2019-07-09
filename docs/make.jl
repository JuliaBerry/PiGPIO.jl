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
    pages = [
        "index.md",
        "API Docs" => "api.md",
        "Examples" => [
            "Blink Once" => "examples/01_blink.md",
            "Blink Twice" => "examples/02_blink_twice.md",
            "Red-Green-Blue" => "examples/03_rgb.md"
        ]
    ]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
