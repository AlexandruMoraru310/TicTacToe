using Combinatorics
using Distributions
using JLD


# Function that assigns an unique number to each possible state. Enables a faster search in the set of possible states.

function state_number(state)

    nr = 0
    nr += (9 - count(==(' '), state)) * 3^9
    num_vector = [c=='X' ? 0 : (c=='O' ? 1 : 2) for c in vec(state)]
    nr += sum(num_vector[i]*3^(9-i) for i in 1:9)
    return nr
end


# Function which determines who's turn is next.

function is_turn(state)
    if count(==('X'), state) == count(==('O'), state)
        return 'X'
    end
    return 'O'
end


# Function which determines if the given state is victory state for the given player.

function is_winner(state, player)
    if all(state[1, :] .== player)
        return true
    elseif all(state[2, :] .== player)
        return true
    elseif all(state[3, :] .== player)
        return true
    elseif all(state[:, 1] .== player)
        return true
    elseif all(state[:, 2] .== player)
        return true
    elseif all(state[:, 3] .== player)
        return true
    elseif state[1, 1] == player && state[2, 2] == player && state[3, 3] == player
        return true
    elseif state[1, 3] == player && state[2, 2] == player && state[3, 1] == player
        return true
    end
    return false
end


# Function which determines if the given state is a tie state.

function is_tie(state)
    if count(==(' '), state) == 0 && !is_winner(state, 'X') && !is_winner(state, 'O')
        return true
    end
    return false
end


# Function which determines if the given state is reachable (i.e. if there is any succsession of moves that could make the game reach that state).

function is_reachable(state)
    if count(==('O'), state) < count(==('X'), state)
        # X a mutat ultimul
        for i in 1:3
            for j in 1:3
                if state[i, j] == 'X'
                    prev_state = state[:, :]
                    prev_state[i, j] = ' '
                    if !is_winner(prev_state, 'X') && !is_winner(prev_state, 'O')
                        return true
                    end
                end
            end
        end
    else
        for i in 1:3
            for j in 1:3
                if state[i, j] == 'O'
                    prev_state = state[:, :]
                    prev_state[i, j] = ' '
                    if !is_winner(prev_state, 'X') && !is_winner(prev_state, 'O')
                        return true
                    end
                end
            end
        end
    end
    if state == [[' ', ' ', ' '] [' ', ' ', ' '] [' ', ' ', ' ']]
        return true
    end
    return false
end


# Count the number of states including impossible states (unreachable states, e.g. states in which both X and O won).

max_number_of_states = 0

for s in 0:9
    if s%2 == 0
        n_xs = s ÷ 2
    else
        n_xs = s ÷ 2 + 1
    end
    n_os = s - n_xs
    global max_number_of_states += binomial(9, n_xs) * binomial(9 - n_xs, n_os)
end


# Initialize a list with empty states and add all states to it (including unreachable states).

all_states = [[[' ', ' ', ' '] [' ', ' ', ' '] [' ', ' ', ' ']] for i in 1:max_number_of_states]

shadow_states = collect(combinations(1:9))

current_index = 1

for shw in shadow_states
    s = length(shw)
    if s%2 == 0
        n_xs = s ÷ 2
    else
        n_xs = s ÷ 2 + 1
    end
    n_os = s - n_xs
    for xs in collect(combinations(shw, n_xs))
        all_states[current_index][shw] .= 'O'
        all_states[current_index][xs] .= 'X'
        global current_index += 1
    end
end


# Filter out the unreachable states. Sort the states by state number.

all_states = all_states[is_reachable.(all_states)]

state_numbers = state_number.(all_states)
indices = sortperm(state_numbers)
all_states = all_states[indices]
state_numbers = state_numbers[indices]


#=
Prepare for training. Initialize the value look-up table with 1s for states in which X wins, 0s for states in which X loses and a number between 0 and 1
    for tie states (e.g. 0.4). Non-terminal states are optimistically initialized with 1 in order to encourage the agent to explore.
=#

value_lookup_table = ones(length(all_states))
X_victory_states = is_winner.(all_states, 'X')
O_victory_states = is_winner.(all_states, 'O')
tie_states = is_tie.(all_states)
terminal_states = X_victory_states .| O_victory_states .| tie_states
value_lookup_table[X_victory_states] .= 1
value_lookup_table[O_victory_states] .= 0
value_lookup_table[tie_states] .= 0.4
all_moves = [Int64[] for i in 1:length(all_states)]


# For each state, create a list of possible moves (=possible next states).

