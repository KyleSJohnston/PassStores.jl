module PassStores

using Logging

export PassStore

"Validates that the pass command is available and working"
function validate_pass_command()
    try
        run(pipeline(`pass --version`, stdout=devnull, stderr=devnull))
    catch e
        if e isa ProcessFailedException || e isa Base.IOError
            throw(SystemError("pass command not found or not working. Please install pass."))
        else
            rethrow(e)
        end
    end
end

"Returns the default password store directory path"
function default_store_directory()
    return joinpath(homedir(), ".password-store")
end

"""
    PassStore(dir::Union{AbstractString,Nothing,Base.EnvDict}=nothing)

A password store interface that provides dictionary-like access to the `pass` command-line password manager.

# Arguments
- `dir`: The password store directory path.

`dir` defaults to nothing, which implies the default store location (`~/.password-store`).
Pass `ENV` to use the store location defined in `PASSWORD_STORE_DIR`, falling back to the
default store location.

For compatibility with v0.1.0, other non-AbstractString values are treated like `ENV` with
a warning about deprecated behavior.

# Examples
```julia
# Use default password store
store = PassStore()

# Use custom password store directory
store = PassStore("/path/to/my/store")

# Retrieve passwords
password = store["service/password"]
```

# Throws
- `SystemError`: If the `pass` command is not available
- `ArgumentError`: If the specified directory doesn't exist or isn't initialized
"""
struct PassStore
    dir::Union{String,Nothing}

    function PassStore(dir::String)
        # Validate pass command exists and works
        validate_pass_command()

        # Resolve store directory
        validate_store_directory(dir)

        @debug "Using password store directory: $dir"

        return new(dir)
    end
end

# coerce `dir` to be a String
PassStore(dir::AbstractString) = PassStore(String(dir))

# use the default location
PassStore(::Nothing) = PassStore(default_store_directory())

# default to `nothing`
PassStore() = PassStore(nothing)

# use the environment variable if set, otherwise default
PassStore(env::Base.EnvDict) = PassStore(get(env, "PASSWORD_STORE_DIR", nothing))

# DEPRECATED
# This method preserves the behavior of `resolve_store_directory`.
function PassStore(dir::Any)
    @warn "This method of constructing `PassStore` is deprecated. Call `PassStore(ENV)` instead." dir
    return PassStore(ENV)
end

# Validates that the specified directory exists and is an initialized password store
function validate_store_directory(dir::AbstractString)
    if !isdir(dir)
        throw(ArgumentError("Password store directory '$dir' does not exist"))
    end

    gpg_id_file = joinpath(dir, ".gpg-id")
    if !isfile(gpg_id_file)
        throw(ArgumentError("Password store not initialized. Run 'pass init <gpg-id>' first in directory '$dir'"))
    end
end



"""
    getindex(pass::PassStore, key::AbstractString)

Retrieve a password from the password store.

# Arguments
- `pass::PassStore`: The password store instance
- `key::AbstractString`: The password entry key/path

# Returns
- `String`: The decrypted password

# Throws
- `KeyError`: If the password entry doesn't exist
- `ArgumentError`: If GPG decryption fails or secret key is unavailable
"""
function Base.getindex(pass::PassStore, key::AbstractString)
    stderr_buffer = IOBuffer()
    cmd = pipeline(addenv(`pass show $key`, "PASSWORD_STORE_DIR" => pass.dir), stderr=stderr_buffer)

    try
        return readchomp(cmd)
    catch e
        if e isa ProcessFailedException
            stderr_output = String(take!(stderr_buffer))

            # Parse specific error types based on stderr content
            if contains(stderr_output, "is not in the password store")
                throw(KeyError(key))
            elseif contains(stderr_output, "gpg: decryption failed") || contains(stderr_output, "gpg: public key decryption failed")
                throw(ArgumentError("GPG decryption failed - check your GPG key and passphrase"))
            elseif contains(stderr_output, "gpg: No secret key") || contains(stderr_output, "gpg: secret key not available")
                throw(ArgumentError("GPG secret key not available for decryption"))
            else
                # Re-throw with more context
                error("pass command failed with exit code $(e.procs[1].exitcode): $stderr_output")
            end
        else
            rethrow(e)
        end
    end
end

"""
    get(pass::PassStore, key::AbstractString, default)

Retrieve a password from the password store with a default fallback.

# Arguments
- `pass::PassStore`: The password store instance
- `key::AbstractString`: The password entry key/path
- `default`: The value to return if the key is not found

# Returns
- `String` or `typeof(default)`: The decrypted password or the default value

# Throws
- `ArgumentError`: If GPG decryption fails or secret key is unavailable (but not for missing keys)
"""
function Base.get(pass::PassStore, key::AbstractString, default)
    try
        return getindex(pass, key)
    catch e
        if e isa KeyError
            return default
        else
            rethrow(e)
        end
    end
end

"""
    haskey(pass::PassStore, key::AbstractString)

Check if a password entry exists in the password store.

# Arguments
- `pass::PassStore`: The password store instance
- `key::AbstractString`: The password entry key/path

# Returns
- `Bool`: `true` if the password exists, `false` otherwise

# Throws
- `ArgumentError`: If GPG decryption fails or secret key is unavailable
"""
function Base.haskey(pass::PassStore, key::AbstractString)
    try
        getindex(pass, key)
        return true
    catch e
        if e isa KeyError
            return false
        else
            rethrow(e)
        end
    end
end

end  # module PassStores
