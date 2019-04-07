##############################################################################
# Model and alternative constructors. 
"""`Model(...)`

The `Model()` function constructs an ERM model. The typical invocation is 
`Model(U, V, Loss(), Reg())`, where `U` and `V` specify raw inputs and targets, 
respectively, and `Loss()` specifies some type of training loss (default: `SquareLoss()`)
and `Reg()` specifies some type of regularizer (default: `L2Reg()`). 
For more details, see the description of ERM models in the usage notes. 
"""

using Random

mutable struct Model
    D::Data
    loss::Loss
    regularizer::Regularizer
    solver::Solver
    S::DataSource
    X
    Y
    regweights
    istrained::Bool
    verbose::Bool
    xydataisinvalid::Bool
    disinvalid::Bool
    Uestnumcols
    Vestnumcols
    embedallwarning::Bool
end


function Model(U, V; loss=SquareLoss(), reg=L2Reg(),
               Unames = nothing, Vnames = nothing,
               embedall = true, verbose=true,
               Uestnumcols = 0, Vestnumcols=0, kwargs...)
    S = makeFrameSource(U, V, Unames, Vnames; kwargs...)
    M =  Model(NoData(),
               loss,
               reg,
               DefaultSolver(),
               S,
               nothing, nothing, #X,Y
               nothing, #regweights
               false, #istrained
               verbose, #verbose
               true, # xydataisinvalid
               true,  # disinvalid
               Uestnumcols, Vestnumcols,
               false)
    setdata(M)
    if embedall
        if M.verbose
            println("Model: applying default embedding")
        end
        defaultembedding(M; kwargs...)
        M.embedallwarning = true
    end
    return M
end
##############################################################################
function getfoldrows(n, nfolds)
    # split into groups
    groups = [convert(Int64, round(x*n/nfolds)) for x in 1:nfolds]
    unshift!(groups,0)
    # i'th fold has indices groups[i]+1:groups[i+1]
    p = randperm(n)
    foldrows = Any[]
    nonfoldrows = Any[]
    for i=1:nfolds
        push!(foldrows, sort(p[groups[i]+1:groups[i+1]]))
        push!(nonfoldrows, sort([ p[1:groups[i]] ; p[groups[i+1]+1:end]]))
    end
    return foldrows, nonfoldrows
end

function splitrows(n, trainfrac::Array{Int64,1})
    trainrows = trainfrac
    allrows = Set(1:n)
    trainset = Set(copy(trainrows))
    testrows = sort(collect(setdiff(allrows, trainset)))
    return trainrows, testrows
end

function splitrows(n, trainfrac::Number; splitmethod=0)
    if splitmethod == 0
        ntrain = convert(Int64, round(trainfrac*n))
        p = randperm(n)
        trainrows = sort(p[1:ntrain])
        testrows = sort(p[ntrain+1:n])
    else
        # pick by Bernoulli
        testrows = Int64[]
        trainrows = Int64[]
        for i=1:n
            if rand()>trainfrac
                push!(testrows,i)
            else
                push!(trainrows,i)
            end
        end
    end
    return trainrows, testrows
end

function setdata(M::Model)
    M.X, M.Y  = getXY(M.S; Uestnumcols = M.Uestnumcols, Vestnumcols = M.Vestnumcols, verbose=M.verbose)
    M.xydataisinvalid = false
    setregweights(M)
    return
end

function setregweights(M::Model)
    if M.xydataisinvalid
        return
    end
    X = M.X
    d = size(X,2)
    R = ones(d)
    for i=1:d
        if Statistics.var(X[:,i]) == 0
            if norm(X[:,i]) != 0
                R[i] = 0
            end
        end
    end
    M.regweights = R
end

# function defaultembedding(M::Model; stand=true)
#     addfeatureV(M, 1, stand=stand)
#     addfeatureU(M, etype="one")
#     d = size(getU(M),2) 
#     for i=1:d
#         addfeatureU(M, i, stand=stand)
#     end
# end

function defaultembedding(M::Model; stand=true, kwargs...)
    addfeatureV(M, 1, stand=stand)
    addfeatureU(M, etype="all", stand=stand, addones=true, kwargs...)
end

##############################################################################


function SplitData(X, Y, trainfrac)
    trainrows, testrows = splitrows(size(X,1), trainfrac)
    Xtrain = X[trainrows,:]
    Ytrain = Y[trainrows,:]
    Xtest = X[testrows,:]
    Ytest = Y[testrows,:]
    return SplitData(Xtrain, Ytrain, Xtest, Ytest, trainrows, testrows, trainfrac, NoResults())
end




function FoldedData(X, Y, nfolds)
    foldrows, nonfoldrows = getfoldrows(size(X,1), nfolds)
    return FoldedData(X, Y, nfolds, foldrows, nonfoldrows, NoResults())
end

##############################################################################

function warndata(M)
    if length(M.S.Xmaps)==0
        println("Warning: Model has no X data. Use addfeatureU or Model(...,embedall=true)")
    end
    if length(M.S.Ymaps)==0
        println("Warning: Model has no Y data. Use addfeatureV or Model(...,embedall=true)")
    end
