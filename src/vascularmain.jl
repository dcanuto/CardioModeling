importall CVModule

function main()

rstflag = "yes" # restart from prior solution, filename format must follow fnames below
hemoflag = "no" # 10% total blood vol. hemorrhage from left femoral artery
saveflag = "yes" # save solution file to .mat struct
coupleflag = "no" # coupling with 3D organ model via ZMQ
assimflag = "yes" # patient data assimilation via EnKF to tune model state & params.
ptbflag = "no" # generate ensemble via random perturbations, ONLY USE ONCE

ensemblesize = 6;
if rstflag == "no"
    fnames = ["arterytree.csv" for i=1:ensemblesize];
elseif rstflag == "yes"
    fnames = ["sparse12_$i.mat" for i=1:ensemblesize];
end

systems = pmap((a1)->CVModule.buildall(a1;numbeatstotal=1,restart=rstflag,
    injury=hemoflag,assim=assimflag),fnames);

println("Reference β: $(systems[1].branches.beta[61][end])")
println("Reference A0: $(systems[1].branches.A0[61][end])")

if ptbflag == "yes"
    # systems = pmap((a1)->CVModule.perturbics!(a1),systems);
    for i = 2:length(systems) # using 1st system as reference for measurements
        CVModule.perturbics!(systems[i])
        println("β for ensemble member $(i-1): $(systems[i].branches.beta[61][end])")
        println("A0 for ensemble member $(i-1): $(systems[i].branches.A0[61][end])")
    end
end

n = [systems[1].solverparams.nstart for i=1:ensemblesize];

# if coupleflag == "yes"
#     ctx=ZMQ.Context();
#     sender=ZMQ.Socket(ctx,ZMQ.REQ);
#     ZMQ.connect(sender,"tcp://127.0.0.1:5555");
# end

if assimflag == "yes"
    # allocators for ensemble augmented state, measurements
    X = [zeros(systems[1].solverparams.JL + length(systems[1].error.pdev)) for i in (1:length(systems)-1)];
    # Y = [zeros(systems[1].solverparams.JL) for i in (1:length(systems)-1)];
    Y = [zeros(1) for i in (1:length(systems)-1)];

    # allocators for state, measurement mean
    xhat = zeros(systems[1].solverparams.JL + length(systems[1].error.pdev));
    # yhat = zeros(systems[1].solverparams.JL);
    yhat = zeros(1);

    # output variables
    println("Number of steps: $(systems[1].solverparams.numsteps)")
    println("Steps between samples: $(systems[1].pdata.nsamp)")
    βhat = zeros(Int(cld(systems[1].solverparams.numsteps,systems[1].pdata.nsamp))+1);
    A0hat = zeros(Int(cld(systems[1].solverparams.numsteps,systems[1].pdata.nsamp))+1);
    Phat = zeros(Int(cld(systems[1].solverparams.numsteps,systems[1].pdata.nsamp))+1,systems[1].solverparams.JL);
    numassims = 0;
    println("Number of assimilations: $(Int(cld(systems[1].solverparams.numsteps,systems[1].pdata.nsamp+1)))")

    # allocators for calculating normalized RMSE ratio
    r1dot = 0;
    r2dot = zeros(ensemblesize-1);

    # parameter distribution smoothing
    δ = 0.985;
    a = (3*δ-1)/(2*δ);
    h = sqrt.(1-a^2);
end

