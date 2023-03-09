using Base: start_base_include
using JSON
using Dates
using TimeZones
using Plots
using ArgParse
using TOML
using Base.Iterators


toml = Dict()
last_was_option_name = false
for arg in ARGS
    global last_was_option_name
    if !last_was_option_name && arg[1] != '-'
        global toml
        toml = TOML.parsefile(arg)
        break
    end
    if arg[1:2] == "--"
        last_was_option_name = true
    else
        last_was_option_name = false
    end
end

s = ArgParseSettings(description = "Burndown chart generator. This script will also accept a TOML file supplying the long form arguments with the -- removed. Command line arguments will override the TOML file.")
@add_arg_table s begin
    "tomlFile"
        help = "TOML file supplying arguments"
    "--start-date", "-s"
        help = "Sprint start date/time (before any sprint tasks or stories are added) in YYYY-MM-DD or YYYY-MM-DDThh:mm:ss"
        required = !haskey(toml, "start-date")
        default = haskey(toml, "start-date") ? toml["start-date"] : nothing
    "--end-date", "-e"
        help = "Sprint end date/time. Used for burndown projection so should be the exact end of the sprint. Same format as --start-date"
        required = !haskey(toml, "end-date")
        default = haskey(toml, "end-date") ? toml["end-date"] : nothing
    "--board-data"
        help = "The trello board data file in JSON format"
        required = !haskey(toml, "board-data")
        default = haskey(toml, "board-data") ? toml["board-data"] : nothing
    "--accepted-task-points"
        help = "Number of accepted task points in total over the sprint. Default value is the max number of active task points in the sprint period"
        default = haskey(toml, "accepted-task-points") ? string(toml["accepted-task-points"]) : nothing
    "--accepted-story-points"
        help = "Number of accepted story points in total over the sprint. Default value is the max number of active story points in the sprint period"
        default = haskey(toml, "accepted-story-points") ? string(toml["accepted-story-points"]) : nothing
    "--stories-list"
        help = "Name of the list of accepted stories"
        required = !haskey(toml, "stories-list")
        default = haskey(toml, "stories-list") ? toml["stories-list"] : nothing
    "--done-stories-list"
        help = "Name of the list of finished stories"
        required = !haskey(toml, "done-stories-list")
        default = haskey(toml, "done-stories-list") ? toml["done-stories-list"] : nothing
    "--tasks-list"
        help = "Name of the list of accepted tasks"
        required = true
        required = !haskey(toml, "tasks-list")
        default = haskey(toml, "tasks-list") ? toml["tasks-list"] : nothing
    "--done-tasks-list"
        help = "Name of the list of finished tasks"
        required = true
        required = !haskey(toml, "done-tasks-list")
        default = haskey(toml, "done-tasks-list") ? toml["done-tasks-list"] : nothing
    "--board-name"
        help = "The name of the trello board"
        required = true
        required = !haskey(toml, "board-name")
        default = haskey(toml, "board-name") ? toml["board-name"] : nothing
    "--task-points-name"
        help = "Your cute name for task points (uncapitalised)"
        default = haskey(toml, "task-points-name") ? toml["task-points-name"] : "task points"
    "--day-start-time"
        help = "Start of the day in hh:mm:ss"
        default = haskey(toml, "day-start-time") ? toml["day-start-time"] : "09:00:00"
    "--day-end-time"
        help = "End of the day in hh:mm:ss"
        default = haskey(toml, "day-end-time") ? toml["day-end-time"] : "17:00:00"
end

parsed_args = parse_args(s)

task_points_capitalised = uppercase(parsed_args["task-points-name"][1]) * parsed_args["task-points-name"][2:end]

pointsPluginId = "5cd476e1efce1d2e0cbe53a8"

cardPoints = Dict()

function computePoints(cardIds, cards)
    points = 0
    for cardId = cardIds
        if haskey(cardPoints, cardId)
            points += cardPoints[cardId]
            continue
        end
        card = cards[cardId]
        if card["closed"] continue end
        pointsPluginIndex = findfirst((plugin)->plugin["idPlugin"] == pointsPluginId, card["pluginData"])
        if isnothing(pointsPluginIndex)
            @warn "Card '" * card["name"] * "' has no points value"
            cardPoints[cardId] = 0
        else
            pointsPlugin = card["pluginData"][pointsPluginIndex]
            pointsPluginData = JSON.parse(pointsPlugin["value"])
            cardPoints[cardId] = pointsPluginData["size"]
            points += pointsPluginData["size"]
        end
    end
    return points
end

