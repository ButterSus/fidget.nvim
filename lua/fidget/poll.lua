local M = {}
local logger = require("fidget.logger")

--- Arbitrary point in time that timestamps are computed relative to.
---@type number
local origin_time = vim.fn.reltime()

--- Obtain the current time (relative to origin_time).
---
---@return number
function M.get_time()
  return vim.fn.reltimefloat(vim.fn.reltime(origin_time))
end

---luv uv_timer_t handle
---@class uv_timer_t
---@field start fun(self: self, atk: number, delay: number, fn: function)
---@field stop fun(self: self)
---@field close fun(self: self)

--- Encapsulates a function that should be called periodically.
---@class Poller
---@field name string
---@field private poll fun(self: Poller): boolean what to do for polling
---@field private timer uv_timer_t? timer handle when this poller is polling
---@field private current_time number time at each poll
---@field private err any? error object possibly encountered while polling
---
--- Note that when the Poller:poll() method returns true, the poller should
--- call it again, but if it returns anything false-y, the poller will stop.
---
--- If a poller encounters an error while polling, it will refuse to start
--- polling again until its err is reset.
local Poller = {}
Poller.__index = Poller

--- Start polling the poll() function at the given poll_rate.
---
--- Only does so after waiting for attack milliseconds; if no attack is
--- specified, it defaults to 15ms.
---
---@param poll_rate number
---@param attack number?
function Poller:start_polling(poll_rate, attack)
  if self.timer then
    return
  end

  attack = attack or 15
  self.timer = vim.loop.new_timer()

  logger.info("Poller (", self.name, ") starting")

  self.timer:start(attack, math.ceil(1000 / poll_rate), vim.schedule_wrap(function()
    if not self.timer or self.err ~= nil then
      return
    end

    self.current_time = M.get_time()

    local ok, cont = pcall(self.poll, self)

    if not ok or not cont then
      self.timer:stop()
      self.timer:close()
      self.timer = nil
      if not ok then
        -- Save error object and propagate it
        logger.info("Poller (", self.name, ") stopping due to error", cont)
        self.err = cont
        error(cont)
      end
      logger.info("Poller (", self.name, ") stopping due to completion")
    end
  end))
end

--- Get the timestamp of the most recent poll frame.
---
--- Useful within a poll frame to provide a synchronous view of the world.
---
---@return number
function Poller:now()
  return self.current_time
end

--- Whether a poller is actively polling.
---
---@return boolean is_polling
function Poller:is_polling()
  return self.timer ~= nil
end

--- Query poller for potential encountered error.
---
---@return any? error_object
function Poller:has_error()
  return self.err
end

--- Forget about error object so that poller can start polling again.
function Poller:reset_error()
  self.err = nil
end

--- Construct a Poller object.
---@param opts { name: string?, poll: fun(self: Poller): boolean }?
---@return Poller poller
function M.Poller(opts)
  opts = opts or {}

  local name = opts.name
  if not name then
    -- Use debug info to construct name
    local info = debug.getinfo(2, "Sl")
    local _, _, filename = string.find(info.short_src, "(/lua/fidget.+)")
    local lineinfo = (filename or info.short_src) .. ":" .. info.currentline
    name = lineinfo
  end

  ---@type Poller
  local poller = {
    name         = name,
    poll         = opts.poll or function() return false end,
    timer        = nil,
    current_time = 0,
    err          = nil,
  }
  return setmetatable(poller, Poller)
end

return M
