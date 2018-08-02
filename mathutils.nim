proc powerOfTwo*(num :uint32): bool =
  ((num and not (num and (num - 1))) == num)