function makeGraphs()
    global parsed_args

    boardData = parsed_args["board-data"]
    if haskey(toml,"board-data")
        boardData = joinpath(splitdir(parsed_args["tomlFile"])[1], toml["board-data"])
    end

    data = JSON.parse(read(boardData,String))

    startDate = DateTime(parsed_args["start-date"])
    endDate = DateTime(parsed_args["end-date"])

    actions = reverse(data["actions"])

    cards = Dict()

    activeStories = Set()

    activeStoriesX = [startDate]
    activeStoriesY = [parse(Int,parsed_args["accepted-story-points"])]

    doneStories = Set()

    doneStoriesX = [startDate]
    doneStoriesY = [0]

    storiesListName = parsed_args["stories-list"]
    doneStoriesListName = parsed_args["done-stories-list"]

    activeTasks = Set()

    activeTasksX = [startDate]
    activeTasksY = [parse(Int,parsed_args["accepted-task-points"])]

    doneTasks = Set()

    doneTasksX = [startDate]
    doneTasksY = [0]

    tasksListName = parsed_args["tasks-list"]
    doneTasksListName = parsed_args["done-tasks-list"]

    for action = actions
        actionDate = TimeZones.DateTime(ZonedDateTime(action["date"]))
        if actionDate < startDate || actionDate > endDate
            continue
        end
        if action["data"]["board"]["name"] != parsed_args["board-name"]
            continue
        end
        numActiveStoriesBeforeAction = length(activeStories)
        numDoneStoriesBeforeAction = length(doneStories)
        numActiveTasksBeforeAction = length(activeTasks)
        numDoneTasksBeforeAction = length(doneTasks)
        if action["type"] == "createCard"
            actionList = action["data"]["list"]["name"]
            cardId = action["data"]["card"]["id"]
            if !haskey(cards,cardId)
                cards[cardId] = data["cards"][findfirst((card)->card["id"] == cardId, data["cards"])]
            end
            if actionList == storiesListName
                push!(activeStories, cardId)
            end
            if actionList == doneStoriesListName
                push!(doneStories, cardId)
            end
            if actionList == tasksListName
                push!(activeTasks, cardId)
            end
            if actionList == doneTasksListName
                push!(doneTasks, cardId)
            end
        end
        if action["type"] == "copyCard"
            actionList = action["data"]["list"]["name"]
            cardId = action["data"]["card"]["id"]
            if !haskey(cards,cardId)
                cards[cardId] = data["cards"][findfirst((card)->card["id"] == cardId, data["cards"])]
            end
            if actionList == storiesListName
                push!(activeStories, cardId)
            end
            if actionList == doneStoriesListName
                push!(doneStories, cardId)
            end
            if actionList == tasksListName
                push!(activeTasks, cardId)
            end
            if actionList == doneTasksListName
                push!(doneTasks, cardId)
            end
        end
        # logic:
        # if it's moved to accepted tasks/stories, it becomes active
        # if it's moved from accepted tasks/stories list, it's still active
        # but if it's closed (archived) while active, it's not active but not done either
        # if it's moved to done, then it's done, even if it wasn't active before
        # if it's moved to done and it was active, it's no longer active
        # if it's moved out of done it goes back to active and stops being done
        # if it's archived while done it stays done
        if action["type"] == "updateCard"
            if haskey(action["data"],"listBefore")
                listBefore = action["data"]["listBefore"]["name"]
                listAfter = action["data"]["listAfter"]["name"]
                cardId = action["data"]["card"]["id"]
                if !haskey(cards,cardId)
                    cards[cardId] = data["cards"][findfirst((card)->card["id"] == cardId, data["cards"])]
                end
                if listBefore == doneStoriesListName
                    delete!(doneStories, cardId)
                    push!(activeStories, cardId)
                end
                if listBefore == doneTasksListName
                    delete!(doneTasks, cardId)
                    push!(activeTasks, cardId)
                end
                if listAfter == storiesListName
                    push!(activeStories, cardId)
                end
                if listAfter == doneStoriesListName
                    delete!(activeStories, cardId)
                    push!(doneStories, cardId)
                end
                if listAfter == tasksListName
                    push!(activeTasks, cardId)
                end
                if listAfter == doneTasksListName
                    delete!(activeTasks, cardId)
                    push!(doneTasks, cardId)
                end
            end
            if (haskey(action["data"],"old")
                && haskey(action["data"]["old"],"closed")
                && haskey(action["data"]["card"],"closed"))

                cardId = action["data"]["card"]["id"]
                if !haskey(cards,cardId)
                    cards[cardId] = data["cards"][findfirst((card)->card["id"] == cardId, data["cards"])]
                end
                actionList = action["data"]["list"]["name"]
                if !action["data"]["old"]["closed"] && action["data"]["card"]["closed"]
                    delete!(activeStories, cardId)
                    delete!(doneStories, cardId)
                    # TODO keep old done stories in the tracker? cli option?
                end
                if action["data"]["old"]["closed"] && !action["data"]["card"]["closed"]
                    if actionList == storiesListName
                        push!(activeStories, cardId)
                    end
                    if actionList == doneStoriesListName
                        push!(doneStories, cardId)
                    end
                    if actionList == tasksListName
                        push!(activeTasks, cardId)
                    end
                    if actionList == doneTasksListName
                        push!(doneTasks, cardId)
                    end
                end
            end
        end
        if length(activeStories) != numActiveStoriesBeforeAction
            push!(activeStoriesX,actionDate)
            push!(activeStoriesY,computePoints(activeStories, cards))
        end
        if length(doneStories) != numDoneStoriesBeforeAction
            push!(doneStoriesX,actionDate)
            push!(doneStoriesY,computePoints(doneStories, cards))
        end
        if length(activeTasks) != numActiveTasksBeforeAction
            push!(activeTasksX,actionDate)
            push!(activeTasksY,computePoints(activeTasks, cards))
        end
        if length(doneTasks) != numDoneTasksBeforeAction
            push!(doneTasksX,actionDate)
            push!(doneTasksY,computePoints(doneTasks, cards))
        end
    end

    plotly()

    linewidth = 4

    if !isnothing(parsed_args["accepted-story-points"])
        numAcceptedStories = parse(Int, parsed_args["accepted-story-points"])
    else
        numAcceptedStories = maximum(activeStoriesY)
    end

    if !isnothing(parsed_args["accepted-task-points"])
        numAcceptedTasks = parse(Int, parsed_args["accepted-task-points"])
    else
        numAcceptedTasks = maximum(activeTasksY)
    end

    notDoneStoriesY = numAcceptedStories .- doneStoriesY
    notDoneTasksY = numAcceptedTasks .- doneTasksY

    currentTime = now()
    if currentTime < endDate
        push!(doneStoriesX, currentTime)
        push!(notDoneStoriesY, notDoneStoriesY[end])
        push!(doneTasksX, currentTime)
        push!(notDoneTasksY, notDoneTasksY[end])
    end

    startTimeOfDay = Time(parsed_args["day-start-time"])
    endTimeOfDay = Time(parsed_args["day-end-time"])

    weekdays = filter((d)->Dates.dayname(d) != "Saturday" && Dates.dayname(d) != "Sunday",
                      floor(startDate, Dates.Day):Dates.Day(1):floor(endDate, Dates.Day))

    doneStoriesXWorkingHours = []
    notDoneStoriesYWorkingHours = []

    doneTasksXWorkingHours = []
    notDoneTasksYWorkingHours = []

    lines = []

    basehour = Hour(0)
    remainingStoryActions = zip(doneStoriesX,notDoneStoriesY)
    remainingTaskActions = zip(doneTasksX,notDoneTasksY)
    for (i,day) = enumerate(weekdays)
        dayStart = i == 1 ? startDate : day + (startTimeOfDay - Time(0))
        dayEnd = i == length(weekdays) ? endDate : day + (endTimeOfDay - Time(0))
        dayLength = dayEnd - dayStart

        remainingStoryActions = dropwhile(((t,y),)->t < dayStart, remainingStoryActions)
        newStoryActions = takewhile(((t,y),)->t <= dayEnd, remainingStoryActions)
        doneStoriesXWorkingHours = vcat(doneStoriesXWorkingHours,map(((t,y),)->Dates.toms((t-dayStart)+basehour)/3600000, newStoryActions))
        notDoneStoriesYWorkingHours = vcat(notDoneStoriesYWorkingHours,map(((t,y),)->y, newStoryActions))

        remainingTaskActions = dropwhile(((t,y),)->t < dayStart, remainingTaskActions)
        newTaskActions = takewhile(((t,y),)->t <= dayEnd, remainingTaskActions)
        doneTasksXWorkingHours = vcat(doneTasksXWorkingHours,map(((t,y),)->Dates.toms((t-dayStart)+basehour)/3600000, newTaskActions))
        notDoneTasksYWorkingHours = vcat(notDoneTasksYWorkingHours,map(((t,y),)->y, newTaskActions))

        basehour += dayLength
        push!(lines,Dates.toms(basehour)/3600000)
    end

    lines = lines[1:end-1]

    storiesPlot = plot(doneStoriesXWorkingHours,
                       notDoneStoriesYWorkingHours,
                       xlabel="Working hours",
                       ylabel="Story points",
                       label="Incomplete story points",
                       linecolor=:red,linewidth=linewidth,ticks=:native)

    plot!(storiesPlot, [0,Dates.toms(basehour)/3600000],[numAcceptedStories,0],
          label="Expected progress",linecolor=:black,
          linewidth=linewidth,ticks=:native)

    for l in lines
        plot!(storiesPlot, [l,l], [0,numAcceptedStories], linecolor=:grey, linestyle=:dash, primary=false)
    end

    tasksPlot = plot(doneTasksXWorkingHours,
                     notDoneTasksYWorkingHours,
                     xlabel="Working hours",
                     ylabel=task_points_capitalised,
                     label="Incomplete " * parsed_args["task-points-name"],
                     linecolor=:blue,linewidth=linewidth,ticks=:native)

    plot!(tasksPlot, [0,Dates.toms(basehour)/3600000],[numAcceptedTasks,0],
          label="Expected progress",linecolor=:black,
          linewidth=linewidth,ticks=:native)

    for l in lines
        plot!(tasksPlot, [l,l], [0,numAcceptedTasks], linecolor=:grey, linestyle=:dash, primary=false)
    end

    plot(storiesPlot, tasksPlot, size=(900,400))
end

display(makeGraphs())
