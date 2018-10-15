dofile("Bitmap.lua")

local function clamp(x, min, max)
  if x < min then
    return min
  elseif x > max then
    return max
  else
    return x
  end
end

function DrawGraphs(bmp, funcs_data, div, interval, int_x, int_y, skip_KP, level_y, write_frames, write_name, frames_step, start_x, start_y, width, height, center_x, center_y)
  div = div or 10
  interval = interval or 1
  level_y = level_y or 0
  frames_step = frames_step or 1
  start_x, start_y = start_x or 0, start_y or 0
  width, height = width or bmp.width, height or bmp.height
  center_x, center_y = center_x or 0, center_y or 0
  
  local order = {}
  for name in pairs(funcs_data.funcs) do
    table.insert(order, name)
  end
  table.sort(order)
  
  local any = funcs_data.funcs[next(funcs_data.funcs)][1]
  local y = level_y and (any.y - level_y) or any.y
  local min_x, min_y, max_x, max_y = any.x, y, any.x, y
  for _, name in ipairs(order) do
    local func_points = funcs_data.funcs[name]
    for _, pt in ipairs(func_points) do
      local x, y = pt.x - center_x, pt.y - center_y
      y = level_y and (y - level_y) or y
      min_x = (x < min_x) and x or min_x
      min_y = (y < min_y) and y or min_y
      max_x = (x > max_x) and x or max_x
      max_y = (y > max_y) and y or max_y
    end
  end
  
  local size_x = math.ceil(max_x - min_x)
  local size_y = math.ceil(max_y - min_x)
  
  local spacing_x, spacing_y = width // (div + 2), height // (div + 2)
  local scale_x, scale_y = div * spacing_x / size_x, div * spacing_y / size_y
  local Ox = start_x + spacing_x
  local Oy = start_y + height - spacing_y
  
  -- draw coordinate system
  bmp:DrawLine(Ox - spacing_x // 2, Oy, Ox + 10 * spacing_x + spacing_x // 2, Oy, {128, 128, 128})
  bmp:DrawLine(Ox, Oy + spacing_y // 2, Ox, Oy - 10 * spacing_y - spacing_y // 2, {128, 128, 128})
  local metric_x, metric_y = spacing_x // 10, spacing_y // 10
  for k = 1, div do
    bmp:DrawLine(Ox + k * spacing_x, Oy - metric_y, Ox + k * spacing_x, Oy + metric_y, {128, 128, 128})
    bmp:DrawLine(Ox - metric_x, Oy - k * spacing_y, Ox + metric_x, Oy - k * spacing_y, {128, 128, 128})
    local text = int_x and string.format("%d", k * size_x // div + center_x) or string.format("%.2f", k * size_x / div + center_x)
    local tw, th = bmp:MeasureText(text)
    bmp:DrawText(Ox + k * spacing_x - tw // 2, Oy + 2 * metric_y, text, {128, 128, 128})
    text = int_y and string.format("%d", level_y + k * size_y // div + center_y) or string.format("%.2f", level_y + k * size_y / div + center_y)
    tw, th = bmp:MeasureText(text)
    bmp:DrawText(0, Oy - k * spacing_y - th // 2, text, {128, 128, 128})
  end
  local level_y_text = int_y and string.format("%d", level_y) or string.format("%.2f", level_y)
  local tw, th = bmp:MeasureText(level_y_text)
  bmp:DrawText(0, Oy - th - 2, level_y_text, {128, 128, 128})
  
  -- draw graphs
  local box_size = 2
  local name_x = spacing_x + 10
  for _, name in ipairs(order) do
    local func_points = funcs_data.funcs[name]
    local last_x, last_y
    local frame = 0
    for idx, pt in ipairs(func_points) do
      if (idx - 1) % interval == 0 then
        local x = math.floor(Ox + scale_x * (pt.x - center_x))
        local y = math.floor(Oy - scale_y * (pt.y - center_y))
        if last_x and last_y then
          bmp:DrawLine(last_x, last_y, x, y, func_points.color)
        end
        if not skip_KP then
          bmp:DrawBox(x - box_size, y - box_size, x + box_size, y + box_size, func_points.color)
        end
        if pt.text then
          local w, h = bmp:MeasureText(pt.text)
          bmp:DrawText(x - w // 2, y - h - 2, pt.text, func_points.color)
        end
        last_x, last_y = x, y
        if write_frames and (not write_name or name == write_name) and (idx % frames_step == 0 or idx == #func_points) then
          frame = frame + 1
          local filename = string.format("%s_%s%04d.bmp", write_frames, not write_name and (name and "_") or "", frame)
          print(string.format("Writing '%s' ...", filename))
          bmp:WriteBMP(filename)
        end
      end
    end
    if #func_points == 1 then
      bmp:SetPixel(last_x, last_y, func_points.color)
      if not skip_KP then
        bmp:DrawBox(last_x - box_size, last_y - box_size, last_x + box_size, last_y + box_size, func_points.color)
      end
      if write_frames then
        local filename = string.format("%s_%s1.bmp", write_frames, not write_name and (name .. "_") or "")
        print(string.format("Writing '%s' ...", filename))
        bmp:WriteBMP(filename)
      end
    end
    local w, h = bmp:MeasureText(name)
    bmp:DrawText(start_x + name_x, start_y + height - h, name, func_points.color)
    name_x = name_x + w + 30
  end
  
  if funcs_data.name_y then
    bmp:DrawText(start_x + 5, start_y + 5, funcs_data.name_y, {128, 128, 128})
  end
  if funcs_data.name_x then
    local w, h = bmp:MeasureText(funcs_data.name_x)
    bmp:DrawText(start_x + width - w - 5, start_y + height - h * 2 - 5, funcs_data.name_x, {128, 128, 128})
  end
  
  return function(pt)
    return {x = Ox + math.floor(scale_x * (pt.x - center_x)), y = Oy - math.floor(scale_y * (pt.y - center_y))}
  end
end

function DrawGraphsAt(bmp, funcs_data, skip_KP, start_x, start_y, width, height, center_x, center_y)
  return DrawGraphs(bmp, funcs_data, nil, nil, nil, nil, skip_KP, nil, nil, nil, nil, start_x, start_y, width, height, center_x, center_y)
end