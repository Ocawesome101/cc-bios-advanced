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

function os.pullEventRaw(filter)
  return coroutine.yield(filter)
end

local nativeshutdown = os.shutdown
function os.shutdown()
  term.clear()
  nativeshutdown()
  while true do
    os.pullEvent()
  end
end

local nativereboot = os.reboot
function os.reboot()
  nativereboot()
  while true do
    os.pullEvent()
  end
end

ccefi.pullEvent = os.pullEventRaw

local keys = loadstring(fs.open("/rom/modules/ccefi/keys.lua", "r").readAll())()

function read(replaceChar) -- mostly API-independent read function
  term.setCursorBlink(true)
  local str = ""
  local x,y = term.getCursorPos()
  local w,h = term.getSize()
  
  local function redraw()
    term.setCursorPos(x,y)
    term.write(string.rep(" ", w-x))
    term.setCursorPos(x,y)
    if replaceChar then
      term.write(string.rep(replaceChar, #str))
    else
      term.write(str)
    end
  end

  while true do
    local event, param = os.pullEventRaw()

    if event == "key" then
      if param == keys.backspace then
        str = str:sub(1,#str-1)
      elseif param == keys.enter then
        break
      end
    elseif event == "char" then
      str = str .. param
    elseif event == "paste" then
      str = str .. param
    end
    redraw()
  end
  ccefi.write("", true)
  return str
end


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

local function unpack(tbl, i)
  local i = i or 1
  if tbl[i] ~= nil then
    return tbl[i], unpack(tbl, i + 1)
  end
end

table.pack = function(...)
  return {...}
end

table.unpack = function(tbl)
  return unpack(tbl)
end

status("Welcome to " .. ccefi.version())
status("Checking for bootable devices....")

function os.pullEvent(f)
  local data = table.pack(os.pullEventRaw())
  if data[1] == "terminate" then
    error("Program terminated")
    return false
  end
  return table.unpack(data)
end

local function run(func)
  local eventData = { n = 0 }
  local filter = ""
  local coro = coroutine.create(func)
  while true do
    if filter == "" or not filter or eventData[1] == filter or eventData[1] == "terminate" then
      local ok, param = coroutine.resume(coro, table.unpack(eventData)) -- Don't ask. I don't know. Magic.
      if not ok then
	status("ERR:" .. err, "err")
	while true do
	  os.pullEvent()
	end
      end
      filter = param
      if coroutine.status(coro) == "dead" then
	return true
      end
    end
    eventData = table.pack(os.pullEvent())
  end
end

local function boot(file)
  local ok, err = loadfile(file)
  if not ok then
    status("Failed to load file " .. file .. ": " .. (err or "No reason given"))
    return
  end
  local ok, err = pcall(run, ok)
  if not ok then
    ccefi.write(err)
    while true do
      os.pullEvent()
    end
  end
  term.setCursorBlink(false)
  while true do
    os.pullEvent()
  end
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
    local cmd = read()
    local ok, err = pcall(function()loadstring(cmd, "shell.lua")()end)
    if not ok then ccefi.write(err, true)end
  end
end
