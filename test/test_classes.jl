using Test
using Classes
using Suppressor
using MacroTools: striplines

@test superclass(Class) === nothing

@test isclass(AbstractClass) == false       # not concrete
@test isclass(Int) == false                 # not <: AbstractClass

@class Foo <: Class begin
   foo::Int

   Foo() = Foo(0)

   # Although Foo is immutable, subclasses might not be,
   # so it's still useful to define this method.
   function Foo(self::absclass(Foo))
        self.foo = 0
    end
end

@test classof(AbstractFoo) == Foo
@test classof(Foo) == Foo

@test superclass(Foo) == Class
@test_throws Exception superclass(AbstractFoo)

function clean_str(s)
    s = replace(s, r"\n" => " ")
    s = replace(s, r"\s\s+" => " ")
end

@class mutable Bar <: Foo begin
    bar::Int

    # Mutable classes can use this pattern
    function Bar(self::Union{Nothing, absclass(Bar)}=nothing)
        self = (self === nothing ? new() : self)
        superclass(Bar)(self)
        Bar(self, 0)
    end
end

@class mutable Baz <: Bar begin
   baz::Int

   function Baz(self::Union{Nothing, absclass(Baz)}=nothing)
        self = (self === nothing ? new() : self)
        superclass(Baz)(self)
        Baz(self, 0)
    end
end

# emitted by class Foo
# @method foo(obj::Foo) = obj.foo

@method function sum(obj::Bar)
    return obj.foo + obj.bar
end

@test Set(superclasses(Baz)) == Set([Foo, Bar, Class])
@test Set(subclasses(Foo)) == Set(Any[Bar, Baz])

x = Foo(1)
y = Bar(10, 11)
z = Baz(100, 101, 102)

@test fieldnames(Foo) == (:foo,)
@test fieldnames(Bar) == (:foo, :bar)
@test fieldnames(Baz) == (:foo, :bar, :baz)

@method foo(x::Foo) = x.foo

@test foo(x) == 1
@test foo(y) == 10
@test foo(z) == 100

@test sum(y) == 21

@method get_bar(x::Bar) = x.bar

@test get_bar(y) == 11
@test get_bar(z) == 101

@test_throws Exception get_bar(x)

# Mutable
@method set_foo!(x::Foo, value) = (x.foo = value)
set_foo!(z, 1000)
@test foo(z) == 1000

# Immutable
@test_throws Exception x.foo = 1000

# test that where clause is amended properly
@method zzz(obj::Foo, bar::T) where {T} = T

@test zzz(x, :x) == Symbol
@test zzz(y, 10.6) == Float64

# Test other @class structural errors
@test_throws(LoadError, eval(Meta.parse("@class X2 x y")))
@test_throws(LoadError, eval(Meta.parse("@class (:junk,)")))

# Test that classof fails if an abstract class has multiple concrete classes
@class Blink <: Baz
struct RenegadeStruct <: AbstractBlink end

@test_throws Exception classof(AbstractBlink)

# Test that parameterized type is handled properly
@class TupleHolder{NT <: NamedTuple} begin
    nt::NT
end

nt = (foo=1, bar=2)
NT = typeof(nt)
th = TupleHolder{NT}(nt)

@test typeof(th).parameters[1] == NT
@test th.nt.foo == 1
@test th.nt.bar == 2

# Test updating using instance of parent class
bar = Bar(1, 2)
baz = Baz(100, 101, 102)

upd = Baz(bar, 555)
@test upd.foo == 1 && upd.bar == 2 && upd.baz == 555

# ...and with parameterized types
@class mutable SubTupleHolder{NT <: NamedTuple} <: Baz begin
    nt::NT
end

sub = SubTupleHolder{NT}(z, nt)
@test sub.nt.foo == 1 && sub.nt.bar == 2 && sub.foo == 1000 && sub.bar == 101 && sub.baz == 102

xyz = SubTupleHolder(sub, 10, 20, 30, (foo=111, bar=222))
@test xyz.nt.foo == 111 && xyz.nt.bar == 222 && xyz.foo == 10

# Test method structure)
# "First argument of method whatever must be explicitly typed"
@test_throws(LoadError, eval(Meta.parse("@method whatever(i) = i")))

expr = quote
    abstract type AbstractX <: AbstractClass end
    struct X{} <: AbstractX
        function X()
            #= /Users/rjp/.julia/dev/Classes/src/Classes.jl:136 =#
            new()
        end
        function X(_self::T) where T <: AbstractX
            _self
        end
    end
    Classes.superclass(::Type{X}) = begin
            Class
        end
    X
end

expected1 = striplines(expr)
emitted1  = striplines(Classes._defclass(:X, Class, false, nothing, []))

@test string(expected1) == string(emitted1)

expr = quote
    abstract type AbstractX <: AbstractClass end
    mutable struct X{NT <: NamedTuple} <: AbstractX
        i::Int
        j::Int
        function X{NT}(i::Int, j::Int) where NT <: NamedTuple
            new{NT}(i, j)
        end
        function X(_self::T, i::Int, j::Int) where {T <: AbstractX, NT <: NamedTuple}
            _self.i = i
            _self.j = j
            _self
        end
    end
    Classes.superclass(::Type{X}) = begin
            Class
        end
    X
end

expected2 = striplines(expr)
emitted2  = striplines(Classes._defclass(:X, Class, true, [:(NT <: NamedTuple)], [:(i::Int), :(j::Int)]))

@test string(expected2) == string(emitted2)
