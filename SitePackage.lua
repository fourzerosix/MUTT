-- “Point A to point B, oh, I know
-- Lots of points with no points in between for me
-- So lonely but never alone, I know
-- I’m at my house, but I wish that I were at home”
--
-- Author: Octopus Oscillator
-- Date: 2025-10-23
-- Description: This is the main file Lmod will use to control the tracking of
--              module usage
------------------------------------------------------------------------------
-- load_hook(): Here we record any modules loaded.
local hook    = require("Hook")
local uname   = require("posix").uname
local cosmic  = require("Cosmic"):singleton()
local syshost = cosmic:value("LMOD_SYSHOST")
local s_msgT = {}

local function load_hook(t)
   -- the arg t is a table:
   --     t.modFullName:  the module full name: (i.e: openmpi/5.0.8)
   --     t.fn:           The file name: (i.e /path/to/spack/linux-rocky9-x86_64/Core/openmpi/5.0.8.lua)
   --     t.mname:        The Module Name object.

   local isVisible = t.mname:isVisible()

   -- Get cluster name
   local host = syshost
   if (not host) then
      host = uname("%n")
      -- Extract just the short hostname
      -- e.g., "ai-rmlutil2.niaid.nih.gov" becomes "ai-rmlutil2"
      local shorthost = host:match("([^.]+)")
      if shorthost then
         host = shorthost
      end
   end

   if (mode() ~= "load") then return end

   -- Get job ID if available
   local jobid = os.getenv("SLURM_JOB_ID") or os.getenv("PBS_JOBID") or "interactive"

   -- This was breaking module load by producing a 'nil' value - belljs
   -- Get Lmod version
   --local lmod_ver = cosmic:version()

   -- This was complicit, removed lmod=%s - belljs
   --local msg = string.format("user=%s module=%s path=%s host=%s jobid=%s lmod=%s time=%f",
   local msg = string.format("user=%s module=%s path=%s host=%s jobid=%s time=%f",

                           os.getenv("USER"), t.modFullName, t.fn, host,
                           -- Causes format error, removed lmod_ver - belljs
                           --jobid, lmod_ver, epoch())
                           jobid, epoch())
   s_msgT[t.modFullName] = msg
end

hook.register("load", load_hook)

local function report_loads()
   for k,msg in pairs(s_msgT) do
      -- Use identifier "ModuleUsage" for tagging
      lmod_system_execute("logger -t ModuleUsage -p local0.info '" .. msg .. "'")
   end
end

ExitHookA.register(report_loads)
