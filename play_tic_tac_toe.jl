using PrettyTables
using JLD


# Function that assigns an unique number to each possible state. Enables a faster search in the set of possible states.

function state_number(state)
    nr = 0
    nr += (9 - count(==(' '), state)) * 3^9
    num_vector = [c=='X' ? 0 : (c=='O' ? 1 : 2) for c in vec(state)]
    nr += sum(num_vector[i]*3^(9-i) for i in 1:9)
    return nr
end


# Load learned parameters and states.

all_states = load("./tic_tac_toe.jld", "all_states")
state_numbers = load("./tic_tac_toe.jld", "state_numbers")
X_victory_states = load("./tic_tac_toe.jld", "X_victory_states")
O_victory_states = load("./tic_tac_toe.jld", "O_victory_states")
tie_states = load("./tic_tac_toe.jld", "tie_states")
terminal_states = load("./tic_tac_toe.jld", "terminal_states")
all_moves = load("./tic_tac_toe.jld", "all_moves")
value_lookup_table = load("./tic_tac_toe.jld", "value_lookup_table")


# Play the game against human.

begin_series = true
restart = "NA"
while restart == "Y" || restart == "y" || begin_series == true
    global begin_series = false
    state = 1
    while true
        if state == 1
            state = rand(all_moves[state])
        elseif count(==('X'), all_states[state]) == count(==('O'), all_states[state])
            ind_max = argmax(value_lookup_table[all_moves[state]])
            state = all_moves[state][ind_max]
        else
            current_state = all_states[state][:, :]
            pretty_table(current_state, ["A", "B", "C"], hlines = [0, 1, 2, 3, 4], show_row_number=true)
            global valid_move = false
            global human_move = "___"
            global row = 0
            global column = 0
            while length(human_move) > 2 || valid_move == false
                global human_move = readline()
                global column = human_move[1] - 'A' + 1
                global row = human_move[2] - '0'
                if row >= 1 && row <= 3 && column >= 1 && column <= 3
                    if current_state[row, column] == ' '
                        global valid_move = true
                    else
                        global valid_move = false
                    end
                else
                    global valid_move = false
                end
            end
            current_state[row, column] = 'O'
            current_state_number = state_number(current_state)
            state = searchsortedfirst(state_numbers, current_state_number)
        end
        if terminal_states[state] == true
            current_state = all_states[state][:, :]
            pretty_table(current_state, ["A", "B", "C"], hlines = [0, 1, 2, 3, 4], show_row_number=true)
            if X_victory_states[state] == true
                println("Victory X")
            elseif O_victory_states[state] == true
                println("Victory O")
            else
                println("Tie")
            end
            break
        end
    end
    valid_input = false
    while valid_input == false
        println("Restart?")
        global restart = readline()
        if restart == "Y" || restart == "y" || restart == "N" || restart == "n"
            valid_input = true
        else
            valid_input = false
        end
    end
end
