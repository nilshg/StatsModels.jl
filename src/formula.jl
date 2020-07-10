# Formulas for representing and working with linear-model-type expressions
# Original by Harlan D. Harris.  Later modifications by John Myles White,
# Douglas M. Bates, and other contributors.

## Formulas are written as expressions and parsed by the Julia parser.
## For example :(y ~ a + b + log(c))
## In Julia the & operator is used for an interaction.  What would be written
## in R as y ~ a + b + a:b is written :(y ~ a + b + a&b) in Julia.
## The equivalent R expression, y ~ a*b, is the same in Julia

## The lhs of a one-sided formula is 0
## The rhs of a formula can be 1

is_call(ex::Expr) = Meta.isexpr(ex, :call)
is_call(ex::Expr, op::Symbol) = Meta.isexpr(ex, :call) && ex.args[1] == op
is_call(::Any) = false
is_call(::Any, ::Any) = false
check_call(ex) = is_call(ex) || throw(ArgumentError("non-call expression encountered: $ex"))

catch_dollar(ex::Expr) =
    Meta.isexpr(ex, :$) && throw(ArgumentError("interpolation with \$ not supported in @formula.  Use @eval @formula(...) instead."))

"""
    @formula(ex)

Capture and parse a formula expression as a `Formula` struct.

A formula is an abstract specification of a dependence between _left-hand_ and
_right-hand_ side variables as in, e.g., a regression model.  Each side
specifies at a high level how tabular data is to be converted to a numerical
matrix suitable for modeling.  This specification looks something like Julia
code, is represented as a Julia `Expr`, but uses special syntax.  The `@formula`
macro takes an expression like `y ~ 1 + a*b`, transforms it according to the
formula syntax rules into a lowered form (like `y ~ 1 + a + b + a&b`), and
constructs a `Formula` struct which captures the original expression, the
lowered expression, and the left- and right-hand-side.

Operators that have special interpretations in this syntax are

* `~` is the formula separator, where it is a binary operator (the first
  argument is the left-hand side, and the second is the right-hand side.
* `+` concatenates variables as columns when generating a model matrix.
* `&` representes an _interaction_ between two or more variables, which
  corresponds to a row-wise kronecker product of the individual terms
  (or element-wise product if all terms involved are continuous/scalar).
* `*` expands to all main effects and interactions: `a*b` is equivalent to
  `a+b+a&b`, `a*b*c` to `a+b+c+a&b+a&c+b&c+a&b&c`, etc.
* `1`, `0`, and `-1` indicate the presence (for `1`) or absence (for `0` and
  `-1`) of an intercept column.

The rules that are applied are

* The associative rule (un-nests nested calls to `+`, `&`, and `*`).
* The distributive rule (interactions `&` distribute over concatenation `+`).
* The `*` rule expands `a*b` to `a+b+a&b` (recursively).
* Subtraction is converted to addition and negation, so `x-1` becomes `x + -1`
  (applies only to subtraction of literal 1).
* Single-argument `&` calls are stripped, so `&(x)` becomes the main effect `x`.
"""
macro formula(ex)
    is_call(ex, :~) || throw(ArgumentError("expected formula separator ~, got $(ex.head)"))
    length(ex.args) == 3 ||  throw(ArgumentError("malformed expression in formula $ex"))
    parse!(ex)
end

const SPECIALS = (:+, :&, :*, :~)


"""
    capture_call_ex!(ex::Expr, ex_parsed::Expr)

Capture a call to a function that is not part of the formula DSL.  This replaces
`ex` with a call to [`capture_call`](@ref).  `ex_parsed` is a copy of `ex` whose
arguments have been parsed according to the normal formula DSL rules and which 
will be passed as the final argument to `capture_call`.
"""
function capture_call_ex!(ex::Expr, ex_parsed::Expr)
    symbols = extract_symbols(ex)
    symbols_ex = Expr(:tuple, symbols...)
    f_anon_ex = esc(Expr(:(->), symbols_ex, copy(ex)))
    f_orig = ex.args[1]
    ex.args = [:capture_call,
               esc(f_orig),
               f_anon_ex,
               tuple(symbols...),
               Meta.quot(deepcopy(ex)),
               :[$(ex_parsed.args[2:end]...)]]
    return ex
end

function parse!(ex::Expr)
    catch_dollar(ex)
    check_call(ex)

    if ex.args[1] ∈ SPECIALS
        ex.args[1] = esc(ex.args[1])
        ex.args[2:end] .= parse!.(ex.args[2:end])
    else
        # capture non-special calls
        ex_parsed = deepcopy(ex)
        ex = capture_call_ex!(ex, ex_parsed)
        # final argument of capture_call holds parsed terms
        ex.args[end].args .= parse!.(ex.args[end].args)
    end
    return ex
    
end

parse!(::Nothing) = :(nothing)
parse!(s::Symbol) = :(Term($(Meta.quot(s))))
parse!(n::Number) = :(ConstantTerm($n))
