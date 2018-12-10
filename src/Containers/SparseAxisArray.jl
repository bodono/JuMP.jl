#  Copyright 2017, Iain Dunning, Joey Huchette, Miles Lubin, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.

"""
    struct SparseAxisArray{T,N,K<:NTuple{N, Any}} <: AbstractArray{T,N}
        data::Dict{K,T}
    end

`N`-dimensional array with elements of type `T` where only a subset of the
entries are defined. The entries with indices `idx = (i1, i2, ..., iN)` in
`keys(data)` has value `data[idx]`. Note that as opposed to
`SparseArrays.AbstractSparseArray`, the missing entries are not assumed to be
`zero(T)`, they are simply not part of the array. This means that the result of
`map(f, sa::SparseAxisArray)` or `f.(sa::SparseAxisArray)` has the same sparsity
structure than `sa` even if `f(zero(T))` is not zero.
"""
struct SparseAxisArray{T,N,K<:NTuple{N, Any}} <: AbstractArray{T,N}
    data::Dict{K,T}
end

Base.length(sa::SparseAxisArray) = length(sa.data)
Base.IteratorSize(::Type{<:SparseAxisArray}) = Base.HasLength()
# By default `IteratorSize` for `Generator{<:AbstractArray{T,N}}` is
# `HasShape{N}`
Base.IteratorSize(::Type{Base.Generator{<:SparseAxisArray}}) = Base.HasLength()
Base.iterate(sa::SparseAxisArray, args...) = iterate(values(sa.data), args...)

# A `length` argument can be given because `IteratorSize` is `HasLength`
function Base.similar(sa::SparseAxisArray{S,N,K}, ::Type{T},
                      length::Integer=0) where {S, T, N, K}
    d = Dict{K, T}()
    if !iszero(length)
        sizehint!(d, length)
    end
    return SparseAxisArray(d)
end
# The generic implementation uses `LinearIndices`
function Base.collect_to_with_first!(dest::SparseAxisArray, first_value, iterator,
                                     state)
    indices = eachindex(iterator)
    dest[first(indices)] = first_value
    for index in Iterators.drop(indices, 1)
        element, state = iterate(iterator, state)
        dest[index] = element
    end
    return dest
end

function Base.mapreduce(f, op, sa::SparseAxisArray)
    mapreduce(f, op, values(sa.data))
end
Base.:(==)(sa1::SparseAxisArray, sa2::SparseAxisArray) = sa1.data == sa2.data

############
# Indexing #
############

Base.haskey(sa::SparseAxisArray, idx) = haskey(sa.data, idx)
function Base.haskey(sa::SparseAxisArray{T,1,Tuple{I}}, idx::I) where {T, I}
    return haskey(sa.data, (idx,))
end

Base.eachindex(g::Base.Generator{<:SparseAxisArray}) = eachindex(g.iter)

# Error for sa[..., :, ...]
function _colon_error() end
function _colon_error(::Colon, args...)
    throw(ArgumentError("Indexing with `:` is not supported by" *
                        " Containers.SparseAxisArray"))
end
_colon_error(arg, args...) = _colon_error(args...)
function Base.setindex!(d::SparseAxisArray{T, N, K}, value,
                        idx::K) where {T, N, K<:NTuple{N, Any}}
    setindex!(d, value, idx...)
end
function Base.setindex!(d::SparseAxisArray, value, idx...)
    _colon_error(idx...)
    setindex!(d.data, value, idx)
end
function Base.getindex(d::SparseAxisArray{T, N, K},
                       idx::K) where {T, N, K<:NTuple{N, Any}}
    getindex(d, idx...)
end
function Base.getindex(d::SparseAxisArray, idx...)
    _colon_error(idx...)
    getindex(d.data, idx)
end
Base.eachindex(d::SparseAxisArray) = keys(d.data)

# Need to define it as indices may be non-integers
Base.to_index(d::SparseAxisArray, idx) = idx

Base.IndexStyle(::Type{<:SparseAxisArray}) = IndexAnyCartesian()
# eachindex redirect to keys
Base.keys(::IndexAnyCartesian, d::SparseAxisArray) = keys(d)

################
# Broadcasting #
################

# Need to define it as indices may be non-integers
Base.Broadcast.newindex(d::SparseAxisArray, idx) = idx