end
function splittraintestx(M, trainfrac)
    setdata(M)
    if M.verbose
        println("Model: splitting data")
    end
    M.D = SplitData(M.X, M.Y, usetrainfrac(M, trainfrac))
    M.disinvalid = false
end

function usetrainfrac(M::Model, trainfrac)
    if trainfrac==nothing
        if isa(M.D, SplitData)
            return M.D.trainfrac
        end
        return 0.8
    end
    return trainfrac
end
        
function splittraintest(M::Model; trainfrac=nothing, resplit=false, force=false)
    if resplit || force
        M.disinvalid = true
    end
    if !M.disinvalid && isa(M.D, SplitData)
        if trainfrac != nothing && trainfrac != M.D.trainfrac
            M.disinvalid = true
        end
    end
    if M.disinvalid ||  !isa(M.D, SplitData)
        splittraintestx(M, trainfrac)
    end
end

function splitfolds(M::Model, nfolds; resplit=false, force=false)
    if resplit || force 
        M.disinvalid = true
    end
    if !M.disinvalid && isa(M.D, FoldedData)
        if M.D.nfolds != nfolds
            M.disinvalid = true
        end
    end

    if M.disinvalid || !isa(M.D, FoldedData)
        setdata(M)
        M.D = FoldedData(M.X, M.Y, nfolds)
        M.disinvalid = false
    end
end




##############################################################################
# fit

function trainx(M::Model, lambda, Xtrain, Xtest, Ytrain, Ytest; theta_guess = nothing)
    assignsolver(M)
    if M.verbose
        println("Model: calling solver: ", M.solver)
        for i=1:length(M.regweights)
            if M.regweights[i] == 0
                println("Model: Not regularizing constant feature X[:,$(i)]")
            end
        end
    end
    theta = solve(M.solver, M.loss, M.regularizer, M.regweights, Xtrain, Ytrain, lambda;
                  theta_guess = theta_guess)
    trainloss = loss(M.loss, predict(M, Xtrain, theta), Ytrain)
    testloss = loss(M.loss,  predict(M, Xtest,  theta), Ytest)
    return PointResults(theta, lambda, trainloss, testloss)
end


function trainfoldsx(M::Model, lambda, nfolds)
    results = Array{PointResults}(nfolds)
    for i=1:nfolds
        results[i] =  trainx(M, lambda, Xtrain(M,i), Xtest(M,i), Ytrain(M,i), Ytest(M,i))
    end
    return FoldResults(results)
end


function trainpathx(M::Model, lambda::Array; quiet=true, kwargs...)
    m = length(lambda)
    results = Array{PointResults}(m)
    for i=1:m
        if i>1
            tg = results[i-1].theta
        else
            tg = nothing
        end
        if M.verbose
            println("lambda = ", lambda[i])
        end
        results[i] = trainx(M, lambda[i], Xtrain(M), Xtest(M), Ytrain(M), Ytest(M);
                            theta_guess = tg)
    end
    imin =  findmin([x.testloss for x in results])[2]
    return RegPathResults(results, imin)
end

"""`trainfolds(M [,lambda=1e-10, nfolds=5])` 

The `trainfolds` function carries out n-fold cross validation on 
a model `M`. Specify regularization weight through optional argument
`lambda`, and the number of folds through `nfolds`. Default: 
`lambda=1e-10`, and `nfolds=5`.
"""
function trainfolds(M::Model; lambda=1e-10, nfolds=5,
                    resplit=false, features=nothing, kwargs...)
    warndata(M)
    splitfolds(M, nfolds, resplit)
    M.D.results = trainfoldsx(M, lambda, nfolds)
    M.istrained = true
    if M.verbose
        status(M)
    end
end

"""`trainpath(M [,lambda=logspace(-5, 5, 100), trainfrac=0.8])`

The `trainpath` function trains a model `M` over a set of regularization weights. 
Specify these weights by invoking the optional argument `lambda`, and set a train-test 
ratio by using the optional argument `trainfrac`. 

Defaults: 
 -  `lambda=logspace(-5,5,100)` so training occurs over `lambda` between 1e-5 and 
1e5. 
 - `trainfrac=0.8`, so training occurs with a 80-20 train-test split.

Example: `trainpath(M, lambda=logspace(-1, 1, 100))` trains over `lambda` between
0.1 and 10. 

Example `trainpath(M, trainfrac=0.75)` trains w/ 75-25 train-test split.
"""
function trainpath(M::Model; lambda=logspace(-5,5,100), trainfrac=0.8,
                   resplit=false, features=nothing, kwargs...)
    warndata(M)
    splittraintest(M; trainfrac=trainfrac, resplit=resplit)
    M.D.results = trainpathx(M, lambda)
    M.istrained = true
    if M.verbose
        status(M)
    end
end

