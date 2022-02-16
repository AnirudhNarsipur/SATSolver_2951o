include("./dimacparser.jl")
#Checks the watchers of the clause and 
# returns literal if it exists
#guarenteed not to have empty clauses

function literalInState(ls::Vector{AbstractAssignment}, st::AbstractAssignment)
    any(map(x -> x == st, ls))
end

function checkAssignment(assigments::Dict{T,LiteralState}, literal::Number) where {T<:Number}
    as = assigments[abs(literal)]
    if (literal < 0 && as == Negative) || (literal > 0 && as == Positive)
        return Satisfied
    elseif as == Unset
        return Undecided
    else
        return Conflict
    end
end
function updateStack(inst::SATInstance, literal::Number)
    # println("pushing ",literal," at level ",length(inst.decisionStack))
    @assert 1 <= convert(inst.usignedtp, abs(literal))  <= inst.numVars
    inst.varAssignment[abs(literal)] = (literal > 0) ? Positive : Negative
    push2DElem(inst.decisionStack, convert(inst.usignedtp, abs(literal)) )
    return nothing
end
function newStackCall(inst::SATInstance)
    pushElem(inst.decisionStack, initializeDynamicVec(inst.usignedtp))
end
function unwindStack(inst::SATInstance)
    last = pop2DElem(inst.decisionStack)
    if last isa Bad
        return nothing
    elseif last isa Some
        # println("last is  ",last.value.vec)
        for i in last.value
            # println("i is ",i)
            # @assert 1 <= i <= inst.numVars
            inst.varAssignment[i] = Unset
        end
        return nothing
    else
        error("unreachable!")
    end
end

function setAssignment(inst::SATInstance, literal::Number)
    curr = checkAssignment(inst.varAssignment, literal)
    if curr == Satisfied
        None()
    elseif curr == Conflict
        Bad()
    elseif curr == Undecided
        updateStack(inst, literal)
        return None()
    else
        error("should not be reached")
    end
end
# Returns Option
function checkWatchers(assigs::Dict{T,LiteralState}, cls::Clause{K}) where {T,K}
    if length(cls.watchers) == 0
        as = checkAssignment(assigs, cls.literals[1])
        if as == Satisfied
            return None()
        elseif as == Conflict
            return Bad()
        elseif as == Undecided
            return Some(cls.literals[1])
        else
            error("not reachable")
        end
    else
        # @assert (length(cls.watchers) == 2)
        watcherst = map(x -> checkAssignment(assigs, cls.literals[x]), cls.watchers)
        if literalInState(watcherst, Satisfied)
            return None()
        elseif literalInState(watcherst, Conflict)
            literalsSt = map(x -> (x, checkAssignment(assigs, cls.literals[x])), 1:length(cls.literals))
            #TODO multi filter
            satlit = filter(x -> x[2] == Satisfied, literalsSt)
            undeclit = filter(x -> x[2] == Undecided, literalsSt)
            if !isempty(satlit)
                for (index, lit) in enumerate(satlit)
                    if index == 3
                        break
                    else
                        cls.watchers[index] = lit[1]
                    end
                end
                return None()
            else
                numUndec = length(undeclit)
                if numUndec == 0
                    return Bad()
                elseif numUndec == 1
                    return Some(cls.literals[undeclit[1][1]])
                else
                    @assert numUndec >= 2
                    cls.watchers[1] = undeclit[1][1]
                    cls.watchers[2] = undeclit[2][1]
                    return None()
                end
            end
        end
        None()
    end
    None()
end

function assignLiteral(inst::SATInstance, literals::Number)
    for lit in literals
        res = setAssignment(inst, lit)
        if res isa Bad
            return Bad
        end
    end
    return None
end

function propUnitLiterals(inst::SATInstance)
    cont = true
    while cont
        cont = false
        for clause in inst.clauses
            res = checkWatchers(inst.varAssignment, clause)
            if res isa None
                continue
            elseif res isa Bad
                return Bad()
            elseif res isa Some
                assignLiteral(inst, res.value)
                cont = true
                continue
            else
                error(join("should not be reached res was : ", res))
            end
        end
    end
    return None()
end


function verify_inst(inst::SATInstance)
    @assert length(keys(inst.varAssignment)) == inst.numVars
    for i = 1:inst.numVars
        @assert inst.varAssignment[i] == Unset
    end
    for key in keys(inst.varAssignment)
        @assert 1 <= key <= inst.numVars
    end
end
#Dumb Just assings everything to Positive
function pickVar(inst::SATInstance)
    for clause in inst.clauses
        for literal in clause.literals
            if checkAssignment(inst.varAssignment, literal) == Undecided
                return Some((abs(literal), (literal > 0) ? Positive : Negative))
            end
        end
    end
    return None()
end
function compDict(d1, d2, l)
    k1 = Set(keys(d1))
    k2 = Set(keys(d2))
    @assert k1 == k2
    for key in k1
        if d1[key] == d2[key]
            continue
        else
            error("For ", key, " ", d1[key], " is not ", d2[key], " at level ", l)
        end
    end
end
function opposite(x::LiteralState)
    if x == Positive
        Negative
    elseif x == Negative
        Positive
    else
        error("bad")
    end
end

function _dpll(inst::SATInstance)
    verify_inst(inst)
    function dpll()
        #BCP
        # println("dpll level ",i)
        newStackCall(inst)
        # @assert(length(inst.decisionStack) == i)
        res = propUnitLiterals(inst)
        if res isa Bad
            unwindStack(inst)
            return res
        else
            # @assert(length(inst.decisionStack) == i)
            VTB = pickVar(inst)
            if VTB isa None
                return None()
            else
                # @assert(length(inst.decisionStack) == i)
                VTB = VTB.value
                # println("VTB is ",VTB)
                @assert 1 <= VTB[1] <= inst.numVars
                inst.varAssignment[VTB[1]] = VTB[2]
                res = dpll()
                if res isa None
                    return res
                else
                    # @assert(length(inst.decisionStack) == i)
                    inst.varAssignment[VTB[1]] = opposite(VTB[2])
                    # compDict(inst.varAssignment,assig,i)
                    res = dpll()
                    if res isa Bad
                        inst.varAssignment[VTB[1]] = Unset
                        unwindStack(inst)
                    end
                    return res
                end
            end
        end
    end
    # verify_inst(inst)
    return dpll()
end

function calc_inst(fl::String)
    inst = read_cnf(fl)
    res = _dpll(inst)
    if res isa None
        giveOutput(fl, 1, SAT(inst.varAssignment))
    elseif res isa Bad
        giveOutput(fl, 1.23, UNSAT())
    else
        error("why oh why", res)
    end
end
@time calc_inst("small_inst/toy_solveable.cnf")
# @time calc_inst("small_inst/large.cnf")

# @time calc_inst("input/C140.cnf")
# @time calc_inst("test_inst/test3.cnf")
# inst = read_cnf("small_inst/toy_solveable.cnf")
# _dpll(inst)
# dc = keys(inst.varAssignment)