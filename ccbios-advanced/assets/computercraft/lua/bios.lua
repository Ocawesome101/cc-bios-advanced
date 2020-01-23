-- Custom EFI. CC-UNIX will be written against this. --

local ccefi = {}

local CCEFI_VERSION = "OC-EFI 2 v0.0.1"

function error(msg)
  local w,h = term.getSize()
  term.setCursorPos(1,h)
  term.setTextColor(16384)
  term.write(msg)
end

function ccefi.version()
  return CCEFI_VERSION
end

-- Write stuff without any formatting at all
function ccefi.write(text, newLine)
  local x,y = term.getCursorPos()
  local w,h = term.getSize()

  local function newline()
    if y+1 <= h then
      term.setCursorPos(1, y + 1)
    else
      term.setCursorPos(1,h)
      term.scroll(1)
    end
    x,y = term.getCursorPos()
  end

  term.write(text)

  if newLine then newline() end
end

function os.pullEvent(filter)
  return coroutine.yield(filter)
end

ccefi.pullEvent = os.pullEvent

ccefi.keys = loadstring(fs.open("/rom/modules/ccefi/keys.lua", "r").readAll())()

function read() -- Very cut-down version of CraftOS's read()
  term.setCursorBlink( true )

  local sLine = ""
  local nPos, nScroll = #sLine, 0

  local w = term.getSize()
  local sx = term.getCursorPos()

  local function redraw( _bClear )
    local cursor_pos = nPos - nScroll
    if sx + cursor_pos >= w then
      -- We've moved beyond the RHS, ensure we're on the edge.
      nScroll = sx + nPos - w
    elseif cursor_pos < 0 then
      -- We've moved beyond the LHS, ensure we're on the edge.
      nScroll = nPos
    end

    local _, cy = term.getCursorPos()
    term.setCursorPos( sx, cy )
    term.write( string.sub( sLine, nScroll + 1 ) )
  end

  local function clear()
    redraw( true )
  end
  redraw()

  while true do
    local sEvent, param, param1, param2 = ccefi.pullEvent()
    if sEvent == "char" then
      -- Typed key
      clear()
      sLine = string.sub( sLine, 1, nPos ) .. param .. string.sub( sLine, nPos + 1 )
      nPos = nPos + 1      
      redraw()

    elseif sEvent == "paste" then
      -- Pasted text
      clear()
      sLine = string.sub( sLine, 1, nPos ) .. param .. string.sub( sLine, nPos + 1 )
      nPos = nPos + #param
      redraw()

    elseif sEvent == "key" then
      if param == ccefi.keys.enter then
        -- Enter
        if nCompletion then
          clear()
          uncomplete()
          redraw()
        end
        break

      elseif param == ccefi.keys.left then
        -- Left
        if nPos > 0 then
          clear()
          nPos = nPos - 1
          
          redraw()
        end

      elseif param == ccefi.keys.right then
        -- Right
        if nPos < #sLine then
          -- Move right
          clear()
          nPos = nPos + 1
          
          redraw()
        end

      elseif param == ccefi.keys.backspace then
        -- Backspace
        if nPos > 0 then
          clear()
          sLine = string.sub( sLine, 1, nPos - 1 ) .. string.sub( sLine, nPos + 1 )
          nPos = nPos - 1
          if nScroll > 0 then nScroll = nScroll - 1 end
          
          redraw()
        end
      elseif param == ccefi.keys.delete then
        -- Delete
        if nPos < #sLine then
          clear()
          sLine = string.sub( sLine, 1, nPos ) .. string.sub( sLine, nPos + 2 )
          
          redraw()
        end
      end
    elseif sEvent == "mouse_click" or sEvent == "mouse_drag" and param == 1 then
      local _, cy = term.getCursorPos()
      if param1 >= sx and param1 <= w and param2 == cy then
        -- Ensure we don't scroll beyond the current line
        nPos = math.min(math.max(nScroll + param1 - sx, 0), #sLine)
        redraw()
      end

    elseif sEvent == "term_resize" then
      -- Terminal resized
      w = term.getSize()
      redraw()

    end
  end

  local cx, cy = term.getCursorPos()
  term.setCursorBlink( false )
  term.setCursorPos( w + 1, cy )
  ccefi.write("", true)

  return sLine
end

ccefi.read = read

local colors = {
  white = 1,
  orange = 2,
  magenta = 4,
  lightBlue = 8,
  yellow = 16,
  lime = 32,
  pink = 64,
  gray = 128,
  lightGray = 256,
  cyan = 512,
  purple = 1024,
  blue = 2048,
  brown = 4096,
  green = 8192,
  red = 16384,
  black = 32768
}

local function status(msg, s)
  if s == "ok" or not s then
    term.setTextColor(colors.white)
  elseif s == "err" then
    term.setTextColor(colors.red)
  end
  ccefi.write(msg, true)
end

local shutdown = os.shutdown
os.shutdown = nil
function ccefi.shutdown()
  shutdown()
  while true do
    coroutine.yield()
  end
end

function loadfile(path)
--  ccefi.write(path, true)
  if not fs.exists(path) then
    return nil, "File not found"
  end

  local buffer = ""
  local h = fs.open(path, "r")
  buffer = h.readAll()
  h.close()
  local func, err = loadstring(buffer, "@" .. path, "bt", _G)
  return func, err
end

_G.ccefi = ccefi

status("Welcome to " .. ccefi.version())
status("Checking for bootable devices....")

local function boot(file)
  local ok, err = loadfile(file)
  if not ok then
    status("Failed to load file " .. file .. ": " .. (err or "No reason given"))
    return
  end
  ok()
  ccefi.shutdown()
end

local bootables = {}

local efi_settings = {}

if fs.exists("/efi/boot") then
  if #fs.list("/efi/boot") >= 1 then
    local files = fs.list("/efi/boot")
    for i=1, #files, 1 do
      table.insert(bootables, "/efi/boot/" .. files[i])
    end
  end
end

if bootables[1] then
  status("Defaulting to first boot device")
  boot(bootables[1])
else
  status("No bootable devices found!")
  status("Entering EFI shell.")
  while true do
    ccefi.write("-> ")
    local cmd = ccefi.read()
    local ok, err = pcall(function()loadstring(cmd, "shell.lua")()end)
    if not ok then ccefi.write(err, true)end
  end
end
