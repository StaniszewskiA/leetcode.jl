function is_power_of_two(n::Int)
    return n > 0 && (n & (n - 1)) == 0
end

cases = [1, 16, 3]

for n in cases
    println("n = $n, ", is_power_of_two(n))
end
