#!/usr/bin/perl
# Parse aggregated sudoers dump files
# 2017/09/24 - TRCM - first stab
# 2017/09/25 - TRCM - Initial server block import complete
#                   - parse sub-blocks into {global,regional,local}
#                   - implement proper option parsing (getopt)
#                   - option to list available blocks for specific server,
#                     and print a single wanted block for that server.
# 2017/09/26 - TRCM - Capture sudo data orphaned outside blocks
#                   - Stop processing remainder of file once all wanted servers are found
#                   - option to suppress comments
#                   - always remove blank lines
#                   - when parsing for all servers, output as CSV (using € delimiter)
#                     servername , sudo_block , sudo_line
#                   - sub-block matching regex updated to #{3,5}
# 2017/09/27 - TRCM - Gather global rule set version numbers.
#                   - Fix bug where choosing orphaned block would print all lines.
#                   - option extended to allow multiple server names
# 2017/09/28 - TRCM - Progress spinner
#                   - Rearrange the hash structure for clarity.
#                     %hash -> $servername -> @'RAW'             (The raw data)
#                     %hash -> $servername -> $PARSED            (a flag)
#                     %hash -> $servername -> 'SUDO' -> @BLOCK_n (The parsed blocks)
#                     %hash -> $servername -> $GBLVER            (A version identifier)
#                     %hash -> $servername -> $INCLUDE           (#include found)
#                   - Record and print the '## GBLVER:' if we find it.
#                   - Record any #include lines if we find them.
#
# NB. Expected sudoers syntactical variations are in final __END__ section.
#     Maybe we should lookup the Global Standards for the latest GBLVER 14.0.2 ?
#
# TODO Sudo Analysis ----------------------------------------------------------
# TODO - Could we compare SHA1 of each GLOBAL section, against known good? (-c&!-i?)
# TODO - Parse 'Defaults' and '#include*' into separate always-print blocks?
# TODO - Allow printing just available blocks for all servers
# TODO - Perform some real analysis on the Aliases and Specs. (-a?)
#        Perhaps first just print all Aliases, followed by all Specs ?
#        Then, unnest the Aliases and enumerate all allowed Specs?
# TODO - Allow printing multiple wanted blocks for one or all servers
# TODO - Join lines extended by backslash newline, once we've done this we will
#        be able to split then iterate the list if required.
#
# TODO Performance ------------------------------------------------------------
# TODO - Can the sudoers blocks be compressed in the hash when parsed?
# TODO - Use Storage to save and load the parsed sudoers hash?
# TODO - For largest use case (1GB data file), we use approx 3GB RAM,
#        This is probably a bit too high, so discard/process data as we go.
#
# TODO UX/UI ------------------------------------------------------------------
# TODO - subroutines should take and return references, fewer global variables
# TODO - place block matching regex into variables
#
use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;
use File::Basename qw(basename);
our $VERSION = "0.75";
my $name = basename($0);
my ($sudofile,@wantservers,%wantservers_lu,$wantblock,$debug,$ignore);
wtf() unless scalar @ARGV > 0 or (-t STDIN);
# FIXME block should take multiple values separated by comma.
GetOptions ('h|help|v|?'     => sub{ info($VERSION);wtf(); },
            'f|file=s'       => \$sudofile,
            'd|debug'        => \$debug,
            'i|ignore'       => \$ignore,
            's|servername=s' => \@wantservers,
            'b|block:s'      => \$wantblock,
            'v|version'      => sub{ info($VERSION);exit 0; },
) or wtf();
wtf() unless defined($sudofile);
die" ! Unable to read sudoers_file : $sudofile\n" unless (-r $sudofile);
# We want a list, not a comma separated string.
@wantservers = split(/,/,join(',',@wantservers));
# Having a lookup table of our wanted servers is handy.
%wantservers_lu = map { $_ => 1; } @wantservers;
$wantblock = (defined $wantblock) ? $wantblock : undef;

#------------------------------------------------------------------------------
my %serverhash;
my ($server, $data);
my ($server_block,$inside_block);
local $| = 1;
importdata($sudofile);

