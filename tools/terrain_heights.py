"""Original 0x483210 full-map height extrema update, excluding last row/column."""


def cell_extrema(heights, width, height):
    if width <= 0 or height <= 0 or len(heights) != width * height:
        raise ValueError('Invalid height grid')
    low = bytearray(width * height)
    high = bytearray(width * height)
    for y in range(height - 1):
        for x in range(width - 1):
            index = y * width + x
            values = (heights[index], heights[index + 1], heights[index + width], heights[index + width + 1])
            low[index], high[index] = min(values), max(values)
    return low, high
