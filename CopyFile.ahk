; =============================================================================
; This function has the extra benefit of not completely locking the GUI.  In my
; tests, the win32 functions could not be paused or cancelled unless the user
; exits the script prematurely, or uses Critical properly to mitigate the amount
; of lag, and to make the callback interruptable.
;
; I tried to include as much of the helpful info as I found in the win32 callback
; functions as possible, as long as it made simplistic sense.
; =============================================================================
; Example
; =============================================================================

progRoutineReturn := 0

g := Gui(,"Copy Test")
g.OnEvent("close",(*)=>ExitApp())
g.OnEvent("escape",(*)=>ExitApp())

g.Add("Button","w150 vStart","Start").OnEvent("click",gui_events)
g.Add("Button","w150 vPause","Pause").OnEvent("click",gui_events)
g.Add("Button","w150 vContinue","Continue").OnEvent("click",gui_events)
g.Add("Button","w150 y+20 vCancel","Cancel").OnEvent("click",gui_events)
g.Add("Edit","w300 r15 vData")
g.Show()

gui_events(ctl,info) {
    Global eParam, src, dest, progRoutineReturn
    
    If (ctl.name = "Start") {
        r := BCopyFile(src,dest,,progRoutine,1048576*2)
    } Else if ctl.Name = "Pause" {
        progRoutineReturn := 2
        msgbox "Pause"
    } Else if ctl.name = "Cancel" {
        progRoutineReturn := 1
        msgbox "Cancel"
    } Else if ctl.name = "Continue" {
        progRoutineReturn := 0
        r := BCopyFile(src, dest) ; resume copy by passing same src/dest parameters
    }
}

progRoutine(obj) { ; callback function
    Global progRoutineReturn, g
    
    p := Round(obj.copied / obj.size * 100,2)
    
    txt := "Size: " obj.size "`nCopied: " obj.copied "`nChunk Number: " obj.segment
    txt .= "`nComplete: " p "%"
    txt .= "`nReturn: " progRoutineReturn
    g["Data"].Value := txt
    
    If (obj.size = obj.copied)
        msgbox "done"
    
    return progRoutineReturn
}

; =============================================================================
; Usage:
;
;   RetValue := CopyFile(src:="", dest:="", modes:="r", cb:="", buf:=1048576)
;
; Parameters:
;
;   src/dest    = Source/Destination files.
;
;   modes       = Modes to use when opening the src file.  These modes are the
;                 same as AHK's FileOpen() modes.
;
;   cb          = A callback function to monitor progress.
;
;   buf         = Buffer (or chunk) size.
;
; Notes:
;
;   The last src/dest files are remembered.  So if you paused a file copy
;   process, you can resume the copy process by calling CopyFile() with the
;   same src/dest files.
;
;   It is also possible to set the buffer/chunk size at the beginning of the
;   script, or change the buffer size on the fly by calling:
;
;       CopyFile(,,,,BufSize)
;
;   Likewise you can change the callback on the fly if desired in the same way.
;
;   All internally saved stats are properly reset, depending on if the file is
;   completed, cancelled, or paused.
;
;   Initial comparisons with the win32 functions have shown this function
;   performs reasonably well (so far).  Heavy testing is still needed.  Current
;   testing has used 2.3-2.6 GB files and has compared well to system CTRL+C and
;   CTRL+V speed.  When a machine has enough RAM to completely cache a file,
;   then subsequent copies of cached files are (as expected) abnormally fast.
;
;   UNC paths are supported.
;
;   I have yet to experience any performance boost from changing the copied
;   chunk size.  The default is 1MB (1024**2 = 1,048,576 bytes).
;
; *** WARNING ***
;
;   Calling this function in the middle of a separate copy operation is
;   currently undefined and not handled.  I would anticiapte that the old
;   src/dest handles would remain open, and the new copy routine would
;   start.  Properly closing the src/dest handles requires doing a proper
;   cancel, pause, or letting the copy process play to completion.
;
;   This function will only work properly in a multi-threading context (AHK_H)
;   if the static variables are separate in each thread.  Furthermore, in this
;   context, each thread would have to be a different file.  This function
;   would not be able to use multiple threads to copy a single file, but such
;   an implementation should be theoretically possible with AHK_H.
; =============================================================================
; Callback function:
;
;   CallbackFunc(obj) {
;       ; ... do stuff
;       return ReturnCode
;   }
; =============================================================================
; Callback obj properties:
;
;   obj.size        = src file size
;   obj.copied      = copied bytes so far
;   obj.oSrc        = src File object
;   obj.oDest       = dest File object
;   obj.src         = src file full path
;   obj.dest        = dest file full path
;   obj.segment     = segment number (like chunk number)
; =============================================================================
; Callback ReturnCode values:
;
;   0 = Continue
;   1 = Cancel      (deletes partial file)
;   2 = Pause       (leaves partial file alone)
;
;   There is no difference between "pausing" or "stoping" the file transfer.
;   It is up to the coder to define those situations properly in code.
; =============================================================================

CopyFile(src:="", dest:="", modes:="r", cb:="", buf:=1048576) {
    Static _s:="", _d:="", _m:="", _cb:="", _b:="", i:=0, copied:=0, ReturnCode:=0
    
    If src="" || !FileExist(src) || dest=""
        return false
    
    ((_s="")?_s:=src:""), ((_d="")?_d:=dest:""), ((_cb="")?_cb:=cb:""), ((_m="")?_m:=modes:""), ((_b="")?_b:=buf:"")
    sF := FileOpen(_s,_m), dF := FileOpen(_d,"a"), _c:=0, bSize := _b
    (_s!=src || _d!=dest) ? (copied:=ReturnCode:=0, _cb:=cb) : (sF.Pos:=copied) ; start from 0 or resume
    
    While (copied < sF.Length) {
        b := Buffer(((remain:=sF.Length-sF.pos)>=bSize)?bSize:remain,0)
        sF.RawRead(b), dF.RawWrite(b), copied += b.size, i++
        obj := {size:sF.Length, copied:dF.Length, oSrc:sF, oDest:dF, src:_s, dest:_d, segment:i}
        IsObject(_cb) ? ReturnCode := _cb(obj) : ""
        
        If (ReturnCode>0) || (_c:=sF.Length=dF.Length) {
            sF.Close(), dF.Close(), b:=sF:=dF:=""
            If (ReturnCode=1) || (_c)
                _s:=_d:=_cb:=_m:="", copied:=0, i:=0, ((ReturnCode=1)?FileDelete(dest):"")
            ReturnCode:=0
            Break
        }
    }
    
    return _c ? true : -1 ; if complete return true, otherwise -1
}