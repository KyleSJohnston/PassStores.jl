using Documenter
using PassStores

makedocs(
    sitename="PassStores.jl",
    modules = [PassStores],
    checkdocs = :public,
)

deploydocs(
    repo = "github.com/KyleSJohnston/PassStores.jl.git",
)
