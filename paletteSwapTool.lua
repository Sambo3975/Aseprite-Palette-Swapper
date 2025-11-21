--- Simple string representation for table used as an array.
-- @tparam table tbl : Table to represent.
local function reprTable(tbl)
  local res = "{ "
  for _,v in ipairs(tbl) do
    res = res..tostring(v)..", "
  end
  return res.."}"
end

local paletteOptions = { "NONE" }
local thisPlugin
local usingColorChannel = false

--- Get a list of all palettes at palettePath
--@tparam string palettePath : Path where palette images are located
--@tparam bool listMatchFromPalette : [default=false] If true, the <<match From Palette>> option is included.
local function listPalettes(palettePath, listMatchFromPalette)
  local files = app.fs.listFiles(palettePath)
  local result = { "<<color channel>>", }
  if listMatchFromPalette then
    table.insert(result, "<<match From Palette>>")
  end
  for _,v in ipairs(files) do
    if v:match("png$") then
      table.insert(result, v:sub(1, -5))
    end
  end
  return result
end

--- Parse the given input as a table of numbers
-- @tparam string input : raw input to parse
-- @return table result : List of numbers if input was valid. nil if input was invalid.
local function parsePaletteRows(input)
  if input == "" then
    return nil
  end
  local result = {}
  for str in string.gmatch(input, "([^ ]+)") do
    local asnum = tonumber(str)
    if asnum == nil then
      return nil
    end
    table.insert(result, asnum)
  end
  return result
end

--- Load a palette image.
-- @tparam string name : Name of the palette
local function loadPalette(name)
  if name == "<<color channel>>" then
    usingColorChannel = true
    return Image{ fromFile = thisPlugin.path.."/channels.png" }
  end
  return Image { fromFile = thisPlugin.preferences.palettePath.."/"..name..".png" }
end

--- Apply all set palette swaps
-- @tparam Dialog dlg : Palette Swap Tool dialog.
local function applyPaletteSwaps(dlg)

  thisPlugin.preferences.dialogBounds = dlg.bounds

  -- Input Validation

  local validationMessages = { "Could not swap palettes due to the following issue(s):" }

  local fromPalette = dlg.data.swapFromPalette
  if fromPalette == "<<match From Palette>>" then
    table.insert(validationMessages, "From Palette cannot be <<match From Palette>>.")
  end
  local fromRows = parsePaletteRows(dlg.data.swapFromRows)
  if (fromRows == nil) then
    table.insert(validationMessages, "From Rows has bad formatting. It should be a list of space-separated numbers (e.g. \"1 2 3\").")
  end
  local toPalette = dlg.data.swapToPalette
  if toPalette == "<<match From Palette>>" then
    toPalette = fromPalette
  end
  local toRows = parsePaletteRows(dlg.data.swapToRows)
  if (toRows == nil) then
    table.insert(validationMessages, "To Rows has bad formatting. It should be a list of space-separated numbers (e.g. \"1 2 3\").")
  end

  if (fromRows and toRows) and #fromRows ~= #toRows then
    table.insert(validationMessages, "From Rows and To Rows are not the same length. They must be the same length.")
  end

  -- Handle invalid input that can be detected without more work.

  if #validationMessages > 1 then
    app.alert{
      title = "Palette Swap Failure",
      text = validationMessages,
    }
    return
  end

  -- Load palettes

  local warnIfDifferentWidths = dlg.data.checkPaletteWidths
  usingColorChannel = false
  fromPaletteName = fromPalette
  toPaletteName = toPalette
  fromPalette = loadPalette(fromPalette) -- change from string to image
  toPalette = loadPalette(toPalette)     -- change from string to image

  -- Ensure rows are in range

  local badRows = {}
  for _,v in ipairs(fromRows) do
    if v < 0 or v >= fromPalette.height then
      table.insert(badRows, v)
    end
  end
  if #badRows > 0 then
    table.insert(validationMessages, "From Palette: The palette '"..fromPaletteName.."' does not have the following requested rows: "..reprTable(badRows))
  end
  badRows = {}
  for _,v in ipairs(toRows) do
    if v < 0 or v >= toPalette.height then
      table.insert(badRows, v)
    end
  end
  if #badRows > 0 then
    table.insert(validationMessages, "To Palette: The palette '"..toPaletteName.."' does not have the following requested rows: "..reprTable(badRows))
  end

  if #validationMessages > 1 then
    app.alert{
      title = "Palette Swap Failure",
      text = validationMessages,
    }
    return
  end

  -- Handle Palette Width Mismatch

  local xScale = 1
  local stepOverToPalette = false
  if fromPalette.width ~= toPalette.width then 
    if not usingColorChannel then
      if app.alert{
        title = "Palette Width Mismatch",
        text = {
          "You are switching between palettes of different widths.",
          "This may have undesired effects. Proceed anyway?",
          "(This warning can be disabled by unchecking Check Palette Widths)"
        },
        buttons = { "Yes", "No" },
      } == 2 then
        return
      end
    end

    -- Step over whichever palette has the smallest width.
    -- This greatly improves performance when switching from a color channel.
    stepOverToPalette = fromPalette.width > toPalette.width
    if stepOverToPalette then
      xScale = fromPalette.width / toPalette.width
    else
      xScale = toPalette.width / fromPalette.width
    end
  end

  -- Do the palette swap

  -- The transaction had to be removed because due to a bug in Aseprite 1.3.15.5, ReplaceColor only works once per 
  -- transaction.

  -- app.transaction(
  --   "Palette swap",
  --   function()
      local cel = app.cel
      for _,v in ipairs(app.sprite.cels) do
        app.cel = v
        for i = 1, #fromRows do
          local y1 = fromRows[i]
          local y2 = toRows[i]
          if stepOverToPalette then
            for x2 = 0, toPalette.width - 1 do
              local x1 = math.floor(x2 * xScale + 0.5)
              local p1 = string.format("%x", fromPalette:getPixel(x1, y1))
              local p2 = string.format("%x", toPalette:getPixel(x2, y2))
              app.command.ReplaceColor{
                ui = false,
                from = Color(fromPalette:getPixel(x1, y1)),
                to = Color(toPalette:getPixel(x2, y2)),
                tolerance = thisPlugin.preferences.tolerance,
              }
            end
          else
            for x1 = 0, fromPalette.width - 1 do
              local x2 = math.floor(x1 * xScale + 0.5)
              local p1 = string.format("%x", fromPalette:getPixel(x1, y1))
              local p2 = string.format("%x", toPalette:getPixel(x2, y2))
              app.command.ReplaceColor{
                ui = false,
                from = Color(fromPalette:getPixel(x1, y1)),
                to = Color(toPalette:getPixel(x2, y2)),
                tolerance = thisPlugin.preferences.tolerance,
              }
            end
          end
        end
      end
      app.cel = cel
  --   end
  -- )

  if dlg.data.closeOnSuccess then
    dlg:close()
  end

  app.refresh()

