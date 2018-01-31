#!/usr/bin/perl -w
use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use File::Basename qw(basename);
my $pacFile;

if (basename($0) eq "pac") {
    $pacFile='/PAC.TXT';
} elsif (basename($0) eq "nar") {
    $pacFile='/NAR_DATA.TXT';
} else {
    die "This script isn't called 'pac' or 'nar', wth?\n";
}

my $allPac;
my @line;
my $found=0;
my @highlight=('a','b','Status','Support Group','Secondary Support Group','NAR ID','Instance Name','c','zzz');
my %colour=(
    green => '32m',
    yellow => '33m',
    blue => '34m',
    cyan => '1;36m',
    red => '31m',
    none => '0m'
);
my %hl=map{$_=>1}@highlight;
my $debug=0;
GetOptions ('d|debug!' => \$debug,
            'h|help' => \&help,
            'a|allpac!' => \$allPac,
           );

my $argString=shift;
my $pacString=shift;
my $searchString;
prterr("No argument given!  Please use -h for help.", "1") unless $argString;

# Allow for glob style searches
# Other string combos need to be escaped or they'll break the search
if ($argString =~ /\*/){
   $argString =~ s/\*/\.\*/g;
}
if ($argString =~ /\S(\.\S)+/){
    # Looks like a FQDN lookup
    $searchString=$argString;
} elsif ($argString =~ /^\S?\d{3,6}-?\d+$/) {
    # Looks like a NARID
    $searchString=$argString;
} else{
    # Looks like a short hostname lookup, add regex for FQDN matching
    $searchString="$argString(\\.\\S)+\.*";
}
if ($allPac && !$pacString){
    $pacFile='/PAC.TXT';
}
if ($pacString){
    $pacFile=$pacString;
    $pacFile='/ALL_PAC.TXT';
}
if ($debug) {
    printf ("PACFILE   : %s\n", $pacFile);	
    printf ("ARGSTRING : %s\n", $argString);	
    printf ("SEARCH    : %s\n", $searchString);	
}
chomp($pacFile);
chomp($searchString);
open PAC, "$pacFile" || &prterr("Cannot open \"$pacFile\" : $!","1");
chomp(my $line=<PAC>);
my @fields=map{({COLUMN=>$_,DATA=>undef})}split(/,/,$line);
print"\e[$colour{none}";
while (<PAC>){
    next unless /^$searchString,/i;
    printf ("HOST: %s\n", $searchString) if ($debug);
    chomp(@line=split(/,/,$_));
    if ($line[0] =~ /^$searchString$/i) {
        print"\n" if ($found >= 1);
        for my $i (0..$#fields){
            $fields[$i]{DATA} = $line[$i];
            if (defined $hl{$fields[$i]{COLUMN}}) {
                $fields[$i]{DATA} =~ s/^/\e[$colour{cyan}/;
                $fields[$i]{DATA} =~ s/$/\e[$colour{none}/;
            }
            printf("%-30s: %-30s\n",$fields[$i]{COLUMN},$fields[$i]{DATA});
        } 
        $found++;
    }
}
close PAC;

if ($debug){
    print <<EOF;
+----------------------------------------
+ DEBUG
+----------------------------------------
+ Matching Entries: $found
+ PAC Entries: $.
+ Search String: /^$searchString\$/i
+----------------------------------------
EOF
}

prterr("$argString not found!", "1") unless ($found);

sub prterr{
    my $Message=shift;
    my $ExitCode=shift;
    print "<E> $Message\n";
    exit $ExitCode;
}

sub help{
    print <<EOF;

Usage: $0 [-ad] hostname

Queries server information in $pacFile file and displays it in a readable format.

Arguments:
 -a, --allpac        parses the allpac feed
 -d, --debug         print debugging information

EOF
    exit 0;
}
