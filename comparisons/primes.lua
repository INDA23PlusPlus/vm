function print_if_prime(n)
    for d = 2, n do
        if d * d > n then
            break
        end
        if n % d == 0 then
            return
        end
    end
    print(n)
end

for i = 2, 999999 do
    print_if_prime(i)
end
