﻿script "TestRunner"
/*
Copyright (C) 2015-2016 LiveCode Ltd.

This file is part of LiveCode.

LiveCode is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License v3 as published by the Free
Software Foundation.

LiveCode is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public License
along with LiveCode.  If not see <http://www.gnu.org/licenses/>.  */

-- FIXME provide this on the command line
constant kLogFilename = "_test_suite.log"

on startup
   send "TestRunnerMain" to me in 0
end startup

----------------------------------------------------------------
-- Command-line processing
----------------------------------------------------------------

private function getCommandLineInfo
   local tRawArg, tSelfCommand, tSelfScript, tInArgs, tArgs

   put false into tInArgs

   -- Treat everything up to & including the first
   -- ".livecodescript" file as the command for running the test
   -- runner, and everything after it as test runner arguments
   put the commandName into tSelfCommand[1]
   repeat for each element tRawArg in the commandArguments

      if tInArgs then
         put tRawArg into tArgs[1 + the number of elements in tArgs]
      else
         put tRawArg into tSelfCommand[1 + the number of elements in tSelfCommand]
         if tRawArg ends with ".livecodescript" then
            put tRawArg into tSelfScript
            put true into tInArgs
         end if
      end if

   end repeat

   local tInfo
   put tSelfCommand into tInfo["self-command"]
   put tSelfScript into tInfo["self-script"]
   put tArgs into tInfo["args"]

   return tInfo
end getCommandLineInfo

----------------------------------------------------------------
-- Top-level actions
----------------------------------------------------------------

command TestRunnerMain
   local tInfo
   put getCommandLineInfo() into tInfo

   switch tInfo["args"][1]
      case "invoke"
         doInvoke tInfo
         break
      case "run"
         doRun tInfo
         break
      case "--help"
      case "-h"
      case "help"
         doUsage 0
         break
      default
         doUsage 1
         break
   end switch
   quit 0
end TestRunnerMain

private command doInvoke pInfo
   put pInfo["args"][2] into pInfo["invoke"]["script"]
   put pInfo["args"][3] into pInfo["invoke"]["command"]

   invokeLoadLibrary pInfo
   invokeTest pInfo
end doInvoke

private command doRun pInfo
   local tScript, tCommand, tAnalysis
   put pInfo["args"][2] into tScript
   put pInfo["args"][3] into tCommand

   runLoadLibrary pInfo
   
   if tScript is empty then
      runAllScripts pInfo
   else if tCommand is empty then
      runTestScript pInfo, tScript
   else
      runTestCommand pInfo, tScript, tCommand
   end if

   put the result into tAnalysis
   
   -- Save the log to file.
   -- We process to binary data ourselves to ensure encoding and
   -- line endings are appropriate.
   local tLogForWriting
   put textEncode(tAnalysis["log"], "utf8") into tLogForWriting
   if the platform is "win32" then
      replace return with numToChar(13) & numToChar(10) in tLogForWriting
   end if
   put tLogForWriting into url ("binfile:" & kLogFilename)
   
   if TesterTapGetWorstResult(tAnalysis) is "FAIL" then
      quit 1
   end if
end doRun

private command doUsage pStatus
   write "Usage: _testrunner.livecodescript run [SCRIPT [COMMAND]]" & return to stderr
   quit pStatus
end doUsage

on ErrorDialog pExecutionError
   write "ERROR:" && pExecutionError & return to stderr
   quit 1
end ErrorDialog

----------------------------------------------------------------
-- Support for invoking test commands
----------------------------------------------------------------

-- Execute a test
private command invokeTest pInfo
   local tStackName, tResult

   -- This should auto-load the test script
   put the name of stack pInfo["invoke"]["script"] into tStackName

   -- Check that the stack script actually compiles
   set the script of tStackname to the script of tStackname
   put the result into tResult
   if tResult is not empty then
      TestDiagnostic tResult
   end if
   TestAssert "script compiles", tResult is empty

   -- Dispatch the test setup command, and check if skipping was requested
   dispatch "TestSetup" to tStackName
   put the result into tResult
   if word 1 of tResult is "SKIP" then
      TestSkip pInfo["invoke"]["command"], word 2 to -1 of tResult
      exit invokeTest
   end if

   -- Run the actual test itself
   dispatch pInfo["invoke"]["command"] to tStackName

   -- Do common cleanup tasks
   dispatch "TestTearDown" to tStackName
end invokeTest

-- Add the unit test library stack and the input library to the backscripts
private command invokeLoadLibrary pInfo
   local tLibrary, tStackName, tStackFile
   repeat for each item tLibrary in "_testlib,_inputlib"
      -- Compute the filename of the library stack and load it
      put invokeGetStackFolder(pInfo) & slash & tLibrary & ".livecodescript" into tStackFile
      put the name of stack tStackFile into tStackName
      
      send "revLoadLibrary" to stack tStackname
   end repeat