"""`train(M [, lambda=1e-10, trainfrac=nothing])` 
This function trains a model `M`. The usual invocation is 
`train(M)`. Users may choose to specify a different choice of 
regularization weight `lambda`. For example to specify 
a weight of `lambda = 0.01`, one invokes 
`train(M, lambda=0.001)`, and to specify a different train split, 
one invokes `train(M, trainfrac=0.75)`, which means that 
75 percent of the data will be used for training and only 25 percent will 
be used for test. The default parameters are 
`lambda = 1e-10` and `trainfrac=nothing`, which will result in a 
80-20 train-test split."""
function train(M::Model; lambda=1e-10, trainfrac=nothing,
               resplit=false, kwargs...)
    warndata(M)
    splittraintest(M; trainfrac=trainfrac, resplit=resplit)
    M.D.results = trainx(M, lambda, Xtrain(M), Xtest(M), Ytrain(M), Ytest(M); kwargs...)
    M.istrained = true
    if M.verbose
        status(M)
    end
end

##############################################################################

function assignsolver(M::Model, force=false)
    if force || isa(M.solver, DefaultSolver) 
        M.solver = getsolver(M.loss, M.regularizer)
    end
end



function setloss(M::Model, l)
    M.loss = l
    assignsolver(M, true)
end
function setreg(M::Model, r)
    M.regularizer = r
    assignsolver(M, true)
end
function setsolver(M::Model, s)
    if s == "default"
        assignsolver(M, true)
        return
    end
    M.solver = s
end
    


##############################################################################
# querying

getU(M::Model) = getU(M.S)
getV(M::Model) = getV(M.S)
#getXY(M::Model) = getXY(M.S)


Xtest(M::Model) = Xtest(M.D)
Xtrain(M::Model) =  Xtrain(M.D)
Xtrain(D::SplitData) = D.Xtrain
Xtest(D::SplitData) = D.Xtest
Utrain(M::Model) = getU(M.S)[M.D.trainrows,:]
Utest(M::Model)  = getU(M.S)[M.D.testrows,:]
Vtrain(M::Model) = getV(M.S)[M.D.trainrows,:]
Vtest(M::Model)  = getV(M.S)[M.D.testrows,:]


Xtest(M::Model, fold) = Xtest(M.D, fold)
Xtrain(M::Model, fold) = Xtrain(M.D, fold)
Xtrain(D::FoldedData, fold) = D.X[D.nonfoldrows[fold],:]
Ytrain(D::FoldedData, fold) = D.Y[D.nonfoldrows[fold],:]
Xtest(D::FoldedData, fold) = D.X[D.foldrows[fold],:]
Ytest(D::FoldedData, fold) = D.Y[D.foldrows[fold],:]
Ytest(M::Model, fold) = Ytest(M.D, fold)
Ytrain(M::Model, fold) = Ytrain(M.D, fold)

Ytest(M::Model) = Ytest(M.D)
Ytrain(M::Model) = Ytrain(M.D)
Ytrain(D::SplitData) = D.Ytrain
Ytest(D::SplitData) = D.Ytest

import Base.split
split(M::Model; kwargs...) = splittraintest(M; force=true, kwargs...)


function warnembeddings(M)
    if !M.verbose
        return
    end
    if !M.embedallwarning
        return
    end
    println("Warning: You are adding features to a model which was created with embedall=true")
end

function addfeatureU(M::Model; kwargs...)
    warnembeddings(M)
    M.xydataisinvalid = true
    M.disinvalid = true
    addfeatureU(M.S, nothing; kwargs...)
end

function addfeatureV(M::Model; kwargs...)
    warnembeddings(M)
    M.xydataisinvalid = true
    M.disinvalid = true
    addfeatureV(M.S, nothing; kwargs...)
end

function addfeatureU(M::Model, col; kwargs...)
    warnembeddings(M)
    M.xydataisinvalid = true
    M.disinvalid = true
    addfeatureU(M.S, col; kwargs...)
end

function addfeatureV(M::Model, col; kwargs...)
    warnembeddings(M)
    M.xydataisinvalid = true
    M.disinvalid = true
    addfeatureV(M.S, col; kwargs...)
end



##############################################################################

function status(io::IO, R::RegPathResults)
    println(io, "----------------------------------------")
    println(io, "Optimal results along regpath")
    println(io, "  optimal lambda: ",  lambdaopt(R))
    println(io, "  optimal test loss: ", testloss(R))
end

function status(io::IO, R::PointResults)
    println(io, "----------------------------------------")
    println(io, "Results for single train/test")
    println(io, "  training  loss: ", trainloss(R))
    println(io, "  test loss: ", testloss(R))
end

"""
Prints and returns the status of the model.
"""
function status(io::IO, M::Model)
    status(io, M.D.results)
    println(io, "  training samples: ", length(Ytrain(M)))
    println(io, "  test samples: ", length(Ytest(M)))
    println(io, "  columns in X: ", size(M.X,2))
    println(io, "----------------------------------------")
end

"""`status(M)` prints the status of the model after the most recent action performed on it."""
status(M::Model; kwargs...)  = status(stdout, M; kwargs...)



