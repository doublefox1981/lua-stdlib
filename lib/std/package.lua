--[[--
 Additions to the core package module.

 The module table returned by `std.package` also contains all of the entries
 from the core package table.  An hygienic way to import this module, then, is
 simply to override the core `package` locally:

    local package = require "std.package"

 @module std.package
]]


local M  -- forward declaration


local base           = require "std.base"
local debug          = require "std.debug_init"
local case           = require "std.functional".case
local catfile        = require "std.io".catfile
local invert         = require "std.table".invert
local escape_pattern = require "std.string".escape_pattern

local argcheck, argscheck, split =
      base.argcheck, base.argscheck, base.split


--- Look for a path segment match of `patt` in `pathstrings`.
-- @string pathstrings `pathsep` delimited path elements
-- @string patt a Lua pattern to search for in `pathstrings`
-- @int[opt=1] init element (not byte index!) to start search at.
--   Negative numbers begin counting backwards from the last element
-- @bool[opt=false] plain unless false, treat `patt` as a plain
--   string, not a pattern. Note that if `plain` is given, then `init`
--   must be given as well.
-- @return the matching element number (not byte index!) and full text
--   of the matching element, if any; otherwise nil
-- @usage i, s = find (package.path, "^[^" .. package.dirsep .. "/]")
local function find (pathstrings, patt, init, plain)
  argscheck ("std.package.find",
    {"string", "string", {"int", "nil"}, {"boolean", ":plain", "nil"}},
    {pathstrings, patt, init, plain})

  local paths = split (pathstrings, M.pathsep)
  if plain then patt = escape_pattern (patt) end
  init = init or 1
  if init < 0 then init = #paths - init end
  for i = init, #paths do
    if paths[i]:find (patt) then return i, paths[i] end
  end
end


--- Substitute special characters in a path string.
-- Characters prefixed with `%` have the `%` stripped, but are not
-- subject to further substitution.
-- @string path a path element with explicit `/` and `?` as necessary
-- @treturn string `path` with `dirsep` and `path_mark` substituted
--   for `/` and `?`
local function pathsub (path)
  return path:gsub ("%%?.", function (capture)
    return case (capture, {
           ["?"] = function ()  return M.path_mark end,
           ["/"] = function ()  return M.dirsep end,
                   function (s) return s:gsub ("^%%", "", 1) end,
    })
  end)
end


--- Normalize a path list.
-- Removing redundant `.` and `..` directories, and keep only the first
-- instance of duplicate elements.  Each argument can contain any number
-- of `pathsep` delimited elements; wherein characters are subject to
-- `/` and `?` normalization, converting `/` to `dirsep` and `?` to
-- `path_mark` (unless immediately preceded by a `%` character).
-- @param ... path elements
-- @treturn string a single normalized `pathsep` delimited paths string
-- @usage package.path = normalize (user_paths, sys_paths, package.path)
local function normalize (...)
  local t = {...}
  if debug._ARGCHECK then
    if #t < 1 then argcheck ("std.package.normalize", 1, "string") end
    for i, v in ipairs (t) do
      argcheck ("std.package.normalize", i, "string", v)
    end
  end

  local i, paths, pathstrings = 1, {}, table.concat (t, M.pathsep)
  for _, path in ipairs (split (pathstrings, M.pathsep)) do
    path = pathsub (path):
      gsub (catfile ("^[^", "]"), catfile (".", "%0")):
      gsub (catfile ("", "%.", ""), M.dirsep):
      gsub (catfile ("", "%.$"), ""):
      gsub (catfile ("", "[^", "]+", "%.%.", ""), M.dirsep):
      gsub (catfile ("", "[^", "]+", "%.%.$"), ""):
      gsub (catfile ("%.", "%..", ""), catfile ("..", "")):
      gsub (catfile ("", "$"), "")

    -- Build an inverted table of elements to eliminate duplicates after
    -- normalization.
    if not paths[path] then
      paths[path], i = i, i + 1
    end
  end
  return table.concat (invert (paths), M.pathsep)
end


------
-- Insert a new element into a `package.path` like string of paths.
-- @function insert
-- @string pathstrings a `package.path` like string
-- @int[opt=n+1] pos element index at which to insert `value`, where `n` is
--   the number of elements prior to insertion
-- @string value new path element to insert
-- @treturn string a new string with the new element inserted
-- @usage
-- package.path = insert (package.path, 1, install_dir .. "/?.lua")

local unpack = unpack or table.unpack

local function insert (pathstrings, ...)
  local args, types = {pathstrings, ...}
  if debug._ARGCHECK then
    if #args == 1 then
      types = {"string", {"int", "string"}}
    elseif #args == 2 then
      types = {"string", "string"}
    else
      types = {"string", "int", "string"}
    end
    argscheck ("std.package.insert", types, args)
  end

  local paths = split (pathstrings, M.pathsep)
  table.insert (paths, ...)
  return normalize (unpack (paths))
end


------
-- Function signature of a callback for @{mappath}.
-- @function mappath_callback
-- @string element an element from a `pathsep` delimited string of
--   paths
-- @param ... additional arguments propagated from @{mappath}
-- @return non-nil to break, otherwise continue with the next element


--- Call a function with each element of a path string.
-- @string pathstrings a `package.path` like string
-- @tparam mappath_callback callback function to call for each element
-- @param ... additional arguments passed to `callback`
-- @return nil, or first non-nil returned by `callback`
-- @usage mappath (package.path, searcherfn, transformfn)
local function mappath (pathstrings, callback, ...)
  argscheck ("std.package.mappath",
             {"string", "function"}, {pathstrings, callback})

  for _, path in ipairs (split (pathstrings, M.pathsep)) do
    local r = callback (path, ...)
    if r ~= nil then return r end
  end
end


--- Remove any element from a `package.path` like string of paths.
-- @string pathstrings a `package.path` like string
-- @int[opt=n] pos element index from which to remove an item, where `n`
--   is the number of elements prior to removal
-- @treturn string a new string with given element removed
-- @usage package.path = remove (package.path)
local function remove (pathstrings, pos)
  argscheck ("std.package.remove",
             {"string", {"int", "nil"}}, {pathstrings, pos})

  local paths = split (pathstrings, M.pathsep)
  table.remove (paths, pos)
  return table.concat (paths, M.pathsep)
end


--- @export
M = {
  find      = find,
  insert    = insert,
  mappath   = mappath,
  normalize = normalize,
  remove    = remove,
}


--- Make named constants for `package.config`
-- (undocumented in 5.1; see luaconf.h for C equivalents).
-- @table package
-- @field dirsep directory separator
-- @field pathsep path separator
-- @field path_mark string that marks substitution points in a path template
-- @field execdir (Windows only) replaced by the executable's directory in a path
-- @field igmark Mark to ignore all before it when building `luaopen_` function name.
M.dirsep, M.pathsep, M.path_mark, M.execdir, M.igmark =
  string.match (package.config, "^([^\n]+)\n([^\n]+)\n([^\n]+)\n([^\n]+)\n([^\n]+)")


for k, v in pairs (package) do
  M[k] = M[k] or v
end

return M