end invokeLoadLibrary

private function invokeGetStackFolder pInfo
   local tFilename
   put pInfo["self-script"] into tFilename
   
   set the itemDelimiter to slash
   return item 1 to -2 of tFilename
end invokeGetStackFolder

----------------------------------------------------------------
-- Support for running tests
----------------------------------------------------------------

-- Add the test runner library stack to the backscripts
private command runLoadLibrary pInfo
	-- Compute the filename of the library stack
	local tFilename
	put pInfo["self-script"] into tFilename

	set the itemDelimiter to slash
	put "_testerlib.livecodescript" into item -1 of tFilename

	-- Load the library
	local tStackname
	put the name of stack tFilename into tStackname

	send "revLoadLibrary" to stack tStackname
end runLoadLibrary

-- Run all the test scripts that can be found below the current
-- directory
private command runAllScripts pInfo
   local tFile, tAnalysis
   repeat for each element tFile in TesterGetTestFileNames()
      runTestScript pInfo, tFile
      put TesterTapCombine(tAnalysis, the result) into tAnalysis
   end repeat
   runPrintSummary(tAnalysis)

   return tAnalysis
end runAllScripts

-- Run the tests found in one specific script file
private command runTestScript pInfo, pScriptFile
   local tCommand, tAnalysis

   repeat for each element tCommand in TesterParseTestCommandNames(pScriptFile)
      runTestCommand pInfo, pScriptFile, tCommand
      put TesterTapCombine(tAnalysis, the result) into tAnalysis
   end repeat
   return tAnalysis
end runTestScript

private command runTestProcessOutput pScriptfile, pCommand, pOutput
   -- Create test log
   local tTestLog
   put "###" && TesterGetPrettyTestName(pScriptFile) && pCommand \
         & return & return into tTestLog
   put pOutput & return after tTestLog
   
   -- Analyse the results and print a summary line
   local tTapResults
   put TesterTapAnalyse(tTestLog) into tTapResults

   TesterLogSummaryLine tTapResults, (TesterGetPrettyTestName(pScriptFile) & ":" && pCommand)

   return tTapResults
end runTestProcessOutput

-- Run a specific named test command tCommand in a script file
-- tScriptFile
private command runTestCommand pInfo, pScriptFile, pCommand
   local tArg, tCommandLine

   repeat for each element tArg in pInfo["self-command"]
      put tArg & " " after tCommandLine
   end repeat

   put "invoke" && pScriptFile && pCommand after tCommandLine

   -- Invoke the test in a subprocess.  This ensures that we can detect
   -- if a crash occurs
   local tTestOutput, tTestExitStatus
   put shell(tCommandLine) into tTestOutput
   put the result into tTestExitStatus
   
   -- The output from the subprocesses will be native encoded utf-8.
   put textDecode(tTestOutput, "utf8") into tTestOutput

   -- Check the exit status.  If it suggests failure, add a "not ok" stanza
   -- to the tail of the TAP output
   if tTestExitStatus is not empty then
      put return after tTestOutput
      put "not ok # Subprocess exited with status" && \
            tTestExitStatus & return after tTestOutput
   end if

   runTestProcessOutput pScriptFile, pCommand, tTestOutput
   return the result
end runTestCommand

-- Print out a table of statistics
private command runPrintSummary pAnalysis
   local tSummaryString, tTotal, tDecoration

   put TesterTapGetTestCount(pAnalysis) into tTotal

   -- Format basic summary information
   if pAnalysis["xfail"] is 0 and pAnalysis["fail"] is 0 then
      put "All" && tTotal && "tests passed" into tSummaryString

   else if pAnalysis["fail"] is 0 then
      put "All" && tTotal && "tests behaved as expected" into tSummaryString

   else
      put pAnalysis["fail"] && "OF" && tTotal && "TESTS FAILED" into tSummaryString
   end if

   put return after tSummaryString

   -- Add extra summary info from expected failure & skip directives
   if pAnalysis["xpass"] > 0 then
      put tab & pAnalysis["xpass"] && "unexpected passes" & return after tSummaryString
   end if
   if pAnalysis["xfail"] > 0 then
      put tab & pAnalysis["xfail"] && "expected failures" & return after tSummaryString
   end if
   if pAnalysis["skip"] > 0 then
      put tab & pAnalysis["skip"] && "skipped" & return after tSummaryString
   end if

   put "================================================================" into tDecoration
   put tDecoration & return before tSummaryString
   put tDecoration & return after tSummaryString

   write tSummaryString to stdout
end runPrintSummary
