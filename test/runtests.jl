using Aqua
using JET
using Logging
using PassStores
using Test

@testset "Source Code Tests" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(PassStores)
    end
    @testset "Code linting (JET.jl)" begin
        JET.test_package(PassStores; target_modules = (PassStores,))
    end
end


# Creates a temporary GPG home directory for testing
# Executes function f with GNUPGHOME set to the temporary directory
function tempgpg(f)
    gpgdir = mktempdir()
    return withenv(f, "GNUPGHOME" => gpgdir)
end

# Returns the path to the GPG configuration file used for test key generation
configpath() = joinpath(dirname(@__FILE__), "gpgconfig.txt")

# Creates a new GPG key for testing using the configuration file
# Returns the key ID of the generated key
function create_gpgkey()
    config = configpath()
    # Generate the key
    stdout_buffer = IOBuffer()
    stderr_buffer = IOBuffer()
    run(pipeline(`gpg --batch --generate-key $config`, stdout=stdout_buffer, stderr=stderr_buffer))
    @debug "GPG key generation stdout: $(String(take!(stdout_buffer)))"
    @debug "GPG key generation stderr: $(String(take!(stderr_buffer)))"
    return "test@example.com"  # email used in gpgconfig.txt
end

# Test utility function to initialize a pass store in the given directory
# Uses the specified GPG key ID for encryption
function init(dir::AbstractString, gpgid::AbstractString)
    cmd = pipeline(addenv(`pass init $gpgid`, "PASSWORD_STORE_DIR" => dir), stderr=IOBuffer())
    result = readchomp(cmd)
    @info result
    return
end

# Test utility function to insert a password into the pass store
# Stores the given value at the specified key path
function insert(dir::AbstractString, key::AbstractString, value::AbstractString)
    cmd = pipeline(addenv(`echo $value`, "PASSWORD_STORE_DIR" => dir), addenv(`pass insert --echo $key`, "PASSWORD_STORE_DIR" => dir))
    result = readchomp(cmd)
    @info result
    return
end

# Finds a non-existent directory path for testing error conditions
# Tries up to 5 random directory names in the temp directory
function find_nonexistent_dir()
    for i in 1:5
        candidate = joinpath(tempdir(), "nonexistent_$(rand(1000:9999))")
        !isdir(candidate) && return candidate
    end
    error("Unable to find nonexistent directory after 5 attempts")
end

tempgpg() do
    gpgkey = create_gpgkey()
    @debug "Using GPG key: $gpgkey"

    @testset "Pass command validation" begin
        # Test when pass command is not available
        withenv("PATH" => "") do
            @test_throws SystemError PassStore()
        end
    end

    @testset "Store directory validation" begin
        # Test nonexistent directory
        nonexistent_dir = find_nonexistent_dir()
        @test_throws ArgumentError PassStore(nonexistent_dir)

        # Test directory without .gpg-id file (uninitialized store)
        mktempdir() do tempdir
            @test_throws ArgumentError PassStore(tempdir)
        end
    end

    @testset "Environment variable handling" begin
        # Test explicit directory takes precedence
        mktempdir() do passdir
            init(passdir, gpgkey)

            withenv("PASSWORD_STORE_DIR" => "/some/other/dir") do
                # Should use explicit directory, not env var
                store = PassStore(passdir)
                @test store.dir == passdir
            end
        end

        # Test environment variable is used when dir not specified
        mktempdir() do passdir2
            init(passdir2, gpgkey)

            withenv("PASSWORD_STORE_DIR" => passdir2) do
                # Test that resolve_store_directory respects env var
                resolved = PassStores.resolve_store_directory(missing)
                @test resolved == passdir2
            end
        end
    end

    @testset "Password operations" begin
        mktempdir() do passdir
            init(passdir, gpgkey)
            store = PassStore(passdir)

            # Test KeyError for missing password
            @test_throws KeyError store["nonexistent"]

            # Test get with default for missing password
            @test get(store, "nonexistent", "default") == "default"
            @test isnothing(get(store, "nonexistent", nothing))

            # Test haskey for missing password
            @test !haskey(store, "nonexistent")
        end
    end

    @testset "Error message differentiation" begin
        mktempdir() do passdir
            init(passdir, gpgkey)
            store = PassStore(passdir)

            # Test that missing passwords throw KeyError specifically
            try
                store["missing-password"]
                @test false  # Should not reach here
            catch e
                @test e isa KeyError
                @test e.key == "missing-password"
            end

            # Test haskey doesn't throw for missing passwords
            @test !haskey(store, "missing-password")

            # Test get returns default for missing passwords
            @test get(store, "missing-password", "fallback") == "fallback"
        end
    end

    @testset "Password insertion and retrieval" begin
        mktempdir() do passdir
            init(passdir, gpgkey)

            # Insert a test password
            test_password = "secret123"
            insert(passdir, "test/service", test_password)

            store = PassStore(passdir)

            # Test password can be retrieved
            @test store["test/service"] == test_password
            @test get(store, "test/service", "fallback") == test_password
            @test haskey(store, "test/service")

            # Insert another password with special characters
            complex_password = "p@ssw0rd!#\$%"
            insert(passdir, "complex/password", complex_password)

            @test store["complex/password"] == complex_password
            @test haskey(store, "complex/password")

            # Test nested paths work
            insert(passdir, "work/email/gmail", "gmail_pass")
            insert(passdir, "work/email/outlook", "outlook_pass")

            @test store["work/email/gmail"] == "gmail_pass"
            @test store["work/email/outlook"] == "outlook_pass"
            @test haskey(store, "work/email/gmail")
            @test haskey(store, "work/email/outlook")
        end
    end

    @testset "Basic functionality" begin
        mktempdir() do passdir
            init(passdir, gpgkey)
            store = PassStore(passdir)
            @test isnothing(get(store, "foo", nothing))
        end
    end
end