tic();
while systems[1].solverparams.numbeats < systems[1].solverparams.numbeatstotal
    soln = pmap((a1,a2)->CVModule.advancetime!(a1,a2;injury=hemoflag),systems,n);
    systems = [soln[i][1] for i in 1:length(soln)];
    n = [soln[i][2] for i in 1:length(soln)];
    if assimflag == "yes"
        println("Current time: $(systems[1].t[n[1]+1])")
        # measurement
        # y = systems[1].branches.P[61][n[1]+1,:];
        y = systems[1].branches.P[61][n[1]+1,6];
        # ensemble forecast state and measurements
        X = [systems[i].branches.A[61][n[i]+1,:] for i in 2:length(soln)];
        # augment state w/ forecast parameters
        # p1bar = 0;
        p2bar = 0;
        for i = 2:length(soln)
            # p1bar += systems[i].branches.beta[61][end];
            p2bar += systems[i].branches.A0[61][end];
        end
        # p1bar /= (ensemblesize-1);
        p2bar /= (ensemblesize-1);
        for i = 2:length(soln)
            # p1 = rand(Distributions.Normal(a*systems[i].branches.beta[61][end]+(1-a)*p1bar,h*systems[1].error.pdev[1]));
            p2 = rand(Distributions.Normal(a*systems[i].branches.A0[61][end]+(1-a)*p2bar,h*systems[1].error.pdev[2]));
            # p1 = systems[i].branches.beta[61][end] + rand(Distributions.Normal(0,systems[1].error.pdev[1]));
            # p2 = systems[i].branches.A0[61][end] + rand(Distributions.Normal(0,systems[1].error.pdev[2]));
            append!(X[i-1],[p2])
            # append!(X[i-1],[p1,p2])
        end
        # println("Forecast X: $X")
        # println("Type of X: $(typeof(X))")
        # println("Size of X: $(size(X))")
        # Y = [systems[i].branches.P[61][n[i]+1,:] for i in 2:length(soln)];
        Y = [systems[i].branches.P[61][n[i]+1,6] for i in 2:length(soln)];
        # println("Type of Y: $(typeof(Y))")
        # println("Size of Y: $(size(Y))")
        # println("Y: $Y")
        # ensemble mean state, measurement
        xhat = mean(X);
        yhat = mean(Y);
        # βhat[numassims+1] = xhat[end-1];
        A0hat[numassims+1] = xhat[end];
        Phat[numassims+1,:] = yhat;
        numassims+=1;
        println("̂x: $xhat")
        println("̂y: $yhat")
        # forecast state/meas. cross covariance, meas. covariance
        Pxy = zeros(length(xhat),length(yhat))
        Pyy = zeros(length(yhat),length(yhat))
        for i = 2:length(soln)
            Pxy += *((X[i-1] - xhat),(Y[i-1] - yhat)');
            Pyy += *((Y[i-1] - yhat),(Y[i-1] - yhat)');
        end
        Pxy /= (ensemblesize-1);
        Pyy /= (ensemblesize-1);
        # add meas. noise to meas. covariance (allows invertibility)
        Pyy += diagm(systems[1].error.odev[1]^2*ones(length(yhat)),0);
        # Kalman gain
        K = Pxy*inv(Pyy);
        # println("Type of K: $(typeof(K))")
        # println("Size of K: $(size(K))")
        # analysis step, NRR tracking
        for i = 2:length(soln)
            yi = y + rand(Distributions.Normal(0,systems[i-1].error.odev[1]));
            # println("Type of correction: $(typeof(K*(yi - Y[i-1])))")
            # println("Size of correction: $(size(K*(yi - Y[i-1])))")
            X[i-1][:] += K*(yi - Y[i-1]);
            r2dot[i-1] += dot((Y[i-1]-yi),(Y[i-1]-yi));
        end
        r1dot += sqrt.(dot((yhat-y),(yhat-y)));
        # println("Analysis X: $X")
        # analysis back into ensemble members
        for i = 2:length(soln)
            systems[i].branches.A[61][n[i]+1,:] = X[i-1][1:systems[i].solverparams.JL];
            # systems[i].branches.beta[61][end] = X[i-1][end-1];
            systems[i].branches.A0[61][end] = X[i-1][end];
            println("Analysis area, ensemble member $(i-1): $(systems[i].branches.A[61][n[i]+1,:])")
            println("Analysis β, ensemble member $(i-1): $(systems[i].branches.beta[61][end])")
            println("Analysis A0, ensemble member $(i-1): $(systems[i].branches.A0[61][end])")
        end
        # # rescale parameter variances
        # for i = 2:length(soln)
        #     systems[i].error.pdev[1] = 0.1*xhat[end-1];
        #     systems[i].error.pdev[2] = 0.1*xhat[end];
        # end
    end
end
toc();

systems = pmap((a1,a2)->CVModule.updatevolumes!(a1,a2),systems,n);

# normalized RMSE ratio (optimal ensemble yields NRR ~ 1)
if assimflag == "yes"
    r2dot = sqrt.(1/systems[1].t[end]*r2dot);
    R1 = 1/systems[1].t[end]*r1dot;
    R2 = sum(r2dot);
    Ra = R1/R2;
    ERa = sqrt.((ensemblesize-1)/(2*(ensemblesize-1)));
    println("Normalized RMSE ratio: $(Ra/ERa)")
end

# if coupleflag == "yes"
#     ZMQ.close(sender)
#     ZMQ.close(ctx)
# end

if saveflag == "yes"
    fnames = ["sparse13_$i.mat" for i=1:ensemblesize];
    for i = 1:length(fnames)
        file = MAT.matopen(fnames[i],"w");
        write(file,"system",systems[i])
        close(file)
    end
end

if assimflag == "yes"
    return systems, n, βhat, A0hat, Phat
else
    return systems, n
end

end
