#!/usr/bin/env perl
# 20140626 - TRCM - lolz
use sigtrap 'handler'=>\&t,'normal-signals';#local $/=\1;
$[=1;$g=1;$a="\e[0m";@y=("\e[1;31m","\e[1;33m","\e[1;32m","\e[1;34m","\e[1;36m","\e[1;35m");
sub t(){print$a};while(<>){print@y[$g].$_;$g++;if($g gt scalar @y){$g=1}};print$a;