#------------------------------------------------------------------------------
# Print the parsed data depending on what our command arguments were.
if (@wantservers) {
# Printing results for one or more servernames
    foreach my $wantserver (@wantservers) {
        if (exists($serverhash{$wantserver})) {
            my $block_found;
            print("[+] Servername : $wantserver, [GBLVER:$serverhash{$wantserver}{'GBLVER'}], [INCLUDES:$serverhash{$wantserver}{'INCLUDE'}]\n");
            if (defined($wantblock) and $wantblock eq "") {
            # Printing results for a single servername, listing available blocks
                print("[-] List of available blocks...\n");
                foreach my $block (sort keys %{$serverhash{$wantserver}{'SUDO'}}) {
                    $block_found++;
                    print("      $block\n");
                }
                print("[!] No sudoers blocks found\n") unless ($block_found);
            } elsif (defined($wantblock)) {
            # Printing results for a single servername and matching sudo block(s)
                foreach my $block (sort keys %{$serverhash{$wantserver}{'SUDO'}}) {
                    if ($block =~ m/^$wantblock/) {
                        $block_found++;
                        print("[-] Sudo block matching \"$wantblock\" : $block\n");
                        printf("%s\n",'-'x78);
                        foreach (@{$serverhash{$wantserver}{'SUDO'}{$block}}) {
                            print("$_\n");
                        }
                        printf("%s\n",'-'x78);
                    }
                }
                print("[!] No sudoers blocks matching \"$wantblock\"\n") unless ($block_found);
            } else {
            # Printing results for a single servername and all blocks parsed
                foreach my $block (keys %{$serverhash{$wantserver}{'SUDO'}}) {
                    $block_found++;
                    print("[-] Sudo block : $block ...\n");
                    printf("%s\n",'-'x78);
                    foreach (@{$serverhash{$wantserver}{'SUDO'}{$block}}) {
                        print("$_\n");
                    }
                    printf("%s\n",'-'x78);
                }
                print("[!] No sudoers blocks found\n") unless ($block_found);
            }
        } else {
            print("[!] ERROR Servername : $wantserver not found.\n");
            exit 1;
        }
    }
} else {
# Printing results for all servernames
    foreach my $server (sort keys %serverhash) {
        my $block_found;
        if (exists($serverhash{$server}{'PARSED'})) {
            printf("%s\n",'-'x78);
            print("[+] Servername : $server\n");
            printf("%s\n",'-'x78);
            foreach my $block (keys %{$serverhash{$server}{'SUDO'}}) {
                $block_found++;
                foreach (@{$serverhash{$server}{'SUDO'}{$block}}) {
                    print("$server€$block€$_\n");
                }
            }
            print("[!] No sudoers blocks found\n") unless ($block_found);
        } else {
            print "[!] Parsing failed for : $server\n";
        }
    }
}
print STDERR ("[?] DEBUG: Processed $. in total.\n") if ($debug);
#------------------------------------------------------------------------------
sub importdata {
    # Read the entire file, and split into chunks per server.
    my $sudofile = shift;
    open (my $FD,'<',$sudofile) || die;
    my @spinner = ('|','/','-','\\');
    while (my $line = <$FD>) {
        printf("[%s] Parsing ...\r",$spinner[$.%4]) if ($.%25001 == 0);
        chomp $line;
        #$line =~ s/\015?\012?$//; # Portable chomp
        # Always remove blank lines.
        next if $line =~ m/^\s*$/;
        if (defined($ignore)) {
            # Skip if one or more whitespace followed by #
            next if $line =~ m/^\s+#/;
            # Skip if only a mix of whitespace and #
            next if $line =~ m/^[#\s]+$/;
            # Skip if one or two # followed by one or more whitespace unless 'GBLVER:'
            next if $line =~ m/^#{1,2}\s+(?!GBLVER:)/;
            # Skip if one # followed by one or more whitespace then any char, ending #
            next if $line =~ m/^#\s+.*#$/;
            # Skip if one #, but not when followed by (# or whitespace or 'include')
            next if $line =~ m/^#(?!(#|\s|include))/;
            # Skip if two or more #, followed by only one or more not # or 'GBLVER:'
            next if $line =~ m/^#{2,}(?!(#+|GBLVER:[0-9\.]+))$/;
        }
        undef $inside_block if $line =~ m/^#{4,6}\ END_OF_SUDOERS|^#{4,6}\ START_OF_SUDOERS/;
        # Record the Global sections version identifier
        $serverhash{$server}{'GBLVER'}=$1 if ($line =~ m/^## GBLVER:([0-9\.]+)/);
        # Flag up #include lines as they're against HSBC security standards
        $serverhash{$server}{'INCLUDE'}++ if ($line =~ m/^#include/ and exists($serverhash{$server}));
        if ($inside_block) {
            push (@{$serverhash{$server}{'RAW'}}, $line) unless exists($serverhash{$server}{'PARSED'});
            next;
        }
        if ($line =~ m/^#{4,6}\ START_OF_SUDOERS_FOR_/) {
            $inside_block++;
            ($server) = $line =~ m/^#{4,6}\ START_OF_SUDOERS_FOR_([\w\.\=]+)/;
            # Initialise the bad '#include' counter to zero.
            $serverhash{$server}{'INCLUDE'}=0;
            # Initialise the Global Version number
            $serverhash{$server}{'GBLVER'}="unknown";
            undef $inside_block if ((@wantservers) and (not exists $wantservers_lu{$server}));
            next;
        }
        if ($line =~ /^#{4,6}\ END_OF_SUDOERS_FOR_/) {
            if ((@wantservers) and exists $wantservers_lu{$server}) {
                # We want specific servers, and this is one of them
                parseserverblock($server);
                # It's done, remove it from our lookup list
                delete $wantservers_lu{$server};
                print STDERR ("[?] DEBUG: ($server) done, servers left=".scalar(keys %wantservers_lu)."\n") if ($debug);
                if (scalar(keys %wantservers_lu) == 0) {
                    # Stop as we parsed the last of our wanted servers
                    print STDERR ("[?] DEBUG: fast importdata exit at line : $.\n") if ($debug);
                    last;
                } else {
                    next;
                }
            } elsif (not @wantservers) {
                # We wanted every server, just process it.
                parseserverblock($server);
            } else {
                # We wanted some servers, this isn't it
                next;
            }
        }
    }
    close($FD);
    return;
}
#------------------------------------------------------------------------------
sub parseserverblock {
    my $server = shift;
    my $block_name;
    my $block_inside;
    foreach (@{$serverhash{$server}{'RAW'}}) {
        chomp;
        # TODO - move block matching regex to variables
        undef $block_inside if m/#{3,5}\ START\ #{3,5}$|#{3,5}\ END\ #{3,5}$/;
        if ($block_inside) {
            # We're inside a block, add the line to the named block array
            push (@{$serverhash{$server}{'SUDO'}{$block_name}}, $_);
            next;
        } elsif (not m/#{3,5}\ START\ #{3,5}$|#{3,5}\ END\ #{3,5}$/) {
            # We're outside both block and block-tags, add line to ORPHANED block array
            push (@{$serverhash{$server}{'SUDO'}{'ORPHANED'}}, $_);
            next;
        }
        if (m/#{3,5}\ START\ #{3,5}/) {
            # We're starting a new block, remember its name
            $block_inside++;
            # '#{3,5} BLOCK_NAME #{3,5} (START|END) #{3,5}'
            # FIXME - using split is crap, what about a look(ahead|behind) regex capture?
            #       - something like...
            #       - m/^(?=#{3,5}\ (GLOBAL|REGIONAL|LOCAL)_)([\w]+)\ /
            $block_name = trim((split(/\ /,$_,3))[1]);
            next;
        }
    }
    # Once we've parsed the whole server block, discard the RAW data
    delete $serverhash{$server}{'RAW'};
    # I'm making a note here, great success
    $serverhash{$server}{'PARSED'}++;
    return;
}
#------------------------------------------------------------------------------
sub trim {
    my $s_string = shift;
    $s_string =~ s/^\s+//;
    $s_string =~ s/\s+$//;
    return $s_string;
}
#------------------------------------------------------------------------------
sub info {
    my $s_version = shift;
    printf("\e[%dm%s\e[m - %s (PERL v%vd)\n",33,$name,$s_version,$^V);
    return;
}
#------------------------------------------------------------------------------
sub wtf {
    printf("Usage: \e[%dm%-12s\e[m [-h] [-i] -f sudoers_file [-s servername] [-b block(s)]\n",33,$name);
    print("       '-b' Without a block name will list available blocks found.\n");
    print("       '-b <block>,<block>,...' Multiple blocks are separated by comma.\n");
    print("       '-i' will ignore/suppress commented lines.\n");
    exit;
}
#------------------------------------------------------------------------------

__END__