struct BroadcastStyle{N, K} <: Broadcast.BroadcastStyle end
function Base.BroadcastStyle(::BroadcastStyle, ::Base.BroadcastStyle)
    throw(ArgumentError("Cannot broadcast Containers.SparseAxisArray with" *
                        " another array of different type"))
end
# Scalars can be used with SparseAxisArray in broadcast
function Base.BroadcastStyle(::BroadcastStyle{N, K},
                             ::Base.Broadcast.DefaultArrayStyle{0}) where {N, K}
    return BroadcastStyle{N, K}()
end
function Base.BroadcastStyle(::Type{<:SparseAxisArray{T, N, K}}) where {T, N, K}
    return BroadcastStyle{N, K}()
end
function Base.similar(b::Base.Broadcast.Broadcasted{BroadcastStyle{N, K}},
                      ::Type{T}) where {T, N, K}
    SparseAxisArray(Dict{K, T}())
end

# Check that all `SparseAxisArray`s involved have the same indices. The other
# arguments are scalars
function check_same_eachindex(each_index) end
check_same_eachindex(each_index, not_sa, args...) = check_same_eachindex(eachindex, args...)
function check_same_eachindex(each_index, sa::SparseAxisArray, args...)
    if Set(each_index) != Set(eachindex(sa))
        throw(ArgumentError("Cannot broadcast Containers.SparseAxisArray with" *
                            " different indices"))
    end
    check_same_eachindex(eachindex, args...)
end
_eachindex(not_sa, args...) = _eachindex(args...)
function _eachindex(sa::SparseAxisArray, args...)
    each_index = eachindex(sa)
    check_same_eachindex(each_index, args...)
    return each_index
end
# Need to define it as it falls back to `axes` by default
function Base.eachindex(bc::Base.Broadcast.Broadcasted{<:BroadcastStyle})
    return _eachindex(bc.args...)
end

# The fallback uses `axes` but recommend in the docstring to create a custom
# method for custom style if needed.
Base.Broadcast.instantiate(bc::Base.Broadcast.Broadcasted{<:BroadcastStyle}) = bc

# The generic method in `Base` is `getindex(::Broadcasted, ::Union{Integer, CartesianIndex})`
# which is not applicable here since the index is not integer
# TODO make a change in `Base` so that we don't have to call a function starting
# with an `_`.
function Base.getindex(bc::Base.Broadcast.Broadcasted{<:BroadcastStyle}, I)
    return Base.Broadcast._broadcast_getindex(bc, I)
end

# The generic implementation fall back to converting `bc` to
# `Broadcasted{Nothing}`. It is advised in `Base` to define a custom method for
# custom styles. The fallback for `Broadcasted{Nothing}` is not appropriate as
# indices are not integers for `SparseAxisArray`.
function Base.copyto!(dest::SparseAxisArray{T, N, K},
                      bc::Base.Broadcast.Broadcasted{BroadcastStyle{N, K}}) where {T, N, K}
    for key in eachindex(bc)
        dest[key] = bc[key]
    end
    return dest
end

########
# Show #
########

# Inspired from Julia SparseArrays stdlib package
function Base.show(io::IO, ::MIME"text/plain", sa::SparseAxisArray)
    num_entries = length(sa.data)
    print(io, typeof(sa), " with ", num_entries,
              isone(num_entries) ? " entry" : " entries")
    if !iszero(num_entries)
        println(io, ":")
        show(io, sa)
    end
end
Base.show(io::IO, x::SparseAxisArray) = show(convert(IOContext, io), x)
function Base.show(io::IOContext, x::SparseAxisArray)
    # TODO: make this a one-line form
    if isempty(x)
        return show(io, MIME("text/plain"), x)
    end
    limit::Bool = get(io, :limit, false)
    half_screen_rows = limit ? div(displaysize(io)[1] - 8, 2) : typemax(Int)
    key_string(key::Tuple) = join(key, ", ")
    print_entry(i) = i < half_screen_rows || i > length(x) - half_screen_rows
    pad = maximum(Int[print_entry(i) ? length(key_string(key)) : 0 for (i, key) in enumerate(keys(x.data))])
    if !haskey(io, :compact)
        io = IOContext(io, :compact => true)
    end
    for (i, (key, value)) = enumerate(x.data)
        if print_entry(i)
            print(io, "  ", '[', rpad(key_string(key), pad), "]  =  ", value)
            if i != length(x)
                println(io)
            end
        elseif i == half_screen_rows
            println(io, "   ", " "^pad, "   \u22ee")
        end
    end
end