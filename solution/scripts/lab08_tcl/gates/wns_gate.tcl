# Lab08: standalone WNS gate -- proves the gate BITES (exit 1 on violation)
set rpts [glob -nocomplain build/timing_*.rpt]
if {[llength $rpts] == 0} { puts "FAIL: no timing reports"; exit 1 }
foreach r $rpts {
    set fh [open $r r]; set txt [read $fh]; close $fh
    foreach {m wns tns} [regexp -all -inline {WNS\(ns\)\s+TNS\(ns\)[^\n]*\n\s*(-?[\d.]+)\s+(-?[\d.]+)} $txt] {
        puts "[file tail $r]: WNS=$wns"
        if {$wns < 0} { puts "FAIL: timing violations"; exit 1 }
    }
}
puts "PASS: all timing clean"