end

local function drawDialog(plugin)
  dlg = Dialog("Palette Swap Tool")
  local enableControls = plugin.preferences.palettePath ~= ""
  dlg:file{
    id = "palettePath",
    label = "Palette Path",
    filename = plugin.preferences.palettePath,
    filetypes = { "png" },
    onchange = function()
      if (dlg.data.palettePath:match("png$")) then -- Prevent cascading calls that result in an empty string
        plugin.preferences.palettePath = app.fs.filePath(dlg.data.palettePath)
        -- Comboboxes can't be modified after creation, so we have to redraw the whole dialog to change them
        plugin.preferences.dialogBounds = dlg.bounds
        dlg:close()
        drawDialog(plugin)
      end
    end
  }:check{
    id = "checkPaletteWidths",
    label = "Check Palette Widths",
    selected = plugin.preferences.checkPaletteWidths,
    onclick = function()
      plugin.preferences.checkPaletteWidths = dlg.data.checkPaletteWidths
    end
  }:check{
    id = "closeOnSuccess",
    label = "Close on Success",
    selected = plugin.preferences.closeOnSuccess,
    onclick = function()
      plugin.preferences.closeOnSuccess = dlg.data.closeOnSuccess
    end
  }:separator{
    text = "Palette Swap(s)",
  }:combobox{
    id = "swapFromPalette",
    label = "  From Palette",
    option = plugin.preferences.fromPalette,
    options = listPalettes(plugin.preferences.palettePath),
    onchange = function()
      plugin.preferences.fromPalette = dlg.data.swapFromPalette
    end,
    enabled = enableControls,
  }:entry{
    id = "swapFromRows",
    label = "  From Row(s)",
    enabled = enableControls,
  }:combobox{
    id = "swapToPalette",
    label = "  To Palette",
    option = plugin.preferences.toPalette,
    options = listPalettes(plugin.preferences.palettePath, true),
    onchange = function()
      plugin.preferences.toPalette = dlg.data.swapToPalette
    end,
    enabled = enableControls,
  }:entry{
    id = "swapToRows",
    label = "  To Row(s)",
    enabled = enableControls,
  }:slider{
    id = "tolerance",
    label = "  Tolerance",
    min = 0,
    max = 255,
    value = plugin.preferences.tolerance,
    onrelease = function()
      plugin.preferences.tolerance = dlg.data.tolerance
    end,
    enabled = enableControls,
  }:separator{
  }:button{
    id = "applyButton",
    text = "Apply Palette Swap(s)",
    onclick = function()
      applyPaletteSwaps(dlg)
    end,
    enabled = enableControls,
  }:show{
    wait = false,
    bounds = plugin.preferences.dialogBounds,
  }
end

function init(plugin)

  if plugin.preferences.palettePath == nil then
    plugin.preferences.palettePath = ""
  end
  if plugin.preferences.checkPaletteWidths == nil then
    plugin.preferences.checkPaletteWidths = true
  end
  if plugin.preferences.closeOnSuccess == nil then
    plugin.preferences.closeOnSuccess = true
  end
  if plugin.preferences.fromPalette == nil then
    plugin.preferences.fromPalette = ""
  end
  if plugin.preferences.toPalette == nil then
    plugin.preferences.toPalette = ""
  end
  if plugin.preferences.tolerance == nil then
    plugin.preferences.tolerance = 0
  end

  thisPlugin = plugin

  plugin:newCommand{
    id="paletteSwap",
    title="Palette Swap Tool",
    group="sprite_color",
    onclick=function()
      drawDialog(plugin)
    end,
    onenabled = function()
      return app.sprite ~= nil
    end,
  }
end

function exit(plugin)
  print("exiting paletteSwapTool")
end