for i in 1:length(all_states)
    state = all_states[i]
    moves = Int64[]
    if terminal_states[i] == false
        if count(==('O'), state) == count(==('X'), state)
            for r in 1:3
                for c in 1:3
                    if state[r, c] == ' '
                        next_state = state[:, :]
                        next_state[r, c] = 'X'
                        next_state_number = state_number(next_state)
                        next_state_index = searchsortedfirst(state_numbers, next_state_number)
                        push!(moves, next_state_index)
                    end
                end
            end
        else
            for r in 1:3
                for c in 1:3
                    if state[r, c] == ' '
                        next_state = state[:, :]
                        next_state[r, c] = 'O'
                        next_state_number = state_number(next_state)
                        next_state_index = searchsortedfirst(state_numbers, next_state_number)
                        push!(moves, next_state_index)
                    end
                end
            end
        end
    end
    all_moves[i] = sort(moves)
end


#= Create a short-sighted opponent for our agent (the O player). This opponent first tries to select a wining move; if no such move exists, it checks if
    player X can make a move to win the game and tries to prevent such a move; it moves randomly otherwise.
=#

all_O_moves = [Int64[] for i in 1:length(all_states)]

for i in 1:length(all_states)
    if terminal_states[i] == false && count(==('O'), all_states[i]) < count(==('X'), all_states[i])
        state = all_states[i]
        if any(O_victory_states[all_moves[i]])
            all_moves[i] = all_moves[i][O_victory_states[all_moves[i]]]
        else
            moves = Int64[]
            for mv in all_moves[i]
                if any(X_victory_states[all_moves[mv]]) == false
                    push!(moves, mv)
                end
            end
            if !isempty(moves)
                all_moves[i] = sort(moves)
            end
        end
    end
end


#= Train the agent by playing a number of games against the short-sighted opponent and learning the values of each state. See Sutton's Reinforcement
    learning book (2nd edition), Section 1.5 An Extended Example: Tic-Tac-Toe
=#

p = 0.6
prob_gen = Bernoulli(p)
number_of_games_train = 50000
alpha_max = 0.4
alpha_min = 0.01
alpha_step = (alpha_max - alpha_min)/number_of_games_train
step_change = "quadratic"

for g in 1:number_of_games_train
    if step_change == "quadratic"
        alpha = (alpha_max - (g - 1) * alpha_step)^2
    else
        alpha = alpha_max - (g - 1) * alpha_step
    end
    state = 1
    previous_state = 0
    while terminal_states[state] == false
        if state == 1
            exploratory_move = true
        else
            exploratory_move = rand(prob_gen)
        end
        if exploratory_move == true
            state = rand(all_moves[state])
        else
            ind_max = argmax(value_lookup_table[all_moves[state]])
            state = all_moves[state][ind_max]
        end
        if previous_state > 0
            value_lookup_table[previous_state] = value_lookup_table[previous_state] + alpha * (value_lookup_table[state] - value_lookup_table[previous_state])
        end
        previous_state = state
        if terminal_states[state] == false
            state = rand(all_moves[state])
        else
            break
        end
        if terminal_states[state] == true
            value_lookup_table[previous_state] = value_lookup_table[previous_state] + alpha * (value_lookup_table[state] - value_lookup_table[previous_state])
        end
    end
end


# Test the efficiency of our trained agent by playing a number of games against the short-sighted opponent and calculation its victory rate.

number_of_games_test = 5000
number_of_X_victories = 0
number_of_O_victories = 0

for g in 1:number_of_games_test
    state = 1
    while true
        if state == 1
            state = rand(all_moves[state])
        elseif count(==('X'), all_states[state]) == count(==('O'), all_states[state])
            ind_max = argmax(value_lookup_table[all_moves[state]])
            state = all_moves[state][ind_max]
        else
            state = rand(all_moves[state])
        end
        if terminal_states[state] == true
            if X_victory_states[state] == true
                global number_of_X_victories += 1
            end
            if O_victory_states[state] == true
                global number_of_O_victories += 1
            end
            break
        end
    end
end

println("Win rate - X: ", number_of_X_victories/number_of_games_test)
println("Win rate - O: ", number_of_O_victories/number_of_games_test)


# Save the learned values of the states.

save(
    "./tic_tac_toe.jld", "all_states", all_states,
    "state_numbers", state_numbers,
    "X_victory_states", X_victory_states,
    "O_victory_states", O_victory_states,
    "tie_states", tie_states,
    "terminal_states", terminal_states,
    "all_moves", all_moves,
    "value_lookup_table", value_lookup_table)
