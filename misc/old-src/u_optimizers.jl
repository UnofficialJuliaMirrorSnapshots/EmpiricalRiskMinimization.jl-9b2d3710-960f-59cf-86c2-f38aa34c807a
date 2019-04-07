
"""
Minimization wrapper for unsupervised learning.
"""
function minimize_unsupervised(L::LossUnsupervised, R::RegularizerUnsupervised, X, k,
                               beta=0.8, alpha=0.5, init=nothing, t_init=1.0;
                               max_iters=5000, verbose=false, tol=1e-8)

    theta_X, theta_Y, losses = optimize_unsupervised(L, R, X, k,
                                                     alpha, beta, init, t_init,
                                                     t_min=1e-15,
                                                     max_iters=max_iters, verbose=verbose, tol=tol)
    return theta_X, theta_Y, losses
end



"""
Alternating minimization for unsupervised problems.
"""
function optimize_unsupervised(L::LossUnsupervised, R::RegularizerUnsupervised,
                               C, k, alpha=.5, beta=.8, init=nothing, t_init=1.0;
                               t_min=1e-15, verbose=true, max_iters=5000, tol=1e-8)

    n, d = size(C)
    decay = true

    if verbose
        info("Solving problem. Shape is $n by $d.")
    end

    # convenience functions
    LOSS(u, v) = eval(L, C, u, v)
    GRAD_X(u, v) = deriv(L, C, u, v, "X")
    GRAD_Y(u, v) = deriv(L, C, u, v, "Y")
    PROX(u) = prox(R, u)
    
    theta_X, theta_Y, losses = [], [], []
    
    if init == nothing
        init_X = rand(n, k)
        init_Y = rand(d, k)
    else 
        init_X = init["X"]
        init_Y = init["Y"]
    end
    
    if verbose
        info("The initial loss is $(LOSS(init_X, init_Y))")
        info("With gradient X $(GRAD_X(init_X, init_Y))")
        info("With gradient Y $(GRAD_Y(init_X, init_Y))")
    end

    assert(size(init_X)[1] == n)
    assert(size(init_Y)[1] == d)
    assert(size(init_X)[2] == k && size(init_Y)[2] == k)

    push!(theta_X, init_X)
    push!(theta_Y, init_Y)

    tx, ty = t_init, t_init

    progress_x, progress_y = true, true

    for k = 1:max_iters
        # Step for X
        curr_grad_x = GRAD_X(theta_X[end], theta_Y[end])
        grad_step_X = PROX(theta_X[end] - tx*curr_grad_x)

        progress_x = true
        prev_loss = LOSS(theta_X[end], theta_Y[end])

        while (LOSS(grad_step_X, theta_Y[end]) >= prev_loss)
            tx *= beta
            grad_step_X = PROX(theta_X[end] - tx*curr_grad_x)
            if tx < t_min
                progress_x = false
                break
            end
        end
        tx *= 2
        
        push!(theta_X, grad_step_X)
        
        # Step for Y
        curr_grad_y = GRAD_Y(theta_X[end], theta_Y[end])
        grad_step_Y = PROX(theta_Y[end] - ty*curr_grad_y)

        progress_y = true
        prev_loss = LOSS(theta_X[end], theta_Y[end])

        while (LOSS(theta_X[end], grad_step_Y) >= prev_loss)
            ty *= beta
            grad_step_Y = PROX(theta_Y[end] - ty*curr_grad_y)
            if ty < t_min
                progress_y = false
                break
            end
        end
        ty *= 2

        push!(theta_Y, grad_step_Y)
        push!(losses, LOSS(theta_X[end], theta_Y[end]))

        if verbose
            info("Iteration: $k,  Loss: $(losses[end])")
        end

        if (!progress_x && !progress_y)
            warn("Algorithm is not making any progress... breaking.")
            return theta_X, theta_Y, losses
        end

        if k > 4 && maximum(abs.(losses[end-4:end-1] - losses[end-3:end])) < tol
            info("Done.")
            return theta_X, theta_Y, losses
        end
    end
    print("Did not converge. Loss: $(losses[end])")
    return -1
end

