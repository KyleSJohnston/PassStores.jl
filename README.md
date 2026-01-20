# PassStores.jl

[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://kylesjohnston.github.io/PassStores.jl/stable)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://kylesjohnston.github.io/PassStores.jl/dev)
[![Build Status](https://github.com/kylesjohnston/PassStores.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/kylesjohnston/PassStores.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![JET](https://img.shields.io/badge/%F0%9F%9B%A9%EF%B8%8F_tested_with-JET.jl-233f9a)](https://github.com/aviatesk/JET.jl)

A Julia interface to the `pass` command-line password manager.

## Overview

PassStores.jl provides a simple, dictionary-like interface to retrieve passwords and secrets stored in the standard Unix `pass` password store. It allows Julia programs to securely access stored credentials without manual intervention.

## Installation

```julia
using Pkg
Pkg.add("PassStores")
```

## Usage

```julia
using PassStores

const PASS = PassStore()

# Retrieve a password (throws KeyError if not found)
password = PASS["example-service/password"]

# Retrieve a password with a default fallback
password = get(PASS, "example-service/password", "default-password")

# Example: Handling missing passwords gracefully
api_key = get(PASS, "another_service/api_key", nothing)
if api_key === nothing
    @warn "API key not found in password store"
else
    # Use the API key
end

# Example: Check if password exists before accessing
if haskey(PASS, "optional_service/token")
    token = PASS["optional_service/token"]
    # Use the token
end
```
