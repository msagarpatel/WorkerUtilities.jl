using Test, WorkerUtilities

@testset "WorkerUtilities" begin

    @testset "WorkerUtilities.@spawn" begin

        WorkerUtilities.init()
        threadid = fetch(WorkerUtilities.@spawn(Threads.threadid()))
        @test Threads.nthreads() == 1 ? (threadid == 1) : (threadid != 1)
        @test WorkerUtilities.@spawn(false, 1 + 1).storage === nothing

    end # @testset "WorkerUtilities.@spawn"

    @testset "Lockable" begin
        # Lockable{T, L<:AbstractLock}
        let # test the constructor `Lockable(value, lock)`
            lockable = Lockable(Dict("foo" => "hello"), ReentrantLock())
            @test lockable.value["foo"] == "hello"
            lock(lockable) do d
                @test d["foo"] == "hello"
            end
            lock(lockable) do d
                d["foo"] = "goodbye"
            end
            @test lockable.value["foo"] == "goodbye"
            lock(lockable) do d
                @test d["foo"] == "goodbye"
            end
        end
        let # test the constructor `Lockable(value)`
            lockable = Lockable(Dict("foo" => "hello"))
            @test lockable.value["foo"] == "hello"
            lock(lockable) do d
                @test d["foo"] == "hello"
            end
            lock(lockable) do d
                d["foo"] = "goodbye"
            end
            @test lockable.value["foo"] == "goodbye"
            lock(lockable) do d
                @test d["foo"] == "goodbye"
            end
        end
    end # @testset "Lockable"

    @testset "OrderedSynchronizer" begin

        x = OrderedSynchronizer()
        A = Vector{Int}(undef, 10)
        @sync for i = 10:-1:1
            @async put!(x, i) do
                A[i] = i
            end
        end
        @test A == 1:10

        reset!(x)
        A = Vector{Int}(undef, 10)
        @sync for i = 1:10
            @async put!(x, i) do
                A[i] = i
            end
        end
        @test A == 1:10

        reset!(x)
        A = Vector{Int}(undef, 10)
        @sync for i in (2, 1, 4, 3, 6, 5, 8, 7, 10, 9)
            @async put!(x, i) do
                A[i] = i
            end
        end
        @test A == 1:10

        reset!(x)
        A = Vector{Int}(undef, 4)
        @sync for (i, j) in zip((2, 1, 4, 3), (3, 1, 7, 5))
            @async put!(x, j, 2) do
                A[i] = j
            end
        end
        @test A == [1, 3, 5, 7]

    end

    @testset "ReadWriteLock" begin
        rw = ReadWriteLock()
        println("test read is blocked while writing")
        lock(rw)
        c = Channel()
        t = @async begin
            put!(c, nothing)
            readlock(rw)
            take!(c)
            readunlock(rw)
            true
        end
        take!(c)
        @test !istaskdone(t)
        unlock(rw)
        @test !istaskdone(t)
        put!(c, nothing)
        @test fetch(t)

        println("test write is blocked until reader done")
        readlock(rw)
        c = Channel()
        t = @async begin
            put!(c, nothing)
            lock(rw)
            take!(c)
            @test islocked(rw)
            unlock(rw)
            true
        end
        take!(c)
        @test !istaskdone(t)
        readunlock(rw)
        @test !istaskdone(t)
        put!(c, nothing)
        @test fetch(t)

        println("test write is blocked until readers done")
        readlock(rw)
        # readlock doesn't count as "locked"
        @test !islocked(rw)
        # start another reader
        secondReaderLocked = Ref(false)
        c = Channel()
        r2 = @async begin
            put!(c, nothing)
            readlock(rw)
            secondReaderLocked[] = true
            take!(c)
            readunlock(rw)
            true
        end
        take!(c)
        wc = Channel()
        t = @async begin
            put!(wc, nothing)
            lock(rw)
            take!(wc)
            unlock(rw)
            true
        end
        take!(wc)
        # write task not done
        @test !istaskdone(t)
        # first reader not done
        @test !istaskdone(r2)
        # but first reader did lock
        @test secondReaderLocked[]
        # start a third reader
        thirdReaderLocked = Ref(false)
        c2 = Channel()
        r3 = @async begin
            put!(c2, nothing)
            readlock(rw)
            thirdReaderLocked[] = true
            take!(c2)
            readunlock(rw)
            true
        end
        take!(c2)
        # no tasks have finished yet
        @test !istaskdone(t)
        @test !istaskdone(r2)
        @test !istaskdone(r3)
        # but third reader didn't lock because it's blocked
        # on a _pending_ write
        @test !thirdReaderLocked[]
        # unblock r2
        put!(c, nothing)
        # it should finish
        @test fetch(r2)
        # now unlock 1st reader so write can happen
        readunlock(rw)
        # write task should finish
        put!(wc, nothing)
        @test fetch(t)
        # now that write has finished, r3 should have lock
        put!(c2, nothing)
        @test thirdReaderLocked[]
        @test fetch(r3)
        @test !islocked(rw)
    end

end # @testset "WorkerUtilities"