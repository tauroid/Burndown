Burndown chart generator
========================

Generates a [Plotly](https://plotly.com/javascript/) burndown 
chart for your Trello sprint. Relies on the [Card Size powerup](https://trello.com/power-ups/5cd476e1efce1d2e0cbe53a8/card-size-by-screenful) 
(every card needs a size!). 

Operates on the JSON file trello will let you export from a board.

Is slow because it's written in Julia.

``` sh
$ julia --project=.
```

``` julia
julia> ]
pkg> instantiate
```

Wait a while for that to finish, then backspace to exit `pkg>`

``` julia
julia> exit()
```

``` sh
$ julia --project=. main.jl --help
```

The help text should guide you from there. You will probably need
to set `--accepted-task-points` and `--accepted-story-points` as
the script is not smart about that.
