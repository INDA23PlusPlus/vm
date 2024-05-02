def print_if_prime(n)
  (2...n).each do |d|
    break if d * d > n
    return if n % d == 0
  end
  puts n
end

(2...10**6).each do |i|
  print_if_prime(i)
end
