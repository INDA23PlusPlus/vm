def print_if_prime(n):
    for d in range(2, n):
        if d * d > n:
            break
        if n % d == 0:
            return
    print(n)

for i in range(2, 10**6):
    print_if_prime(i)