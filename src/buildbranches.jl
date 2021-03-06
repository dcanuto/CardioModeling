type ArterialTerminal # lumped peripheral vasculature
    C::Vector{Float64}
    R::Vector{Float64}
    L::Vector{Float64}
    V0::Vector{Float64}
    P::Any
    V::Any
    Q::Any

    function ArterialTerminal()
        this = new()
        this.C = Vector{Float64}[];
        this.R = Vector{Float64}[];
        this.L = Vector{Float64}[];
        this.V0 = Vector{Float64}[];
        this.P = Array{Float64,2}[];
        this.V = Array{Float64,2}[];
        this.Q = Array{Float64,2}[];
        return this
    end
end

type ArterialBranches # 1D arterial domain
    name::Vector{String}
    parentname::Vector{String}
    ID::Vector{Int64}
    parentID::Vector{Int64}
    lengthincm::Vector{Float64}
    radiusincm::Vector{Float64}
    thicknessincm::Vector{Float64}
    YoungsModinMPa::Vector{Float64}
    A0::Any
    beta::Any
    c0::Any
    k::Vector{Float64}
    group::Vector{String}
    A::Any
    Q::Any
    P::Any
    Fp::Any
    Fbarforward::Any
    Fbarbackward::Any
    Abackward::Any
    Aforward::Any
    Qbackward::Any
    Qforward::Any
    W1end::Vector{Float64}
    W1::Vector{Float64}
    W2::Vector{Float64}
    W1root::Float64
    W2root::Float64
    children::Any
    term::Any
    # Rao::Float64

    function ArterialBranches(filename="test.csv",old=Dict("a"=>0),restart="no")
        this = new()
        this.name = Vector{String}[];
        this.parentname = Vector{String}[];
        this.ID = Vector{Int64}[];
        this.parentID = Vector{Int64}[];
        this.children = Vector{Int64}[];
        this.lengthincm = Vector{Float64}[];
        this.radiusincm = Vector{Float64}[];
        this.thicknessincm = Vector{Float64}[];
        this.YoungsModinMPa = Vector{Float64}[];
        this.A0 = Array{Float64,1}[];
        this.beta = Array{Float64,1}[];
        this.c0 = Array{Float64,1}[];
        this.k = Vector{Float64}[];
        this.group = Vector{String}[];
        this.A = Array{Float64,2}[];
        this.Q = Array{Float64,2}[];
        this.P = Array{Float64,2}[];
        this.Fp = Array{Float64,1}[];
        this.Fbarforward = Array{Float64,1}[];
        this.Fbarbackward = Array{Float64,1}[];
        this.Abackward = Array{Float64,1}[];
        this.Aforward = Array{Float64,1}[];
        this.Qbackward = Array{Float64,1}[];
        this.Qforward = Array{Float64,1}[];
        this.W1end = Vector{Float64}[];
        this.W1 = Vector{Float64}[];
        this.W2 = Vector{Float64}[];
        if restart == "no"
            this.W1root = Float64(0);
            this.W2root = Float64(0);
            # this.Rao = 0.01*mmHgToPa/cm3Tom3;

            # pull in artery data from text file
            temp = CVModule.loadtexttree(filename);
            this.name = [string(temp[1,:Name])]
            this.parentname = [string(temp[1,:ParentName])]
            this.ID = [temp[1,:ID]]
            this.parentID = [temp[1,:parentID]]
            this.lengthincm = [temp[1,:Length_cm]]
            this.radiusincm = [temp[1,:Radius_cm]]
            this.thicknessincm = [temp[1,:Thickness_cm]]
            this.YoungsModinMPa = [temp[1,:YoungsModulus_MPa]]
            for i = 2:length(temp[:Name])
                push!(this.name,string(temp[i,:Name]))
                push!(this.parentname,string(temp[i,:ParentName]))
                push!(this.ID,temp[i,:ID])
                push!(this.parentID,temp[i,:parentID])
                push!(this.lengthincm,temp[i,:Length_cm])
                push!(this.radiusincm,temp[i,:Radius_cm])
                push!(this.thicknessincm,temp[i,:Thickness_cm])
                push!(this.YoungsModinMPa,temp[i,:YoungsModulus_MPa])
            end
            for i in 1:size(temp[:children_1],1)
                if !isa(temp[i,:group],Missings.Missing)
                    push!(this.group,string(temp[i,:group]))
                else
                    push!(this.group,"NA")
                end
                if !isa(temp[i,:children_1],Missings.Missing)
                    push!(this.children,[temp[i,:children_1]])
                else
                    push!(this.children,[])
                end
                if !isa(temp[i,:children_2],Missings.Missing)
                    push!(this.children[i],temp[i,:children_2])
                end
                if !isa(temp[i,:children_3],Missings.Missing)
                    push!(this.children[i],temp[i,:children_3])
                end
                if !isa(temp[i,:children_4],Missings.Missing)
                    push!(this.children[i],temp[i,:children_4])
                end
            end
        elseif restart == "yes"
            this.W1root = old["W1root"];
            this.W2root = old["W2root"];
            this.name = [old["name"][1]];
            this.parentname = [old["parentname"][1]];
            this.ID = [old["ID"][1]];
            this.parentID = [old["parentID"][1]];
            this.group = [old["group"][1]];
            this.lengthincm = [old["lengthincm"][1]];
            this.radiusincm = [old["radiusincm"][1]];
            this.thicknessincm = [old["thicknessincm"][1]];
            this.YoungsModinMPa = [old["YoungsModinMPa"][1]];
            for i = 2:length(old["ID"])
                push!(this.name,old["name"][i]);
                push!(this.parentname,old["parentname"][i]);
                push!(this.ID,old["ID"][i]);
                push!(this.parentID,old["parentID"][i]);
                push!(this.group,old["group"][i]);
                push!(this.lengthincm,old["lengthincm"][i]);
                push!(this.radiusincm,old["radiusincm"][i]);
                push!(this.thicknessincm,old["thicknessincm"][i]);
                push!(this.YoungsModinMPa,old["YoungsModinMPa"][i]);
            end
            for i = 1:length(old["children"])
                temp = Array{Int64}(1);
                if length(old["children"][i]) == 1
                    temp = [old["children"][i]];
                elseif length(old["children"][i]) > 1
                    temp = old["children"][i];
                else
                    temp = [0];
                end
                push!(this.children,temp)
                deleteat!(this.children[i],findin(this.children[i],0))
            end
        end

        this.term = Vector{CVModule.ArterialTerminal}(length(this.ID));

        return this
    end
end
