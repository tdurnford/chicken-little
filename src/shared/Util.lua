local Util = {}

function Util.clamp(x: number, lo: number, hi: number): number
  if x < lo then
    return lo
  end
  if x > hi then
    return hi
  end
  return x
end

return Util
